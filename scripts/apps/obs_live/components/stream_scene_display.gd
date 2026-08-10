class_name StreamSceneDisplay extends Control
## 直播画面的背景与 3D 主播模型承载层。

@export var background_texture: Texture2D = null

@onready var _background: TextureRect = %Background
@onready var _avatar_root: Node3D = %AvatarRoot
@onready var _camera: Camera3D = %AvatarCamera
@onready var _avatar_viewport_container: SubViewportContainer = %AvatarViewportContainer
@onready var _world_environment: WorldEnvironment = $AvatarViewportContainer/AvatarViewport/WorldEnvironment
@onready var _key_light: DirectionalLight3D = $AvatarViewportContainer/AvatarViewport/KeyLight
@onready var _rim_light: OmniLight3D = $AvatarViewportContainer/AvatarViewport/RimLight

var _model_resource: StreamerModelResource = null
var _avatar: Node3D = null
var _current_expression: StringName = &""
var _avatar_graph_ready: bool = false
var _avatar_visible: bool = true


func _ready() -> void:
	_background.texture = background_texture
	_apply_avatar_visibility()


func setup(model_resource: StreamerModelResource) -> bool:
	_clear_avatar()
	_model_resource = model_resource
	if _model_resource == null or not _model_resource.is_valid():
		return false
	_apply_render_profile()
	_camera.position = _model_resource.camera_position
	_camera.fov = _model_resource.camera_fov
	if _model_resource.camera_orthogonal:
		_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		_camera.size = _model_resource.camera_orthogonal_size
	else:
		_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	_camera.look_at(_model_resource.camera_target)
	_avatar = _model_resource.avatar_scene.instantiate() as Node3D
	if _avatar == null:
		return false
	_avatar_graph_ready = false
	if _avatar.has_signal("avatar_ready"):
		_avatar.avatar_ready.connect(_on_avatar_ready, CONNECT_ONE_SHOT)
	_avatar_root.add_child(_avatar)
	if not _avatar.has_method("setup") or not bool(_avatar.call("setup", _model_resource)):
		_clear_avatar()
		return false
	_current_expression = &""
	_apply_avatar_visibility()
	return set_expression(_model_resource.default_expression, 0.0)


func _apply_render_profile() -> void:
	if _model_resource == null:
		return
	if _world_environment.environment != null:
		var environment := _world_environment.environment.duplicate() as Environment
		environment.ambient_light_color = _model_resource.ambient_light_color
		environment.ambient_light_energy = _model_resource.ambient_light_energy
		_world_environment.environment = environment
	_key_light.light_color = _model_resource.key_light_color
	_key_light.light_energy = _model_resource.key_light_energy
	_key_light.rotation_degrees = _model_resource.key_light_rotation_degrees
	_rim_light.light_color = _model_resource.rim_light_color
	_rim_light.light_energy = _model_resource.rim_light_energy
	var outline_material := _avatar_viewport_container.material as ShaderMaterial
	if outline_material != null:
		outline_material = outline_material.duplicate() as ShaderMaterial
		outline_material.set_shader_parameter("outline_color", _model_resource.outline_color)
		outline_material.set_shader_parameter("outline_width_px", _model_resource.outline_width_px)
		_avatar_viewport_container.material = outline_material


func wait_for_avatar_ready() -> void:
	if _avatar_graph_ready or _avatar == null:
		return
	if _avatar.has_signal("avatar_ready"):
		await _avatar.avatar_ready
		return
	await get_tree().process_frame


func set_background(texture: Texture2D) -> void:
	background_texture = texture
	if _background != null:
		_background.texture = texture


func set_avatar_visible(visible_value: bool) -> void:
	_avatar_visible = visible_value
	_apply_avatar_visibility()


func set_expression(expression_name: StringName, duration: float = -1.0) -> bool:
	if (
		_model_resource == null
		or _avatar == null
		or not _model_resource.has_expression(expression_name)
		or not _avatar.has_method("set_expression")
	):
		return false
	if not bool(_avatar.call("set_expression", expression_name, duration)):
		return false
	_current_expression = expression_name
	return true


func set_talking(enabled: bool) -> void:
	if _avatar != null and _avatar.has_method("set_talking"):
		_avatar.call("set_talking", enabled)


func set_posture(posture_name: StringName) -> bool:
	if _avatar == null or not _avatar.has_method("set_posture"):
		return false
	return bool(_avatar.call("set_posture", posture_name))


func set_arm_pose(pose_name: StringName) -> bool:
	if _avatar == null or not _avatar.has_method("set_arm_pose"):
		return false
	return bool(_avatar.call("set_arm_pose", pose_name))


func set_head_pose(pose_name: StringName) -> bool:
	if _avatar == null or not _avatar.has_method("set_head_pose"):
		return false
	return bool(_avatar.call("set_head_pose", pose_name))


func play_gesture(gesture_name: StringName) -> bool:
	if _avatar == null or not _avatar.has_method("play_gesture"):
		return false
	return bool(_avatar.call("play_gesture", gesture_name))


func set_costume(costume_name: StringName) -> bool:
	if _avatar == null or not _avatar.has_method("set_costume"):
		return false
	return bool(_avatar.call("set_costume", costume_name))


func get_current_expression() -> StringName:
	return _current_expression


func get_model_resource() -> StreamerModelResource:
	return _model_resource


func _apply_avatar_visibility() -> void:
	if _avatar_viewport_container != null:
		_avatar_viewport_container.visible = _avatar_visible


func _clear_avatar() -> void:
	_avatar_graph_ready = false
	if _avatar != null and is_instance_valid(_avatar):
		_avatar.queue_free()
	_avatar = null
	_current_expression = &""


func _on_avatar_ready() -> void:
	_avatar_graph_ready = true
