extends "res://scripts/avg/commands/command_handler.gd"
class_name SetHudVisibleHandler
## Handler for SET_HUD_VISIBLE command
## 控制游戏内 HUD（存读档按钮层）的显示/隐藏。

const ParamDef = preload("res://scripts/avg/commands/param_definition.gd")


func _init() -> void:
	super._init("SET_HUD_VISIBLE")


func _create_schema() -> ParamSchemaClass:
	var schema := ParamSchemaClass.new(command_type, "显示/隐藏游戏HUD")
	schema.add_param(ParamDef.bool_param("visible", "是否显示HUD", true, true, "显示"))
	return schema


func execute(command: Resource, context: RefCounted) -> CommandResultClass:
	var p_visible: bool = _get_param(command, "visible", true)
	var runner: Node = context.scene_runner if "scene_runner" in context else null
	if runner != null and runner.has_method("set_game_ui_visible"):
		runner.set_game_ui_visible(p_visible)
		# 同步 _ui_hidden 状态
		if "_ui_hidden" in runner:
			runner._ui_hidden = not p_visible
	return CommandResultClass.ok()
