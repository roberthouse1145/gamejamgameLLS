class_name CommandRegistry extends RefCounted
## Registry for AVG command handlers
## Manages registration and lookup of command handlers and their schemas.
## Singleton pattern (not autoload - instantiate as needed)
## Validates: Requirement 10.7

# Preload dependencies to ensure they are available
const CommandResultClass = preload("res://scripts/avg/commands/command_result.gd")
const ValidationResultClass = preload("res://scripts/avg/commands/validation_result.gd")

## Registered command handlers by command type (String -> CommandHandler)
var _handlers: Dictionary = {}

## Singleton instance
static var _instance: CommandRegistry = null


func _init() -> void:
	pass


## Get the singleton instance of CommandRegistry
static func get_instance() -> CommandRegistry:
	if _instance == null:
		_instance = CommandRegistry.new()
	return _instance


## Reset the singleton instance (useful for testing)
static func reset_instance() -> void:
	_instance = null


## Register a command handler
## @param handler: The CommandHandler to register
func register_handler(handler) -> void:
	if handler == null:
		push_error("Cannot register null handler")
		return
	
	if handler.command_type == "":
		push_error("Cannot register handler with empty command_type")
		return
	
	if _handlers.has(handler.command_type):
		push_warning("Overwriting existing handler for command type: " + handler.command_type)
		return
	
	_handlers[handler.command_type] = handler


## Unregister a command handler by type
## @param command_type: The command type to unregister
func unregister_handler(command_type: String) -> void:
	if _handlers.has(command_type):
		_handlers.erase(command_type)


## Get a handler for a command type
## @param command_type: The command type to look up
## @return: The CommandHandler or null if not found
func get_handler(command_type: String):  # -> CommandHandler
	return _handlers.get(command_type, null)


## Check if a handler is registered for a command type
## @param command_type: The command type to check
## @return: True if a handler is registered
func has_handler(command_type: String) -> bool:
	return _handlers.has(command_type)


## Get the schema for a command type
## @param command_type: The command type to look up
## @return: The ParamSchema or null if not found
func get_schema(command_type: String):  # -> ParamSchema
	var handler = get_handler(command_type)
	if handler != null:
		return handler.get_schema()
	return null


## Get all registered command types
## @return: Array of command type strings
func get_all_command_types() -> Array:  # Array[String]
	return _handlers.keys()


## Get all registered handlers
## @return: Array of CommandHandler instances
func get_all_handlers() -> Array:  # Array[CommandHandler]
	return _handlers.values()


## Get the number of registered handlers
## @return: Number of registered handlers
func handler_count() -> int:
	return _handlers.size()


## Execute a command using the appropriate handler
## @param command: The AVGCommand to execute
## @param context: The CommandContext for execution
## @return: CommandResult from execution
func execute_command(command: Resource, context: RefCounted):  # -> CommandResult
	if command == null:
		return CommandResultClass.new(false, "Command is null")
	
	var handler = get_handler(command.command_type)
	if handler == null:
		return CommandResultClass.new(false, "No handler registered for command type: " + command.command_type)
	
	# Validate first
	var validation = handler.validate(command)
	if validation.is_invalid():
		return CommandResultClass.new(false, "Validation failed: " + validation.get_error_string("; "))
	
	# Execute
	return handler.execute(command, context)


## Validate a command using the appropriate handler
## @param command: The AVGCommand to validate
## @return: ValidationResult from validation
func validate_command(command: Resource):  # -> ValidationResult
	if command == null:
		return ValidationResultClass.new(false, ["Command is null"])
	
	var handler = get_handler(command.command_type)
	if handler == null:
		return ValidationResultClass.new(false, ["No handler registered for command type: " + command.command_type])
	
	return handler.validate(command)


## Get all schemas as a dictionary
## @return: Dictionary mapping command_type to ParamSchema
func get_all_schemas() -> Dictionary:
	var schemas: Dictionary = {}
	for command_type in _handlers:
		var handler = _handlers[command_type]
		schemas[command_type] = handler.get_schema()
	return schemas


## Clear all registered handlers
func clear() -> void:
	_handlers.clear()
