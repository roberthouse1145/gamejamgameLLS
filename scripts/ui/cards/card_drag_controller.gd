class_name CardDragController extends Control
## 当前界面唯一拖拽协调器：真卡跟手、命中容器、提交 move/swap 或回弹。

signal drag_started(card: Control, payload: Dictionary)
signal drag_finished(success: bool, card: Control, payload: Dictionary, target: Node)
signal move_committed(card: Control, payload: Dictionary, source: Node, target: Node)
signal drop_rejected(card: Control, payload: Dictionary, target: Node)

var _containers: Array[Node] = []
var _drag_canvas: CanvasLayer = null
var _drag_layer: Control = null
var _active: CardInteraction = null
var _active_card: Control = null
var _source: Node = null
var _source_index: int = -1
var _original_parent: Node = null
var _original_child_index: int = -1
var _source_home: Vector2 = Vector2.ZERO
var _grab_offset: Vector2 = Vector2.ZERO
var _preview_target: Node = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_ensure_drag_layer()


func _process(_delta: float) -> void:
	if _active == null or _active_card == null:
		return
	_active_card.global_position = get_global_mouse_position() - _grab_offset
	_update_preview()
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_end_drag()


func register_container(container: Node) -> void:
	if container == null or container in _containers:
		return
	_containers.append(container)


func unregister_container(container: Node) -> void:
	_containers.erase(container)


func clear_containers_except(keep: Node = null) -> void:
	var next: Array[Node] = []
	if keep != null and keep in _containers:
		next.append(keep)
	_containers = next


func bind_card(card: Control) -> CardInteraction:
	var interaction := _ensure_interaction(card)
	interaction.bind_controller(self)
	return interaction


func begin_drag(interaction: CardInteraction, grab_offset: Vector2) -> void:
	if _active != null:
		interaction.cancel_press()
		return
	_active = interaction
	_active_card = interaction.get_card()
	_grab_offset = grab_offset
	_original_parent = _active_card.get_parent()
	_original_child_index = _active_card.get_index()
	_source = _find_owner_container(_active_card)
	_source_index = -1
	_source_home = _active_card.global_position
	if _source != null and _source.has_method("get_card_index"):
		_source_index = int(_source.call("get_card_index", _active_card))
	if _source != null and _source.has_method("get_card_global_position"):
		_source_home = _source.call("get_card_global_position", _active_card) as Vector2
	if _source != null and _source.has_method("can_release_card"):
		if not bool(_source.call("can_release_card", _active_card)):
			_active.cancel_press()
			_clear_active()
			return
	interaction.begin_drag_visual()
	_ensure_drag_layer()
	var global_pos: Vector2 = _active_card.global_position
	if _source != null and _source.has_method("detach_card_for_drag"):
		_source.call("detach_card_for_drag", _active_card)
	elif _active_card.get_parent() != null:
		_active_card.get_parent().remove_child(_active_card)
	_drag_layer.add_child(_active_card)
	_active_card.global_position = global_pos
	drag_started.emit(_active_card, interaction.get_card_payload())


func _end_drag() -> void:
	if _active == null or _active_card == null:
		_clear_active()
		return
	var card: Control = _active_card
	var interaction: CardInteraction = _active
	var payload: Dictionary = interaction.get_card_payload()
	var target: Node = _pick_target(get_global_mouse_position())
	_clear_all_previews()
	var success: bool = false
	if target != null:
		success = _try_commit(card, interaction, _source, _source_index, target)
		if not success:
			drop_rejected.emit(card, payload, target)
	if not success:
		_return_to_source(card, interaction)
	drag_finished.emit(success, card, payload, target)
	_clear_active()


func _try_commit(card: Control, interaction: CardInteraction, source: Node, source_index: int, target: Node) -> bool:
	if target == source:
		if target.has_method("commit_reorder"):
			var reorder_global: Vector2 = card.global_position
			var ok: bool = bool(target.call("commit_reorder", card, get_global_mouse_position()))
			if ok:
				card.global_position = reorder_global
				_settle_into_container(card, interaction, target)
				move_committed.emit(card, interaction.get_card_payload(), source, target)
			return ok
		if target.has_method("set_card"):
			var return_global: Vector2 = card.global_position
			target.call("set_card", card)
			card.global_position = return_global
			_settle_into_container(card, interaction, target)
			return true
		return false
	if not _can_accept(target, card, source):
		return false
	# Occupied slot swap: both directions must be legal.
	if target.has_method("get_card") and target.has_method("has_card") and bool(target.call("has_card")):
		var occupied: Control = target.call("get_card") as Control
		if occupied == null:
			return false
		if source == null:
			return false
		if not _can_accept(source, occupied, target):
			return false
		if target.has_method("can_release_card") and not bool(target.call("can_release_card", occupied)):
			return false
		if source.has_method("can_release_card") and not bool(source.call("can_release_card", card)):
			return false
		var card_global: Vector2 = card.global_position
		var occ_global: Vector2 = occupied.global_position
		if target.has_method("detach_card_for_drag"):
			target.call("detach_card_for_drag", occupied)
		if source.has_method("insert_card"):
			source.call("insert_card", occupied, source_index)
		elif source.has_method("set_card"):
			source.call("set_card", occupied)
		else:
			return false
		if target.has_method("set_card"):
			target.call("set_card", card)
		elif target.has_method("insert_card"):
			target.call("insert_card", card, -1)
		else:
			return false
		card.global_position = card_global
		occupied.global_position = occ_global
		_settle_into_container(card, interaction, target)
		var occ_interaction := _find_interaction(occupied)
		if occ_interaction != null:
			_settle_into_container(occupied, occ_interaction, source)
		move_committed.emit(card, interaction.get_card_payload(), source, target)
		return true
	# Empty target / deck insert
	var drop_global: Vector2 = card.global_position
	if target.has_method("insert_card"):
		target.call("insert_card", card, _preview_index_for(target, get_global_mouse_position()))
	elif target.has_method("set_card"):
		target.call("set_card", card)
	else:
		return false
	card.global_position = drop_global
	_settle_into_container(card, interaction, target)
	move_committed.emit(card, interaction.get_card_payload(), source, target)
	return true


func _return_to_source(card: Control, interaction: CardInteraction) -> void:
	if _source == null:
		var original_global: Vector2 = card.global_position
		if is_instance_valid(_original_parent):
			if card.get_parent() != null:
				card.get_parent().remove_child(card)
			_original_parent.add_child(card)
			_original_parent.move_child(card, clampi(_original_child_index, 0, _original_parent.get_child_count() - 1))
			card.global_position = original_global
			interaction.settle_to(_source_home)
		else:
			interaction.snap_idle()
		return
	var return_global: Vector2 = card.global_position
	if _source.has_method("insert_card"):
		_source.call("insert_card", card, _source_index)
	elif _source.has_method("set_card"):
		_source.call("set_card", card)
	card.global_position = return_global
	_settle_into_container(card, interaction, _source)


func _settle_into_container(card: Control, interaction: CardInteraction, container: Node) -> void:
	if container.has_method("layout_now"):
		container.call("layout_now")
	var home: Vector2 = card.global_position
	if container.has_method("get_card_global_position"):
		home = container.call("get_card_global_position", card) as Vector2
	interaction.set_home_position(home)
	interaction.settle_to(home, _on_card_settled.bind(container, card))


func _on_card_settled(container: Node, card: Control) -> void:
	if is_instance_valid(container) and container.has_method("card_settled"):
		container.call("card_settled", card)


func _update_preview() -> void:
	var target: Node = _pick_target(get_global_mouse_position())
	if target != _preview_target:
		_clear_all_previews()
		_preview_target = target
	if target != null and target.has_method("preview_drag"):
		target.call("preview_drag", _active_card, get_global_mouse_position())


func _clear_all_previews() -> void:
	for container: Node in _containers:
		if is_instance_valid(container) and container.has_method("clear_preview"):
			container.call("clear_preview")
	_preview_target = null


func _pick_target(global_pos: Vector2) -> Node:
	var best: Node = null
	var best_area: float = INF
	for container: Node in _containers:
		if not is_instance_valid(container) or not (container is Control):
			continue
		var control := container as Control
		var position_valid: bool = false
		if container.has_method("is_drop_position_valid"):
			position_valid = bool(container.call("is_drop_position_valid", _active_card, global_pos))
		else:
			position_valid = control.get_global_rect().has_point(global_pos)
		if not position_valid:
			continue
		var area: float = control.size.x * control.size.y
		if area < best_area:
			best_area = area
			best = container
	return best


func _can_accept(container: Node, card: Control, from_container: Node) -> bool:
	if container == null or card == null:
		return false
	if container.has_method("can_accept_card"):
		return bool(container.call("can_accept_card", card, from_container))
	return false


func _preview_index_for(container: Node, global_pos: Vector2) -> int:
	if container.has_method("get_preview_insert_index"):
		return int(container.call("get_preview_insert_index", global_pos))
	return -1


func _find_owner_container(card: Control) -> Node:
	var node: Node = card.get_parent()
	while node != null:
		if node in _containers:
			return node
		# Deck may wrap cards indirectly; check method marker.
		if node.has_method("is_card_container") and bool(node.call("is_card_container")):
			return node
		node = node.get_parent()
	return null


func _ensure_interaction(card: Control) -> CardInteraction:
	for child: Node in card.get_children():
		if child is CardInteraction:
			return child as CardInteraction
	var interaction := CardInteraction.new()
	interaction.name = "CardInteraction"
	card.add_child(interaction)
	return interaction


func _find_interaction(card: Control) -> CardInteraction:
	if card == null:
		return null
	for child: Node in card.get_children():
		if child is CardInteraction:
			return child as CardInteraction
	return null


func _ensure_drag_layer() -> void:
	if _drag_layer != null and is_instance_valid(_drag_layer):
		return
	_drag_canvas = CanvasLayer.new()
	_drag_canvas.name = "DragCanvas"
	_drag_canvas.layer = 100
	add_child(_drag_canvas)
	_drag_layer = Control.new()
	_drag_layer.name = "DragLayer"
	_drag_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_drag_canvas.add_child(_drag_layer)


func _clear_active() -> void:
	_active = null
	_active_card = null
	_source = null
	_source_index = -1
	_original_parent = null
	_original_child_index = -1
	_source_home = Vector2.ZERO
	_preview_target = null
