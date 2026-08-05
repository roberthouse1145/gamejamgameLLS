extends Node
## 通用虚拟浏览器服务：预制网页、可选 LLM 网页生成、缓存与浏览历史。

const AIServiceClass = preload("res://scripts/llm/AIService.gd")
const AIConfigManagerClass = preload("res://scripts/llm/ai_config_manager.gd")
const PageMarkParserClass = preload("res://scripts/apps/browser/page_mark_parser.gd")
const WebPageResourceClass = preload("res://scripts/apps/browser/web_page_resource.gd")
const WebPageIndexClass = preload("res://scripts/apps/browser/web_page_index.gd")

const PAGES_INDEX_PATH: String = "res://resources/data/browser_pages/index.tres"
const HISTORY_PATH: String = "user://browser/history.json"
const SEARCH_PROMPT_KEY: String = "browser_search"
const PAGE_PROMPT_KEY: String = "browser_webpage"

signal search_completed(request_id: String, keyword: String, results: Array)
signal search_failed(request_id: String, keyword: String, error: String)
signal page_generated(request_id: String, url: String, content: Dictionary)
signal page_failed(request_id: String, url: String, error: String)
signal url_open_requested(url: String, design_prompt: String, page_context: String)
signal browser_history_updated()
signal surf_started(request_id: String, keyword: String)
signal surf_completed(request_id: String, keyword: String, url: String, page_summary: String, page: Dictionary)
signal surf_failed(request_id: String, keyword: String, error: String)

var persist_history: bool = true
var allow_ai_requests: bool = true

var _ai_service: AIService = null
var _ai_available: bool = false
var _request_meta: Dictionary = {}
var _request_counter: int = 0
var _premade_pages: Dictionary = {}
var _page_cache: Dictionary = {}
var _search_cache: Dictionary = {}
var _history_entries: Array[Dictionary] = []
var _history_counter: int = 0
var _browser_state: Dictionary = {}


func _ready() -> void:
	_setup_ai_service()
	_load_premade_pages()
	_load_history()


func search(keyword: String) -> String:
	var normalized: String = keyword.strip_edges()
	var request_id: String = _next_request_id("search")
	if normalized.is_empty():
		search_failed.emit.call_deferred(request_id, normalized, "搜索关键词不能为空")
		return request_id
	if _search_cache.has(normalized):
		search_completed.emit.call_deferred(request_id, normalized, _search_cache[normalized].duplicate(true))
		return request_id

	var premade_results: Array = _search_premade_pages(normalized)
	if not premade_results.is_empty():
		_search_cache[normalized] = premade_results.duplicate(true)
		search_completed.emit.call_deferred(request_id, normalized, premade_results)
		return request_id
	if not _can_request_ai():
		search_failed.emit.call_deferred(request_id, normalized, "浏览器 AI 配置不可用")
		return request_id

	var ai_request_id: String = _ai_service.chat(_build_search_messages(normalized))
	if ai_request_id.is_empty():
		search_failed.emit.call_deferred(request_id, normalized, "搜索请求创建失败")
		return request_id
	_request_meta[ai_request_id] = {
		"type": "search",
		"public_request_id": request_id,
		"keyword": normalized,
	}
	return request_id


func open_page(url: String, design_prompt: String = "", page_context: String = "") -> String:
	var normalized: String = url.strip_edges()
	var request_id: String = _next_request_id("page")
	if normalized.is_empty():
		page_failed.emit.call_deferred(request_id, normalized, "网页地址不能为空")
		return request_id

	var premade_page: Resource = _find_premade_page(normalized)
	if premade_page != null:
		var premade_content: Dictionary = _build_premade_page_payload(premade_page)
		if premade_content.is_empty():
			page_failed.emit.call_deferred(request_id, normalized, "预制网页内容为空")
		else:
			_emit_page_success.call_deferred(request_id, normalized, premade_content)
		return request_id
	if _page_cache.has(normalized):
		page_generated.emit.call_deferred(request_id, normalized, _page_cache[normalized].duplicate(true))
		return request_id
	if not _can_request_ai():
		page_failed.emit.call_deferred(request_id, normalized, "浏览器 AI 配置不可用")
		return request_id

	var ai_request_id: String = _ai_service.chat(_build_page_messages(normalized, design_prompt, page_context))
	if ai_request_id.is_empty():
		page_failed.emit.call_deferred(request_id, normalized, "网页请求创建失败")
		return request_id
	_request_meta[ai_request_id] = {
		"type": "page",
		"public_request_id": request_id,
		"url": normalized,
	}
	return request_id


## 根据关键词直接打开一张网页；优先使用匹配的预制网页，否则生成虚拟网页。
func surf(keyword: String) -> String:
	var normalized: String = keyword.strip_edges()
	var request_id: String = _next_request_id("surf")
	if normalized.is_empty():
		surf_failed.emit.call_deferred(request_id, normalized, "关键词不能为空")
		return request_id
	surf_started.emit(request_id, normalized)

	var premade_results: Array = _search_premade_pages(normalized)
	if not premade_results.is_empty():
		var url: String = str(premade_results[0].get("url", ""))
		var premade_page: Resource = _find_premade_page(url)
		var content: Dictionary = _build_premade_page_payload(premade_page)
		_complete_surf.call_deferred(request_id, normalized, url, content)
		return request_id
	if not _can_request_ai():
		surf_failed.emit.call_deferred(request_id, normalized, "浏览器 AI 配置不可用")
		return request_id

	var url: String = "browser://generated/%s" % normalized.uri_encode()
	var ai_request_id: String = _ai_service.chat(_build_page_messages(url, "", "围绕关键词“%s”生成一张完整网页。" % normalized))
	if ai_request_id.is_empty():
		surf_failed.emit.call_deferred(request_id, normalized, "网页请求创建失败")
		return request_id
	_request_meta[ai_request_id] = {
		"type": "surf",
		"public_request_id": request_id,
		"keyword": normalized,
		"url": url,
	}
	return request_id


func request_open_url(url: String, design_prompt: String = "", page_context: String = "") -> void:
	var normalized: String = url.strip_edges()
	if not normalized.is_empty():
		url_open_requested.emit(normalized, design_prompt, page_context)


func get_history_entries(limit: int = 0) -> Array:
	var result: Array = _history_entries.duplicate(true)
	result.reverse()
	if limit > 0 and result.size() > limit:
		result.resize(limit)
	return result


func get_history_entry(entry_id: String) -> Dictionary:
	for entry: Dictionary in _history_entries:
		if str(entry.get("entry_id", "")) == entry_id:
			return entry.duplicate(true)
	return {}


func register_generated_page_entry(action_id: String, payload: Dictionary, entry_prefix: String = "browser") -> Dictionary:
	var entry: Dictionary = _create_history_entry(
		str(payload.get("url", "")),
		str(payload.get("title", action_id)),
		_dictionary_value(payload.get("page", {})),
		entry_prefix
	)
	_history_entries.append(entry)
	_save_history()
	browser_history_updated.emit()
	return entry.duplicate(true)


func get_cached_search(keyword: String) -> Array:
	return _search_cache.get(keyword.strip_edges(), []).duplicate(true)


func get_cached_page(url: String) -> Dictionary:
	return _dictionary_value(_page_cache.get(url.strip_edges(), {}))


func clear_cache() -> void:
	_page_cache.clear()
	_search_cache.clear()


func clear_search_cache_for(keyword: String) -> void:
	_search_cache.erase(keyword.strip_edges())


func clear_page_cache_for(url: String) -> void:
	_page_cache.erase(url.strip_edges())


func set_browser_state_value(key: String, value: Variant) -> void:
	var normalized: String = key.strip_edges()
	if not normalized.is_empty():
		_browser_state[normalized] = value


func get_browser_state_value(key: String, default_value: Variant = null) -> Variant:
	return _browser_state.get(key.strip_edges(), default_value)


func set_browser_state_values(values: Dictionary) -> void:
	_browser_state.merge(values, true)


func has_pending_requests() -> bool:
	return not _request_meta.is_empty()


func has_pending_surf_requests() -> bool:
	for meta_value: Variant in _request_meta.values():
		if meta_value is Dictionary and str(meta_value.get("type", "")) == "surf":
			return true
	return false


func get_surf_blocking_reason() -> String:
	return "网页生成中" if has_pending_surf_requests() else ""


func get_run_state() -> Dictionary:
	return {
		"browser_state": _browser_state.duplicate(true),
		"page_cache": _page_cache.duplicate(true),
		"search_cache": _search_cache.duplicate(true),
		"history_entries": _history_entries.duplicate(true),
		"history_counter": _history_counter,
	}


func load_run_state(data: Dictionary) -> bool:
	_browser_state = _dictionary_value(data.get("browser_state", {}))
	_page_cache = _dictionary_value(data.get("page_cache", {}))
	_search_cache = _dictionary_value(data.get("search_cache", {}))
	_history_entries.clear()
	var history_value: Variant = data.get("history_entries", [])
	if history_value is Array:
		for entry_value: Variant in history_value:
			if entry_value is Dictionary:
				_history_entries.append(entry_value.duplicate(true))
	_history_counter = int(data.get("history_counter", _history_entries.size()))
	browser_history_updated.emit()
	return true


func reset_runtime_state(clear_persistent_history: bool = false) -> void:
	_request_meta.clear()
	clear_cache()
	_browser_state.clear()
	if clear_persistent_history:
		_history_entries.clear()
		_history_counter = 0
		_save_history()
		browser_history_updated.emit()


func has_premade_page(url: String) -> bool:
	return _find_premade_page(url.strip_edges()) != null


func _setup_ai_service() -> void:
	_ai_service = AIServiceClass.new()
	_ai_service.name = "BrowserAIService"
	add_child(_ai_service)
	_ai_service.request_completed.connect(_on_ai_request_completed)
	_ai_service.request_failed.connect(_on_ai_request_failed)
	var config_manager: AIConfigManager = AIConfigManagerClass.get_instance()
	_ai_available = config_manager.apply_to_service(_ai_service, "browser")
	if not _ai_available:
		_ai_available = config_manager.apply_to_service(_ai_service, "chat_default")


func _can_request_ai() -> bool:
	return allow_ai_requests and _ai_available and _ai_service != null


func _on_ai_request_completed(request_id: String, response: Dictionary) -> void:
	if not _request_meta.has(request_id):
		return
	var meta: Dictionary = _request_meta[request_id]
	_request_meta.erase(request_id)
	var content_text: String = AIServiceClass.extract_content(response).strip_edges()
	match str(meta.get("type", "")):
		"search":
			var results: Array = _parse_search_results(content_text)
			var keyword: String = str(meta.get("keyword", ""))
			var public_id: String = str(meta.get("public_request_id", ""))
			if results.is_empty():
				search_failed.emit(public_id, keyword, "搜索结果为空")
			else:
				_search_cache[keyword] = results.duplicate(true)
				search_completed.emit(public_id, keyword, results)
		"page", "surf":
			var page: Dictionary = _parse_page_content(content_text)
			var url: String = str(meta.get("url", ""))
			var public_id: String = str(meta.get("public_request_id", ""))
			if page.is_empty():
				if str(meta.get("type", "")) == "surf":
					surf_failed.emit(public_id, str(meta.get("keyword", "")), "网页内容无法解析")
				else:
					page_failed.emit(public_id, url, "网页内容无法解析")
				return
			page["title"] = str(meta.get("keyword", url))
			if str(meta.get("type", "")) == "surf":
				_complete_surf(public_id, str(meta.get("keyword", "")), url, page)
			else:
				_emit_page_success(public_id, url, page)


func _on_ai_request_failed(request_id: String, error: String, _error_code: int) -> void:
	if not _request_meta.has(request_id):
		return
	var meta: Dictionary = _request_meta[request_id]
	_request_meta.erase(request_id)
	var public_id: String = str(meta.get("public_request_id", ""))
	match str(meta.get("type", "")):
		"search": search_failed.emit(public_id, str(meta.get("keyword", "")), error)
		"page": page_failed.emit(public_id, str(meta.get("url", "")), error)
		"surf": surf_failed.emit(public_id, str(meta.get("keyword", "")), error)


func _emit_page_success(request_id: String, url: String, content: Dictionary) -> void:
	_page_cache[url] = content.duplicate(true)
	_record_history(url, str(content.get("title", url)), content)
	page_generated.emit(request_id, url, content)


func _complete_surf(request_id: String, keyword: String, url: String, page: Dictionary) -> void:
	if page.is_empty():
		surf_failed.emit(request_id, keyword, "网页内容为空")
		return
	_page_cache[url] = page.duplicate(true)
	_record_history(url, str(page.get("title", keyword)), page)
	surf_completed.emit(request_id, keyword, url, str(page.get("title", keyword)), page)


func _build_search_messages(keyword: String) -> Array:
	return [
		{"role": "system", "content": _resolve_prompt(SEARCH_PROMPT_KEY)},
		{"role": "user", "content": "搜索关键词：%s" % keyword},
	]


func _build_page_messages(url: String, design_prompt: String, page_context: String) -> Array:
	var user_text: String = "网址：%s" % url
	if not page_context.strip_edges().is_empty():
		user_text += "\n页面内容目标：%s" % page_context
	if not design_prompt.strip_edges().is_empty():
		user_text += "\n页面视觉方向：%s" % design_prompt
	return [
		{"role": "system", "content": _resolve_prompt(PAGE_PROMPT_KEY)},
		{"role": "user", "content": user_text},
	]


func _resolve_prompt(key: String) -> String:
	var prompt_manager: Node = get_node_or_null("/root/PromptManager")
	if prompt_manager != null and prompt_manager.has_method("resolve"):
		return str(prompt_manager.call("resolve", key))
	return ""


func _parse_search_results(text: String) -> Array:
	var parsed: Variant = JSON.parse_string(_strip_code_fences(text))
	var results: Array = []
	if not parsed is Array:
		return results
	for item_value: Variant in parsed:
		if not item_value is Dictionary:
			continue
		var item: Dictionary = item_value
		var title: String = str(item.get("title", "")).strip_edges()
		var url: String = str(item.get("url", "")).strip_edges()
		if title.is_empty() or url.is_empty():
			continue
		results.append({
			"title": title,
			"url": url,
			"hint": str(item.get("hint", "")),
			"design_prompt": str(item.get("design_prompt", "")),
		})
	return results


func _parse_page_content(text: String) -> Dictionary:
	var parsed: Dictionary = PageMarkParserClass.parse(_strip_code_fences(text))
	return _dictionary_value(parsed.get("tree", {}))


func _strip_code_fences(text: String) -> String:
	var stripped: String = text.strip_edges()
	if not stripped.begins_with("```"):
		return stripped
	var lines: PackedStringArray = stripped.split("\n")
	if not lines.is_empty():
		lines.remove_at(0)
	if not lines.is_empty() and lines[lines.size() - 1].strip_edges().begins_with("```"):
		lines.remove_at(lines.size() - 1)
	return "\n".join(lines).strip_edges()


func _load_premade_pages() -> void:
	_premade_pages.clear()
	if not ResourceLoader.exists(PAGES_INDEX_PATH):
		return
	var index: Resource = ResourceLoader.load(PAGES_INDEX_PATH)
	if index == null or not index is WebPageIndexClass:
		return
	for page_value: Variant in index.pages:
		var page: Resource = page_value as Resource
		if page != null and page is WebPageResourceClass and not str(page.url).strip_edges().is_empty():
			_premade_pages[str(page.url).strip_edges()] = page


func _find_premade_page(url: String) -> Resource:
	if _premade_pages.has(url):
		return _premade_pages[url] as Resource
	var normalized: String = url.replace("https://", "").replace("http://", "").trim_suffix("/")
	for key_value: Variant in _premade_pages:
		var key: String = str(key_value)
		if key.replace("https://", "").replace("http://", "").trim_suffix("/") == normalized:
			return _premade_pages[key] as Resource
	return null


func _search_premade_pages(keyword: String) -> Array:
	var results: Array = []
	var normalized: String = keyword.to_lower()
	for page_value: Variant in _premade_pages.values():
		var page: Resource = page_value as Resource
		if page == null or not bool(page.searchable) or not _matches_search_conditions(page.search_conditions):
			continue
		var searchable_text: String = "%s %s %s" % [page.title, page.hint, " ".join(page.search_keywords)]
		if searchable_text.to_lower().find(normalized) < 0:
			continue
		results.append({
			"title": page.title,
			"url": page.url,
			"hint": page.hint,
			"design_prompt": page.design_prompt,
		})
	return results


func _matches_search_conditions(conditions: Array[Dictionary]) -> bool:
	for condition: Dictionary in conditions:
		if not _evaluate_condition(condition):
			return false
	return true


func _evaluate_condition(condition: Dictionary) -> bool:
	var source: String = str(condition.get("source", "browser")).strip_edges()
	var field: String = str(condition.get("field", "")).strip_edges()
	var expected: Variant = condition.get("value")
	var actual: Variant = null
	match source:
		"browser": actual = _read_path(_browser_state, field)
		"state":
			var game_state: Node = get_node_or_null("/root/GameState")
			if game_state != null and game_state.has_method("to_dict"):
				actual = _read_path(_dictionary_value(game_state.call("to_dict")), field)
		"story":
			var story_director: Node = get_node_or_null("/root/StoryDirector")
			if story_director != null:
				actual = _read_path(_dictionary_value(story_director.get("story_variables")), field)
	return _compare(actual, expected, str(condition.get("op", "==")))


func _compare(actual: Variant, expected: Variant, operator: String) -> bool:
	match operator:
		"==": return actual == expected
		"!=": return actual != expected
		">": return actual != null and expected != null and actual > expected
		">=": return actual != null and expected != null and actual >= expected
		"<": return actual != null and expected != null and actual < expected
		"<=": return actual != null and expected != null and actual <= expected
		"contains":
			if actual is String:
				return actual.contains(str(expected))
			if actual is Array:
				return actual.has(expected)
	return false


func _build_premade_page_payload(page: Resource) -> Dictionary:
	if page == null:
		return {}
	var scene_path: String = str(page.scene_path).strip_edges()
	if not scene_path.is_empty() and ResourceLoader.exists(scene_path):
		return {
			"scene_path": scene_path,
			"title": str(page.title),
			"icon_path": str(page.icon_path),
		}
	var content: Dictionary = _parse_page_content(str(page.content))
	if not content.is_empty():
		content["title"] = str(page.title)
		content["icon_path"] = str(page.icon_path)
	return content


func _record_history(url: String, title: String, page: Dictionary) -> void:
	var entry: Dictionary = _create_history_entry(url, title, page)
	_history_entries.append(entry)
	_save_history()
	browser_history_updated.emit()


func _create_history_entry(url: String, title: String, page: Dictionary, prefix: String = "browser") -> Dictionary:
	_history_counter += 1
	return {
		"entry_id": "%s_%04d" % [prefix, _history_counter],
		"title": title,
		"url": url,
		"summary": title,
		"timestamp": int(Time.get_unix_time_from_system()),
		"page_snapshot": page.duplicate(true),
	}


func _load_history() -> void:
	if not FileAccess.file_exists(HISTORY_PATH):
		return
	var file: FileAccess = FileAccess.open(HISTORY_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return
	_history_counter = int(parsed.get("next_id", 0))
	var entries_value: Variant = parsed.get("entries", [])
	if entries_value is Array:
		for entry_value: Variant in entries_value:
			if entry_value is Dictionary:
				_history_entries.append(entry_value.duplicate(true))


func _save_history() -> void:
	if not persist_history:
		return
	var directory: String = HISTORY_PATH.get_base_dir()
	if not DirAccess.dir_exists_absolute(directory):
		DirAccess.make_dir_recursive_absolute(directory)
	var file: FileAccess = FileAccess.open(HISTORY_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({"next_id": _history_counter, "entries": _history_entries}, "  "))
	file.close()


func _next_request_id(prefix: String) -> String:
	_request_counter += 1
	return "%s_%d_%d" % [prefix, Time.get_ticks_msec(), _request_counter]


func _read_path(root: Dictionary, path: String) -> Variant:
	var current: Variant = root
	for segment: String in path.split(".", false):
		if current is Dictionary and current.has(segment):
			current = current[segment]
		else:
			return null
	return current


func _dictionary_value(value: Variant) -> Dictionary:
	return value.duplicate(true) if value is Dictionary else {}
