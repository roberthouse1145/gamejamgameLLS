@tool
class_name StreamerCardFlowContainer extends Container
## 卡牌库的响应式流式排布：按可用宽度自动计算列数，并保持稳定的行优先顺序。

@export var card_size: Vector2 = CardDisplayMetrics.FULL_SIZE:
	set(value):
		card_size = Vector2(maxf(value.x, 1.0), maxf(value.y, 1.0))
		update_minimum_size()
		queue_sort()
@export_range(0, 128, 1) var horizontal_separation: int = 22:
	set(value):
		horizontal_separation = maxi(value, 0)
		update_minimum_size()
		queue_sort()
@export_range(0, 128, 1) var vertical_separation: int = 22:
	set(value):
		vertical_separation = maxi(value, 0)
		update_minimum_size()
		queue_sort()

var _last_layout_width: float = -1.0


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_SORT_CHILDREN:
			_layout_cards()
		NOTIFICATION_RESIZED:
			if not is_equal_approx(_last_layout_width, size.x):
				_last_layout_width = size.x
				update_minimum_size()
				queue_sort()
		NOTIFICATION_CHILD_ORDER_CHANGED:
			update_minimum_size()
			queue_sort()


func _get_minimum_size() -> Vector2:
	var card_count: int = _get_layout_children().size()
	if card_count == 0:
		return Vector2(card_size.x, 0.0)
	var columns: int = _get_column_count(maxf(size.x, card_size.x))
	var rows: int = int(ceil(float(card_count) / float(columns)))
	var height: float = rows * card_size.y + maxi(rows - 1, 0) * vertical_separation
	return Vector2(card_size.x, height)


func _layout_cards() -> void:
	var cards: Array[Control] = _get_layout_children()
	var available_width: float = maxf(size.x, card_size.x)
	var columns: int = _get_column_count(available_width)
	for index: int in range(cards.size()):
		var column: int = index % columns
		@warning_ignore("integer_division")
		var row: int = index / columns
		var row_start_index: int = row * columns
		var row_card_count: int = mini(columns, cards.size() - row_start_index)
		var row_width: float = row_card_count * card_size.x + maxi(row_card_count - 1, 0) * horizontal_separation
		var row_start_x: float = maxf((available_width - row_width) * 0.5, 0.0)
		var card_position := Vector2(
			row_start_x + column * (card_size.x + horizontal_separation),
			row * (card_size.y + vertical_separation)
		)
		fit_child_in_rect(cards[index], Rect2(card_position, card_size))


func _get_column_count(available_width: float) -> int:
	var cell_width: float = card_size.x + horizontal_separation
	return maxi(int(floor((available_width + horizontal_separation) / cell_width)), 1)


func _get_layout_children() -> Array[Control]:
	var result: Array[Control] = []
	for child: Node in get_children():
		if child is Control and child.visible and not child.is_queued_for_deletion():
			result.append(child as Control)
	return result
