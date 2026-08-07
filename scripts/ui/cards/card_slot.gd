class_name CardSlot extends Control
## 单卡槽：过滤、锁定、占位高亮；占用时由 DragController 做原子交换。

signal card_changed(card: Control)
signal drop_rejected(card: Control)

const COLOR_EMPTY_BG: Color = Color("#FBF8FB")
const COLOR_EMPTY_BORDER: Color = Color("#C9B9C6")
const COLOR_HOVER_BG: Color = Color("#FFE8EE")
const COLOR_HOVER_BORDER: Color = Color("#E5486D")
const COLOR_LOCKED_BG: Color = Color("#EDF2F8")
const COLOR_LOCKED_BORDER: Color = Color("#8793A5")
const COLOR_TEXT: Color = Color("#9A8997")

@export var accepted_kinds: Array[String] = []
@export var locked: bool = false:
	set(value):
		locked = value
		_refresh_style()
@export var placeholder_text: String = "放置卡牌":
	set(value):
		placeholder_text = value
		if _placeholder != null:
			_placeholder.text = value
@export var card_size: Vector2 = CardDisplayMetrics.FULL_SIZE

var slot_key: Variant = 0
var accept_filter: Callable = Callable()

var _card: Control = null
var _placeholder: Label = null
var _panel: PanelContainer = null
var _preview_active: bool = false
var _preview_ok: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = CardDisplayMetrics.FULL_SIZE
	_build_chrome()
	_refresh_style()


func is_card_container() -> bool:
	return true


func get_card_size() -> Vector2:
	return card_size


func setup(key: Variant, kinds: Array, text: String, slot_size: Vector2 = CardDisplayMetrics.FULL_SIZE) -> void:
	slot_key = key
	accepted_kinds.clear()
	for kind_value: Variant in kinds:
		accepted_kinds.append(String(kind_value))
	placeholder_text = text
	card_size = slot_size
	custom_minimum_size = slot_size
	if is_inside_tree():
		size = slot_size
	_refresh_style()


func set_accept_filter(filter: Callable) -> void:
	accept_filter = filter


func has_card() -> bool:
	return _card != null and is_instance_valid(_card)


func get_card() -> Control:
	return _card


func get_card_index(_card_ref: Control) -> int:
	return 0 if has_card() else -1


func can_release_card(_card_ref: Control) -> bool:
	return has_card() and not locked


func can_accept_card(card: Control, _from_container: Node) -> bool:
	if locked or card == null:
		return false
	if has_card() and card == _card:
		return true
	var payload: Dictionary = _payload_of(card)
	if not accepted_kinds.is_empty():
		var kind: String = String(payload.get("kind", ""))
		if kind not in accepted_kinds:
			return false
	if accept_filter.is_valid() and not bool(accept_filter.call(card, payload)):
		return false
	return true


func is_drop_position_valid(card: Control, _global_pos: Vector2) -> bool:
	if card == null:
		return false
	var card_center: Vector2 = card.get_global_transform() * (card.size * 0.5)
	return get_global_rect().has_point(card_center)


func set_card(card: Control) -> void:
	if _placeholder == null and _panel == null:
		_build_chrome()
	if card == null:
		clear_card()
		return
	if _card == card:
		_fit_card()
		return
	if has_card() and _card.get_parent() == self:
		remove_child(_card)
	_card = card
	if card.get_parent() != null:
		card.get_parent().remove_child(card)
	add_child(card)
	if _placeholder != null:
		_placeholder.visible = false
	_fit_card()
	_reset_card_if_idle()
	card_changed.emit(card)
	_refresh_style()


func clear_card() -> void:
	if has_card() and _card.get_parent() == self:
		remove_child(_card)
	_card = null
	if _placeholder != null:
		_placeholder.visible = true
	card_changed.emit(null)
	_refresh_style()


func detach_card_for_drag(card: Control) -> void:
	if card != _card:
		return
	if card.get_parent() == self:
		remove_child(card)
	_card = null
	_placeholder.visible = true
	_refresh_style()


func get_card_global_position(_card_ref: Control) -> Vector2:
	return get_global_transform() * Vector2.ZERO


func card_settled(card: Control) -> void:
	if card == _card:
		_fit_card()


func preview_drag(card: Control, _global_pos: Vector2) -> void:
	_preview_active = true
	_preview_ok = can_accept_card(card, null)
	_refresh_style()


func clear_preview() -> void:
	_preview_active = false
	_preview_ok = false
	_refresh_style()


func _build_chrome() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	_placeholder = Label.new()
	_placeholder.set_anchors_preset(Control.PRESET_FULL_RECT)
	_placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_placeholder.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_placeholder.add_theme_font_size_override("font_size", 26)
	_placeholder.add_theme_color_override("font_color", COLOR_TEXT)
	_placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_placeholder.text = placeholder_text
	_panel.add_child(_placeholder)


func _fit_card() -> void:
	if not has_card():
		return
	_card.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_card.custom_minimum_size = card_size
	_card.size = card_size
	_card.pivot_offset = _card.size * 0.5
	_card.position = Vector2.ZERO


func _reset_card_if_idle() -> void:
	if not has_card():
		return
	for child: Node in _card.get_children():
		if child is CardInteraction:
			var interaction := child as CardInteraction
			if not interaction.is_motion_locked():
				interaction.snap_idle()
			break


func _payload_of(card: Control) -> Dictionary:
	for child: Node in card.get_children():
		if child is CardInteraction:
			return (child as CardInteraction).get_card_payload()
	if card.has_method("get_card_payload"):
		var payload: Variant = card.call("get_card_payload")
		return payload if payload is Dictionary else {}
	if "payload" in card:
		var payload: Variant = card.get("payload")
		return payload if payload is Dictionary else {}
	if "drag_payload" in card:
		var payload: Variant = card.get("drag_payload")
		return payload if payload is Dictionary else {}
	return {}


func _refresh_style() -> void:
	if _panel == null:
		return
	var style := StyleBoxFlat.new()
	if locked:
		style.bg_color = COLOR_LOCKED_BG
		style.border_color = COLOR_LOCKED_BORDER
	elif _preview_active and _preview_ok:
		style.bg_color = COLOR_HOVER_BG
		style.border_color = COLOR_HOVER_BORDER
	else:
		style.bg_color = COLOR_EMPTY_BG
		style.border_color = COLOR_EMPTY_BORDER
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	style.corner_radius_top_left = 20
	style.corner_radius_top_right = 20
	style.corner_radius_bottom_left = 20
	style.corner_radius_bottom_right = 20
	_panel.add_theme_stylebox_override("panel", style)
	_placeholder.visible = not has_card()
