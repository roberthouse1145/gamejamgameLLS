class_name AVGCommand extends Resource
## AVG Command Resource
## A simple structure containing command_type and params for AVG instructions.
## Validates: Requirement 7.4, 10.1

@export var command_type: String = ""
@export var params: Dictionary = {}

func _init(p_type: String = "", p_params: Dictionary = {}) -> void:
	command_type = p_type
	params = p_params
