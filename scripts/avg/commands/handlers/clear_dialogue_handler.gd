extends "res://scripts/avg/commands/command_handler.gd"
class_name ClearDialogueHandler
## Handler for CLEAR_DIALOGUE command
## 清空并隐藏对话框。非阻塞，立即生效。

const ParamDef = preload("res://scripts/avg/commands/param_definition.gd")


func _init() -> void:
	super._init("CLEAR_DIALOGUE")


func _create_schema() -> ParamSchemaClass:
	var schema := ParamSchemaClass.new(
		command_type,
		"Clear and hide the dialogue box"
	)
	return schema


func execute(_command: Resource, context: RefCounted) -> CommandResultClass:
	if context.dialog_box != null:
		if context.dialog_box.has_method("clear"):
			context.dialog_box.clear()
		if context.dialog_box.has_method("hide_box"):
			context.dialog_box.hide_box()

	return CommandResultClass.ok()
