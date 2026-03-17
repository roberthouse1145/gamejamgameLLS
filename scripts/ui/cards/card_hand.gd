class_name CardHand extends HBoxContainer
## CardHand — 手牌容器
## 持有多张 BaseCard，支持拖入、拖出、手牌内重排
## 拖拽悬停时显示插入位置占位符

signal card_added(card_data: Dictionary, index: int)
signal card_removed(card_data: Dictionary, index: int)

## 容量上限，-1 = 无限
@export var max_cards: int = -1
## 允许的卡牌类型，空 = 全部接受
@export var accepted_types: Array[String] = []

var _placeholder: Control = null
var _placeholder_index: int = -1
## 正在被拖拽的子卡牌（用于区分重排和外部拖入）
var _dragging_child: BaseCard = null


func _ready() -> void:
	add_to_group("card_drop_targets")
	_on_hand_ready()


## 子类可重写
func _on_hand_ready() -> void:
	pass


#region 卡牌管理

## 添加卡牌到手牌
func add_card(card: BaseCard, index: int = -1) -> void:
	if max_cards >= 0 and get_card_count() >= max_cards:
		return
	card.drag_completed.connect(_on_child_drag_completed.bind(card))
	if index < 0 or index >= get_child_count():
		add_child(card)
	else:
		add_child(card)
		move_child(card, index)
	card_added.emit(card._get_drag_payload(), card.get_index())


## 移除卡牌
func remove_card(card: BaseCard) -> void:
	if not card or not is_instance_valid(card):
		return
	if card.get_parent() != self:
		return
	var idx: int = card.get_index()
	var data: Dictionary = card._get_drag_payload()
	if card.drag_completed.is_connected(_on_child_drag_completed):
		card.drag_completed.disconnect(_on_child_drag_completed)
	remove_child(card)
	card_removed.emit(data, idx)


## 移除并释放卡牌
func remove_and_free_card(card: BaseCard) -> void:
	remove_card(card)
	if card and is_instance_valid(card):
		card.queue_free()


func get_cards() -> Array[BaseCard]:
	var result: Array[BaseCard] = []
	for child in get_children():
		if child is BaseCard:
			result.append(child)
	return result


func get_card_count() -> int:
	var count: int = 0
	for child in get_children():
		if child is BaseCard:
			count += 1
	return count

#endregion


#region 子卡牌拖拽回调

func _on_child_drag_completed(dropped: bool, target: Control, card: BaseCard) -> void:
	_dragging_child = null
	_remove_placeholder()
	if dropped and target != self:
		# 卡牌被拖到外部目标，从手牌移除
		remove_and_free_card(card)

#endregion


#region Drop 接收（外部卡牌拖入 / 手牌内重排）

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not (data is Dictionary):
		return false
	if data.get("type", "") != "card":
		return false
	var card_type: String = data.get("card_type", "")
	if accepted_types.size() > 0 and not accepted_types.has(card_type):
		return false
	# 重排：来源是自己的子卡牌，总是允许
	var source = data.get("_source")
	if source is BaseCard and source.get_parent() == self:
		return true
	# 外部拖入：检查容量
	if max_cards >= 0 and get_card_count() >= max_cards:
		return false
	return true


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if not (data is Dictionary):
		return
	var insert_idx: int = _placeholder_index if _placeholder_index >= 0 else get_child_count()
	_remove_placeholder()

	var source = data.get("_source")
	if source is BaseCard and source.get_parent() == self:
		# 重排：移动子节点位置
		var current_idx: int = source.get_index()
		# 如果占位符在卡牌之后，移除占位符后索引要调整
		if insert_idx > current_idx:
			insert_idx -= 1
		move_child(source, insert_idx)
		source.modulate = source._original_modulate
	else:
		# 外部拖入：子类通过 _on_external_card_dropped 处理
		_on_external_card_dropped(data, insert_idx)


## 子类重写：处理外部卡牌拖入（创建对应的 BaseCard 实例）
func _on_external_card_dropped(_data: Dictionary, _index: int) -> void:
	pass

#endregion


#region 占位符（插入位置指示）

func _process(_delta: float) -> void:
	if not _is_any_card_dragging():
		if _placeholder:
			_remove_placeholder()
		return
	# 有卡牌正在拖拽且鼠标在手牌范围内，更新占位符
	var mouse_pos: Vector2 = get_global_mouse_position()
	var rect := get_global_rect()
	if rect.has_point(mouse_pos):
		var idx := _calc_insert_index(mouse_pos)
		_update_placeholder(idx)
	else:
		_remove_placeholder()


func _is_any_card_dragging() -> bool:
	return BaseCard.currently_dragging != null


func _calc_insert_index(mouse_global: Vector2) -> int:
	var cards := get_cards()
	if cards.is_empty():
		return 0
	for i in range(cards.size()):
		var card_rect := cards[i].get_global_rect()
		var card_center_x: float = card_rect.position.x + card_rect.size.x / 2.0
		if mouse_global.x < card_center_x:
			return cards[i].get_index()
	# 鼠标在所有卡牌右边
	return cards.back().get_index() + 1


func _update_placeholder(index: int) -> void:
	if _placeholder and _placeholder_index == index:
		return
	_remove_placeholder()
	_placeholder = Control.new()
	_placeholder.custom_minimum_size = Vector2(BaseCard.CARD_SIZE.x, 0)
	_placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_placeholder)
	# 确保索引不越界
	var clamped_idx: int = clampi(index, 0, get_child_count() - 1)
	move_child(_placeholder, clamped_idx)
	_placeholder_index = clamped_idx


func _remove_placeholder() -> void:
	if _placeholder and is_instance_valid(_placeholder):
		_placeholder_index = -1
		_placeholder.queue_free()
		_placeholder = null

#endregion


#region 高亮

func _highlight(on: bool) -> void:
	if on:
		modulate = Color(1.15, 1.15, 1.15)
	else:
		modulate = Color.WHITE

#endregion
