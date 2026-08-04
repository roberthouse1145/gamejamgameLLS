extends CommandHandler
class_name ChangeBackgroundHandler
## Handler for CHANGE_BACKGROUND command
## Changes the scene background with optional shader transition.

const ParamDef = preload("res://scripts/avg/commands/param_definition.gd")


func _init() -> void:
	super._init("CHANGE_BACKGROUND")


## Create the parameter schema for CHANGE_BACKGROUND command
func _create_schema() -> ParamSchemaClass:
	var schema := ParamSchemaClass.new(
		command_type,
		"Changes the scene background with optional transition"
	)
	
	schema.add_param(ParamDef.texture_param(
		"texture",
		"The background texture to display",
		false,
		"背景图"
	))
	schema.add_param(ParamDef.string_param(
		"texture_path",
		"Path or alias of the background texture",
		false,
		"",
		"",
		"背景路径"
	))
	
	schema.add_param(ParamDef.float_param(
		"fade_duration",
		"Duration of the transition in seconds",
		false,
		0.5,
		"转场时长"
	))
	
	schema.add_param(ParamDef.choices_param(
		"transition",
		["fade", "dissolve", "wipe_left", "wipe_right", "wipe_up", "wipe_down"],
		"Transition type",
		false,
		"fade",
		"转场类型"
	))
	
	return schema


func validate(command: Resource):
	var result = super.validate(command)
	var has_texture: bool = command != null and command.params != null and command.params.has("texture") and command.params.get("texture") != null
	var texture_path: String = ""
	if command != null and command.params != null and command.params.has("texture_path"):
		texture_path = str(command.params.get("texture_path", "")).strip_edges()
	if not has_texture and texture_path.is_empty():
		result.add_error("CHANGE_BACKGROUND requires texture or texture_path")
	return result


## Execute the CHANGE_BACKGROUND command
func execute(command: Resource, context: RefCounted) -> CommandResultClass:
	var texture: Variant = _get_param(command, "texture", null)
	var texture_path: String = str(_get_param(command, "texture_path", "")).strip_edges()
	var fade_duration: float = _get_param(command, "fade_duration", 0.5)
	var transition: String = _get_param(command, "transition", "fade")
	
	if texture == null and not texture_path.is_empty() and context.scene_runner != null and context.scene_runner.has_method("load_game_texture"):
		texture = context.scene_runner.load_game_texture(texture_path)

	if texture == null:
		push_warning("CHANGE_BACKGROUND: texture not found ('%s'), keeping current background" % texture_path)
		return CommandResultClass.ok()
	
	# 优先使用 runner 的 shader 转场方法
	if context.scene_runner != null and context.scene_runner.has_method("change_background_transition"):
		context.scene_runner.change_background_transition(texture, fade_duration, transition)
	elif context.has_method("change_background"):
		context.change_background(texture, fade_duration)
	
	return CommandResultClass.ok({
		"texture": texture,
		"texture_path": texture_path,
		"fade_duration": fade_duration,
		"transition": transition,
	})
