class_name ValidationResult extends RefCounted
## Result of validating AVG command parameters
## Contains validation status and list of error messages.
## Validates: Requirement 10.1

## Whether the validation passed
var valid: bool = true

## List of validation error messages
var errors: Array = []  # Array[String]


func _init(p_valid: bool = true, p_errors: Array = []) -> void:
	valid = p_valid
	errors = p_errors


## Create a valid result
static func ok() -> ValidationResult:
	return ValidationResult.new(true, [])


## Create an invalid result with errors
static func invalid(p_errors: Array) -> ValidationResult:
	return ValidationResult.new(false, p_errors)


## Create an invalid result with a single error
static func error(error_message: String) -> ValidationResult:
	return ValidationResult.new(false, [error_message])


## Check if validation passed
func is_valid() -> bool:
	return valid


## Check if validation failed
func is_invalid() -> bool:
	return not valid


## Add an error message
func add_error(error_message: String) -> ValidationResult:
	errors.append(error_message)
	valid = false
	return self


## Get all error messages as a single string
func get_error_string(separator: String = "\n") -> String:
	return separator.join(errors)


## Get the number of errors
func error_count() -> int:
	return errors.size()


## Merge another validation result into this one
func merge(other: ValidationResult) -> ValidationResult:
	if other.is_invalid():
		valid = false
		errors.append_array(other.errors)
	return self
