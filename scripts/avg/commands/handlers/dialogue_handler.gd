extends "res://scripts/avg/commands/command_handler.gd"
class_name DialogueHandler
## Handler for DIALOGUE command
## 显示对话文本。合并了原 NARRATION 功能。
## speaker 为空时为旁白模式，填 character_id 自动解析为角色名，填普通字符串直接显示。

const ParamDef = preload("res://scripts/avg/commands/param_definition.gd")


func _init() -> void:
	super._init("DIALOGUE")


## Create the parameter schema for DIALOGUE command
func _create_schema() -> ParamSchemaClass:
	var schema := ParamSchemaClass.new(
		command_type,
		"显示对话文本（speaker 为空时为旁白模式）"
	)

	schema.add_param(ParamDef.string_param(
		"text",
		"对话文本，支持 BBCode",
		true,
		"",
		"multiline",
		"文本"
	))

	schema.add_param(ParamDef.string_param(
		"speaker",
		"说话者：character_id 自动解析为角色名，普通字符串直接显示，空为旁白",
		false,
		"",
		"",
		"说话者",
		"character_ref"
	))

	schema.add_param(ParamDef.string_param(
		"emotion",
		"角色表情（仅 speaker 为有效 character_id 时生效）",
		false,
		"",
		"",
		"表情"
	))

	schema.add_param(ParamDef.float_param(
		"text_speed",
		"打字速度（字/秒），-1 使用项目默认值",
		false,
		-1.0,
		"打字速度"
	))

	schema.add_param(ParamDef.audio_param(
		"voice",
		"语音文件",
		false,
		"语音"
	))

	schema.add_param(ParamDef.choices_param(
		"position",
		["default", "bottom", "center", "top"],
		"对话框位置",
		false,
		"default",
		"对话框位置"
	))

	schema.add_param(ParamDef.bool_param(
		"transparent",
		"是否隐藏对话框背景",
		false,
		false,
		"透明背景"
	))

	return schema


## Execute the DIALOGUE command
func execute(command: Resource, context: RefCounted) -> CommandResultClass:
	var text: String = _get_param(command, "text", "")
	var speaker: String = _get_param(command, "speaker", "")
	if speaker.is_empty():
		speaker = _get_param(command, "speaker_id", "")
	if speaker.is_empty():
		speaker = _get_param(command, "speaker_name", "")
	var emotion: String = _get_param(command, "emotion", "")
	if emotion.is_empty():
		emotion = _get_param(command, "expression", "")
	var text_speed: float = _get_param(command, "text_speed", -1.0)
	var voice: Variant = _get_param(command, "voice", null)
	var position: String = _get_param(command, "position", "default")
	var transparent: bool = _get_param(command, "transparent", false)

	if text.is_empty():
		return CommandResultClass.error("text is required for DIALOGUE command")

	if context.dialog_box != null:
		context.dialog_box.show_dialogue({
			"text": text,
			"speaker": speaker,
			"emotion": emotion,
			"text_speed": text_speed,
			"voice": voice,
			"position": position,
			"transparent": transparent,
		})
	else:
		push_warning("DialogueHandler: dialog_box not available in context")

	# Emotion linkage: if speaker is a valid character_id and emotion is set,
	# trigger expression change on CharacterDisplay
	if not speaker.is_empty() and not emotion.is_empty() and context.character_display != null:
		var target_character_id: String = ""
		if context.character_display.has_method("resolve_visible_character_id"):
			target_character_id = context.character_display.resolve_visible_character_id(speaker)
		elif context.character_display.is_character_visible(speaker):
			target_character_id = speaker
		if not target_character_id.is_empty():
			context.character_display.change_expression(target_character_id, emotion)

	# 播放语音
	if voice != null and context.audio_manager != null:
		var voice_path: String = ""
		if voice is String:
			voice_path = voice
		elif voice is Resource:
			voice_path = voice.resource_path
		if not voice_path.is_empty():
			context.audio_manager.play_voice(voice_path)

	return CommandResultClass.ok()
