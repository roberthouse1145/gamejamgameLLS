extends CommandHandler
class_name ScreenShakeHandler
## Handler for SCREEN_SHAKE command
## 屏幕震动效果。非阻塞 — 触发后立即继续。
## 参数:
##   intensity: 震动强度（像素偏移量，支持数值或 small/medium/large）
##   duration: 震动持续时间（秒）
##   frequency: 震动频率（每秒震动次数）

const ParamDef = preload("res://scripts/avg/commands/param_definition.gd")

const INTENSITY_PRESETS: Dictionary = {
	"small": 5.0,
	"medium": 10.0,
	"large": 15.0,
}


func _init() -> void:
	super._init("SCREEN_SHAKE")


func _create_schema() -> ParamSchemaClass:
	var schema := ParamSchemaClass.new(
		command_type,
		"Screen shake effect"
	)

	schema.add_param(ParamDef.string_param(
		"intensity",
		"Shake intensity in pixels or preset: small, medium, large",
		false,
		"10.0",
		"",
		"强度"
	))

	schema.add_param(ParamDef.float_param(
		"duration",
		"Shake duration in seconds",
		false,
		0.5,
		"时长"
	))

	schema.add_param(ParamDef.float_param(
		"frequency",
		"Shake frequency (times per second)",
		false,
		20.0,
		"频率"
	))

	return schema


func validate(command: Resource):
	if command == null:
		return ValidationResultClass.error("Command is null")

	var result := ValidationResultClass.new()
	var params: Dictionary = command.params if command.params != null else {}

	if not _coerce_intensity(params.get("intensity", null), 10.0).get("valid", false):
		result.add_error("Parameter 'intensity' must be a number or one of: small, medium, large")

	if not _coerce_number(params.get("duration", null), 0.5).get("valid", false):
		result.add_error("Parameter 'duration' must be a number")

	if not _coerce_number(params.get("frequency", null), 20.0).get("valid", false):
		result.add_error("Parameter 'frequency' must be a number")

	return result


func execute(command: Resource, context: RefCounted) -> CommandResultClass:
	var intensity_result: Dictionary = _coerce_intensity(_get_param(command, "intensity", "10.0"), 10.0)
	var duration_result: Dictionary = _coerce_number(_get_param(command, "duration", 0.5), 0.5)
	var frequency_result: Dictionary = _coerce_number(_get_param(command, "frequency", 20.0), 20.0)

	var intensity: float = intensity_result.get("value", 10.0)
	var duration: float = duration_result.get("value", 0.5)
	var frequency: float = frequency_result.get("value", 20.0)

	if context.scene_runner != null and context.scene_runner.has_method("screen_shake"):
		context.scene_runner.screen_shake(intensity, duration, frequency)

	return CommandResultClass.ok({
		"intensity": intensity,
		"duration": duration,
		"frequency": frequency,
	})


func _coerce_intensity(value: Variant, default_value: float) -> Dictionary:
	if value is String:
		var text: String = value.strip_edges().to_lower()
		if text.is_empty():
			return {"valid": true, "value": default_value}
		if INTENSITY_PRESETS.has(text):
			return {"valid": true, "value": float(INTENSITY_PRESETS[text])}
		return _coerce_number(text, default_value)

	return _coerce_number(value, default_value)


func _coerce_number(value: Variant, default_value: float) -> Dictionary:
	if value == null:
		return {"valid": true, "value": default_value}

	if value is float or value is int:
		return {"valid": true, "value": float(value)}

	if value is String:
		var text: String = value.strip_edges()
		if text.is_empty():
			return {"valid": true, "value": default_value}
		if text.is_valid_int() or text.is_valid_float():
			return {"valid": true, "value": text.to_float()}

	return {"valid": false, "value": default_value}
