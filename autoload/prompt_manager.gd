extends Node
## PromptManager Autoload — 通用 prompt 模板引擎，可在不同项目间复用。
## 支持 {{key}} 递归替换，内置环形引用检测。
## 启动时自动扫描 prompts_dir 加载所有 .md 文件。
## 支持 <注释>...</注释> 标签，resolve 时自动剥离，方便调试。
## 支持通过 JSON 声明式配置 provider（node + method 绑定）。
##
## 三层数据源（同名冲突时按此优先级）：
##   1. caller vars  — resolve_with_vars() 传入的当次上下文，用完即弃
##   2. providers    — register_provider() / JSON 配置注册的全局懒求值回调
##   3. prompts      — .md 文件自动加载 / register_prompt() 注册的静态模板
## 三者均递归展开内部 {{…}}。

const MAX_RESOLVE_DEPTH: int = 10

## 模板目录，可在 _ready 前修改。
var prompts_dir: String = "res://prompts/"

## Provider 声明式绑定 JSON 路径，可在 _ready 前修改。
## JSON 格式：{ "key": { "node": "AutoloadName", "method": "method_name" }, ... }
var providers_config_path: String = "res://config/prompt_providers.json"

## Seed 词池 JSON 路径，可在 _ready 前修改。
## JSON 格式：{ "group_name": ["词1", "词2", ...], ... }
var seed_pools_path: String = "res://prompts/seed_pools.json"

## 用于剥离 <注释>...</注释> 块的正则（支持多行、嵌套内容）
var _comment_regex: RegEx

## 用于匹配 {{seed:group,N}} 的正则
var _seed_regex: RegEx

## prompt_key -> template_text（静态模板）
var _prompts: Dictionary = {}

## key -> Callable（全局懒求值回调，resolve 时调用获取最新值）
var _providers: Dictionary = {}

## group_name -> Array[String]（seed 词池）
var _seed_pools: Dictionary = {}

## group_name -> Array[int]（已使用的索引，耗尽时自动重置）
var _seed_used: Dictionary = {}


func _ready() -> void:
	_comment_regex = RegEx.new()
	_comment_regex.compile("(?s)<注释>.*?</注释>")
	_seed_regex = RegEx.new()
	_seed_regex.compile("\\{\\{seed:(\\w+),(\\d+)\\}\\}")
	_load_prompts_from_dir(prompts_dir)
	_load_providers_from_json(providers_config_path)
	_load_seed_pools(seed_pools_path)


## 按 key 查找 prompt，递归替换所有 {{xxx}}。
## 找不到 key 返回空字符串。
func resolve(key: String) -> String:
	if not _prompts.has(key):
		push_warning("PromptManager: prompt key '%s' not found" % key)
		return ""
	return _resolve_recursive(_prompts[key], {}, 0, {})


## 对任意文本做 {{xxx}} 替换。
func resolve_template(text: String) -> String:
	return _resolve_recursive(text, {}, 0, {})


## 按 key 查找 prompt，并用 vars 注入动态变量。
func resolve_with_vars(key: String, vars: Dictionary) -> String:
	if not _prompts.has(key):
		push_warning("PromptManager: prompt key '%s' not found" % key)
		return ""
	return _resolve_recursive(_prompts[key], {}, 0, vars)


## 对任意文本做 {{xxx}} 替换，并注入动态变量。
func resolve_template_with_vars(text: String, vars: Dictionary) -> String:
	return _resolve_recursive(text, {}, 0, vars)


## 手动注册一个模板片段（resolve 时递归展开内部 {{…}}）。
func register_prompt(key: String, template: String) -> void:
	_prompts[key] = template


## 注册一个全局懒求值 Provider。resolve 时调用 Callable 获取最新值。
## 适合调用方提供的全局动态内容。
## [codeblock]
## PromptManager.register_provider("runtime_context", func():
##     return RuntimeState.get_context())
## [/codeblock]
func register_provider(key: String, provider: Callable) -> void:
	_providers[key] = provider


## 移除一个 Provider。
func remove_provider(key: String) -> void:
	_providers.erase(key)


## 清空所有 Provider。
func clear_all_providers() -> void:
	_providers.clear()


## 检查 key 是否存在（prompt 或 provider）。
func has_prompt(key: String) -> bool:
	return _prompts.has(key) or _providers.has(key)


## 获取所有已注册的 key。
func get_all_keys() -> Array[String]:
	var result: Array[String] = []
	for k in _prompts.keys():
		result.append(str(k))
	return result


## 从目录递归加载所有 .md 文件作为 prompt。
## 子目录中的文件 key 带路径前缀，如 review/display_name。
func _load_prompts_from_dir(dir_path: String, prefix: String = "") -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if dir.current_is_dir() and not file_name.begins_with("."):
			var sub_prefix: String = prefix + file_name + "/"
			_load_prompts_from_dir(dir_path + file_name + "/", sub_prefix)
		elif not dir.current_is_dir() and file_name.ends_with(".md"):
			var key: String = prefix + file_name.get_basename()
			var full_path: String = dir_path + file_name
			var file: FileAccess = FileAccess.open(full_path, FileAccess.READ)
			if file:
				_prompts[key] = file.get_as_text()
				file.close()
		file_name = dir.get_next()
	dir.list_dir_end()


## 从 JSON 文件加载声明式 Provider 绑定。
## JSON 格式：{ "key": { "node": "AutoloadName", "method": "method_name" }, ... }
## 每个条目会在 /root/ 下查找 node，将其 method 包装为 Callable 注册到 _providers。
func _load_providers_from_json(json_path: String) -> void:
	if not FileAccess.file_exists(json_path):
		return
	var file: FileAccess = FileAccess.open(json_path, FileAccess.READ)
	if file == null:
		push_warning("PromptManager: cannot open providers config '%s'" % json_path)
		return
	var text: String = file.get_as_text()
	file.close()

	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		push_warning("PromptManager: failed to parse providers config '%s': %s" % [json_path, json.get_error_message()])
		return
	var data: Variant = json.data
	if not data is Dictionary:
		push_warning("PromptManager: providers config root must be a JSON object")
		return

	for key in data:
		var entry: Variant = data[key]
		if not entry is Dictionary:
			push_warning("PromptManager: provider entry '%s' must be an object" % key)
			continue
		var node_name: String = str(entry.get("node", ""))
		var method_name: String = str(entry.get("method", ""))
		if node_name.is_empty() or method_name.is_empty():
			push_warning("PromptManager: provider entry '%s' missing node or method" % key)
			continue
		var node: Node = get_node_or_null("/root/%s" % node_name)
		if node == null:
			push_warning("PromptManager: provider node '/root/%s' not found for key '%s'" % [node_name, key])
			continue
		if not node.has_method(method_name):
			push_warning("PromptManager: node '%s' has no method '%s' for key '%s'" % [node_name, method_name, key])
			continue
		_providers[str(key)] = Callable(node, method_name)


## 剥离文本中所有 <注释>...</注释> 块。
func _strip_comments(text: String) -> String:
	return _comment_regex.sub(text, "", true)


## 从 JSON 文件加载 seed 词池。
## JSON 格式：{ "group": ["词1", "词2", ...], ... }
func _load_seed_pools(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("PromptManager: cannot open seed pools '%s'" % path)
		return
	var text: String = file.get_as_text()
	file.close()

	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		push_warning("PromptManager: failed to parse seed pools '%s': %s" % [path, json.get_error_message()])
		return
	var data: Variant = json.data
	if not data is Dictionary:
		push_warning("PromptManager: seed pools root must be a JSON object")
		return

	for group_name in data:
		var pool: Variant = data[group_name]
		if pool is Array:
			var typed_pool: Array[String] = []
			for item in pool:
				typed_pool.append(str(item))
			_seed_pools[str(group_name)] = typed_pool


## 将文本中的所有 {{seed:group,N}} 替换为从词池随机抽取的 N 个词。
## 跨调用不重复：已用过的索引会被跳过，直到该组池子耗尽才重置。
func _resolve_seeds(text: String) -> String:
	var matches: Array[RegExMatch] = _seed_regex.search_all(text)
	if matches.is_empty():
		return text

	var result: String = text
	# 从后往前替换，避免偏移量问题
	matches.reverse()
	for m in matches:
		var group_name: String = m.get_string(1)
		var count: int = int(m.get_string(2))
		var pool: Array = _seed_pools.get(group_name, []) as Array
		if pool.is_empty():
			push_warning("PromptManager: seed pool '%s' not found or empty" % group_name)
			continue

		# 获取或初始化该组的已用索引集合
		if not _seed_used.has(group_name):
			_seed_used[group_name] = []
		var used: Array = _seed_used[group_name] as Array

		# 计算可用索引
		var available_indices: Array[int] = []
		for i in pool.size():
			if i not in used:
				available_indices.append(i)

		# 如果可用数量不足，重置该组并重新计算
		if available_indices.size() < count:
			_seed_used[group_name] = []
			used = _seed_used[group_name] as Array
			available_indices.clear()
			for i in pool.size():
				available_indices.append(i)

		# 随机抽取 count 个不重复的词
		var picked: Array[String] = []
		for i in mini(count, available_indices.size()):
			var rand_idx: int = randi() % available_indices.size()
			var pool_idx: int = available_indices[rand_idx]
			picked.append(str(pool[pool_idx]))
			used.append(pool_idx)
			available_indices.remove_at(rand_idx)

		var replacement: String = ", ".join(picked)
		result = result.substr(0, m.get_start()) + replacement + result.substr(m.get_end())

	return result


## 递归替换 {{key}} 模板变量。
## 解析优先级：seed → caller vars → providers → prompts。
## 三者均递归展开内部 {{…}}。
func _resolve_recursive(text: String, visited: Dictionary, depth: int, vars: Dictionary) -> String:
	if depth > MAX_RESOLVE_DEPTH:
		push_warning("PromptManager: max resolve depth exceeded, possible circular reference")
		return text
	
	var result: String = _strip_comments(text)

	# 先处理 {{seed:group,N}} 模式
	result = _resolve_seeds(result)

	var regex: RegEx = RegEx.new()
	regex.compile("\\{\\{([\\w/]+)\\}\\}")
	
	var matches: Array[RegExMatch] = regex.search_all(result)
	if matches.is_empty():
		return result
	
	# 从后往前替换，避免偏移量问题
	matches.reverse()
	for m in matches:
		var key: String = m.get_string(1)

		if visited.has(key):
			push_warning("PromptManager: circular reference detected for key '%s'" % key)
			continue

		# 按优先级查找：caller vars → providers → prompts
		var replacement_text: String = ""
		var found: bool = false

		if vars.has(key):
			replacement_text = str(vars.get(key, ""))
			found = true
		elif _providers.has(key):
			replacement_text = str(_providers[key].call())
			found = true
		elif _prompts.has(key):
			replacement_text = str(_prompts[key])
			found = true

		if not found:
			# 未知 key 保留原样
			continue

		var new_visited: Dictionary = visited.duplicate()
		new_visited[key] = true
		var replacement: String = _resolve_recursive(replacement_text, new_visited, depth + 1, vars)
		# 规范化首尾空白：调用方/Provider 偶发的多余前后换行会让"完全一样的内容"
		# 在不同调用间产生 1-2 个 token 的偏移，从此处起破坏 DeepSeek 缓存前缀命中。
		replacement = replacement.strip_edges()
		result = result.substr(0, m.get_start()) + replacement + result.substr(m.get_end())
	
	return result
