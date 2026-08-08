extends Node
## 人设卡必须通过 StreamerModelResource 提供出镜模型和语义动作能力。


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
