extends CommandHandler
class_name ScreenFlashHandler
## Handler for SCREEN_FLASH command
## 屏幕闪烁效果（白闪/黑闪等）。非阻塞 — 触发后立即继续。
## 参数:
##   color: 闪烁颜色（默认白色）
##   duration: 闪烁持续时间（秒）
##   intensity: 闪烁强度 0.0-1.0（也兼容 small/medium/large、轻/中/重）

const ParamDef = preload("res://scripts/avg/commands/param_definition.gd")

const INTENSITY_PRESETS: Dictionary = {
	"light": 0.35,
	"small": 0.35,
	"soft": 0.35,
	"low": 0.35,
	"weak": 0.35,
	"轻": 0.35,
	"弱": 0.35,
	"medium": 0.7,
	"mid": 0.7,
	"normal": 0.7,
	"moderate": 0.7,
	"中": 0.7,
	"普通": 0.7,
	"large": 1.0,
	"heavy": 1.0,
	"strong": 1.0,
	"high": 1.0,
	"重": 1.0,
	"强": 1.0,
}


func _init() -> void:
	super._init("SCREEN_FLASH")


func _create_schema() -> ParamSchemaClass:
	var schema := ParamSchemaClass.new(
		command_type,
		"Screen flash effect"
	)

	schema.add_param(ParamDef.color_param(
		"color",
		"Flash color",
		false,
		Color.WHITE,
		"颜色"
	))

	schema.add_param(ParamDef.float_param(
		"duration",
		"Flash duration in seconds",
		false,
		0.3,
		"时长"
	))

	schema.add_param(ParamDef.float_param(
		"intensity",
		"Flash intensity (0.0 to 1.0)",
		false,
		1.0,
		"强度"
	))

	return schema


func validate(command: Resource):
	if command == null:
		return ValidationResultClass.error("Command is null")

	var result := ValidationResultClass.new()
	var params: Dictionary = command.params if command.params != null else {}

	if not _coerce_number(params.get("duration", null), 0.3).get("valid", false):
		result.add_error("Parameter 'duration' must be a number")

	return result


func execute(command: Resource, context: RefCounted) -> CommandResultClass:
	var color: Color = _get_param(command, "color", Color.WHITE)
	var duration_result: Dictionary = _coerce_number(_get_param(command, "duration", 0.3), 0.3)
	var intensity_result: Dictionary = _coerce_intensity(_get_param(command, "intensity", 1.0), 1.0)
	var duration: float = duration_result.get("value", 0.3)
	var intensity: float = intensity_result.get("value", 1.0)

	if context.scene_runner != null and context.scene_runner.has_method("screen_flash"):
		context.scene_runner.screen_flash(color, duration, intensity)

	return CommandResultClass.ok({
		"color": color,
		"duration": duration,
		"intensity": intensity,
	})


func _coerce_intensity(value: Variant, default_value: float) -> Dictionary:
	if value is String:
		var text: String = value.strip_edges().to_lower()
		if text.is_empty():
			return {"valid": true, "value": default_value}
		if INTENSITY_PRESETS.has(text):
			return {"valid": true, "value": float(INTENSITY_PRESETS[text])}
		return _coerce_number(text, default_value, 0.0, 1.0)

	return _coerce_number(value, default_value, 0.0, 1.0)


func _coerce_number(
	value: Variant,
	default_value: float,
	min_value: float = -INF,
	max_value: float = INF
) -> Dictionary:
	if value == null:
		return {"valid": true, "value": default_value}

	var number: float = default_value
	if value is float or value is int:
		number = float(value)
	elif value is String:
		var text: String = value.strip_edges()
		if text.is_empty():
			return {"valid": true, "value": default_value}
		if text.is_valid_int() or text.is_valid_float():
			number = text.to_float()
		else:
			return {"valid": true, "value": default_value}
	else:
		return {"valid": false, "value": default_value}

	number = clampf(number, min_value, max_value)
	return {"valid": true, "value": number}
