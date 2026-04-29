class_name CommandHandler extends RefCounted
## Abstract base class for AVG command handlers
## Subclasses implement specific command logic.
## Validates: Requirement 10.1, 10.7

# Preload dependencies to ensure they are available
const CommandResultClass = preload("res://scripts/avg/commands/command_result.gd")
const ValidationResultClass = preload("res://scripts/avg/commands/validation_result.gd")
const ParamSchemaClass = preload("res://scripts/avg/commands/param_schema.gd")

## The command type this handler processes
var command_type: String = ""

## The parameter schema for this command (ParamSchema)
var _schema = null


func _init(p_command_type: String = "") -> void:
	command_type = p_command_type


## Execute the command with given parameters and context
## Override this method in subclasses
## @param command: The AVGCommand to execute
## @param context: The CommandContext providing runtime access
## @return: CommandResult indicating success or failure
func execute(_command: Resource, _context: RefCounted):  # -> CommandResult
	push_error("CommandHandler.execute() must be overridden in subclass: " + command_type)
	return CommandResultClass.new(false, "Not implemented")


## Validate command parameters before execution
## Override this method in subclasses for custom validation
## @param command: The AVGCommand to validate
## @return: ValidationResult indicating valid or invalid with errors
func validate(command: Resource):  # -> ValidationResult
	var result = ValidationResultClass.new()
	var schema = get_schema()
	
	if schema == null:
		return result
	
	# Check required parameters
	for param in schema.get_required_params():
		if not command.params.has(param.name):
			result.add_error("Missing required parameter: " + param.name)
		elif _is_empty_value(command.params[param.name], param.type):
			result.add_error("Required parameter is empty: " + param.name)
	
	# Validate parameter types
	for param in schema.params:
		if command.params.has(param.name):
			var type_error := _validate_param_type(command.params[param.name], param)
			if type_error != "":
				result.add_error(type_error)
	
	return result


## Get the parameter schema for this command
## Override this method in subclasses to define the schema
## @return: ParamSchema defining the command's parameters
func get_schema():  # -> ParamSchema
	if _schema == null:
		_schema = _create_schema()
	return _schema


## Create the parameter schema for this command
## Override this method in subclasses
## @return: ParamSchema for this command type
func _create_schema():  # -> ParamSchema
	return ParamSchemaClass.new(command_type, "Base command handler")


## Check if a value is considered empty for the given type
func _is_empty_value(value: Variant, type: String) -> bool:
	match type:
		"string", "character_ref", "scene_ref":
			return value == null or (value is String and value == "")
		"texture", "audio":
			return value == null
		"choices":
			return value == null or (value is String and value == "")
		_:
			return value == null


## Validate that a parameter value matches its expected type
## @param value: The value to validate
## @param param: ParamDefinition instance
func _validate_param_type(value: Variant, param) -> String:
	if value == null:
		return ""  # Null is handled by required check
	
	match param.type:
		"string", "character_ref", "scene_ref":
			if not _is_string_like_value(value):
				return "Parameter '%s' must be a string" % param.name
		"variable_ref":
			if not _is_string_like_value(value):
				return "Parameter '%s' must be a string" % param.name
		"int":
			if not _is_number_like_value(value):
				return "Parameter '%s' must be an integer" % param.name
		"float":
			if not _is_number_like_value(value):
				return "Parameter '%s' must be a number" % param.name
		"bool":
			if not _is_bool_like_value(value):
				return "Parameter '%s' must be a boolean" % param.name
		"choices":
			if not _is_string_like_value(value):
				return "Parameter '%s' must be a string" % param.name
		"color":
			if not _is_color_like_value(value):
				return "Parameter '%s' must be a Color" % param.name
		"vector2":
			if not _is_vector2_like_value(value):
				return "Parameter '%s' must be a Vector2" % param.name
	
	return ""


## Helper to get a parameter value with default fallback
func _get_param(command: Resource, param_name: String, default: Variant = null) -> Variant:
	var fallback: Variant = default
	var schema = get_schema()
	var param = null
	if schema != null:
		param = schema.get_param(param_name)
		if fallback == null and param != null:
			fallback = param.default_value

	if command.params.has(param_name):
		var raw_value: Variant = command.params[param_name]
		if param != null:
			return _coerce_param_value(raw_value, param, fallback)
		return raw_value
	
	if schema != null:
		if param != null:
			return param.default_value
	
	return default


func _coerce_param_value(value: Variant, param, fallback: Variant) -> Variant:
	match param.type:
		"string", "character_ref", "scene_ref", "variable_ref", "texture", "audio":
			return _coerce_string_value(value, fallback)
		"choices":
			return _coerce_choice_value(value, param.options, fallback)
		"int":
			return _coerce_int_value(value, fallback)
		"float":
			return _coerce_float_value(value, fallback)
		"bool":
			return _coerce_bool_value(value, fallback)
		"color":
			return _coerce_color_value(value, fallback)
		"vector2":
			return _coerce_vector2_value(value, fallback)
	return value


func _coerce_string_value(value: Variant, fallback: Variant) -> String:
	if value == null:
		return str(fallback)
	if value is String:
		return value
	if _is_string_like_value(value):
		return str(value)
	return str(fallback)


func _coerce_choice_value(value: Variant, options: Array, fallback: Variant) -> String:
	var text: String = _coerce_string_value(value, fallback).strip_edges()
	if text.is_empty():
		return str(fallback)

	for option in options:
		var option_text: String = str(option).strip_edges()
		if option_text == text:
			return option_text
		if not option_text.is_empty() and option_text.to_lower() == text.to_lower():
			return option_text

	return str(fallback)


func _coerce_int_value(value: Variant, fallback: Variant) -> int:
	var fallback_int: int = int(_coerce_float_value(fallback, 0.0))
	if value == null:
		return fallback_int
	if value is int or value is float:
		return int(value)
	if value is bool:
		return 1 if value else 0
	if value is String:
		var text: String = value.strip_edges()
		if text.is_empty():
			return fallback_int
		if text.is_valid_int() or text.is_valid_float():
			return int(text.to_float())
	return fallback_int


func _coerce_float_value(value: Variant, fallback: Variant) -> float:
	var fallback_float: float = 0.0
	if fallback is int or fallback is float:
		fallback_float = float(fallback)
	elif fallback is String and (fallback.is_valid_int() or fallback.is_valid_float()):
		fallback_float = fallback.to_float()

	if value == null:
		return fallback_float
	if value is int or value is float:
		return float(value)
	if value is bool:
		return 1.0 if value else 0.0
	if value is String:
		var text: String = value.strip_edges()
		if text.is_empty():
			return fallback_float
		if text.is_valid_int() or text.is_valid_float():
			return text.to_float()
	return fallback_float


func _coerce_bool_value(value: Variant, fallback: Variant) -> bool:
	var fallback_bool: bool = bool(fallback)
	if value == null:
		return fallback_bool
	if value is bool:
		return value
	if value is int or value is float:
		return float(value) != 0.0
	if value is String:
		var text: String = value.strip_edges().to_lower()
		if text.is_empty():
			return fallback_bool
		if text in ["true", "1", "yes", "y", "on", "enable", "enabled", "是", "开"]:
			return true
		if text in ["false", "0", "no", "n", "off", "disable", "disabled", "否", "关"]:
			return false
	return fallback_bool


func _coerce_color_value(value: Variant, fallback: Variant) -> Color:
	var fallback_color: Color = fallback if fallback is Color else Color.WHITE
	if value == null:
		return fallback_color
	if value is Color:
		return value
	if value is String:
		var text: String = value.strip_edges()
		if text.is_empty():
			return fallback_color
		return Color.from_string(text, fallback_color)
	return fallback_color


func _coerce_vector2_value(value: Variant, fallback: Variant) -> Vector2:
	var fallback_vector: Vector2 = fallback if fallback is Vector2 else Vector2.ZERO
	if value == null:
		return fallback_vector
	if value is Vector2:
		return value
	if value is Array and value.size() >= 2:
		return Vector2(
			_coerce_float_value(value[0], fallback_vector.x),
			_coerce_float_value(value[1], fallback_vector.y)
		)
	if value is String:
		var text: String = value.strip_edges()
		if text.is_empty():
			return fallback_vector
		text = text.trim_prefix("(").trim_suffix(")")
		text = text.trim_prefix("[").trim_suffix("]")
		var parts: PackedStringArray = text.split(",", false)
		if parts.size() >= 2:
			var x_text: String = parts[0].strip_edges()
			var y_text: String = parts[1].strip_edges()
			if (x_text.is_valid_int() or x_text.is_valid_float()) and (y_text.is_valid_int() or y_text.is_valid_float()):
				return Vector2(x_text.to_float(), y_text.to_float())
	return fallback_vector


func _is_string_like_value(value: Variant) -> bool:
	return value is String or value is int or value is float or value is bool


func _is_number_like_value(value: Variant) -> bool:
	if value is int or value is float or value is bool:
		return true
	return value is String


func _is_bool_like_value(value: Variant) -> bool:
	if value is bool or value is int or value is float:
		return true
	return value is String


func _is_color_like_value(value: Variant) -> bool:
	return value is Color or value is String


func _is_vector2_like_value(value: Variant) -> bool:
	if value is Vector2 or value is String:
		return true
	return value is Array and value.size() >= 2
