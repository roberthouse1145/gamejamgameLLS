class_name ParamSchema extends Resource
## Parameter Schema for AVG Commands
## Defines the structure of command parameters for UI generation in the editor.
## Validates: Requirement 10.7

@export var command_type: String = ""
@export var description: String = ""
## Array of ParamDefinition - use untyped to avoid cross-file type issues
@export var params: Array = []  # Array[ParamDefinition]


func _init(p_command_type: String = "", p_description: String = "", p_params: Array = []) -> void:
	command_type = p_command_type
	description = p_description
	params = p_params


## Add a parameter definition to the schema
## @param param: ParamDefinition instance
func add_param(param) -> ParamSchema:
	params.append(param)
	return self


## Get a parameter definition by name
## @return: ParamDefinition or null
func get_param(param_name: String):
	for param in params:
		if param.name == param_name:
			return param
	return null


## Get all required parameters
## @return: Array of ParamDefinition
func get_required_params() -> Array:
	var required: Array = []
	for param in params:
		if param.required:
			required.append(param)
	return required


## Get all optional parameters
## @return: Array of ParamDefinition
func get_optional_params() -> Array:
	var optional: Array = []
	for param in params:
		if not param.required:
			optional.append(param)
	return optional
