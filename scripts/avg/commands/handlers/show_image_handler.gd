extends "res://scripts/avg/commands/command_handler.gd"
class_name ShowImageHandler
## Handler for SHOW_IMAGE command
## 显示CG/图片到图片层。非阻塞。
## 参数:
##   image_id: 图片唯一标识（用于后续 HIDE_IMAGE 引用）
##   image_path: 图片路径（相对于项目资源目录）
##   position: 归一化位置 Vector2 (0,0)=左上 (0.5,0.5)=居中
##   size: 归一化尺寸 Vector2 (1,1)=全屏
##   fade_duration: 淡入时间（秒），0=立即显示
##   z_order: 图层顺序（越大越靠前）

const ParamDef = preload("res://scripts/avg/commands/param_definition.gd")


func _init() -> void:
	super._init("SHOW_IMAGE")


func _create_schema() -> ParamSchemaClass:
	var schema := ParamSchemaClass.new(
		command_type,
		"Show an image/CG on the image layer"
	)

	schema.add_param(ParamDef.string_param(
		"image_id",
		"Unique identifier for this image instance",
		true,
		"",
		"",
		"图片ID"
	))

	schema.add_param(ParamDef.string_param(
		"image_path",
		"Path to the image file",
		true,
		"",
		"",
		"图片路径",
		"texture"
	))

	schema.add_param(ParamDef.vector2_param(
		"position",
		"Normalized position (0.5, 0.5 = center)",
		false,
		Vector2(0.0, 0.0),
		"位置"
	))

	schema.add_param(ParamDef.vector2_param(
		"size",
		"Normalized size (1.0, 1.0 = full screen)",
		false,
		Vector2(1.0, 1.0),
		"尺寸"
	))

	schema.add_param(ParamDef.float_param(
		"fade_duration",
		"Fade in duration in seconds (0 = instant)",
		false,
		0.0,
		"淡入时长"
	))

	schema.add_param(ParamDef.int_param(
		"z_order",
		"Layer order (higher = on top)",
		false,
		0,
		"图层顺序"
	))

	return schema


func execute(command: Resource, context: RefCounted) -> CommandResultClass:
	var image_id: String = _get_param(command, "image_id", "")
	var image_path: String = _get_param(command, "image_path", "")

	if image_id.is_empty():
		return CommandResultClass.error("image_id is required")
	if image_path.is_empty():
		return CommandResultClass.error("image_path is required")

	var pos: Vector2 = _get_param(command, "position", Vector2(0.0, 0.0))
	var img_size: Vector2 = _get_param(command, "size", Vector2(1.0, 1.0))
	var fade_duration: float = _get_param(command, "fade_duration", 0.0)
	var z_order: int = _get_param(command, "z_order", 0)

	if context.scene_runner != null and context.scene_runner.has_method("show_image"):
		context.scene_runner.show_image(image_id, image_path, pos, img_size, fade_duration, z_order)

	return CommandResultClass.ok({
		"image_id": image_id,
		"image_path": image_path,
		"position": pos,
		"size": img_size,
		"fade_duration": fade_duration,
		"z_order": z_order,
	})
