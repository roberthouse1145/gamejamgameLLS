class_name BaseCard extends PanelContainer
## BaseCard — 卡牌基类
## 固定尺寸、自定义拖拽（不使用 Godot 内置 drag/drop）
## 预览使用 top_level 确保在所有 UI 之上
## 子类重写 _get_card_type() 和 _get_drag_payload()

signal drag_completed(dropped: bool, target: Control)

const CARD_SIZE := Vector2(100, 140)
const DRAG_THRESHOLD: float = 5.0

## 全局追踪：当前正在拖拽的卡牌（用于 CardHand 等外部组件检测）
static var currently_dragging: BaseCard = null

@onready var background: TextureRect = $Background
@onready var content: MarginContainer = $Content

var _is_pressed: bool = false
var _press_pos: Vector2 = Vector2.ZERO
var _is_dragging: bool = false
var _drag_preview: Control = null
## 拖拽开始时隐藏原卡牌
var _original_modulate: Color = Color.WHITE


func _ready() -> void:
	_enforce_size()
	mouse_filter = Control.MOUSE_FILTER_STOP
	# 如果标记为锁定（只读展示），禁用所有鼠标交互
	if get_meta("locked", false):
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_set_preview_ignore_mouse(self)
	_on_card_ready()


## 子类可重写
func _on_card_ready() -> void:
	pass


func _enforce_size() -> void:
	custom_minimum_size = CARD_SIZE
	size = CARD_SIZE
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		if size != CARD_SIZE:
			size = CARD_SIZE


#region 自定义拖拽

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_is_pressed = true
				_press_pos = mb.global_position
				accept_event()
			else:
				if _is_dragging:
					_end_drag()
					accept_event()
				_is_pressed = false

	elif event is InputEventMouseMotion and _is_pressed:
		var mm := event as InputEventMouseMotion
		if not _is_dragging:
			if _press_pos.distance_to(mm.global_position) > DRAG_THRESHOLD:
				_start_drag()
		if _is_dragging:
			_update_drag(mm.global_position)
			accept_event()


func _input(event: InputEvent) -> void:
	# 全局监听：拖拽中鼠标释放（可能在卡牌外部释放）
	if _is_dragging and event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			_end_drag()
			_is_pressed = false
			if is_inside_tree():
				get_viewport().set_input_as_handled()


func _start_drag() -> void:
	var payload: Dictionary = _get_drag_payload()
	if payload.is_empty():
		_is_pressed = false
		return
	payload["type"] = "card"
	payload["card_type"] = _get_card_type()
	payload["_source"] = self

	_is_dragging = true
	_original_modulate = modulate
	modulate = Color(1, 1, 1, 0.3)
	BaseCard.currently_dragging = self

	# 创建预览：top_level 确保在所有 UI 之上
	_drag_preview = duplicate()
	_drag_preview.modulate = Color(1, 1, 1, 0.85)
	_drag_preview.top_level = true
	_drag_preview.z_index = 4096
	_drag_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_preview_ignore_mouse(_drag_preview)
	_drag_preview.size = CARD_SIZE
	add_child(_drag_preview)

	_update_drag(get_global_mouse_position())

	# 存储 payload 供 drop 时使用
	set_meta("_drag_payload", payload)


func _update_drag(mouse_global: Vector2) -> void:
	if _drag_preview:
		_drag_preview.global_position = mouse_global - CARD_SIZE / 2.0
	# 高亮检测
	_update_drop_target_highlight(mouse_global)


func _end_drag() -> void:
	if not _is_dragging:
		return
	_is_dragging = false
	modulate = _original_modulate

	var payload: Dictionary = get_meta("_drag_payload", {})
	var dropped: bool = false
	var drop_target: Control = null

	# 检测鼠标下方是否有 drop 目标
	if is_inside_tree():
		var mouse_pos: Vector2 = get_global_mouse_position()
		var target: Control = _find_drop_target(mouse_pos)
		if target and target.has_method("_drop_data"):
			target._drop_data(Vector2.ZERO, payload)
			dropped = true
			drop_target = target

	# 清理预览
	if _drag_preview and is_instance_valid(_drag_preview):
		_drag_preview.queue_free()
		_drag_preview = null

	# 清理高亮
	_clear_all_highlights()

	remove_meta("_drag_payload")

	_on_drag_ended(dropped)
	drag_completed.emit(dropped, drop_target)
	BaseCard.currently_dragging = null


## 子类可重写：拖拽结束后的回调
func _on_drag_ended(_dropped: bool) -> void:
	pass

#endregion


#region Drop 目标检测

func _find_drop_target(mouse_global: Vector2) -> Control:
	if not is_inside_tree():
		return null
	var payload: Dictionary = get_meta("_drag_payload", {})
	var targets: Array[Node] = get_tree().get_nodes_in_group("card_drop_targets")
	# 收集所有命中的候选 target
	var candidates: Array[Control] = []
	for node in targets:
		if not (node is Control):
			continue
		var ctrl := node as Control
		if not ctrl.is_visible_in_tree():
			continue
		var rect := ctrl.get_global_rect()
		if not rect.has_point(mouse_global):
			continue
		if not ctrl.has_method("_can_drop_data") or not ctrl._can_drop_data(Vector2.ZERO, payload):
			continue
		candidates.append(ctrl)
	if candidates.is_empty():
		return null
	# 按绘制顺序排序（后绘制 = 视觉上更靠前），取最上层的
	candidates.sort_custom(_compare_draw_order)
	# 检查最上层候选是否被其他非 target 控件遮挡
	# 如果有更高绘制顺序的 STOP 控件覆盖了鼠标位置，则该 target 被遮挡
	var top_candidate: Control = candidates.back()
	if _is_occluded_by_sibling(top_candidate, mouse_global):
		return null
	return top_candidate


func _update_drop_target_highlight(mouse_global: Vector2) -> void:
	if not is_inside_tree():
		return
	var targets: Array[Node] = get_tree().get_nodes_in_group("card_drop_targets")
	var best: Control = _find_drop_target(mouse_global) if has_meta("_drag_payload") else null
	for node in targets:
		if not (node is Control):
			continue
		var ctrl := node as Control
		if not ctrl.has_method("_highlight"):
			continue
		ctrl._highlight(ctrl == best)


func _clear_all_highlights() -> void:
	if not is_inside_tree():
		return
	var targets: Array[Node] = get_tree().get_nodes_in_group("card_drop_targets")
	for node in targets:
		if node is Control and node.has_method("_highlight"):
			node._highlight(false)

#endregion


#region 绘制顺序与遮挡检测

## 获取节点的完整绘制顺序路径（从根到自身的 [z_index, child_index] 序列）
## 后绘制的节点在视觉上更靠前
static func _get_draw_order_key(ctrl: Control) -> Array:
	var path: Array = []
	var node: Node = ctrl
	while node:
		var parent: Node = node.get_parent()
		if parent:
			var z: int = node.z_index if node is CanvasItem else 0
			var idx: int = node.get_index()
			path.push_front([z, idx])
		node = parent
	return path


## 比较两个控件的绘制顺序，用于排序
## 返回 true 表示 a 在 b 之前绘制（a 在下面）
static func _compare_draw_order(a: Control, b: Control) -> bool:
	var key_a: Array = _get_draw_order_key(a)
	var key_b: Array = _get_draw_order_key(b)
	var min_len: int = mini(key_a.size(), key_b.size())
	for i in range(min_len):
		var za: int = key_a[i][0]
		var zb: int = key_b[i][0]
		if za != zb:
			return za < zb
		var ia: int = key_a[i][1]
		var ib: int = key_b[i][1]
		if ia != ib:
			return ia < ib
	return key_a.size() < key_b.size()


## 检查 target 是否被同级或更高层的非 target 控件遮挡
## 从 target 向上找到 window_container 级别的祖先，检查同级中更靠后的兄弟
static func _is_occluded_by_sibling(target: Control, mouse_global: Vector2) -> bool:
	# 从 target 向上遍历，在每一层检查是否有更靠后的兄弟遮挡了鼠标位置
	var child: Node = target
	var parent: Node = target.get_parent()
	while parent:
		var child_idx: int = child.get_index()
		var child_z: int = child.z_index if child is CanvasItem else 0
		# 检查同级中绘制顺序更靠后的兄弟
		for i in range(parent.get_child_count()):
			var sibling: Node = parent.get_child(i)
			if sibling == child:
				continue
			if not (sibling is Control):
				continue
			var sib_ctrl := sibling as Control
			if not sib_ctrl.visible:
				continue
			var sib_z: int = sib_ctrl.z_index
			# 兄弟在 child 之后绘制（z 更高，或 z 相同但 index 更大）
			var draws_after: bool = (sib_z > child_z) or (sib_z == child_z and i > child_idx)
			if not draws_after:
				continue
			# 检查这个兄弟（或其子孙）是否覆盖了鼠标位置且会吸收输入
			if _control_blocks_at(sib_ctrl, mouse_global):
				return true
		child = parent
		parent = parent.get_parent()
	return false


## 检查一个控件树是否在指定位置阻挡输入（有 STOP 的控件覆盖该位置）
static func _control_blocks_at(ctrl: Control, mouse_global: Vector2) -> bool:
	if not ctrl.visible:
		return false
	var rect := ctrl.get_global_rect()
	if not rect.has_point(mouse_global):
		return false
	# 如果这个控件本身是 STOP，它会吸收输入
	if ctrl.mouse_filter == Control.MOUSE_FILTER_STOP:
		return true
	# 如果是 PASS，检查子节点
	if ctrl.mouse_filter == Control.MOUSE_FILTER_PASS:
		for child in ctrl.get_children():
			if child is Control and _control_blocks_at(child, mouse_global):
				return true
	# IGNORE 不阻挡
	return false

#endregion


#region 工具方法

## 递归设置所有子控件忽略鼠标（预览用）
func _set_preview_ignore_mouse(ctrl: Control) -> void:
	ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in ctrl.get_children():
		if child is Control:
			_set_preview_ignore_mouse(child)

#endregion


#region 子类接口

func _get_card_type() -> String:
	return "base"


func _get_drag_payload() -> Dictionary:
	return {}

#endregion
