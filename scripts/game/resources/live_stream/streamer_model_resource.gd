class_name StreamerModelResource extends Resource
## 主播模型及其演出配置。人设只引用本资源，不关心具体模型实现。

@export var model_id: StringName = &""
@export var model_scene: PackedScene = null
## 实现统一语义动作接口的模型控制场景。
@export var avatar_scene: PackedScene = null
@export var default_expression: StringName = &"neutral"
@export var supported_expressions: Array[StringName] = []
@export var supported_postures: Array[StringName] = []
@export var supported_arm_poses: Array[StringName] = []
@export var supported_head_poses: Array[StringName] = []
@export var supported_gestures: Array[StringName] = []
@export var default_costume: StringName = &""
@export var supported_costumes: Array[StringName] = []

@export_group("Model Placement")
@export var model_position: Vector3 = Vector3.ZERO
@export var model_rotation_degrees: Vector3 = Vector3.ZERO

@export_group("Camera")
@export var camera_position: Vector3 = Vector3(0.0, 1.33, 3.15)
@export var camera_target: Vector3 = Vector3(0.0, 1.33, 0.0)
@export_range(1.0, 120.0, 0.5) var camera_fov: float = 24.0
@export var camera_orthogonal: bool = false
@export_range(0.1, 10.0, 0.01) var camera_orthogonal_size: float = 1.0

@export_group("Illustration Rendering")
## 仅将匹配的材质替换为固定两色色阶；脸、头发等未匹配材质保留原贴图显示。
@export var illustration_enabled: bool = false
@export var illustration_material_fragments: PackedStringArray = PackedStringArray()
@export var illustration_shadow_tint: Color = Color(0.82, 0.86, 0.94, 1.0)
@export var illustration_light_direction_view: Vector3 = Vector3(-0.25, 0.45, 0.86)
@export_range(0.0, 1.0, 0.01) var illustration_shade_threshold: float = 0.48
@export_range(0.0, 0.5, 0.01) var illustration_shade_softness: float = 0.06
@export_range(0.0, 1.0, 0.01) var illustration_shade_strength: float = 0.16
@export var outline_color: Color = Color(0.045, 0.055, 0.085, 1.0)
@export_range(0.0, 12.0, 0.5) var outline_width_px: float = 3.0

@export_group("Studio Lighting")
@export var ambient_light_color: Color = Color(0.42, 0.50, 0.72, 1.0)
@export_range(0.0, 4.0, 0.05) var ambient_light_energy: float = 0.55
@export var key_light_color: Color = Color(1.0, 0.93, 0.86, 1.0)
@export_range(0.0, 8.0, 0.05) var key_light_energy: float = 1.15
@export var key_light_rotation_degrees: Vector3 = Vector3(-18.0, -22.0, 0.0)
@export var rim_light_color: Color = Color(0.36, 0.58, 1.0, 1.0)
@export_range(0.0, 8.0, 0.05) var rim_light_energy: float = 0.0


func has_expression(expression_name: StringName) -> bool:
	return expression_name in supported_expressions


func has_costume(costume_name: StringName) -> bool:
	return costume_name in supported_costumes


func get_expression_names() -> Array[StringName]:
	return supported_expressions.duplicate()


func is_valid() -> bool:
	return (
		not String(model_id).strip_edges().is_empty()
		and model_scene != null
		and avatar_scene != null
		and has_expression(default_expression)
	)
