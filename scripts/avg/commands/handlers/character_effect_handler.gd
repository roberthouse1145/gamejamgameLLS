extends CommandHandler
class_name CharacterEffectHandler
## Handler for CHARACTER_EFFECT command
## Plays animation effects on a character (jump, shake, nod, bounce).

const ParamDef = preload("res://scripts/avg/commands/param_definition.gd")

const INTENSITY_ALIASES: Dictionary = {
	"small": "small",
	"light": "small",
	"soft": "small",
	"弱": "small",
	"轻": "small",
	"medium": "medium",
	"mid": "medium",
	"normal": "medium",
	"普通": "medium",
	"中": "medium",
	"large": "large",
	"heavy": "large",
	"strong": "large",
	"强": "large",
	"重": "large",
}


func _init() -> void:
	super._init("CHARACTER_EFFECT")


func _create_schema() -> ParamSchemaClass:
	var schema := ParamSchemaClass.new(command_type, "角色动画特效")
	schema.add_param(ParamDef.character_ref_param("character_id", "角色ID", true, "角色"))
	schema.add_param(ParamDef.choices_param("effect", ["jump", "shake", "nod", "bounce"], "特效类型", true, "jump", "特效"))
	schema.add_param(ParamDef.choices_param("intensity", ["small", "medium", "large"], "强度", false, "medium", "强度"))
	schema.add_param(ParamDef.float_param("duration", "持续时长(-1=自动)", false, -1.0, "时长"))
	return schema


func execute(command: Resource, context: RefCounted) -> CommandResultClass:
	var character_id: String = _get_param(command, "character_id", "")
	var effect_name: String = _get_param(command, "effect", "jump")
	var raw_intensity: Variant = command.params.get("intensity", "medium") if command != null and command.params != null else "medium"
	var intensity: String = _normalize_intensity(raw_intensity)
	var duration: float = _get_param(command, "duration", -1.0)

	if character_id.is_empty():
		return CommandResultClass.error("character_id is required")

	if context.character_display != null:
		context.character_display.play_effect(character_id, effect_name, intensity, duration)

	return CommandResultClass.ok()


func _normalize_intensity(value: Variant) -> String:
	var text: String = str(value).strip_edges().to_lower()
	if text.is_empty():
		return "medium"
	if INTENSITY_ALIASES.has(text):
		return str(INTENSITY_ALIASES[text])
	return "medium"
