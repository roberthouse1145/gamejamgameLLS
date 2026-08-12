extends Node
## 只验证玩家配置的稳定契约：默认值、独立字段与跨实例持久化。

const PlayerConfigScript = preload("res://autoload/player_config.gd")
const TEST_CONFIG_PATH: String = "user://test_player_config.cfg"


func _ready() -> void:
	_remove_test_config()

	var writer: Node = PlayerConfigScript.new(TEST_CONFIG_PATH)
	assert(writer.is_screen_chat_enabled())
	assert(writer.is_donation_animation_enabled())
	assert(writer.set_screen_chat_enabled(false) == OK)
	assert(writer.set_donation_animation_enabled(false) == OK)

	var reader: Node = PlayerConfigScript.new(TEST_CONFIG_PATH)
	assert(reader.reload() == OK)
	assert(not reader.is_screen_chat_enabled())
	assert(not reader.is_donation_animation_enabled())
	assert(reader.set_screen_chat_enabled(true) == OK)

	var second_reader: Node = PlayerConfigScript.new(TEST_CONFIG_PATH)
	assert(second_reader.reload() == OK)
	assert(second_reader.is_screen_chat_enabled())
	assert(not second_reader.is_donation_animation_enabled())

	writer.free()
	reader.free()
	second_reader.free()
	_remove_test_config()
	print("PLAYER_CONFIG_TEST_PASS")


func _remove_test_config() -> void:
	var absolute_path: String = ProjectSettings.globalize_path(TEST_CONFIG_PATH)
	if FileAccess.file_exists(TEST_CONFIG_PATH):
		var error: Error = DirAccess.remove_absolute(absolute_path)
		assert(error == OK)
