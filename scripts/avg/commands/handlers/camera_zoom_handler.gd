extends CommandHandler
class_name CameraZoomHandler
## Handler for CAMERA_ZOOM command
## 缩放摄像机，支持语义化焦点目标（角色名 / "center" / "between"）或自动推断

const ParamDef = preload("res://scripts/avg/commands/param_definition.gd")


func _init() -> void:
	super._init("CAMERA_ZOOM")


func _create_schema() -> ParamSchemaClass:
	var schema := ParamSchemaClass.new(command_type, "Zoom camera to focus point")
	schema.add_param(ParamDef.float_param("zoom", "Zoom level (1.0=default, 2.0=2x)", true, 1.5, "缩放倍数"))
	schema.add_param(ParamDef.string_param("focus", "Focus target: character name / 'center' / 'between' (auto-infer if omitted)", false, "", "", "聚焦目标"))
	schema.add_param(ParamDef.float_param("focus_x", "Focus X (0~1, 0.5=center)", false, 0.5, "焦点X"))
	schema.add_param(ParamDef.float_param("focus_y", "Focus Y (0~1, 0.5=center)", false, 0.5, "焦点Y"))
	schema.add_param(ParamDef.float_param("duration", "Animation duration (0=instant)", false, 1.0, "时长"))
	return schema


func execute(command: Resource, context: RefCounted) -> CommandResultClass:
	var zoom: float = _get_param(command, "zoom", 1.5)
	var duration: float = _get_param(command, "duration", 1.0)
	var runner: Node = context.scene_runner
	if runner == null:
		return CommandResultClass.error("CAMERA_ZOOM: no scene_runner")

	var focus_pos: Vector2 = _resolve_focus(command, runner)
	runner.camera_zoom(zoom, focus_pos.x, focus_pos.y, duration)
	return CommandResultClass.ok()


## 解析焦点目标，返回归一化坐标 (0~1)
## 优先级：显式 focus_x/focus_y > 语义化 focus 参数 > 自动推断
func _resolve_focus(command: Resource, runner: Node) -> Vector2:
	# 1. 显式坐标覆盖（向后兼容）
	if command != null and command.params != null and (command.params.has("focus_x") or command.params.has("focus_y")):
		return Vector2(
			_get_param(command, "focus_x", 0.5),
			_get_param(command, "focus_y", 0.5)
		)

	var char_display: Control = runner.character_display if runner else null
	var focus_str: String = str(_get_param(command, "focus", "")).strip_edges()

	# 2. 语义化焦点目标
	if not focus_str.is_empty():
		if focus_str == "center":
			return Vector2(0.5, 0.5)
		if focus_str == "between":
			if char_display and char_display.has_method("get_between_focus_point"):
				return char_display.get_between_focus_point()
			return Vector2(0.5, 0.5)
		# 尝试作为角色名解析 — 基于精灵实际渲染位置 + 面部偏移
		if char_display and char_display.has_method("get_character_focus_point"):
			return char_display.get_character_focus_point(focus_str)
		return Vector2(0.5, 0.5)

	# 3. 自动推断：无焦点参数时，单角色聚焦该角色，否则居中
	if char_display and char_display.has_method("get_all_character_states"):
		var all_states: Dictionary = char_display.get_all_character_states()
		if all_states.size() == 1:
			var only_id: String = all_states.keys()[0]
			if char_display.has_method("get_character_focus_point"):
				return char_display.get_character_focus_point(only_id)

	return Vector2(0.5, 0.5)
