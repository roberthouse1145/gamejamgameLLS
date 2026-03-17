extends Node
## PromptManager Autoload
## 集中管理所有 prompt 模板，支持 {{key}} 递归替换。
## 启动时自动扫描 res://prompts/ 加载所有 .md 文件。
## 内置环形引用检测。

const PROMPTS_DIR: String = "res://prompts/"
const MAX_RESOLVE_DEPTH: int = 10

## prompt_key -> template_text
var _prompts: Dictionary = {}


func _ready() -> void:
	_load_prompts_from_dir(PROMPTS_DIR)


## 按 key 查找 prompt，递归替换所有 {{xxx}}。
## 找不到 key 返回空字符串。
func resolve(key: String) -> String:
	if not _prompts.has(key):
		push_warning("PromptManager: prompt key '%s' not found" % key)
		return ""
	return _resolve_recursive(_prompts[key], {}, 0)


## 对任意文本做 {{xxx}} 替换。
func resolve_template(text: String) -> String:
	return _resolve_recursive(text, {}, 0)


## 手动注册一个 prompt（代码中动态添加）。
func register_prompt(key: String, template: String) -> void:
	_prompts[key] = template


## 检查 key 是否存在。
func has_prompt(key: String) -> bool:
	return _prompts.has(key)


## 获取所有已注册的 key。
func get_all_keys() -> Array[String]:
	var result: Array[String] = []
	for k in _prompts.keys():
		result.append(str(k))
	return result


## 从目录递归加载所有 .md 文件作为 prompt。
## 子目录中的文件 key 带路径前缀，如 npc/lin_xia。
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


## 递归替换 {{key}} 模板变量。
## visited: 已访问的 key 集合，用于环形引用检测。
## depth: 当前递归深度。
func _resolve_recursive(text: String, visited: Dictionary, depth: int) -> String:
	if depth > MAX_RESOLVE_DEPTH:
		push_warning("PromptManager: max resolve depth exceeded, possible circular reference")
		return text
	
	var result: String = text
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
		
		if not _prompts.has(key):
			# 未知 key 保留原样
			continue
		
		var new_visited: Dictionary = visited.duplicate()
		new_visited[key] = true
		var replacement: String = _resolve_recursive(_prompts[key], new_visited, depth + 1)
		result = result.substr(0, m.get_start()) + replacement + result.substr(m.get_end())
	
	return result
