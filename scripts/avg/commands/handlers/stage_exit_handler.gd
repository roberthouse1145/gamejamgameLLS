extends CommandHandler
class_name StageExitHandler
## Handler for STAGE_EXIT command.
## 让角色离开当前舞台，并自动补位。

const ParamDef = preload("res://scripts/avg/commands/param_definition.gd")


func _init() -> void:
	super._init("STAGE_EXIT")


func _create_schema() -> ParamSchemaClass:
	var schema := ParamSchemaClass.new(command_type, "Exit characters from the stage")
	schema.add_param(ParamDef.string_param("characters_csv", "Comma-separated exiting characters", false, "", "", "离场角色"))
	schema.add_param(ParamDef.float_param("duration", "Shared hide/move duration", false, 0.35, "时长"))
	schema.add_param(ParamDef.choices_param(
		"exit_effect",
		["fade", "slide_to_left", "slide_to_right", "slide_to_top", "slide_to_bottom", "pop_out", "none"],
		"Exit effect",
		false,
		"fade",
		"离场"
	))
	schema.add_param(ParamDef.float_param("exit_distance", "Exit travel distance", false, 0.08, "离场距离"))
	schema.add_param(ParamDef.choices_param("move_easing", ["linear", "ease_in", "ease_out", "ease_in_out"], "Move easing", false, "ease_in_out", "补位缓动"))
	schema.add_param(ParamDef.choices_param("exit_easing", ["linear", "ease_in", "ease_out", "ease_in_out"], "Exit easing", false, "ease_in", "离场缓动"))
	return schema


func validate(command: Resource):
	var result = ValidationResultClass.ok()
	if command == null:
		return ValidationResultClass.error("Command is null")

	var params: Dictionary = command.params if command.params else {}
	if params.has("characters") and not (params.get("characters") is Array):
		result.add_error("characters must be an Array")
	if params.has("characters_csv") and not (params.get("characters_csv") is String):
		result.add_error("characters_csv must be a String")
	if params.has("duration") and not (params.get("duration") is int or params.get("duration") is float):
		result.add_error("duration must be a number")
	return result


func execute(command: Resource, context: RefCounted) -> CommandResultClass:
	var params: Dictionary = command.params if command.params else {}
	var stage_characters: Array[String] = _extract_stage_characters(params)
	var duration: float = float(params.get("duration", 0.35))
	var exit_effect: String = str(params.get("exit_effect", "fade")).strip_edges()
	var exit_distance: float = float(params.get("exit_distance", 0.08))
	var move_easing: String = str(params.get("move_easing", "ease_in_out")).strip_edges()
	var exit_easing: String = str(params.get("exit_easing", "ease_in")).strip_edges()

	if context.character_display == null or not context.character_display.has_method("stage_exit"):
		return CommandResultClass.error("stage_exit is unavailable on character_display")

	context.character_display.stage_exit(
		stage_characters,
		duration,
		exit_effect,
		exit_distance,
		exit_easing,
		move_easing
	)
	return CommandResultClass.ok()


func _extract_stage_characters(params: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var raw_characters: Variant = params.get("characters", [])
	if raw_characters is Array:
		for entry in raw_characters:
			var trimmed: String = str(entry).strip_edges()
			if trimmed.is_empty():
				continue
			result.append(trimmed)
		if not result.is_empty():
			return result

	var raw_csv: String = str(params.get("characters_csv", "")).strip_edges()
	if raw_csv.is_empty():
		return result
	for entry in raw_csv.split(","):
		var trimmed_csv: String = entry.strip_edges()
		if trimmed_csv.is_empty():
			continue
		result.append(trimmed_csv)
	return result
