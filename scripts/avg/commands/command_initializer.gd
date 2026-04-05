class_name CommandInitializer extends RefCounted
## Initializes and registers all core AVG command handlers
## Provides a centralized registration point for the command system.
## Validates: Requirement 10.1, 10.7

# Preload CommandRegistry
const CommandRegistryClass = preload("res://scripts/avg/commands/command_registry.gd")

# Preload all handler classes (prefixed to avoid shadowing global class_name)
const _DialogueHandler = preload("res://scripts/avg/commands/handlers/dialogue_handler.gd")
const _ShowCharacterHandler = preload("res://scripts/avg/commands/handlers/show_character_handler.gd")
const _HideCharacterHandler = preload("res://scripts/avg/commands/handlers/hide_character_handler.gd")
const _StageSetHandler = preload("res://scripts/avg/commands/handlers/stage_set_handler.gd")
const _WaitClickHandler = preload("res://scripts/avg/commands/handlers/wait_click_handler.gd")
const _WaitTimeHandler = preload("res://scripts/avg/commands/handlers/wait_time_handler.gd")
const _ChoiceHandler = preload("res://scripts/avg/commands/handlers/choice_handler.gd")
const _LabelHandler = preload("res://scripts/avg/commands/handlers/label_handler.gd")
const _JumpLabelHandler = preload("res://scripts/avg/commands/handlers/jump_label_handler.gd")
const _JumpSceneHandler = preload("res://scripts/avg/commands/handlers/jump_scene_handler.gd")
const _SetVariableHandler = preload("res://scripts/avg/commands/handlers/set_variable_handler.gd")
const _CallEventHandler = preload("res://scripts/avg/commands/handlers/call_event_handler.gd")
const _ChangeBackgroundHandler = preload("res://scripts/avg/commands/handlers/change_background_handler.gd")
const _AudioHandlers = preload("res://scripts/avg/commands/handlers/audio_handlers.gd")
const _IfHandler = preload("res://scripts/avg/commands/handlers/if_handler.gd")
const _CheckVarHandler = preload("res://scripts/avg/commands/handlers/check_var_handler.gd")
const _ChangeExpressionHandler = preload("res://scripts/avg/commands/handlers/change_expression_handler.gd")
const _ChangeOutfitHandler = preload("res://scripts/avg/commands/handlers/change_outfit_handler.gd")
const _MoveCharacterHandler = preload("res://scripts/avg/commands/handlers/move_character_handler.gd")
const _MoveCharacterByHandler = preload("res://scripts/avg/commands/handlers/move_character_by_handler.gd")
const _FlipCharacterHandler = preload("res://scripts/avg/commands/handlers/flip_character_handler.gd")
const _CharacterEffectHandler = preload("res://scripts/avg/commands/handlers/character_effect_handler.gd")
const _SetCharacterPropertyHandler = preload("res://scripts/avg/commands/handlers/set_character_property_handler.gd")
const _ScreenFadeHandler = preload("res://scripts/avg/commands/handlers/screen_fade_handler.gd")
const _SetTimeOfDayHandler = preload("res://scripts/avg/commands/handlers/set_time_of_day_handler.gd")
const _ScreenFlashHandler = preload("res://scripts/avg/commands/handlers/screen_flash_handler.gd")
const _ScreenShakeHandler = preload("res://scripts/avg/commands/handlers/screen_shake_handler.gd")
const _ShowImageHandler = preload("res://scripts/avg/commands/handlers/show_image_handler.gd")
const _HideImageHandler = preload("res://scripts/avg/commands/handlers/hide_image_handler.gd")
const _SetTextSpeedHandler = preload("res://scripts/avg/commands/handlers/set_text_speed_handler.gd")
const _ClearDialogueHandler = preload("res://scripts/avg/commands/handlers/clear_dialogue_handler.gd")
const _ShowNotificationHandler = preload("res://scripts/avg/commands/handlers/show_notification_handler.gd")
const _EndGameHandler = preload("res://scripts/avg/commands/handlers/end_game_handler.gd")
const _ReturnToTitleHandler = preload("res://scripts/avg/commands/handlers/return_to_title_handler.gd")
const _OpenMenuHandler = preload("res://scripts/avg/commands/handlers/open_menu_handler.gd")
const _SaveGameHandler = preload("res://scripts/avg/commands/handlers/save_game_handler.gd")
const _LoadGameHandler = preload("res://scripts/avg/commands/handlers/load_game_handler.gd")
const _CheckHoverHandler = preload("res://scripts/avg/commands/handlers/check_hover_handler.gd")
const _CheckClickHandler = preload("res://scripts/avg/commands/handlers/check_click_handler.gd")
const _CameraZoomHandler = preload("res://scripts/avg/commands/handlers/camera_zoom_handler.gd")
const _CameraPanHandler = preload("res://scripts/avg/commands/handlers/camera_pan_handler.gd")
const _CameraResetHandler = preload("res://scripts/avg/commands/handlers/camera_reset_handler.gd")
const _SetTextHandler = preload("res://scripts/avg/commands/handlers/set_text_handler.gd")
const _SetStyleHandler = preload("res://scripts/avg/commands/handlers/set_style_handler.gd")
const _MoveNodeHandler = preload("res://scripts/avg/commands/handlers/move_node_handler.gd")
const _ResizeNodeHandler = preload("res://scripts/avg/commands/handlers/resize_node_handler.gd")
const _ShowNodeHandler = preload("res://scripts/avg/commands/handlers/show_node_handler.gd")
const _HideNodeHandler = preload("res://scripts/avg/commands/handlers/hide_node_handler.gd")
const _RemoveNodeHandler = preload("res://scripts/avg/commands/handlers/remove_node_handler.gd")
const _SpawnNodeHandler = preload("res://scripts/avg/commands/handlers/spawn_node_handler.gd")
const _SetHudVisibleHandler = preload("res://scripts/avg/commands/handlers/set_hud_visible_handler.gd")


## Register all core command handlers with the given registry
## @param registry: The CommandRegistry to register handlers with
static func register_all_commands(registry: RefCounted) -> void:
	if registry == null:
		push_error("CommandInitializer: Cannot register commands with null registry")
		return
	
	# Text display commands
	registry.register_handler(_DialogueHandler.new())
	
	# Character commands
	registry.register_handler(_ShowCharacterHandler.new())
	registry.register_handler(_HideCharacterHandler.new())
	registry.register_handler(_StageSetHandler.new())
	registry.register_handler(_ChangeExpressionHandler.new())
	registry.register_handler(_ChangeOutfitHandler.new())
	registry.register_handler(_MoveCharacterHandler.new())
	registry.register_handler(_MoveCharacterByHandler.new())
	registry.register_handler(_FlipCharacterHandler.new())
	registry.register_handler(_CharacterEffectHandler.new())
	registry.register_handler(_SetCharacterPropertyHandler.new())
	
	# Wait commands
	registry.register_handler(_WaitClickHandler.new())
	registry.register_handler(_WaitTimeHandler.new())
	
	# Choice and branching commands
	registry.register_handler(_ChoiceHandler.new())
	registry.register_handler(_LabelHandler.new())
	registry.register_handler(_JumpLabelHandler.new())
	registry.register_handler(_JumpSceneHandler.new())
	
	# Variable commands
	registry.register_handler(_SetVariableHandler.new())
	
	# Event commands
	registry.register_handler(_CallEventHandler.new())
	
	# Audio commands
	registry.register_handler(_AudioHandlers.PlayBGMHandler.new())
	registry.register_handler(_AudioHandlers.StopBGMHandler.new())
	registry.register_handler(_AudioHandlers.PlaySFXHandler.new())
	
	# Background commands
	registry.register_handler(_ChangeBackgroundHandler.new())
	
	# Conditional commands
	registry.register_handler(_IfHandler.new())
	registry.register_handler(_CheckVarHandler.new())
	registry.register_handler(_CheckHoverHandler.new())
	registry.register_handler(_CheckClickHandler.new())

	# Node operation commands
	registry.register_handler(_SetTextHandler.new())
	registry.register_handler(_SetStyleHandler.new())
	registry.register_handler(_MoveNodeHandler.new())
	registry.register_handler(_ResizeNodeHandler.new())
	registry.register_handler(_ShowNodeHandler.new())
	registry.register_handler(_HideNodeHandler.new())
	registry.register_handler(_RemoveNodeHandler.new())
	registry.register_handler(_SpawnNodeHandler.new())

	# Screen effect commands
	registry.register_handler(_ScreenFadeHandler.new())
	registry.register_handler(_SetTimeOfDayHandler.new())
	registry.register_handler(_ScreenFlashHandler.new())
	registry.register_handler(_ScreenShakeHandler.new())

	# Camera commands
	registry.register_handler(_CameraZoomHandler.new())
	registry.register_handler(_CameraPanHandler.new())
	registry.register_handler(_CameraResetHandler.new())

	# Image layer commands
	registry.register_handler(_ShowImageHandler.new())
	registry.register_handler(_HideImageHandler.new())

	# Text control commands
	registry.register_handler(_SetTextSpeedHandler.new())
	registry.register_handler(_ClearDialogueHandler.new())

	# Notification commands
	registry.register_handler(_ShowNotificationHandler.new())

	# HUD commands
	registry.register_handler(_SetHudVisibleHandler.new())

	# System commands (TODO)
	registry.register_handler(_EndGameHandler.new())
	registry.register_handler(_ReturnToTitleHandler.new())
	registry.register_handler(_OpenMenuHandler.new())
	registry.register_handler(_SaveGameHandler.new())
	registry.register_handler(_LoadGameHandler.new())


## Get a list of all core command types
## @return: Array of command type strings
static func get_all_command_types() -> Array[String]:
	return [
		"DIALOGUE",
		"SHOW_CHARACTER",
		"HIDE_CHARACTER",
		"STAGE_SET",
		"CHANGE_EXPRESSION",
		"CHANGE_OUTFIT",
		"MOVE_CHARACTER",
		"MOVE_CHARACTER_BY",
		"FLIP_CHARACTER",
		"CHARACTER_EFFECT",
		"SET_CHARACTER_PROPERTY",
		"WAIT_CLICK",
		"WAIT_TIME",
		"CHOICE",
		"LABEL",
		"JUMP_LABEL",
		"JUMP_SCENE",
		"SET_VARIABLE",
		"CALL_EVENT",
		"PLAY_BGM",
		"STOP_BGM",
		"PLAY_SFX",
		"CHANGE_BACKGROUND",
		"IF",
		"CHECK_VAR",
		"CHECK_HOVER",
		"CHECK_CLICK",
		"SET_TEXT",
		"SET_STYLE",
		"MOVE_NODE",
		"RESIZE_NODE",
		"SHOW_NODE",
		"HIDE_NODE",
		"REMOVE_NODE",
		"SPAWN_NODE",
		"SCREEN_FADE",
		"SET_TIME_OF_DAY",
		"SCREEN_FLASH",
		"SCREEN_SHAKE",
		"CAMERA_ZOOM",
		"CAMERA_PAN",
		"CAMERA_RESET",
		"SHOW_IMAGE",
		"HIDE_IMAGE",
		"SET_TEXT_SPEED",
		"CLEAR_DIALOGUE",
		"SHOW_NOTIFICATION",
		"END_GAME",
		"RETURN_TO_TITLE",
		"OPEN_MENU",
		"SAVE_GAME",
		"LOAD_GAME",
	]
