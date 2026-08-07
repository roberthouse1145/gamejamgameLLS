class_name StreamerCharacterResource extends Resource
## 直播域的主播视觉定义。与 AVGCharacter 相互独立。

@export var streamer_id: StringName = &""
@export var display_name: String = ""
@export var expressions: Dictionary = {}
@export var default_expression: StringName = &"default"
## 相对于直播画面尺寸的立绘中心偏移。
@export var portrait_offset: Vector2 = Vector2.ZERO
## 立绘目标高度相对于直播画面高度的倍率。
@export_range(0.1, 3.0, 0.05) var portrait_scale: float = 1.0


func get_expression_names() -> Array[StringName]:
	var names: Array[StringName] = []
	for key: Variant in expressions.keys():
		var expression_name := StringName(str(key).strip_edges())
		if not String(expression_name).is_empty():
			names.append(expression_name)
	names.sort()
	return names


func has_expression(expression_name: StringName) -> bool:
	return expressions.has(expression_name) or expressions.has(String(expression_name))


func get_expression_texture(expression_name: StringName) -> Texture2D:
	var texture: Texture2D = _get_texture(expression_name)
	if texture != null:
		return texture
	if expression_name != default_expression:
		return _get_texture(default_expression)
	return null


func is_valid() -> bool:
	return (
		not String(streamer_id).strip_edges().is_empty()
		and not display_name.strip_edges().is_empty()
		and has_expression(default_expression)
		and get_expression_texture(default_expression) != null
	)


func _get_texture(expression_name: StringName) -> Texture2D:
	var value: Variant = expressions.get(expression_name, expressions.get(String(expression_name), null))
	return value as Texture2D
