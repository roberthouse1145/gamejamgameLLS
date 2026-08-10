class_name CardDeck extends Control
## 多行牌组：固定行数手牌，或按宽度自动换行（类 GridContainer）。
## auto_wrap=false：按 row_count 均分行，可压缩间距 + hover 展开。
## auto_wrap=true：按可用宽度算列数并自动换行，间距固定为正值。

signal cards_changed
signal card_clicked(card: Control)

const HOVER_LIFT_PAD: float = 24.0

@export var auto_wrap: bool = false:
	set(value):
		auto_wrap = value
		if is_node_ready():
			_request_layout()
@export var row_count: int = 1:
	set(value):
		row_count = maxi(value, 1)
		if is_node_ready():
			_request_layout()
@export var card_size: Vector2 = Vector2(440, 600):
	set(value):
		card_size = Vector2(maxf(value.x, 1.0), maxf(value.y, 1.0))
		if is_node_ready():
			_request_layout()
@export var normal_gap: float = 16.0:
	set(value):
		normal_gap = value
		if is_node_ready():
			_request_layout()
@export var min_gap: float = -360.0
@export var hover_extra_gap: float = 48.0
@export var row_separation: float = 20.0:
	set(value):
		row_separation = value
		if is_node_ready():
			_request_layout()
@export var accepted_kinds: Array[String] = []
@export var locked: bool = false

var accept_filter: Callable = Callable()

var _cards: Array[Control] = []
var _hover_index: int = -1
var _preview_index: int = -1
var _dragging_card: Control = null
var _layout_dirty: bool = false
var _draw_order_sync_queued: bool = false
var _tweens: Dictionary = {} # Control -> Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	if not resized.is_connected(_request_layout):
		resized.connect(_request_layout)
	_request_layout()


func _process(_delta: float) -> void:
	if _layout_dirty:
		_layout_dirty = false
		_layout_cards(true)
		set_process(false)


func is_card_container() -> bool:
	return true


func get_card_size() -> Vector2:
	return card_size


func set_accept_filter(filter: Callable) -> void:
	accept_filter = filter


func get_cards() -> Array[Control]:
	return _cards.duplicate()


func get_card_count() -> int:
	return _cards.size()


func get_card_index(card: Control) -> int:
	return _cards.find(card)


func can_release_card(_card: Control) -> bool:
	return not locked


func can_accept_card(card: Control, _from_container: Node) -> bool:
	if locked or card == null:
		return false
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


func add_card(card: Control, index: int = -1) -> void:
	insert_card(card, index)


func insert_card(card: Control, index: int = -1) -> void:
	if card == null:
		return
	if card in _cards:
		_cards.erase(card)
	var parent: Node = card.get_parent()
	if parent != null and parent != self:
		parent.remove_child(card)
	if card.get_parent() != self:
		add_child(card)
	if index < 0 or index > _cards.size():
		_cards.append(card)
	else:
		_cards.insert(index, card)
	_sync_card_draw_order()
	_dragging_card = null
	_preview_index = -1
	_prepare_card(card)
	_request_layout()
	cards_changed.emit()


func remove_card(card: Control) -> void:
	if card == null:
		return
	_cards.erase(card)
	if card.get_parent() == self:
		remove_child(card)
	_hover_index = -1
	_request_layout()
	cards_changed.emit()


func clear_cards() -> void:
	for card: Control in _cards.duplicate():
		if card.get_parent() == self:
			remove_child(card)
		card.queue_free()
	_cards.clear()
	_hover_index = -1
	_preview_index = -1
	_request_layout()
	cards_changed.emit()


func detach_card_for_drag(card: Control) -> void:
	if card == null:
		return
	_dragging_card = card
	_cards.erase(card)
	if card.get_parent() == self:
		remove_child(card)
	_hover_index = -1
	_request_layout()


func commit_reorder(card: Control, global_pos: Vector2) -> bool:
	var index: int = get_preview_insert_index(global_pos)
	insert_card(card, index)
	_dragging_card = null
	_preview_index = -1
	return true


func get_preview_insert_index(global_pos: Vector2) -> int:
	var count: int = _cards.size()
	if count == 0:
		return 0
	var local: Vector2 = get_global_transform().affine_inverse() * global_pos
	var metrics: Dictionary = _compute_metrics(count)
	var rows: int = int(metrics["rows"])
	var per_row: int = int(metrics["per_row"])
	var card_h: float = float(metrics["card_h"])
	var card_w: float = float(metrics["card_w"])
	var stride: float = float(metrics["stride"])
	var row: int = clampi(int(local.y / (card_h + row_separation)), 0, maxi(rows - 1, 0))
	var row_start: int = row * per_row
	var row_end: int = mini(row_start + per_row, count)
	if row_start >= count:
		return count
	var best: int = row_end
	for i: int in range(row_start, row_end):
		var center_x: float = float(i - row_start) * stride + card_w * 0.5
		if local.x < center_x:
			best = i
			break
	return best


func preview_drag(card: Control, global_pos: Vector2) -> void:
	_dragging_card = card
	_preview_index = get_preview_insert_index(global_pos)
	_request_layout()


func clear_preview() -> void:
	_preview_index = -1
	if _dragging_card != null and _dragging_card not in _cards:
		_dragging_card = null
	_request_layout()


func get_card_global_position(card: Control) -> Vector2:
	var index: int = _cards.find(card)
	if index < 0:
		return card.global_position
	var positions: Dictionary = _compute_positions(_cards.size(), _hover_index, -1)
	var visual_top_left: Vector2 = positions.get(index, Vector2.ZERO)
	return get_global_transform() * visual_top_left


func _prepare_card(card: Control) -> void:
	card.set_anchors_preset(Control.PRESET_TOP_LEFT)
	card.custom_minimum_size = card_size
	card.size = card_size
	card.pivot_offset = card.size * 0.5
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	for child: Node in card.get_children():
		if child is CardInteraction:
			var interaction := child as CardInteraction
			if not interaction.clicked.is_connected(_on_card_clicked.bind(card)):
				interaction.clicked.connect(_on_card_clicked.bind(card))
			if not interaction.visual_state_changed.is_connected(_on_card_visual_state_changed.bind(card)):
				interaction.visual_state_changed.connect(_on_card_visual_state_changed.bind(card))
			break


func _on_card_clicked(card: Control) -> void:
	card_clicked.emit(card)


func _on_card_visual_state_changed(is_hovered: bool, is_dragging: bool, card: Control) -> void:
	var index: int = _cards.find(card)
	var draw_order_changed: bool = false
	if is_dragging:
		if index == _hover_index:
			_hover_index = -1
			draw_order_changed = true
	elif is_hovered and index >= 0:
		_hover_index = index
		draw_order_changed = true
	elif index == _hover_index:
		_hover_index = -1
		draw_order_changed = true
	if draw_order_changed:
		_sync_card_draw_order()
	_request_layout()


func _request_layout() -> void:
	_layout_dirty = true
	set_process(true)


func _layout_cards(animate: bool) -> void:
	_sync_auto_wrap_width()
	var count: int = _cards.size()
	var positions: Dictionary = _compute_positions(count, _hover_index, _preview_index)
	var metrics: Dictionary = _compute_metrics(count)
	var needed_h: float = float(metrics["needed_h"])
	var min_w: float = size.x if auto_wrap and size.x > card_size.x else card_size.x
	custom_minimum_size = Vector2(min_w, needed_h)
	for i: int in range(count):
		var card: Control = _cards[i]
		var visual_top_left: Vector2 = positions.get(i, Vector2.ZERO)
		var target: Vector2 = visual_top_left
		if card.size != card_size:
			card.custom_minimum_size = card_size
			card.size = card_size
		var interaction: CardInteraction = _interaction_of(card)
		if interaction == null or not interaction.is_motion_locked():
			_move_card(card, target, animate)


func _sync_auto_wrap_width() -> void:
	if not auto_wrap:
		return
	var parent_node: Node = get_parent()
	if parent_node is ScrollContainer:
		var scroll := parent_node as ScrollContainer
		var target_w: float = scroll.size.x
		if target_w > 1.0 and not is_equal_approx(size.x, target_w):
			size.x = target_w
	elif size.x < card_size.x and custom_minimum_size.x > size.x:
		size.x = custom_minimum_size.x


func _move_card(card: Control, target: Vector2, animate: bool) -> void:
	if not animate or not is_inside_tree():
		card.position = target
		return
	if _tweens.has(card):
		var old: Tween = _tweens[card]
		if old != null and old.is_valid():
			old.kill()
	var tween := create_tween()
	tween.tween_property(card, "position", target, 0.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tweens[card] = tween


func _compute_metrics(count: int) -> Dictionary:
	var card_w: float = card_size.x
	var card_h: float = card_size.y
	var width: float = maxf(size.x, card_w)
	var per_row: int
	var rows: int
	var stride: float
	if auto_wrap:
		var gap: float = maxf(normal_gap, 0.0)
		per_row = maxi(int(floor((width + gap) / (card_w + gap))), 1)
		rows = 0 if count <= 0 else int(ceili(float(count) / float(per_row)))
		stride = card_w + gap
	else:
		rows = maxi(row_count, 1)
		per_row = 1 if count <= 0 else int(ceili(float(count) / float(rows)))
		stride = card_w + normal_gap
		if per_row > 1:
			var available: float = width - card_w
			stride = available / float(per_row - 1)
			stride = clampf(stride, card_w + min_gap, card_w + normal_gap)
	var needed_h: float = 0.0
	if rows > 0:
		needed_h = float(rows) * card_h + float(maxi(rows - 1, 0)) * row_separation
		if not auto_wrap:
			needed_h += HOVER_LIFT_PAD
	return {
		"rows": rows,
		"per_row": per_row,
		"card_w": card_w,
		"card_h": card_h,
		"stride": stride,
		"needed_h": needed_h,
	}


func _compute_positions(count: int, hover_index: int, preview_index: int) -> Dictionary:
	var result: Dictionary = {}
	if count <= 0:
		return result
	var card_w: float = card_size.x
	var card_h: float = card_size.y
	var virtual_count: int = count + (1 if preview_index >= 0 else 0)
	var base_metrics: Dictionary = _compute_metrics(virtual_count)
	var per_row: int = int(base_metrics["per_row"])
	var rows: int = int(base_metrics["rows"])
	var slot_to_card: Dictionary = {}
	for card_index: int in range(count):
		var slot_index: int = card_index
		if preview_index >= 0 and card_index >= preview_index:
			slot_index += 1
		slot_to_card[slot_index] = card_index

	for row: int in range(rows):
		var row_start: int = row * per_row
		var row_end: int = mini(row_start + per_row, virtual_count)
		var row_length: int = row_end - row_start
		if row_length <= 0:
			continue
		var stride: float = float(base_metrics["stride"])
		if not auto_wrap and row_length > 1:
			stride = minf(card_w + normal_gap, (maxf(size.x, card_w) - card_w) / float(row_length - 1))
			stride = maxf(stride, card_w + min_gap)
		var x_values: Array[float] = []
		x_values.resize(row_length)
		for column: int in range(row_length):
			x_values[column] = float(column) * stride

		var hover_slot: int = hover_index
		if preview_index >= 0 and hover_index >= preview_index:
			hover_slot += 1
		var hover_column: int = hover_slot - row_start
		if not auto_wrap and hover_index >= 0 and hover_column >= 0 and hover_column < row_length:
			for column: int in range(row_length):
				var distance: int = absi(column - hover_column)
				if distance == 0:
					continue
				var direction: float = -1.0 if column < hover_column else 1.0
				# Fisheye：近邻让位更多，远端间距自动吸收变化。
				x_values[column] += direction * hover_extra_gap / float(distance)
			_fit_row_to_width(x_values, card_w)

		for column: int in range(row_length):
			var slot_index: int = row_start + column
			if not slot_to_card.has(slot_index):
				continue
			var card_index: int = int(slot_to_card[slot_index])
			var y: float = float(row) * (card_h + row_separation)
			if not auto_wrap and card_index == hover_index:
				y -= 12.0
			result[card_index] = Vector2(x_values[column], y)
	return result


func _fit_row_to_width(x_values: Array[float], card_w: float) -> void:
	if x_values.size() <= 1:
		return
	var min_x: float = x_values[0]
	var max_x: float = x_values[x_values.size() - 1]
	var available: float = maxf(size.x - card_w, 0.0)
	var span: float = max_x - min_x
	if span <= 0.0:
		return
	var scale_x: float = minf(available / span, 1.0)
	for i: int in range(x_values.size()):
		x_values[i] = (x_values[i] - min_x) * scale_x


func card_settled(_card: Control) -> void:
	_layout_cards(false)


func layout_now() -> void:
	_layout_dirty = false
	_layout_cards(false)


func _sync_card_draw_order() -> void:
	if _draw_order_sync_queued:
		return
	_draw_order_sync_queued = true
	call_deferred("_apply_card_draw_order")


func _apply_card_draw_order() -> void:
	_draw_order_sync_queued = false
	for index: int in range(_cards.size()):
		var card: Control = _cards[index]
		if card.get_parent() == self:
			move_child(card, index)
	if _hover_index < 0 or _hover_index >= _cards.size():
		return
	var hovered_card: Control = _cards[_hover_index]
	if hovered_card.get_parent() == self:
		move_child(hovered_card, get_child_count() - 1)


func _interaction_of(card: Control) -> CardInteraction:
	for child: Node in card.get_children():
		if child is CardInteraction:
			return child as CardInteraction
	return null


func _payload_of(card: Control) -> Dictionary:
	for child: Node in card.get_children():
		if child is CardInteraction:
			return (child as CardInteraction).get_card_payload()
	if "payload" in card:
		var payload: Variant = card.get("payload")
		return payload if payload is Dictionary else {}
	return {}
