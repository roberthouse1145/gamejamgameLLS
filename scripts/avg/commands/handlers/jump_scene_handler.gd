extends CommandHandler
class_name JumpSceneHandler
## Handler for JUMP_SCENE command
## Jumps to a different scene with optional transition effect.

const ParamDef = preload("res://scripts/avg/commands/param_definition.gd")


func _init() -> void:
	super._init("JUMP_SCENE")


## Create the parameter schema for JUMP_SCENE command
func _create_schema() -> ParamSchemaClass:
	var schema := ParamSchemaClass.new(
		command_type,
		"Jumps to a different scene with optional transition"
	)
	
	schema.add_param(ParamDef.scene_ref_param(
		"scene_id",
		"The scene ID to jump to",
		true,
		"目标场景"
	))
	
	schema.add_param(ParamDef.choices_param(
		"transition",
		["", "fade", "dissolve", "wipe_left", "wipe_right", "wipe_up", "wipe_down"],
		"Transition type (empty = hard cut)",
		false,
		"",
		"转场效果"
	))
	
	schema.add_param(ParamDef.float_param(
		"duration",
		"Transition duration in seconds",
		false,
		1.0,
		"转场时长"
	))
	
	schema.add_param(ParamDef.color_param(
		"color",
		"Transition color",
		false,
		Color.BLACK,
		"转场颜色"
	))
	
	return schema


## Execute the JUMP_SCENE command
func execute(command: Resource, context: RefCounted) -> CommandResultClass:
	var scene_id: String = _get_param(command, "scene_id", "")
	var transition: String = _get_param(command, "transition", "")
	var duration: float = _get_param(command, "duration", 1.0)
	var color: Color = _get_param(command, "color", Color.BLACK)
	
	if scene_id.is_empty():
		return CommandResultClass.error("scene_id is required for JUMP_SCENE command")
	
	# 如果有转场效果，先设置转场参数到 runner
	if not transition.is_empty() and context.scene_runner != null and context.scene_runner.has_method("set_jump_transition"):
		context.scene_runner.set_jump_transition(transition, duration, color)
	
	# 执行跳转
	if context.has_method("jump_to_scene"):
		context.jump_to_scene(scene_id)
	else:
		push_warning("JumpSceneHandler: jump_to_scene method not available in context")
	
	return CommandResultClass.ok({"jump_scene": scene_id, "transition": transition})
