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
