extends "res://scripts/avg/commands/command_handler.gd"
class_name ShowCharacterHandler
## Handler for SHOW_CHARACTER command.

const ParamDef = preload("res://scripts/avg/commands/param_definition.gd")


func _init() -> void:
	super._init("SHOW_CHARACTER")


func _create_schema() -> ParamSchemaClass:
	var schema := ParamSchemaClass.new(command_type, "Show character")
	schema.add_param(ParamDef.character_ref_param("character_id", "Character ID", true, "Character"))
	schema.add_param(ParamDef.choices_param("position", ["left", "center", "right", "far_left", "far_right", "custom"], "Screen position", false, "center", "Position"))
	schema.add_param(ParamDef.float_param("custom_x", "Custom X (0~1)", false, 0.5, "Custom X"))
	schema.get_param("custom_x").visible_when = "position == custom"
	schema.add_param(ParamDef.float_param("custom_y", "Custom Y (0~1)", false, 0.5, "Custom Y"))
	schema.get_param("custom_y").visible_when = "position == custom"
	schema.add_param(ParamDef.string_param("emotion", "Expression name", false, "", "", "Expression"))
	schema.add_param(ParamDef.string_param("outfit", "Outfit name", false, "", "", "Outfit"))
	schema.add_param(ParamDef.float_param("fade_duration", "Enter animation duration", false, 0.3, "Duration"))
	schema.add_param(ParamDef.bool_param("flip", "Flip horizontally", false, false, "Flip"))
	schema.add_param(ParamDef.float_param("scale", "Character scale", false, 1.0, "Scale"))
	schema.add_param(ParamDef.float_param("opacity", "Opacity (0~1)", false, 1.0, "Opacity"))
	schema.add_param(ParamDef.choices_param(
		"enter_effect",
		["fade", "slide_from_left", "slide_from_right", "slide_from_top", "slide_from_bottom", "pop_in", "none"],
		"Shortcut enter effect",
		false,
		"fade",
		"Enter"
	))
	schema.add_param(ParamDef.float_param("enter_distance", "Enter travel distance (normalized)", false, 0.08, "Distance"))
	schema.add_param(ParamDef.choices_param(
		"enter_easing",
		["linear", "ease_in", "ease_out", "ease_in_out"],
		"Enter easing",
		false,
		"ease_out",
		"Easing"
	))
	return schema


func execute(command: Resource, context: RefCounted) -> CommandResultClass:
	var character_id: String = _get_param(command, "character_id", "")
	var position: String = _get_param(command, "position", "center")
	var emotion: String = _get_param(command, "emotion", "")
	var outfit: String = _get_param(command, "outfit", "")
	var fade_duration: float = _get_param(command, "fade_duration", 0.3)
	var flip: bool = _get_param(command, "flip", false)
	var char_scale: float = _get_param(command, "scale", 1.0)
	var opacity: float = _get_param(command, "opacity", 1.0)
	var enter_effect: String = _get_param(command, "enter_effect", "fade")
	var enter_distance: float = _get_param(command, "enter_distance", 0.08)
	var enter_easing: String = _get_param(command, "enter_easing", "ease_out")

	if character_id.is_empty():
		return CommandResultClass.error("character_id is required")

	var resolved_position: String = position
	if position == "custom":
		var cx: float = _get_param(command, "custom_x", 0.5)
		var cy: float = _get_param(command, "custom_y", 0.5)
		resolved_position = "%s,%s" % [cx, cy]

	if context.character_display != null:
		context.character_display.show_character(
			character_id,
			resolved_position,
			emotion,
			fade_duration,
			flip,
			char_scale,
			opacity,
			outfit,
			enter_effect,
			enter_distance,
			enter_easing
		)

	return CommandResultClass.ok()
