extends Node
## 人设卡必须通过 StreamerModelResource 提供出镜模型和语义动作能力。

const LIVE_SHOW_PLAYER_SCENE: PackedScene = preload(
	"res://scenes/apps/obs_live/components/live_show_player.tscn"
)


func _ready() -> void:
	var model := StreamerModelResource.new()
	model.model_id = &"test_model"
	model.model_scene = _make_scene("TestModel")
	model.avatar_scene = _make_scene("TestAvatar")
	model.default_expression = &"neutral"
	model.supported_expressions = [&"neutral", &"happy"]
	model.supported_postures = [&"idle"]
	model.supported_gestures = [&"wave"]
	assert(model.is_valid())
	assert(model.has_expression(&"happy"))
	assert(not model.has_expression(&"missing"))

	var persona := StreamPersonaResource.new()
	persona.content_id = &"test_persona"
	persona.display_name = "测试人设"
	persona.icon = _make_texture()
	persona.model = model
	persona.channel_name = "测试频道"
	persona.channel_avatar = _make_texture()
	persona.resting_background = _make_texture()
	assert(persona.is_valid())
	assert(persona.model.model_id == &"test_model")

	persona.model = null
	assert(not persona.is_valid())

	var default_persona := load(
		"res://resources/live_stream/personas/default_persona.tres"
	) as StreamPersonaResource
	assert(default_persona != null)
	assert(default_persona.model != null)
	assert(default_persona.model.model_id == &"platinum")
	assert(default_persona.channel_name == "白星眠")
	assert(default_persona.channel_avatar != null)
	assert(default_persona.resting_background != null)
	var resting_size: Vector2i = default_persona.resting_background.get_image().get_size()
	assert(resting_size.x * 9 == resting_size.y * 16, "resting background must be exact 16:9")
	assert(default_persona.speech_blip is AudioStreamWAV)
	assert(default_persona.speech_blip.resource_path.ends_with(".wav"))
	var show_player := LIVE_SHOW_PLAYER_SCENE.instantiate() as LiveShowPlayer
	add_child(show_player)
	show_player.configure_persona(default_persona)
	var speech_player := show_player.get_node("SpeechBlipPlayer") as AudioStreamPlayer
	assert(speech_player.stream == default_persona.speech_blip)
	assert(is_equal_approx(speech_player.volume_db, default_persona.speech_blip_volume_db))
	assert(show_player._is_spoken_character("你"))
	assert(not show_player._is_spoken_character("，"))
	assert(not show_player._is_spoken_character("。"))
	assert(not show_player._is_spoken_character("“"))
	show_player.queue_free()
	print("PERSONA_MODEL_RESOURCE_TEST_PASS")


func _make_scene(root_name: String) -> PackedScene:
	var root := Node3D.new()
	root.name = root_name
	var scene := PackedScene.new()
	assert(scene.pack(root) == OK)
	root.free()
	return scene


func _make_texture() -> Texture2D:
	var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	return ImageTexture.create_from_image(image)
