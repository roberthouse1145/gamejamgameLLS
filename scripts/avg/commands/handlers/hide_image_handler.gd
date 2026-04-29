extends CommandHandler
class_name HideImageHandler
## Handler for HIDE_IMAGE command
## 隐藏/移除图片层中的图片。非阻塞。
## 参数:
##   image_id: 要隐藏的图片标识（对应 SHOW_IMAGE 的 image_id）
##   fade_duration: 淡出时间（秒），0=立即隐藏
##   transition: 隐藏方式（fade / instant）

const ParamDef = preload("res://scripts/avg/commands/param_definition.gd")


func _init() -> void:
	super._init("HIDE_IMAGE")


func _create_schema() -> ParamSchemaClass:
	var schema := ParamSchemaClass.new(
		command_type,
		"Hide/remove an image from the image layer"
	)

	schema.add_param(ParamDef.string_param(
		"image_id",
		"Image identifier to hide (from SHOW_IMAGE)",
		true,
		"",
		"",
		"图片ID"
	))

	schema.add_param(ParamDef.float_param(
		"fade_duration",
		"Fade out duration in seconds (0 = instant)",
		false,
		0.0,
		"淡出时长"
	))

	schema.add_param(ParamDef.choices_param(
		"transition",
		["", "fade", "instant"],
		"Hide transition mode",
		false,
		"",
		"切换"
	))

	return schema


func execute(command: Resource, context: RefCounted) -> CommandResultClass:
	var image_id: String = _get_param(command, "image_id", "")
	if image_id.is_empty():
		return CommandResultClass.error("image_id is required")

	var fade_duration: float = _get_param(command, "fade_duration", 0.0)
	var transition: String = _get_param(command, "transition", "")

	if context.scene_runner != null and context.scene_runner.has_method("hide_image"):
		context.scene_runner.hide_image(image_id, fade_duration, transition)

	return CommandResultClass.ok({
		"image_id": image_id,
		"fade_duration": fade_duration,
		"transition": transition,
	})
