extends Node
const PromptPipelineScript = preload("res://scripts/prompt/prompt_pipeline.gd")

signal search_completed(request_id: String, keyword: String, results: Array)
signal search_failed(request_id: String, keyword: String, error: String)
signal page_generated(request_id: String, url: String, content: Dictionary)
signal page_failed(request_id: String, url: String, error: String)
signal url_open_requested(url: String, design_prompt: String, page_context: String)
signal browser_history_updated()
signal browser_state_changed()

const SEARCH_PROMPT_KEY: String = "browser_search"
const PAGE_PROMPT_KEY: String = "browser_webpage"
const DEFAULT_SEARCH_COUNT: int = 6
const BROWSER_PAGES_DIR: String = "res://resources/data/browser_pages/"
const BROWSER_DATA_PATH: String = "res://resources/data/browser/browser_content.json"
const HISTORY_RELATIVE_PATH: String = "browser/history.json"
const HISTORY_LIMIT: int = 100

@onready var _ai_service: AIService = $AIService

var _request_counter: int = 0
var _pending_requests: Dictionary = {}
var _search_cache: Dictionary = {}
var _page_cache: Dictionary = {}
var _search_inflight: Dictionary = {}
var _page_inflight: Dictionary = {}
var _request_followers: Dictionary = {}
var _browser_state: Dictionary = {}
## 预制页面：url → WebPageResource
var _premade_pages: Dictionary = {}
## 预制页面搜索索引：keyword_lower → [WebPageResource]
var _premade_keyword_index: Dictionary = {}
var _browser_content: Dictionary = {}
var _history_entries: Array = []
var _history_counter: int = 0


func _ready() -> void:
	if _ai_service == null:
		push_error("BrowserManager: AIService not found")
		return

	_setup_ai_service()
	_ai_service.request_completed.connect(_on_ai_request_completed)
	_ai_service.request_failed.connect(_on_ai_request_failed)
	_load_premade_pages()
	_load_browser_content()


func _setup_ai_service() -> void:
	var cfg := AIConfigManager.get_instance()
	if not cfg.apply_to_service(_ai_service, "browser"):
		cfg.apply_to_service(_ai_service, "chat_default")

	_ai_service.auto_execute_tools = false
	_ai_service.stream_enabled = false
	_ai_service.max_concurrent_requests = max(_ai_service.max_concurrent_requests, 5)
	_ai_service.default_temperature = 0.7


func search(keyword: String) -> String:
	var normalized: String = keyword.strip_edges()
	if normalized.is_empty():
		return ""

	if _search_cache.has(normalized):
		var local_id := _next_local_request_id("search_cache")
		var cached: Array = _search_cache[normalized].get("results", [])
		call_deferred("_emit_cached_search", local_id, normalized, cached)
		return local_id

	if _search_inflight.has(normalized):
		var canonical_id: String = str(_search_inflight[normalized])
		var follower_id := _next_local_request_id("search_join")
		_append_follower(canonical_id, follower_id)
		return follower_id

	var messages := _build_search_messages(normalized)
	var request_id: String = _ai_service.chat(messages, {
		"temperature": 0.8,
		"max_tokens": 4096
	})
	if request_id.is_empty():
		return ""
	_pending_requests[request_id] = {
		"kind": "search",
		"keyword": normalized
	}
	_search_inflight[normalized] = request_id
	return request_id


func open_page(url: String, design_prompt: String = "", page_context: String = "") -> String:
	var normalized: String = url.strip_edges()
	if normalized.is_empty():
		return ""

	# 优先查预制页面
	var premade := _find_premade_page(normalized)
	if premade != null:
		var premade_payload: Dictionary = _build_premade_page_payload(premade)
		if not premade_payload.is_empty():
			var local_id := _next_local_request_id("premade")
			_page_cache[normalized] = {
				"content": premade_payload.duplicate(true),
				"updated_at": Time.get_unix_time_from_system()
			}
			call_deferred("_emit_cached_page", local_id, normalized, premade_payload)
			return local_id

	if _page_cache.has(normalized):
		var local_id := _next_local_request_id("page_cache")
		var cached_content: Dictionary = _page_cache[normalized].get("content", {})
		call_deferred("_emit_cached_page", local_id, normalized, cached_content)
		return local_id

	if _page_inflight.has(normalized):
		var canonical_id: String = str(_page_inflight[normalized])
		var follower_id := _next_local_request_id("page_join")
		_append_follower(canonical_id, follower_id)
		return follower_id

	var messages := _build_page_messages(normalized, design_prompt, page_context)
	# 若有预制页面但 content 为空，使用其 design_prompt 和 hint
	if premade != null:
		if design_prompt.is_empty() and not premade.design_prompt.strip_edges().is_empty():
			design_prompt = premade.design_prompt
		if page_context.is_empty() and not premade.hint.strip_edges().is_empty():
			page_context = premade.hint
		messages = _build_page_messages(normalized, design_prompt, page_context)
	var request_id: String = _ai_service.chat(messages, {
		"temperature": 0.7,
		"max_tokens": 8192
	})
	if request_id.is_empty():
		return ""
	_pending_requests[request_id] = {
		"kind": "page",
		"url": normalized,
		"design_prompt": design_prompt,
		"page_context": page_context
	}
	_page_inflight[normalized] = request_id
	return request_id


func request_open_url(url: String, design_prompt: String = "", page_context: String = "") -> void:
	var normalized: String = url.strip_edges()
	if normalized.is_empty():
		return

	var cleaned_design_prompt: String = design_prompt.strip_edges()
	var cleaned_page_context: String = page_context.strip_edges()
	var app_mgr: Node = get_node_or_null("/root/AppManager")
	if app_mgr != null:
		if app_mgr.has_method("focus_app"):
			app_mgr.focus_app("browser", true)
		elif app_mgr.has_method("launch_app"):
			app_mgr.launch_app("browser", true)

	call_deferred("_emit_open_url_request", normalized, cleaned_design_prompt, cleaned_page_context)


func _emit_open_url_request(url: String, design_prompt: String, page_context: String) -> void:
	url_open_requested.emit(url, design_prompt, page_context)


func get_history_entries(limit: int = 0) -> Array:
	var entries: Array = _history_entries.duplicate(true)
	if limit > 0 and entries.size() > limit:
		return entries.slice(0, limit)
	return entries


func get_history_entry(entry_id: String) -> Dictionary:
	for entry in _history_entries:
		if entry is Dictionary and str(entry.get("entry_id", "")) == entry_id:
			return entry.duplicate(true)
	return {}


func register_generated_page_entry(action_id: String, payload: Dictionary, entry_prefix: String = "browser") -> Dictionary:
	var url: String = str(payload.get("url", "")).strip_edges()
	var page_snapshot: Dictionary = payload.get("page", {}).duplicate(true)
	if not url.is_empty() and not page_snapshot.is_empty():
		_page_cache[url] = {
			"content": page_snapshot.duplicate(true),
			"updated_at": Time.get_unix_time_from_system()
		}

	var entry := _create_history_entry_v2(action_id, payload, entry_prefix)
	_record_history_entry(entry)
	return entry.duplicate(true)


func get_cached_search(keyword: String) -> Array:
	var normalized: String = keyword.strip_edges()
	if normalized.is_empty() or not _search_cache.has(normalized):
		return []
	return _search_cache[normalized].get("results", []).duplicate(true)


func get_cached_page(url: String) -> Dictionary:
	var normalized: String = url.strip_edges()
	if normalized.is_empty() or not _page_cache.has(normalized):
		return {}
	return _page_cache[normalized].get("content", {}).duplicate(true)


func clear_cache() -> void:
	_search_cache.clear()
	_page_cache.clear()


func clear_search_cache_for(keyword: String) -> void:
	var normalized: String = keyword.strip_edges()
	if _search_cache.has(normalized):
		_search_cache.erase(normalized)


func clear_page_cache_for(url: String) -> void:
	var normalized: String = url.strip_edges()
	if _page_cache.has(normalized):
		_page_cache.erase(normalized)


func set_browser_state_value(key: String, value: Variant) -> void:
	var normalized_key := key.strip_edges()
	if normalized_key.is_empty():
		return
	var changed: bool = not _browser_state.has(normalized_key) or _browser_state[normalized_key] != value
	_browser_state[normalized_key] = value
	if changed:
		browser_state_changed.emit()


func get_browser_state_value(key: String, default_value: Variant = null) -> Variant:
	var normalized_key := key.strip_edges()
	if normalized_key.is_empty():
		return default_value
	return _browser_state.get(normalized_key, default_value)


func set_browser_state_values(values: Dictionary) -> void:
	for key in values:
		set_browser_state_value(str(key), values[key])


func has_pending_requests() -> bool:
	return not _pending_requests.is_empty()


func get_run_state() -> Dictionary:
	return {
		"browser_state": _browser_state.duplicate(true),
	}


func load_run_state(data: Dictionary) -> bool:
	_browser_state.clear()
	var browser_state: Variant = data.get("browser_state", {})
	if browser_state is Dictionary:
		_browser_state = (browser_state as Dictionary).duplicate(true)
	_load_history()
	browser_state_changed.emit()
	return true


func reset_runtime_state(clear_persistent_history: bool = false) -> void:
	_pending_requests.clear()
	_search_inflight.clear()
	_page_inflight.clear()
	_request_followers.clear()
	_browser_state.clear()
	_search_cache.clear()
	_page_cache.clear()
	_history_entries.clear()
	_history_counter = 0
	if clear_persistent_history:
		_save_history()
	browser_history_updated.emit()
	browser_state_changed.emit()


func _emit_cached_search(request_id: String, keyword: String, results: Array) -> void:
	search_completed.emit(request_id, keyword, _inject_premade_search_results(keyword, results))


func _emit_cached_page(request_id: String, url: String, content: Dictionary) -> void:
	page_generated.emit(request_id, url, content)


func _on_ai_request_completed(request_id: String, response: Dictionary) -> void:
	if not _pending_requests.has(request_id):
		return

	var meta: Dictionary = _pending_requests[request_id]
	_pending_requests.erase(request_id)

	var content: String = _extract_content(response)
	if content.is_empty():
		_match_failed(meta, request_id, "LLM 返回为空")
		return

	var kind: String = meta.get("kind", "")
	if kind == "search":
		var keyword: String = meta.get("keyword", "")
		_search_inflight.erase(keyword)
		var ai_results: Array = _parse_search_results(content)
		if ai_results.is_empty():
			_emit_search_failed_with_followers(request_id, keyword, "搜索结果 JSON 解析失败")
			return
		_search_cache[keyword] = {
			"results": ai_results,
			"updated_at": Time.get_unix_time_from_system()
		}
		var results := _inject_premade_search_results(keyword, ai_results)
		_emit_search_completed_with_followers(request_id, keyword, results)
		return

	if kind == "page":
		var url: String = meta.get("url", "")
		_page_inflight.erase(url)
		var page_content: Dictionary = _parse_page_content(content)
		if page_content.is_empty():
			_emit_page_failed_with_followers(request_id, url, "网页 JSON 解析失败")
			return
		_page_cache[url] = {
			"content": page_content,
			"updated_at": Time.get_unix_time_from_system()
		}
		_emit_page_generated_with_followers(request_id, url, page_content)
		return


func _on_ai_request_failed(request_id: String, error: String, _error_code: int) -> void:
	if not _pending_requests.has(request_id):
		return
	var meta: Dictionary = _pending_requests[request_id]
	_pending_requests.erase(request_id)
	var kind: String = meta.get("kind", "")
	if kind == "search":
		_search_inflight.erase(meta.get("keyword", ""))
	elif kind == "page":
		_page_inflight.erase(meta.get("url", ""))
	_match_failed(meta, request_id, error)


func _match_failed(meta: Dictionary, request_id: String, error: String) -> void:
	var kind: String = meta.get("kind", "")
	if kind == "search":
		_emit_search_failed_with_followers(request_id, meta.get("keyword", ""), error)
	elif kind == "page":
		_emit_page_failed_with_followers(request_id, meta.get("url", ""), error)


func _append_follower(canonical_id: String, follower_id: String) -> void:
	if not _request_followers.has(canonical_id):
		_request_followers[canonical_id] = []
	var followers: Array = _request_followers[canonical_id]
	followers.append(follower_id)
	_request_followers[canonical_id] = followers


func _take_followers(canonical_id: String) -> Array:
	if not _request_followers.has(canonical_id):
		return []
	var followers: Array = _request_followers[canonical_id]
	_request_followers.erase(canonical_id)
	return followers


func _emit_search_completed_with_followers(request_id: String, keyword: String, results: Array) -> void:
	search_completed.emit(request_id, keyword, results)
	var followers: Array = _take_followers(request_id)
	for follower_id in followers:
		search_completed.emit(str(follower_id), keyword, results)


func _emit_search_failed_with_followers(request_id: String, keyword: String, error: String) -> void:
	search_failed.emit(request_id, keyword, error)
	var followers: Array = _take_followers(request_id)
	for follower_id in followers:
		search_failed.emit(str(follower_id), keyword, error)


func _emit_page_generated_with_followers(request_id: String, url: String, content: Dictionary) -> void:
	page_generated.emit(request_id, url, content)
	var followers: Array = _take_followers(request_id)
	for follower_id in followers:
		page_generated.emit(str(follower_id), url, content)


func _emit_page_failed_with_followers(request_id: String, url: String, error: String) -> void:
	page_failed.emit(request_id, url, error)
	var followers: Array = _take_followers(request_id)
	for follower_id in followers:
		page_failed.emit(str(follower_id), url, error)


func _extract_content(response: Dictionary) -> String:
	if response.has("choices") and response["choices"] is Array and response["choices"].size() > 0:
		var choice: Dictionary = response["choices"][0]
		var message: Dictionary = choice.get("message", {})
		var message_content: Variant = message.get("content", "")
		if message_content is String:
			return message_content.strip_edges()
	return ""


func _parse_search_results(text: String) -> Array:
	var parsed: Variant = _parse_json_payload(text)
	var list: Array = []

	if parsed is Array:
		list = parsed
	elif parsed is Dictionary:
		if parsed.has("results") and parsed["results"] is Array:
			list = parsed["results"]
		else:
			list = [parsed]

	var sanitized: Array = []
	for item in list:
		if not item is Dictionary:
			continue
		var title: String = str(item.get("title", "")).strip_edges()
		var url: String = str(item.get("url", "")).strip_edges()
		if title.is_empty() or url.is_empty():
			continue
		sanitized.append({
			"title": title,
			"url": url,
			"hint": str(item.get("hint", "")).strip_edges(),
			"design_prompt": str(item.get("design_prompt", "")).strip_edges()
		})
	return sanitized


func _parse_page_content(text: String) -> Dictionary:
	var stripped := text.strip_edges()

	# 去除 markdown 代码围栏
	if stripped.begins_with("```"):
		var first_nl := stripped.find("\n")
		if first_nl >= 0:
			stripped = stripped.substr(first_nl + 1)
		if stripped.ends_with("```"):
			stripped = stripped.substr(0, stripped.length() - 3)
		stripped = stripped.strip_edges()

	# 自动检测格式: { 开头 → JSON, < 开头 → 标签 DSL
	if stripped.begins_with("{"):
		var parsed: Variant = _parse_json_payload(text)
		if parsed is Dictionary:
			if parsed.has("content") and parsed["content"] is Dictionary:
				return parsed["content"]
			return parsed
		return {}

	# 标签式 DSL（含 < 即尝试）
	if stripped.find("<") >= 0:
		var dsl_result := DslPageParser.parse(stripped)
		if not dsl_result.is_empty():
			return dsl_result

	# 最后尝试 JSON
	var parsed_fallback: Variant = _parse_json_payload(text)
	if parsed_fallback is Dictionary:
		return parsed_fallback
	return {}


func _parse_json_payload(text: String) -> Variant:
	var cleaned: String = text.strip_edges()
	if cleaned.is_empty():
		return null

	if cleaned.begins_with("```"):
		var lines: PackedStringArray = cleaned.split("\n")
		if lines.size() >= 2:
			lines.remove_at(0)
			if lines.size() > 0 and lines[lines.size() - 1].begins_with("```"):
				lines.remove_at(lines.size() - 1)
			cleaned = "\n".join(lines).strip_edges()

	# 尝试直接解析
	var parsed_direct: Variant = JSON.parse_string(cleaned)
	if parsed_direct != null:
		return parsed_direct

	# 提取 {...} 或 [...]
	var candidate: String = ""
	var obj_start: int = cleaned.find("{")
	var obj_end: int = cleaned.rfind("}")
	var arr_start: int = cleaned.find("[")
	var arr_end: int = cleaned.rfind("]")

	if obj_start >= 0 and obj_end > obj_start:
		candidate = cleaned.substr(obj_start, obj_end - obj_start + 1)
		var parsed_obj: Variant = JSON.parse_string(candidate)
		if parsed_obj != null:
			return parsed_obj
	elif arr_start >= 0 and arr_end > arr_start:
		candidate = cleaned.substr(arr_start, arr_end - arr_start + 1)
		var parsed_arr: Variant = JSON.parse_string(candidate)
		if parsed_arr != null:
			return parsed_arr

	# JSON 解析失败，尝试修复 LLM 常见的未转义引号
	var to_repair: String = candidate if not candidate.is_empty() else cleaned
	var repaired: String = _repair_json_quotes(to_repair)
	if repaired != to_repair:
		var parsed_repaired: Variant = JSON.parse_string(repaired)
		if parsed_repaired != null:
			return parsed_repaired

	return null


## 修复 LLM 返回 JSON 中的常见错误：
## 1) 字符串值内未转义的双引号 → 转义为 \"
## 2) 冒号后缺失字符串值的开引号 → 自动补 "
func _repair_json_quotes(text: String) -> String:
	var result: PackedByteArray = PackedByteArray()
	var i: int = 0
	var length: int = text.length()
	var in_string: bool = false
	var expect_value: bool = false

	while i < length:
		var ch: String = text[i]

		if not in_string:
			# 冒号后跳过空白，判断值是否缺少开引号
			if expect_value:
				if ch == " " or ch == "\t" or ch == "\n" or ch == "\r":
					result.append_array(ch.to_utf8_buffer())
					i += 1
					continue
				expect_value = false
				# 合法的 JSON 值起始字符：" { [ 数字 - t f n
				if ch == "\"" or ch == "{" or ch == "[" or ch == "t" or ch == "f" or ch == "n" or ch == "-" or (ch >= "0" and ch <= "9"):
					result.append_array(ch.to_utf8_buffer())
					if ch == "\"":
						in_string = true
					i += 1
					continue
				# 缺少开引号，补一个 " 并进入字符串模式
				result.append_array("\"".to_utf8_buffer())
				result.append_array(ch.to_utf8_buffer())
				in_string = true
				i += 1
				continue

			result.append_array(ch.to_utf8_buffer())
			if ch == "\"":
				in_string = true
			elif ch == ":":
				expect_value = true
			i += 1
			continue

		# 在字符串内部
		if ch == "\\":
			# 转义序列，原样保留两个字符
			result.append_array(ch.to_utf8_buffer())
			i += 1
			if i < length:
				result.append_array(text[i].to_utf8_buffer())
				i += 1
			continue

		if ch == "\"":
			# 判断这个 " 是否为结构性闭合引号
			if _is_structural_close_quote(text, i + 1, length):
				result.append_array(ch.to_utf8_buffer())
				in_string = false
			else:
				# 野引号，转义
				result.append_array("\\\"".to_utf8_buffer())
			i += 1
			continue

		result.append_array(ch.to_utf8_buffer())
		i += 1

	return result.get_string_from_utf8()


## 判断位置 pos 之后（跳过空白）是否紧跟 JSON 结构字符 , } ] :
## 或者已到达文本末尾。如果是，说明前面的 " 是结构性闭合引号。
func _is_structural_close_quote(text: String, pos: int, length: int) -> bool:
	var j: int = pos
	while j < length and (text[j] == " " or text[j] == "\t" or text[j] == "\n" or text[j] == "\r"):
		j += 1
	if j >= length:
		return true
	var next_ch: String = text[j]
	return next_ch == "," or next_ch == "}" or next_ch == "]" or next_ch == ":"


func _build_search_messages(keyword: String) -> Array:
	var system_prompt: String = _resolve_prompt(SEARCH_PROMPT_KEY)
	if system_prompt.is_empty():
		system_prompt = "你是模拟现代互联网的搜索引擎。只返回JSON数组，字段必须为title,url,hint,design_prompt。禁止输出解释文本。"

	var matched_premade: Array = _search_premade_pages(keyword)
	var ai_result_count = max(0, DEFAULT_SEARCH_COUNT - matched_premade.size())
	var user_text := "搜索关键词：%s\n总共需要 %d 条结果。你负责生成其中 %d 条结果。" % [keyword, DEFAULT_SEARCH_COUNT, ai_result_count]
	if not matched_premade.is_empty():
		user_text += "\n以下预制网页已经存在，系统会直接把它们注入最终搜索结果。不要再生成与它们相同或高度相似的结果，不要重复官网、镜像页、同站改写页或只是标题稍微变化的重复结果："
		for page: WebPageResource in matched_premade:
			user_text += "\n- %s | %s | %s" % [
				page.title.strip_edges(),
				page.url.strip_edges(),
				page.hint.strip_edges(),
			]
		if ai_result_count <= 0:
			user_text += "\n当前可见的预制网页已经足够覆盖本次搜索结果。此时返回空 JSON 数组 []。"
		else:
			user_text += "\n请只补充剩余结果，并优先选择不同类型的网站，避免与上述预制网页撞题。"

	return [
		{"role": "system", "content": system_prompt},
		{"role": "user", "content": user_text}
	]


func _build_page_messages(url: String, design_prompt: String, page_context: String = "") -> Array:
	var pm: Node = get_node_or_null("/root/PromptManager")
	var system_prompt: String = ""

	if pm != null and pm.has_method("resolve_with_vars"):
		# 两遍 resolve：先展开 prompt → 用完整文本匹配 lore → 注入 lore
		var pipeline_result := PromptPipelineScript.build_prompt(
			PAGE_PROMPT_KEY,
			{},
			{
				"lore_mode": "browser",
				"lore_args": {
					"url": url,
					"design_prompt": design_prompt,
					"page_context": page_context,
				},
			}
		)
		system_prompt = str(pipeline_result.get("prompt", ""))
	else:
		system_prompt = _resolve_prompt(PAGE_PROMPT_KEY)

	if system_prompt.is_empty():
		system_prompt = "你是模拟现代互联网的网页内容生成器。只返回JSON对象，禁止img类型，必须使用支持的UI节点类型。使用浅色背景深色文字。"

	var user_text := "网址：%s" % url
	if not page_context.is_empty():
		user_text += "\n页面摘要：%s" % page_context
	if not design_prompt.is_empty():
		user_text += "\n风格参考：%s" % design_prompt

	return [
		{"role": "system", "content": system_prompt},
		{"role": "user", "content": user_text}
	]


func _resolve_prompt_with_lore(key: String, lore_payload: Dictionary) -> String:
	var pm: Node = get_node_or_null("/root/PromptManager")
	if pm == null or not pm.has_method("resolve_with_vars"):
		return _resolve_prompt(key)
	var vars: Dictionary = PromptPipelineScript.build_lore_vars(lore_payload)
	return str(pm.resolve_with_vars(key, vars))


func _resolve_prompt(key: String) -> String:
	var pm: Node = get_node_or_null("/root/PromptManager")
	if pm == null:
		return ""
	if not pm.has_method("resolve"):
		return ""
	return str(pm.resolve(key))


func _next_local_request_id(prefix: String) -> String:
	_request_counter += 1
	return "%s_%d_%d" % [prefix, Time.get_ticks_msec(), _request_counter]


func _load_browser_content() -> void:
	_browser_content.clear()
	if not FileAccess.file_exists(BROWSER_DATA_PATH):
		push_warning("BrowserManager: browser content file missing: %s" % BROWSER_DATA_PATH)
		return
	var file := FileAccess.open(BROWSER_DATA_PATH, FileAccess.READ)
	if file == null:
		push_warning("BrowserManager: failed to open browser content file")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed == null or not parsed is Dictionary:
		push_warning("BrowserManager: invalid browser content json")
		return
	_browser_content = parsed


func _load_history() -> void:
	_history_entries.clear()
	_history_counter = 0
	var history_path := _get_history_path()
	if history_path.is_empty() or not FileAccess.file_exists(history_path):
		return
	var file := FileAccess.open(history_path, FileAccess.READ)
	if file == null:
		push_warning("BrowserManager: failed to open browser history")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed == null or not parsed is Dictionary:
		push_warning("BrowserManager: invalid browser history json")
		return
	_history_counter = int(parsed.get("next_id", 0))
	for entry in parsed.get("entries", []):
		if not entry is Dictionary:
			continue
		_history_entries.append(entry)
		var url := str(entry.get("url", "")).strip_edges()
		var snapshot: Dictionary = entry.get("page_snapshot", {})
		if not url.is_empty() and not snapshot.is_empty():
			_page_cache[url] = {
				"content": snapshot.duplicate(true),
				"updated_at": int(entry.get("timestamp", Time.get_unix_time_from_system()))
			}


func _save_history() -> void:
	var history_path := _get_history_path()
	if history_path.is_empty():
		return
	if history_path.begins_with("res://templates/"):
		return
	var dir_path := history_path.get_base_dir() + "/"
	if not DirAccess.dir_exists_absolute(dir_path):
		var dir_err := DirAccess.make_dir_recursive_absolute(dir_path)
		if dir_err != OK:
			push_warning("BrowserManager: failed to create history dir: %s" % dir_path)
			return
	var file := FileAccess.open(history_path, FileAccess.WRITE)
	if file == null:
		push_warning("BrowserManager: failed to write browser history")
		return
	file.store_string(JSON.stringify({
		"next_id": _history_counter,
		"entries": _history_entries
	}, "\t"))
	file.close()


func _get_history_path() -> String:
	var run_manager: Node = get_node_or_null("/root/CampaignRunManager")
	if run_manager != null and run_manager.has_method("get_browser_history_path"):
		var run_history_path: String = str(run_manager.call("get_browser_history_path")).strip_edges()
		if not run_history_path.is_empty():
			return run_history_path

	var storage: Node = get_node_or_null("/root/StorageManager")
	if storage == null:
		return ""
	var project_path: String = str(storage.get("current_project_path"))
	if project_path.is_empty():
		return ""
	if not project_path.ends_with("/"):
		project_path += "/"
	return project_path + HISTORY_RELATIVE_PATH


func _record_history_entry(entry: Dictionary) -> void:
	_history_entries.push_front(entry)
	if _history_entries.size() > HISTORY_LIMIT:
		_history_entries = _history_entries.slice(0, HISTORY_LIMIT)
	_save_history()
	browser_history_updated.emit()


func _get_current_day() -> int:
	var glm: Node = get_node_or_null("/root/GameLoopManager")
	if glm != null:
		return int(glm.get("current_day"))
	var tm: Node = get_node_or_null("/root/TimeManager")
	if tm != null and tm.has_method("get_day"):
		return tm.get_day()
	return 1


func _get_current_timestamp() -> int:
	var tm: Node = get_node_or_null("/root/TimeManager")
	if tm != null and tm.has_method("get_game_timestamp"):
		return tm.get_game_timestamp()
	return int(Time.get_unix_time_from_system())


func _create_history_entry_v2(action_id: String, payload: Dictionary, entry_prefix: String = "browser") -> Dictionary:
	_history_counter += 1
	var phase_name := "UNKNOWN"
	var glm: Node = get_node_or_null("/root/GameLoopManager")
	if glm != null and glm.has_method("get_phase_name"):
		phase_name = glm.get_phase_name(glm.get("time_phase"))
	var normalized_prefix: String = entry_prefix.strip_edges()
	if normalized_prefix.is_empty():
		normalized_prefix = "browser"
	return {
		"entry_id": "%s_%04d" % [normalized_prefix, _history_counter],
		"day": _get_current_day(),
		"phase": phase_name,
		"action_id": action_id,
		"source_site": str(payload.get("site", {}).get("site_id", "")),
		"title": str(payload.get("title", "")),
		"url": str(payload.get("url", "")),
		"summary": str(payload.get("summary", "")),
		"timestamp": _get_current_timestamp(),
		"page_snapshot": payload.get("page", {}).duplicate(true),
		"related_topic_ids": [str(payload.get("topic", {}).get("topic_id", ""))]
	}


# ── 预制页面 ──────────────────────────────────────────

func _load_premade_pages() -> void:
	_premade_pages.clear()
	_premade_keyword_index.clear()
	if OS.has_feature("editor"):
		_rebuild_premade_index()
	var index_path := BROWSER_PAGES_DIR + "index.tres"
	if not ResourceLoader.exists(index_path):
		return
	var index_res: Resource = load(index_path)
	if index_res == null or not index_res is WebPageIndex:
		return
	for page: WebPageResource in index_res.pages:
		if page != null and not page.url.strip_edges().is_empty():
			_register_premade_page(page)
	if not _premade_pages.is_empty():
		print("[BrowserManager] Loaded %d premade pages" % _premade_pages.size())


func _register_premade_page(page: WebPageResource) -> void:
	var url := page.url.strip_edges()
	_premade_pages[url] = page
	for kw in page.search_keywords:
		var lower := kw.strip_edges().to_lower()
		if lower.is_empty():
			continue
		if not _premade_keyword_index.has(lower):
			_premade_keyword_index[lower] = []
		_premade_keyword_index[lower].append(page)


## 编辑器模式下扫描文件夹，自动重建 index.tres
func _rebuild_premade_index() -> void:
	var dir := DirAccess.open(BROWSER_PAGES_DIR)
	if dir == null:
		return
	var pages: Array[WebPageResource] = []
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres") and file_name != "index.tres":
			var res_path := BROWSER_PAGES_DIR + file_name
			var res: Resource = load(res_path)
			if res is WebPageResource and not res.url.strip_edges().is_empty():
				pages.append(res)
		file_name = dir.get_next()
	dir.list_dir_end()
	# 加载或创建 index
	var index_path := BROWSER_PAGES_DIR + "index.tres"
	var index: WebPageIndex
	if ResourceLoader.exists(index_path):
		var existing := load(index_path)
		if existing is WebPageIndex:
			index = existing
		else:
			index = WebPageIndex.new()
	else:
		index = WebPageIndex.new()
	index.pages = pages
	ResourceSaver.save(index, index_path)
	print("[BrowserManager] Auto-rebuilt index.tres (%d pages)" % pages.size())


func _build_premade_page_payload(page: WebPageResource) -> Dictionary:
	if page == null:
		return {}

	var scene_path: String = page.scene_path.strip_edges()
	if not scene_path.is_empty():
		if ResourceLoader.exists(scene_path):
			return {
				"scene_path": scene_path,
				"title": page.title,
			}
		push_warning("BrowserManager: premade scene page missing scene: %s" % scene_path)

	if page.content.strip_edges().is_empty():
		return {}

	var parsed: Dictionary = _parse_page_content(page.content)
	if parsed.is_empty():
		return {}
	if not page.title.strip_edges().is_empty() and not parsed.has("title"):
		parsed["title"] = page.title
	return parsed


func _find_premade_page(url: String) -> WebPageResource:
	if _premade_pages.has(url):
		return _premade_pages[url] as WebPageResource
	# 模糊匹配（忽略末尾斜杠、协议等）
	var stripped := url.replace("https://", "").replace("http://", "").trim_suffix("/")
	for key in _premade_pages:
		var k: String = key.replace("https://", "").replace("http://", "").trim_suffix("/")
		if k == stripped:
			return _premade_pages[key] as WebPageResource
	return null


func _inject_premade_search_results(keyword: String, ai_results: Array) -> Array:
	var matched: Array = _search_premade_pages(keyword)
	var filtered_ai_results: Array = []
	for item in ai_results:
		if not item is Dictionary:
			continue
		var item_url := str(item.get("url", "")).strip_edges()
		var premade := _find_premade_page(item_url)
		if premade != null and not _is_page_search_visible(premade):
			continue
		filtered_ai_results.append(item)

	if matched.is_empty():
		return filtered_ai_results
	# 去重：已有相同 url 的不重复添加
	var existing_urls: Dictionary = {}
	for item in filtered_ai_results:
		if item is Dictionary and item.has("url"):
			existing_urls[str(item["url"])] = true
	var injected: Array = []
	for page: WebPageResource in matched:
		if not existing_urls.has(page.url):
			injected.append({
				"title": page.title,
				"url": page.url,
				"hint": page.hint,
				"design_prompt": page.design_prompt
			})
	# 预制结果置顶
	injected.append_array(filtered_ai_results)
	return injected


func _search_premade_pages(keyword: String) -> Array:
	var results: Array = []
	var seen: Dictionary = {}
	var kw_lower := keyword.strip_edges().to_lower()
	# 精确关键词匹配
	if _premade_keyword_index.has(kw_lower):
		for page: WebPageResource in _premade_keyword_index[kw_lower]:
			if _is_page_search_visible(page) and not seen.has(page.url):
				results.append(page)
				seen[page.url] = true
	# 模糊匹配：关键词包含在搜索词中或搜索词包含在关键词中
	for idx_kw: String in _premade_keyword_index:
		if kw_lower.find(idx_kw) >= 0 or idx_kw.find(kw_lower) >= 0:
			for page: WebPageResource in _premade_keyword_index[idx_kw]:
				if _is_page_search_visible(page) and not seen.has(page.url):
					results.append(page)
					seen[page.url] = true
	# 标题模糊匹配
	for url: String in _premade_pages:
		var page: WebPageResource = _premade_pages[url]
		if _is_page_search_visible(page) and not seen.has(page.url) and page.title.to_lower().find(kw_lower) >= 0:
			results.append(page)
			seen[page.url] = true
	return results


func _is_page_search_visible(page: WebPageResource) -> bool:
	if page == null or not page.searchable:
		return false
	if page.search_conditions.is_empty():
		return true
	for condition in page.search_conditions:
		if not _evaluate_search_condition(condition):
			return false
	return true


func _evaluate_search_condition(condition: Dictionary) -> bool:
	var source := str(condition.get("source", "")).strip_edges().to_lower()
	var field := str(condition.get("field", "")).strip_edges()
	var op := str(condition.get("op", "==")).strip_edges()
	var expected: Variant = condition.get("value", null)
	var actual: Variant = null

	match source:
		"time":
			actual = _get_time_condition_value(field)
		"game":
			actual = _get_game_condition_value(field)
		"browser_state":
			actual = _browser_state.get(field, null)
		_:
			push_warning("BrowserManager: Unknown search condition source: %s" % source)
			return false

	return _compare_condition_values(actual, expected, op)


func _get_time_condition_value(field: String) -> Variant:
	var tm := get_node_or_null("/root/TimeManager")
	if tm == null:
		return null
	match field:
		"day":
			return tm.get_day() if tm.has_method("get_day") else null
		"hour":
			return tm.get_hour() if tm.has_method("get_hour") else null
		"minute":
			return tm.get_minute() if tm.has_method("get_minute") else null
		"total_minutes":
			return tm.get_total_minutes() if tm.has_method("get_total_minutes") else null
		"timestamp":
			return tm.get_game_timestamp() if tm.has_method("get_game_timestamp") else null
		_:
			return null


func _get_game_condition_value(field: String) -> Variant:
	var gm := get_node_or_null("/root/GameManager")
	if gm == null:
		return null
	return gm.get(field)


func _compare_condition_values(actual: Variant, expected: Variant, op: String) -> bool:
	match op:
		"==":
			return actual == expected
		"!=":
			return actual != expected
		">":
			return actual != null and expected != null and actual > expected
		">=":
			return actual != null and expected != null and actual >= expected
		"<":
			return actual != null and expected != null and actual < expected
		"<=":
			return actual != null and expected != null and actual <= expected
		"in":
			if expected is Array:
				return expected.has(actual)
			if expected is PackedStringArray:
				return expected.has(actual)
			return false
		"contains":
			if actual is String:
				return actual.find(str(expected)) >= 0
			if actual is Array:
				return actual.has(expected)
			if actual is PackedStringArray:
				return actual.has(str(expected))
			return false
		_:
			push_warning("BrowserManager: Unknown search condition op: %s" % op)
			return false
