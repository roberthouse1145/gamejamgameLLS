extends Node

const REQUIRED_ROLES: Array[String] = [
	"chat_default",
	"avg_scene_writer",
	"dsl_repair",
]


func _ready() -> void:
	var config_manager := AIConfigManager.new()
	_assert(config_manager.load_config(), "AI config can be loaded")
	for role in REQUIRED_ROLES:
		var config: Dictionary = config_manager.get_config_for_role(role)
		_assert(not config.is_empty(), "role '%s' resolves to a profile" % role)
		_assert(not str(config.get("base_url", "")).is_empty(), "role '%s' has base_url" % role)
		_assert(not str(config.get("model", "")).is_empty(), "role '%s' has model" % role)


func _assert(condition: bool, message: String) -> void:
	if condition:
		print("[PASS] %s" % message)
	else:
		push_error("[FAIL] %s" % message)
