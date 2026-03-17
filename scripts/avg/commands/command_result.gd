class_name CommandResult extends RefCounted
## Result of executing an AVG command
## Contains success status, error message, and optional data.
## Validates: Requirement 10.1

## Whether the command executed successfully
var success: bool = true

## Error message if execution failed
var error_message: String = ""

## Additional data returned by the command (e.g., for branching decisions)
var data: Dictionary = {}


func _init(p_success: bool = true, p_error_message: String = "", p_data: Dictionary = {}) -> void:
	success = p_success
	error_message = p_error_message
	data = p_data


## Create a successful result
static func ok(p_data: Dictionary = {}) -> CommandResult:
	return CommandResult.new(true, "", p_data)


## Create a failed result with error message
static func error(p_error_message: String, p_data: Dictionary = {}) -> CommandResult:
	return CommandResult.new(false, p_error_message, p_data)


## Check if the result indicates success
func is_success() -> bool:
	return success


## Check if the result indicates failure
func is_error() -> bool:
	return not success


## Get a value from the data dictionary
func get_data(key: String, default: Variant = null) -> Variant:
	return data.get(key, default)


## Set a value in the data dictionary
func set_data(key: String, value: Variant) -> CommandResult:
	data[key] = value
	return self
