class_name ParamDefinition extends Resource
## Parameter Definition for AVG Command Parameters
## Defines a single parameter's metadata for UI generation.
## Validates: Requirement 10.7

## Parameter name (used as key in params Dictionary)
@export var name: String = ""

## Display name for UI (localized). Falls back to name if empty.
@export var display_name: String = ""

## Parameter type: "string", "int", "float", "bool", "character_ref",
## "scene_ref", "texture", "audio", "choices", "color", "vector2"
@export var type: String = "string"

## Default value when parameter is not specified
@export var default_value: Variant = null

## Human-readable description for UI tooltips
@export var description: String = ""

## Whether this parameter is required
@export var required: bool = true

## Available options for enum/choices type parameters
@export var options: Array = []  # Array[String] or Array[Dictionary]

## Additional hints for UI generation (e.g., "multiline" for text)
@export var hint: String = ""

## Reference type for assisted selection (e.g., "character_ref", "variable_ref", "scene_ref")
## When set on a string param, UI shows a browse button alongside the text input.
@export var ref_type: String = ""

## Conditional visibility: "param_name == value" or "param_name != value"
## When set, this parameter is only visible in UI when the condition is met.
## Supports: ==, !=, and comma-separated values: "param_name == a,b,c"
@export var visible_when: String = ""


func _init(
	p_name: String = "",
	p_type: String = "string",
	p_default_value: Variant = null,
	p_description: String = "",
	p_required: bool = true,
	p_options: Array = [],
	p_hint: String = "",
	p_display_name: String = ""
) -> void:
	name = p_name
	type = p_type
	default_value = p_default_value
	description = p_description
	required = p_required
	options = p_options
	hint = p_hint
	display_name = p_display_name


## Get the display name (falls back to name)
func get_display_name() -> String:
	return display_name if not display_name.is_empty() else name


## Create a string parameter
static func string_param(
	p_name: String,
	p_description: String = "",
	p_required: bool = true,
	p_default: String = "",
	p_hint: String = "",
	p_display_name: String = "",
	p_ref_type: String = ""
) -> ParamDefinition:
	var p := ParamDefinition.new(p_name, "string", p_default, p_description, p_required, [], p_hint, p_display_name)
	p.ref_type = p_ref_type
	return p


## Create an integer parameter
static func int_param(
	p_name: String,
	p_description: String = "",
	p_required: bool = true,
	p_default: int = 0,
	p_display_name: String = ""
) -> ParamDefinition:
	return ParamDefinition.new(p_name, "int", p_default, p_description, p_required, [], "", p_display_name)


## Create a float parameter
static func float_param(
	p_name: String,
	p_description: String = "",
	p_required: bool = true,
	p_default: float = 0.0,
	p_display_name: String = ""
) -> ParamDefinition:
	return ParamDefinition.new(p_name, "float", p_default, p_description, p_required, [], "", p_display_name)


## Create a boolean parameter
static func bool_param(
	p_name: String,
	p_description: String = "",
	p_required: bool = true,
	p_default: bool = false,
	p_display_name: String = ""
) -> ParamDefinition:
	return ParamDefinition.new(p_name, "bool", p_default, p_description, p_required, [], "", p_display_name)


## Create a choices/enum parameter
static func choices_param(
	p_name: String,
	p_options: Array,
	p_description: String = "",
	p_required: bool = true,
	p_default: String = "",
	p_display_name: String = ""
) -> ParamDefinition:
	var default_val: String = p_default if p_default != "" else (p_options[0] if p_options.size() > 0 else "")
	return ParamDefinition.new(p_name, "choices", default_val, p_description, p_required, p_options, "", p_display_name)


## Create a character reference parameter
static func character_ref_param(
	p_name: String,
	p_description: String = "",
	p_required: bool = true,
	p_display_name: String = ""
) -> ParamDefinition:
	return ParamDefinition.new(p_name, "character_ref", "", p_description, p_required, [], "", p_display_name)


## Create a scene reference parameter
static func scene_ref_param(
	p_name: String,
	p_description: String = "",
	p_required: bool = true,
	p_display_name: String = ""
) -> ParamDefinition:
	return ParamDefinition.new(p_name, "scene_ref", "", p_description, p_required, [], "", p_display_name)


## Create a texture parameter
static func texture_param(
	p_name: String,
	p_description: String = "",
	p_required: bool = true,
	p_display_name: String = ""
) -> ParamDefinition:
	return ParamDefinition.new(p_name, "texture", null, p_description, p_required, [], "", p_display_name)


## Create an audio parameter
static func audio_param(
	p_name: String,
	p_description: String = "",
	p_required: bool = true,
	p_display_name: String = ""
) -> ParamDefinition:
	return ParamDefinition.new(p_name, "audio", null, p_description, p_required, [], "", p_display_name)


## Create a color parameter
static func color_param(
	p_name: String,
	p_description: String = "",
	p_required: bool = true,
	p_default: Color = Color.WHITE,
	p_display_name: String = ""
) -> ParamDefinition:
	return ParamDefinition.new(p_name, "color", p_default, p_description, p_required, [], "", p_display_name)


## Create a variable reference parameter
static func variable_ref_param(
	p_name: String,
	p_description: String = "",
	p_required: bool = true,
	p_display_name: String = ""
) -> ParamDefinition:
	return ParamDefinition.new(p_name, "variable_ref", "", p_description, p_required, [], "", p_display_name)


## Create a vector2 parameter
static func vector2_param(
	p_name: String,
	p_description: String = "",
	p_required: bool = true,
	p_default: Vector2 = Vector2.ZERO,
	p_display_name: String = ""
) -> ParamDefinition:
	return ParamDefinition.new(p_name, "vector2", p_default, p_description, p_required, [], "", p_display_name)
