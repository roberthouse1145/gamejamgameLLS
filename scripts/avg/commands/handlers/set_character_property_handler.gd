extends "res://scripts/avg/commands/command_handler.gd"
class_name SetCharacterPropertyHandler
## Handler for SET_CHARACTER_PROPERTY command
## 设置角色视觉属性（颜色/透明度、缩放）。
## color 使用 Color 类型（RGBA），透明度和着色合一。

const ParamDef = preload("res://scripts/avg/commands/param_definition.gd")


func _init() -> void:
	super._init("SET_CHARACTER_PROPERTY")


func _create_schema() -> ParamSchemaClass:
	var schema := ParamSchemaClass.new(command_type, "设置角色视觉属性")
	schema.add_param(ParamDef.character_ref_param("character_id", "角色ID", true, "角色"))
	schema.add_param(ParamDef.choices_param("property", ["color", "scale"], "属性名", true, "color", "属性"))
	schema.add_param(ParamDef.color_param("color_value", "目标颜色 (RGBA)", true, Color.WHITE, "颜色"))
	schema.params[-1].visible_when = "property == color"
	schema.add_param(ParamDef.float_param("scale_value", "缩放倍数", true, 1.0, "缩放"))
	schema.params[-1].visible_when = "property == scale"
	schema.add_param(ParamDef.float_param("duration", "过渡时长(秒)", false, 0.3, "时长"))
	return schema


func execute(command: Resource, context: RefCounted) -> CommandResultClass:
	var character_id: String = _get_param(command, "character_id", "")
	var property: String = _get_param(command, "property", "color")
	var duration: float = _get_param(command, "duration", 0.3)

	# 从对应属性的专用参数读取值，兼容旧的 value 字段
	var raw_value: Variant
	match property:
		"color":
			raw_value = _get_param(command, "color_value", null)
		"scale":
			raw_value = _get_param(command, "scale_value", null)
		_:
			raw_value = null
	# 向后兼容：旧数据可能只有 value 字段
	if raw_value == null:
		raw_value = _get_param(command, "value", null)

	if character_id.is_empty():
		return CommandResultClass.error("character_id is required")
	if raw_value == null:
		return CommandResultClass.error("value is required")

	# 向后兼容：旧的 opacity/tint 映射到 color
	if property == "opacity":
		var alpha: float = clampf(float(raw_value), 0.0, 1.0)
		property = "color"
		raw_value = Color(1.0, 1.0, 1.0, alpha)
	elif property == "tint":
		property = "color"
		if raw_value is String:
			raw_value = Color.from_string(raw_value, Color.WHITE)

	# 解析 value
	var parsed_value: Variant = raw_value
	match property:
		"color":
			if parsed_value is String:
				parsed_value = Color.from_string(parsed_value, Color.WHITE)
			elif parsed_value is Color:
				pass
			else:
				parsed_value = Color.WHITE
		"scale":
			parsed_value = float(parsed_value)

	if context.character_display != null:
		context.character_display.set_character_property(character_id, property, parsed_value, duration)

	return CommandResultClass.ok()
