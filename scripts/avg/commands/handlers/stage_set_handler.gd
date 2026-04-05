extends CommandHandler
class_name StageSetHandler
## Handler for STAGE_SET command.
## 根据角色顺序自动安排舞台站位，并处理登场/离场补位。

const ParamDef = preload("res://scripts/avg/commands/param_definition.gd")


func _init() -> void:
	super._init("STAGE_SET")


func _create_schema() -> ParamSchemaClass:
	var schema := ParamSchemaClass.new(command_type, "Auto arrange stage characters")
	schema.add_param(ParamDef.string_param("characters_csv", "Comma-separated character order", false, "", "", "角色顺序"))
	schema.add_param(ParamDef.string_param("emotions", "Comma-separated emotion overrides", false, "", "", "表情列表"))
	schema.add_param(ParamDef.string_param("outfits", "Comma-separated outfit overrides", false, "", "", "服装列表"))
	schema.add_param(ParamDef.float_param("duration", "Shared move/show/hide duration", false, 0.35, "时长"))
	schema.add_param(ParamDef.choices_param(
		"enter_effect",
		["fade", "slide_from_left", "slide_from_right", "slide_from_top", "slide_from_bottom", "pop_in", "none"],
		"Enter effect",
		false,
		"fade",
		"入场"
	))
	schema.add_param(ParamDef.choices_param(
		"exit_effect",
		["fade", "slide_to_left", "slide_to_right", "slide_to_top", "slide_to_bottom", "pop_out", "none"],
		"Exit effect",
		false,
		"fade",
		"离场"
	))
	schema.add_param(ParamDef.float_param("enter_distance", "Enter travel distance", false, 0.08, "入场距离"))
	schema.add_param(ParamDef.float_param("exit_distance", "Exit travel distance", false, 0.08, "离场距离"))
	schema.add_param(ParamDef.choices_param("move_easing", ["linear", "ease_in", "ease_out", "ease_in_out"], "Move easing", false, "ease_in_out", "补位缓动"))
	schema.add_param(ParamDef.choices_param("enter_easing", ["linear", "ease_in", "ease_out", "ease_in_out"], "Enter easing", false, "ease_out", "入场缓动"))
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
	if params.has("emotions") and not (params.get("emotions") is String):
		result.add_error("emotions must be a String")
	if params.has("outfits") and not (params.get("outfits") is String):
		result.add_error("outfits must be a String")
	if params.has("duration") and not (params.get("duration") is int or params.get("duration") is float):
		result.add_error("duration must be a number")
	return result


func execute(command: Resource, context: RefCounted) -> CommandResultClass:
	var params: Dictionary = command.params if command.params else {}
	var stage_characters: Array[String] = _extract_stage_characters(params)
	var emotions: String = str(params.get("emotions", "")).strip_edges()
	var outfits: String = str(params.get("outfits", "")).strip_edges()
	var duration: float = float(params.get("duration", 0.35))
	var enter_effect: String = str(params.get("enter_effect", "fade")).strip_edges()
	var exit_effect: String = str(params.get("exit_effect", "fade")).strip_edges()
	var enter_distance: float = float(params.get("enter_distance", 0.08))
	var exit_distance: float = float(params.get("exit_distance", 0.08))
	var move_easing: String = str(params.get("move_easing", "ease_in_out")).strip_edges()
	var enter_easing: String = str(params.get("enter_easing", "ease_out")).strip_edges()
	var exit_easing: String = str(params.get("exit_easing", "ease_in")).strip_edges()

	if context.character_display == null or not context.character_display.has_method("stage_set"):
		return CommandResultClass.error("stage_set is unavailable on character_display")

	context.character_display.stage_set(
		stage_characters,
		emotions,
		outfits,
		duration,
		enter_effect,
		exit_effect,
		enter_distance,
		exit_distance,
		enter_easing,
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
