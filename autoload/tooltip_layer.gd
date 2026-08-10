extends CanvasLayer
## 全局悬浮提示层：显示在屏幕顶层，不受任何容器裁剪。
## 任意控件调用 TooltipLayer.show_tooltip(text, global_pos) / hide_tooltip()；鼠标移动时调用 move_tooltip() 跟随。

const TOOLTIP_SCENE: PackedScene = preload("res://scenes/apps/obs_live/components/card_tooltip.tscn")
const TOOLTIP_OFFSET: Vector2 = Vector2(18, 18)
const VIEWPORT_MARGIN: float = 8.0

var _tooltip: CardTooltipView = null


func _ready() -> void:
	layer = 100
	_tooltip = TOOLTIP_SCENE.instantiate()
	add_child(_tooltip)
	_tooltip.visible = false


func show_tooltip(text: String, global_pos: Vector2) -> void:
	if _tooltip == null:
		return
	_tooltip.configure(text)
	_tooltip.reset_size()
	_tooltip.position = _clamp_position(global_pos + TOOLTIP_OFFSET, _tooltip.size)
	_tooltip.visible = true


func move_tooltip(global_pos: Vector2) -> void:
	if _tooltip == null or not _tooltip.visible:
		return
	_tooltip.position = _clamp_position(global_pos + TOOLTIP_OFFSET, _tooltip.size)


func hide_tooltip() -> void:
	if _tooltip != null:
		_tooltip.visible = false


func is_tooltip_visible() -> bool:
	return _tooltip != null and _tooltip.visible


func _clamp_position(pos: Vector2, tip_size: Vector2) -> Vector2:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	if pos.x + tip_size.x > viewport_size.x - VIEWPORT_MARGIN:
		pos.x = pos.x - tip_size.x - TOOLTIP_OFFSET.x * 2.0
	if pos.y + tip_size.y > viewport_size.y - VIEWPORT_MARGIN:
		pos.y = pos.y - tip_size.y - TOOLTIP_OFFSET.y * 2.0
	pos.x = clampf(pos.x, VIEWPORT_MARGIN, maxf(VIEWPORT_MARGIN, viewport_size.x - tip_size.x - VIEWPORT_MARGIN))
	pos.y = clampf(pos.y, VIEWPORT_MARGIN, maxf(VIEWPORT_MARGIN, viewport_size.y - tip_size.y - VIEWPORT_MARGIN))
	return pos
