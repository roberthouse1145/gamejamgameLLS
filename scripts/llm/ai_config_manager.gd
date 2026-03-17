class_name AIConfigManager extends RefCounted
## AI 配置管理器
## 管理多 profile + role 映射的 AI 服务配置。
## 加载优先级: user://ai_config.cfg > res://ai_config.cfg
## 纯数据类，不需要 .tscn。

const DEFAULT_CONFIG_PATH: String = "res://ai_config.cfg"
const USER_CONFIG_PATH: String = "user://ai_config.cfg"

## profile_name -> {base_url, api_key, model}
var _profiles: Dictionary = {}
## role_name -> profile_name
var _roles: Dictionary = {}
## 加载来源描述
var _loaded_from: String = ""
## 是否打印加载日志（测试时可设为 false 减少噪音）
var verbose: bool = true


## 加载配置。先加载 res:// 默认配置，再用 user:// 覆盖。
## 返回 true 表示至少加载了一个配置文件。
func load_config() -> bool:
	_profiles.clear()
	_roles.clear()
	_loaded_from = ""
	
	var has_default: bool = _load_file(DEFAULT_CONFIG_PATH)
	var has_user: bool = _load_file(USER_CONFIG_PATH)
	
	if has_user:
		_loaded_from = "玩家自定义 + 默认" if has_default else "玩家自定义"
	elif has_default:
		_loaded_from = "默认"
	
	return has_default or has_user


## 获取指定 role 的配置。
## 返回 {base_url, api_key, model}，找不到则返回空 Dictionary。
func get_config_for_role(role: String) -> Dictionary:
	var profile_name: String = _roles.get(role, "")
	if profile_name.is_empty():
		return {}
	return _profiles.get(profile_name, {}).duplicate()


## 将配置应用到 AIService 实例。
## 仅支持 type="chat" 的 profile（OpenAI 兼容 API）。
## 返回 true 表示成功应用。
func apply_to_service(ai_service: Node, role: String) -> bool:
	var config: Dictionary = get_config_for_role(role)
	if config.is_empty():
		push_warning("AIConfigManager: No config found for role '%s'" % role)
		return false
	
	var profile_type: String = config.get("type", "chat")
	if profile_type != "chat":
		push_warning("AIConfigManager: Role '%s' uses type '%s', but AIService only supports 'chat'" % [role, profile_type])
		return false
	
	ai_service.api_base_url = config.get("base_url", "")
	ai_service.api_key = config.get("api_key", "")
	ai_service.model = config.get("model", "")
	return true


## 将配置应用到 ArtAIService 实例。
## 仅支持 type="image" 的 profile。
## 返回 true 表示成功应用。
func apply_to_art_service(art_service: Node, role: String) -> bool:
	var config: Dictionary = get_config_for_role(role)
	if config.is_empty():
		push_warning("AIConfigManager: No config found for role '%s'" % role)
		return false
	
	var profile_type: String = config.get("type", "chat")
	if profile_type != "image":
		push_warning("AIConfigManager: Role '%s' uses type '%s', but ArtAIService requires 'image'" % [role, profile_type])
		return false
	
	art_service.api_base_url = config.get("base_url", "")
	art_service.api_key = config.get("api_key", "")
	art_service.model = config.get("model", "")
	return true


## 获取所有已注册的 role 名称。
func get_roles() -> Array[String]:
	var result: Array[String] = []
	for key in _roles.keys():
		result.append(str(key))
	return result


## 获取所有已注册的 profile 名称。
func get_profiles() -> Array[String]:
	var result: Array[String] = []
	for key in _profiles.keys():
		result.append(str(key))
	return result


## 获取加载来源描述。
func get_loaded_from() -> String:
	return _loaded_from


## 加载单个配置文件，合并到当前状态（后加载的覆盖先加载的）。
func _load_file(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	
	var config: ConfigFile = ConfigFile.new()
	var err: Error = config.load(path)
	if err != OK:
		push_warning("AIConfigManager: Failed to load config: %s" % path)
		return false
	
	# 解析 profiles
	var sections: PackedStringArray = config.get_sections()
	if verbose:
		print("[AIConfigManager] Loaded sections from %s: %s" % [path, str(sections)])
	for section in sections:
		if section.begins_with("profiles/"):
			var profile_name: String = section.substr("profiles/".length())
			_profiles[profile_name] = {
				"type": config.get_value(section, "type", "chat"),
				"base_url": config.get_value(section, "base_url", ""),
				"api_key": config.get_value(section, "api_key", ""),
				"model": config.get_value(section, "model", ""),
			}
			if verbose:
				print("[AIConfigManager] Loaded profile: %s" % profile_name)
		elif section == "roles":
			for key in config.get_section_keys("roles"):
				_roles[key] = config.get_value("roles", key, "")
				if verbose:
					print("[AIConfigManager] Loaded role: %s -> %s" % [key, _roles[key]])
	
	return true
