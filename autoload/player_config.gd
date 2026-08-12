extends Node
## 玩家长期偏好的统一持久化入口。

signal setting_changed(section: StringName, key: StringName, value: Variant)

const DEFAULT_CONFIG_PATH: String = "user://player_config.cfg"
const LIVE_STREAM_SECTION: StringName = &"live_stream"
const SCREEN_CHAT_KEY: StringName = &"screen_chat_enabled"
const DONATION_ANIMATION_KEY: StringName = &"donation_animation_enabled"

var _config_path: String = DEFAULT_CONFIG_PATH
var _config := ConfigFile.new()


func _init(config_path: String = DEFAULT_CONFIG_PATH) -> void:
	_config_path = config_path


func _ready() -> void:
	reload()


func reload() -> Error:
	_config = ConfigFile.new()
	var error: Error = _config.load(_config_path)
	if error == ERR_FILE_NOT_FOUND:
		return OK
	if error != OK:
		push_warning("PlayerConfig: failed to load %s (%s)" % [_config_path, error_string(error)])
	return error


func is_screen_chat_enabled() -> bool:
	return bool(_config.get_value(LIVE_STREAM_SECTION, SCREEN_CHAT_KEY, true))


func set_screen_chat_enabled(enabled: bool) -> Error:
	return _set_bool(LIVE_STREAM_SECTION, SCREEN_CHAT_KEY, enabled, true)


func is_donation_animation_enabled() -> bool:
	return bool(_config.get_value(LIVE_STREAM_SECTION, DONATION_ANIMATION_KEY, true))


func set_donation_animation_enabled(enabled: bool) -> Error:
	return _set_bool(LIVE_STREAM_SECTION, DONATION_ANIMATION_KEY, enabled, true)


func get_config_path() -> String:
	return _config_path


func _set_bool(section: StringName, key: StringName, value: bool, default_value: bool) -> Error:
	var current_value: bool = bool(_config.get_value(section, key, default_value))
	if current_value == value and _config.has_section_key(section, key):
		return OK
	_config.set_value(section, key, value)
	var error: Error = _config.save(_config_path)
	if error != OK:
		push_warning("PlayerConfig: failed to save %s (%s)" % [_config_path, error_string(error)])
		return error
	setting_changed.emit(section, key, value)
	return OK
