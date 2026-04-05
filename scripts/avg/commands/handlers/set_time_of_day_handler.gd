extends CommandHandler
class_name SetTimeOfDayHandler

const ParamDef = preload("res://scripts/avg/commands/param_definition.gd")


func _init() -> void:
	super._init("SET_TIME_OF_DAY")


func _create_schema() -> ParamSchemaClass:
	var schema := ParamSchemaClass.new(command_type, "Set world time-of-day grading preset")
	schema.add_param(ParamDef.choices_param(
		"preset",
		["day", "dusk", "night"],
		"Time-of-day preset",
		true,
		"day",
		"氛围"
	))
	schema.add_param(ParamDef.float_param(
		"duration",
		"Transition duration in seconds",
		false,
		0.6,
		"时长"
	))
	return schema


func execute(command: Resource, context: RefCounted) -> CommandResultClass:
	var preset: String = str(_get_param(command, "preset", "day")).strip_edges().to_lower()
	var duration: float = float(_get_param(command, "duration", 0.6))

	if context.scene_runner != null and context.scene_runner.has_method("set_time_of_day"):
		context.scene_runner.set_time_of_day(preset, duration)

	return CommandResultClass.ok({
		"preset": preset,
		"duration": duration,
	})
