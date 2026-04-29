class_name AIConfigManager extends RefCounted
## AI 配置管理器
## 管理多 profile + role 映射的 AI 服务配置。
## 加载优先级: user://ai_config.cfg > res://ai_config.cfg
## 纯数据类，不需要 .tscn。

const DEFAULT_CONFIG_PATH: String = "res://ai_config.cfg"
const USER_CONFIG_PATH: String = "user://ai_config.cfg"

## 全局单例（生产代码用 get_instance()，测试代码可自行 new() 隔离）
static var _instance: AIConfigManager = null

## 获取全局共享实例，首次调用时自动加载配置。
static func get_instance() -> AIConfigManager:
	if _instance == null:
		_instance = AIConfigManager.new()
		_instance.load_config()
	return _instance

## profile_name -> {base_url, api_key, model}
var _profiles: Dictionary = {}
## role_name -> profile_name
var _roles: Dictionary = {}
## role_name -> 覆盖设置
var _role_settings: Dictionary = {}
## [dev] 节的键值对
var _dev_settings: Dictionary = {}
## 加载来源描述
var _loaded_from: String = ""
## 是否打印加载日志（测试时可设为 false 减少噪音）
var verbose: bool = false


## 获取 [dev] 配置项。
func get_dev_setting(key: String, default_value: Variant = null) -> Variant:
	return _dev_settings.get(key, default_value)


func is_background_llm_disabled() -> bool:
	return _is_truthy(get_dev_setting("disable_background_llm", false))


func is_quiet_logs_enabled() -> bool:
	return _is_truthy(get_dev_setting("quiet_debug_logs", false))


## 加载配置。先加载 res:// 默认配置，再用 user:// 覆盖。
## 返回 true 表示至少加载了一个配置文件。
func load_config() -> bool:
	_profiles.clear()
	_roles.clear()
	_role_settings.clear()
	_dev_settings.clear()
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
	var config: Dictionary = _profiles.get(profile_name, {}).duplicate()
	config.merge(_role_settings.get(role, {}), true)
	return config


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
	ai_service.default_thinking = str(config.get("thinking", "disabled"))
	ai_service.default_enable_thinking = _is_truthy(config.get("enable_thinking", false))
	ai_service.default_reasoning_effort = str(config.get("reasoning_effort", ""))
	for property_info in ai_service.get_property_list():
		if str(property_info.get("name", "")) == "service_role":
			ai_service.set("service_role", role)
			break
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
			_apply_llm_runtime_settings(config, section, _profiles[profile_name])
			if verbose:
				print("[AIConfigManager] Loaded profile: %s" % profile_name)
		elif section == "roles":
			for key in config.get_section_keys("roles"):
				_roles[key] = config.get_value("roles", key, "")
				if verbose:
					print("[AIConfigManager] Loaded role: %s -> %s" % [key, _roles[key]])
		elif section.begins_with("role_settings/"):
			var role_name: String = section.substr("role_settings/".length())
			var role_settings: Dictionary = {}
			_apply_llm_runtime_settings(config, section, role_settings)
			_role_settings[role_name] = role_settings
			if verbose:
				print("[AIConfigManager] Loaded role settings: %s -> %s" % [role_name, str(role_settings)])
		elif section == "dev":
			for key in config.get_section_keys("dev"):
				_dev_settings[key] = config.get_value("dev", key, "")
				if verbose:
					print("[AIConfigManager] Loaded dev setting: %s = %s" % [key, str(_dev_settings[key])])
	
	return true


func _apply_llm_runtime_settings(config: ConfigFile, section: String, target: Dictionary) -> void:
	for key in ["thinking", "enable_thinking", "reasoning_effort"]:
		if config.has_section_key(section, key):
			target[key] = config.get_value(section, key)


func _is_truthy(value: Variant) -> bool:
	match typeof(value):
		TYPE_BOOL:
			return value
		TYPE_INT, TYPE_FLOAT:
			return value != 0
		_:
			var normalized: String = str(value).strip_edges().to_lower()
			return normalized == "true" or normalized == "1" or normalized == "yes" or normalized == "on"
