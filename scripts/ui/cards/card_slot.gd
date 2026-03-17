class_name CardSlot extends PanelContainer
## CardSlot — 卡槽基类
## 自定义拖拽接收（配合 BaseCard 的自定义拖拽）
## 放入后显示真实卡牌，支持拖出（后悔机制）

signal card_placed(card_data: Dictionary)
signal card_cleared()

const SLOT_SIZE := Vector2(100, 140)

## 允许放入的卡牌类型列表，空数组表示接受所有类型
@export var accepted_types: Array[String] = []

var _current_card_data: Dictionary = {}
var _is_occupied: bool = false
var _card_visual: BaseCard = null
var _default_modulate: Color = Color.WHITE

@onready var placeholder: Label = $Placeholder


func _ready() -> void:
	_enforce_size()
	_default_modulate = modulate
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group("card_slots")
	add_to_group("card_drop_targets")
	_on_slot_ready()


## 子类可重写
func _on_slot_ready() -> void:
	pass


func _enforce_size() -> void:
	custom_minimum_size = SLOT_SIZE
	size = SLOT_SIZE
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		if size != SLOT_SIZE:
			size = SLOT_SIZE


#region 接收卡牌（由 BaseCard._end_drag 调用）

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not (data is Dictionary):
		return false
	if data.get("type", "") != "card":
		return false
	if _is_occupied:
		return false
	var card_type: String = data.get("card_type", "")
	if accepted_types.size() > 0 and not accepted_types.has(card_type):
		return false
	return _can_accept_card(data)


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if not (data is Dictionary):
		return
	_current_card_data = data.duplicate()
	# 移除 _source 引用，不需要存储
	_current_card_data.erase("_source")
	_is_occupied = true
	_show_card_visual(_current_card_data)
	_on_card_placed(_current_card_data)
	card_placed.emit(_current_card_data)


## 子类可重写
func _can_accept_card(_data: Dictionary) -> bool:
	return true


## 子类可重写
func _on_card_placed(_data: Dictionary) -> void:
	pass

#endregion


#region 状态管理

func clear_card() -> void:
	_clear_internal()
	card_cleared.emit()


func _clear_internal() -> void:
	_current_card_data = {}
	_is_occupied = false
	_remove_card_visual()
	_on_card_cleared()


## 子类可重写
func _on_card_cleared() -> void:
	pass


func is_occupied() -> bool:
	return _is_occupied


func get_card_data() -> Dictionary:
	return _current_card_data

#endregion


#region 卡牌视觉

func _show_card_visual(data: Dictionary) -> void:
	_remove_card_visual()
	if placeholder:
		placeholder.visible = false
	_card_visual = _create_card_visual(data)
	if _card_visual:
		# 卡牌保持可交互，拖拽走 BaseCard 统一流程
		_card_visual.drag_completed.connect(_on_visual_drag_completed)
		add_child(_card_visual)


func _remove_card_visual() -> void:
	if _card_visual and is_instance_valid(_card_visual):
		if _card_visual.drag_completed.is_connected(_on_visual_drag_completed):
			_card_visual.drag_completed.disconnect(_on_visual_drag_completed)
		_card_visual.queue_free()
		_card_visual = null
	if placeholder:
		placeholder.visible = true


## 卡牌视觉被拖走后的回调
func _on_visual_drag_completed(dropped: bool, _target: Control) -> void:
	if dropped:
		# 卡牌成功放到了其他目标，清空卡槽
		_current_card_data = {}
		_is_occupied = false
		_remove_card_visual()
		_on_card_cleared()
		card_cleared.emit()
	else:
		# 没有放到有效目标，卡牌回到原位（BaseCard 会恢复 modulate）
		pass


## 子类必须重写：根据卡牌数据创建对应的卡牌视觉实例
func _create_card_visual(_data: Dictionary) -> BaseCard:
	return null

#endregion


#region 高亮

func _highlight(on: bool) -> void:
	if on:
		modulate = Color(1.3, 1.3, 1.3)
	else:
		modulate = _default_modulate

#endregion
