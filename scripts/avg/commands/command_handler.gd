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
			if not value is String:
				return "Parameter '%s' must be a string" % param.name
		"int":
			if not (value is int or value is float):
				return "Parameter '%s' must be an integer" % param.name
		"float":
			if not (value is int or value is float):
				return "Parameter '%s' must be a number" % param.name
		"bool":
			if not value is bool:
				return "Parameter '%s' must be a boolean" % param.name
		"choices":
			if not value is String:
				return "Parameter '%s' must be a string" % param.name
			if param.options.size() > 0 and not param.options.has(value):
				return "Parameter '%s' must be one of: %s" % [param.name, ", ".join(param.options)]
		"color":
			if not value is Color:
				return "Parameter '%s' must be a Color" % param.name
		"vector2":
			if not value is Vector2:
				return "Parameter '%s' must be a Vector2" % param.name
	
	return ""


## Helper to get a parameter value with default fallback
func _get_param(command: Resource, param_name: String, default: Variant = null) -> Variant:
	if command.params.has(param_name):
		return command.params[param_name]
	
	var schema = get_schema()
	if schema != null:
		var param = schema.get_param(param_name)
		if param != null:
			return param.default_value
	
	return default
