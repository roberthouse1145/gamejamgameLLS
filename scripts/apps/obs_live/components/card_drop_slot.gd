class_name CardDropSlot extends CardSlot
## OBS 拼图空卡框槽：复用通用 CardSlot 契约，保留 CardSlotEdges 视觉。

signal card_dropped(slot_key: Variant, data: Dictionary)

const COLOR_PLACEHOLDER: Color = Color("#68748A")

var _slot_edges: CardSlotEdges = null
var _content_host: Control = null


func _ready() -> void:
	# Skip generic panel chrome; build puzzle edges instead.
	mouse_filter = Control.MOUSE_FILTER_STOP
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = CardDisplayMetrics.FULL_SIZE
	_build_puzzle_chrome()
	_refresh_style()


func setup(key: Variant, kinds: Array, text: String, slot_size: Vector2 = CardDisplayMetrics.FULL_SIZE) -> void:
	if _slot_edges == null:
		_build_puzzle_chrome()
	super.setup(key, kinds, text, slot_size)
	if _placeholder != null:
		_placeholder.text = text
	_fit_puzzle()


## 兼容旧 API：放入已生成的卡牌视图。
func set_content(content: Control) -> void:
	if _slot_edges == null:
		_build_puzzle_chrome()
	set_card(content)


func clear_content() -> void:
	clear_card()


func has_content() -> bool:
	return has_card()


func _build_puzzle_chrome() -> void:
	if _slot_edges != null:
		return
	_slot_edges = CardSlotEdges.new()
	_slot_edges.name = "SlotEdges"
	_slot_edges.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slot_edges.configure([], [], false)
	add_child(_slot_edges)

	_placeholder = Label.new()
	_placeholder.name = "Placeholder"
	_placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_placeholder.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_placeholder.add_theme_font_size_override("font_size", 26)
	_placeholder.add_theme_color_override("font_color", COLOR_PLACEHOLDER)
	_placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_placeholder.text = placeholder_text
	add_child(_placeholder)
	_panel = null
	_fit_puzzle()


func _fit_puzzle() -> void:
	if _slot_edges == null or _placeholder == null:
		return
	var target: Vector2 = size if size.x > 1.0 and size.y > 1.0 else custom_minimum_size
	_slot_edges.position = Vector2.ZERO
	_slot_edges.size = target
	_slot_edges.queue_redraw()
	_placeholder.position = Vector2(48, 48)
	_placeholder.size = Vector2(maxi(target.x - 96.0, 1.0), maxi(target.y - 96.0, 1.0))


func _refresh_style() -> void:
	if _slot_edges == null:
		return
	_fit_puzzle()
	_placeholder.visible = not has_card()
	_slot_edges.visible = not has_card()
	var highlight: bool = _preview_active and _preview_ok and not locked
	_slot_edges.set_interaction_state(false, highlight, locked)
	_slot_edges.queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _slot_edges != null:
		_fit_puzzle()


func emit_dropped(data: Dictionary) -> void:
	card_dropped.emit(slot_key, data)
