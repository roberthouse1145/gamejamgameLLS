extends RefCounted
## Audio command handlers for AVG engine
## Contains handlers for PLAY_BGM, STOP_BGM, and PLAY_SFX commands.
## Validates: Requirement 10.1

const CommandHandlerBase = preload("res://scripts/avg/commands/command_handler.gd")
const CommandResultClass = preload("res://scripts/avg/commands/command_result.gd")
const ParamSchemaClass = preload("res://scripts/avg/commands/param_schema.gd")
const ParamDef = preload("res://scripts/avg/commands/param_definition.gd")


## Handler for PLAY_BGM command
## Plays background music with optional fade-in.
class PlayBGMHandler extends CommandHandlerBase:
	
	func _init() -> void:
		super._init("PLAY_BGM")
	
	
	## Create the parameter schema for PLAY_BGM command
	func _create_schema() -> ParamSchemaClass:
		var schema := ParamSchemaClass.new(
			command_type,
			"Plays background music with optional fade-in"
		)
		
		schema.add_param(ParamDef.audio_param(
			"audio_path",
			"Path to the audio file to play",
			true,
			"音频路径"
		))
		
		schema.add_param(ParamDef.float_param(
			"fade_duration",
			"Duration of the fade-in in seconds",
			false,
			1.0,
			"淡入时长"
		))
		
		schema.add_param(ParamDef.float_param(
			"volume",
			"Volume level (0.0 to 1.0)",
			false,
			1.0,
			"音量"
		))
		
		return schema
	
	
	## Execute the PLAY_BGM command
	func execute(command: Resource, context: RefCounted) -> CommandResultClass:
		var audio_path: String = _get_param(command, "audio_path", "")
		var fade_duration: float = _get_param(command, "fade_duration", 1.0)
		var volume: float = _get_param(command, "volume", 1.0)
		
		if audio_path.is_empty():
			return CommandResultClass.error("audio_path is required for PLAY_BGM command")
		
		# Clamp volume to valid range
		volume = clampf(volume, 0.0, 1.0)
		
		# Execute the BGM play
		if context.audio_manager != null:
			context.audio_manager.play_bgm(audio_path, fade_duration, volume)
		else:
			push_warning("PlayBGMHandler: audio_manager not available in context")
		
		return CommandResultClass.ok({
			"audio_path": audio_path,
			"fade_duration": fade_duration,
			"volume": volume
		})


## Handler for STOP_BGM command
## Stops background music with optional fade-out.
class StopBGMHandler extends CommandHandlerBase:
	
	func _init() -> void:
		super._init("STOP_BGM")
	
	
	## Create the parameter schema for STOP_BGM command
	func _create_schema() -> ParamSchemaClass:
		var schema := ParamSchemaClass.new(
			command_type,
			"Stops background music with optional fade-out"
		)
		
		schema.add_param(ParamDef.float_param(
			"fade_duration",
			"Duration of the fade-out in seconds",
			false,
			1.0,
			"淡出时长"
		))
		
		return schema
	
	
	## Execute the STOP_BGM command
	func execute(command: Resource, context: RefCounted) -> CommandResultClass:
		var fade_duration: float = _get_param(command, "fade_duration", 1.0)
		
		# Execute the BGM stop
		if context.audio_manager != null:
			context.audio_manager.stop_bgm(fade_duration)
		else:
			push_warning("StopBGMHandler: audio_manager not available in context")
		
		return CommandResultClass.ok({"fade_duration": fade_duration})


## Handler for PLAY_SFX command
## Plays a sound effect.
class PlaySFXHandler extends CommandHandlerBase:
	
	func _init() -> void:
		super._init("PLAY_SFX")
	
	
	## Create the parameter schema for PLAY_SFX command
	func _create_schema() -> ParamSchemaClass:
		var schema := ParamSchemaClass.new(
			command_type,
			"Plays a sound effect"
		)
		
		schema.add_param(ParamDef.audio_param(
			"audio_path",
			"Path to the sound effect file to play",
			true,
			"音频路径"
		))
		
		schema.add_param(ParamDef.float_param(
			"volume",
			"Volume level (0.0 to 1.0)",
			false,
			1.0,
			"音量"
		))
		
		return schema
	
	
	## Execute the PLAY_SFX command
	func execute(command: Resource, context: RefCounted) -> CommandResultClass:
		var audio_path: String = _get_param(command, "audio_path", "")
		var volume: float = _get_param(command, "volume", 1.0)
		
		if audio_path.is_empty():
			return CommandResultClass.error("audio_path is required for PLAY_SFX command")
		
		# Clamp volume to valid range
		volume = clampf(volume, 0.0, 1.0)
		
		# Execute the SFX play
		if context.audio_manager != null:
			context.audio_manager.play_sfx(audio_path, volume)
		else:
			push_warning("PlaySFXHandler: audio_manager not available in context")
		
		return CommandResultClass.ok({
			"audio_path": audio_path,
			"volume": volume
		})
