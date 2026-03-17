extends "res://scripts/avg/commands/command_handler.gd"
class_name ShowCharacterHandler
## Handler for SHOW_CHARACTER command.

const ParamDef = preload("res://scripts/avg/commands/param_definition.gd")


func _init() -> void:
	super._init("SHOW_CHARACTER")


func _create_schema() -> ParamSchemaClass:
	var schema := ParamSchemaClass.new(command_type, "显示角色")
	schema.add_param(ParamDef.character_ref_param("character_id", "角色ID", true, "角色"))
	schema.add_param(ParamDef.choices_param("position", ["left", "center", "right", "far_left", "far_right", "custom"], "屏幕位置", false, "center", "位置"))
	schema.add_param(ParamDef.float_param("custom_x", "自定义X坐标(0~1)", false, 0.5, "自定义X"))
	schema.get_param("custom_x").visible_when = "position == custom"
	schema.add_param(ParamDef.float_param("custom_y", "自定义Y坐标(0~1)", false, 0.5, "自定义Y"))
	schema.get_param("custom_y").visible_when = "position == custom"
	schema.add_param(ParamDef.string_param("emotion", "表情名", false, "", "", "表情"))
	schema.add_param(ParamDef.string_param("outfit", "服装名", false, "", "", "服装"))
	schema.add_param(ParamDef.float_param("fade_duration", "淡入时长", false, 0.3, "淡入"))
	schema.add_param(ParamDef.bool_param("flip", "水平翻转", false, false, "翻转"))
	schema.add_param(ParamDef.float_param("scale", "缩放", false, 1.0, "缩放"))
	schema.add_param(ParamDef.float_param("opacity", "透明度(0-1)", false, 1.0, "透明度"))
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

	if character_id.is_empty():
		return CommandResultClass.error("character_id is required")

	var resolved_position: String = position
	if position == "custom":
		var cx: float = _get_param(command, "custom_x", 0.5)
		var cy: float = _get_param(command, "custom_y", 0.5)
		resolved_position = "%s,%s" % [cx, cy]

	if context.character_display != null:
		context.character_display.show_character(character_id, resolved_position, emotion, fade_duration, flip, char_scale, opacity, outfit)

	return CommandResultClass.ok()
