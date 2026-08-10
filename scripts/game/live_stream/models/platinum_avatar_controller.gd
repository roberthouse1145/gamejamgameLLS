class_name PlatinumAvatarController extends Node3D
## Platinum 模型的语义动画控制器。
## 对外只暴露姿态、手臂姿势、头部姿势、手势、表情、口型和服装，不泄漏骨骼或 Shape Key 名称。
## 动画数据由 avatar 场景自带的 AnimationPlayer 动画库与 AnimationTree 混合树资源提供，
## 本脚本只做语义映射与播放控制，不创建动画节点。

signal avatar_ready()


## DSL 表情名 → 表情状态机状态。允许多个语义名共享同一状态。
const EXPRESSION_STATES: Dictionary = {
	&"default": &"neutral",
	&"neutral": &"neutral",
	&"smile": &"smile",
	&"happy": &"happy",
	&"laugh": &"laugh",
	&"excited": &"excited",
	&"embarrassed": &"embarrassed",
	&"shy": &"embarrassed",
	&"worried": &"worried",
	&"strained": &"worried",
	&"sad": &"sad",
	&"angry": &"angry",
	&"serious": &"serious",
	&"surprised": &"surprised",
	&"shocked": &"shocked",
	&"panicked": &"panicked",
	&"thinking": &"thinking",
	&"smug": &"smug",
	&"love": &"love",
	&"wink": &"wink",
	&"sleepy": &"sleepy",
	&"teasing": &"teasing",
	&"dizzy": &"dizzy",
}


## 服装 → 网格可见性与贴图替换。当前仅使用模型默认外观，暂无额外服装。
const COSTUME_CONFIGS: Dictionary = {}
const ILLUSTRATION_SHADER: Shader = preload(
	"res://scenes/game/live_stream/models/streamer_illustration.gdshader"
)

@export var model_resource: StreamerModelResource = null

@onready var _model_anchor: Node3D = %ModelAnchor

var _model: Node3D = null
var _animation_player: AnimationPlayer = null
var _animation_tree: AnimationTree = null
var _posture_playback: AnimationNodeStateMachinePlayback = null
var _arm_playback: AnimationNodeStateMachinePlayback = null
var _head_playback: AnimationNodeStateMachinePlayback = null
var _emotion_playback: AnimationNodeStateMachinePlayback = null
var _gesture_clip: AnimationNodeAnimation = null
var _posture: StringName = &"idle"
var _arm_pose: StringName = &"idle"
var _head_pose: StringName = &"idle"
var _expression: StringName = &"neutral"
var _costume: StringName = &""
var _mouth_amount: float = 0.0
var _mouth_target: float = 0.0
var _initialized: bool = false
var _pending_gesture: StringName = &""


func _ready() -> void:
	if model_resource != null:
		_initialize()


func _process(delta: float) -> void:
	if _animation_tree == null:
		return
	_mouth_amount = move_toward(_mouth_amount, _mouth_target, delta / 0.08)
	_animation_tree.set("parameters/MouthLayer/add_amount", _mouth_amount)
	_flush_pending_gesture()


func setup(resource: StreamerModelResource) -> bool:
	if resource == null or not resource.is_valid():
		return false
	if _initialized:
		return resource == model_resource
	model_resource = resource
	_initialize()
	return _initialized


func set_expression(expression_name: StringName, _duration: float = -1.0) -> bool:
	if model_resource == null or not model_resource.has_expression(expression_name):
		return false
	if not EXPRESSION_STATES.has(expression_name):
		return false
	_expression = expression_name
	var state := StringName(str(EXPRESSION_STATES.get(expression_name, &"neutral")))
	if _emotion_playback != null:
		_emotion_playback.travel(state)
	return true


func set_posture(posture_name: StringName) -> bool:
	if model_resource == null or posture_name not in model_resource.supported_postures:
		return false
	if not _has_clip(StringName("posture_%s" % posture_name)):
		return false
	_posture = posture_name
	if _posture_playback != null:
		_posture_playback.travel(posture_name)
	return true


## 切换持续手臂姿势（与身体姿态独立，可任意组合）。
func set_arm_pose(pose_name: StringName) -> bool:
	if model_resource == null or pose_name not in model_resource.supported_arm_poses:
		return false
	if not _has_clip(StringName("arm_%s" % pose_name)):
		return false
	_arm_pose = pose_name
	if _arm_playback != null:
		_arm_playback.travel(pose_name)
	return true


## 切换持续头部姿势（与身体姿态、手臂姿势独立，可任意组合）。
func set_head_pose(pose_name: StringName) -> bool:
	if model_resource == null or pose_name not in model_resource.supported_head_poses:
		return false
	if not _has_clip(StringName("head_%s" % pose_name)):
		return false
	_head_pose = pose_name
	if _head_playback != null:
		_head_playback.travel(pose_name)
	return true


func _has_clip(clip_name: StringName) -> bool:
	if _animation_player == null:
		return false
	return _animation_player.has_animation(clip_name)


func play_gesture(gesture_name: StringName) -> bool:
	if (
		_animation_tree == null
		or _gesture_clip == null
		or model_resource == null
		or gesture_name not in model_resource.supported_gestures
		or not _has_clip(StringName("gesture_%s" % gesture_name))
	):
		return false
	# OneShot 播放中直接改 animation 会硬切；先淡出回姿态，再启动新手势。
	if bool(_animation_tree.get("parameters/Gesture/active")):
		_pending_gesture = gesture_name
		_animation_tree.set(
			"parameters/Gesture/request",
			AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT
		)
		return true
	_pending_gesture = &""
	_fire_gesture(gesture_name)
	return true


func _fire_gesture(gesture_name: StringName) -> void:
	_gesture_clip.animation = StringName("gesture_%s" % gesture_name)
	_animation_tree.set(
		"parameters/Gesture/request",
		AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE
	)


func _flush_pending_gesture() -> void:
	if _pending_gesture == &"":
		return
	if bool(_animation_tree.get("parameters/Gesture/active")):
		return
	var next_gesture: StringName = _pending_gesture
	_pending_gesture = &""
	_fire_gesture(next_gesture)


func set_costume(costume_name: StringName) -> bool:
	if model_resource == null or not model_resource.has_costume(costume_name):
		return false
	if not COSTUME_CONFIGS.has(costume_name):
		return false
	_costume = costume_name
	if _initialized:
		_apply_costume()
	return true


func set_talking(enabled: bool) -> void:
	_mouth_target = 1.0 if enabled else 0.0
	if not enabled:
		_mouth_amount = 0.0
		if _animation_tree != null:
			_animation_tree.set("parameters/MouthLayer/add_amount", 0.0)


func get_current_expression() -> StringName:
	return _expression


func get_current_posture() -> StringName:
	return _posture


func get_current_arm_pose() -> StringName:
	return _arm_pose


func get_current_head_pose() -> StringName:
	return _head_pose


func get_current_costume() -> StringName:
	return _costume


func is_initialized() -> bool:
	return _initialized


func _initialize() -> void:
	if _initialized or model_resource == null or not model_resource.is_valid():
		return
	# 优先复用场景中嵌入的模型实例；没有才从资源实例化（兼容旧用法）。
	if _model_anchor.get_child_count() > 0:
		_model = _model_anchor.get_child(0) as Node3D
	if _model == null:
		_model = model_resource.model_scene.instantiate() as Node3D
		if _model == null:
			return
		_model_anchor.add_child(_model)
	_model_anchor.position = model_resource.model_position
	_model_anchor.rotation_degrees = model_resource.model_rotation_degrees
	# 动画由 avatar 场景自带的 AnimationPlayer/AnimationTree 资源提供。
	_animation_player = _model.get_node_or_null("AnimationPlayer") as AnimationPlayer
	_animation_tree = _model.get_node_or_null("AnimationTree") as AnimationTree
	if _animation_player == null or _animation_tree == null:
		push_error("Platinum avatar 场景缺少模型内的 AnimationPlayer/AnimationTree 节点")
		return
	if COSTUME_CONFIGS.has(model_resource.default_costume):
		_costume = model_resource.default_costume
	_apply_costume()
	_initialized = true
	call_deferred("_start_animation_graph")



func _apply_costume() -> void:
	if _model == null:
		return
	var config: Dictionary = COSTUME_CONFIGS.get(_costume, {})
	var hidden: Array = config.get("hidden_meshes", [])
	var texture_map: Dictionary = config.get("material_textures", {})
	var hideable: Array[StringName] = _collect_hideable_meshes()
	for node: Node in _model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		if mesh_instance.name in hideable:
			mesh_instance.visible = mesh_instance.name not in hidden
		for surface: int in range(mesh_instance.mesh.get_surface_count()):
			mesh_instance.set_surface_override_material(surface, null)
			var surface_material: Material = mesh_instance.mesh.surface_get_material(surface)
			if surface_material == null:
				continue
			var material_name := StringName(surface_material.resource_name)
			var replace_texture: bool = texture_map.has(material_name)
			var apply_illustration: bool = _should_apply_illustration(
				surface_material,
				material_name
			)
			if not replace_texture and not apply_illustration:
				continue
			var override: Material = surface_material
			if replace_texture:
				override = surface_material.duplicate() as Material
				var texture: Texture2D = load(str(texture_map[material_name])) as Texture2D
				if texture != null:
					_set_material_albedo(override, texture)
			if apply_illustration:
				override = _create_illustration_material(override as BaseMaterial3D)
			mesh_instance.set_surface_override_material(surface, override)


func _should_apply_illustration(source_material: Material, material_name: StringName) -> bool:
	if model_resource == null or not model_resource.illustration_enabled:
		return false
	if not source_material is BaseMaterial3D:
		return false
	var lowered_name := String(material_name).to_lower()
	for fragment: String in model_resource.illustration_material_fragments:
		if lowered_name.contains(fragment.to_lower()):
			return true
	return false


func _create_illustration_material(source_material: BaseMaterial3D) -> ShaderMaterial:
	if source_material == null or model_resource == null:
		return null
	var target_material := ShaderMaterial.new()
	target_material.shader = ILLUSTRATION_SHADER
	target_material.resource_name = "%s_illustration" % source_material.resource_name
	target_material.render_priority = source_material.render_priority
	if source_material.albedo_texture != null:
		target_material.set_shader_parameter("albedo_texture", source_material.albedo_texture)
	target_material.set_shader_parameter("albedo_color", source_material.albedo_color)
	target_material.set_shader_parameter(
		"uv_transform",
		Vector4(
			source_material.uv1_scale.x,
			source_material.uv1_scale.y,
			source_material.uv1_offset.x,
			source_material.uv1_offset.y
		)
	)
	target_material.set_shader_parameter(
		"shadow_tint",
		model_resource.illustration_shadow_tint
	)
	target_material.set_shader_parameter(
		"light_direction_view",
		model_resource.illustration_light_direction_view
	)
	target_material.set_shader_parameter(
		"shade_threshold",
		model_resource.illustration_shade_threshold
	)
	target_material.set_shader_parameter(
		"shade_softness",
		model_resource.illustration_shade_softness
	)
	target_material.set_shader_parameter(
		"shade_strength",
		model_resource.illustration_shade_strength
	)
	target_material.set_shader_parameter(
		"alpha_cutoff",
		source_material.alpha_scissor_threshold
	)
	return target_material


func _collect_hideable_meshes() -> Array[StringName]:
	var names: Array[StringName] = []
	for costume_name: StringName in COSTUME_CONFIGS:
		var config: Dictionary = COSTUME_CONFIGS[costume_name]
		for mesh_name: Variant in config.get("hidden_meshes", []):
			var value := StringName(str(mesh_name))
			if value not in names:
				names.append(value)
	return names


func _set_material_albedo(target_material: Material, texture: Texture2D) -> void:
	var shader_material := target_material as ShaderMaterial
	if shader_material != null:
		if shader_material.get_shader_parameter("_MainTex") != null:
			shader_material.set_shader_parameter("_MainTex", texture)
		if shader_material.get_shader_parameter("_ShadeTexture") != null:
			shader_material.set_shader_parameter("_ShadeTexture", texture)
		return
	var standard_material := target_material as BaseMaterial3D
	if standard_material != null:
		standard_material.albedo_texture = texture



func _start_animation_graph() -> void:
	if _animation_tree == null:
		return
	var blend_tree := _animation_tree.tree_root as AnimationNodeBlendTree
	if blend_tree == null:
		return
	_gesture_clip = blend_tree.get_node(&"GestureClip") as AnimationNodeAnimation
	_posture_playback = _animation_tree.get(
		"parameters/Posture/playback"
	) as AnimationNodeStateMachinePlayback
	_arm_playback = _animation_tree.get(
		"parameters/Arm/playback"
	) as AnimationNodeStateMachinePlayback
	_head_playback = _animation_tree.get(
		"parameters/Head/playback"
	) as AnimationNodeStateMachinePlayback
	_emotion_playback = _animation_tree.get(
		"parameters/Emotion/playback"
	) as AnimationNodeStateMachinePlayback
	if (
		_posture_playback == null
		or _arm_playback == null
		or _head_playback == null
		or _emotion_playback == null
	):
		return
	var emotion_state := StringName(str(EXPRESSION_STATES.get(_expression, &"neutral")))
	_posture_playback.start(_posture)
	_arm_playback.start(_arm_pose)
	_head_playback.start(_head_pose)
	_emotion_playback.start(emotion_state)
	_animation_tree.set("parameters/ArmLayer/add_amount", 1.0)
	_animation_tree.set("parameters/HeadLayer/add_amount", 1.0)
	_animation_tree.set("parameters/EmotionLayer/add_amount", 1.0)
	_animation_tree.set("parameters/MouthLayer/add_amount", _mouth_amount)
	_animation_tree.set("parameters/BlinkLayer/add_amount", 1.0)
	avatar_ready.emit()
