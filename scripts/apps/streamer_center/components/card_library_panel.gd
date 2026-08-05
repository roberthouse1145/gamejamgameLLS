extends Control
## 玩家卡牌目录：行为卡与修饰卡共享目录，但不混入素材实例。

const CARD_SCENE: PackedScene = preload("res://scenes/apps/obs_live/components/live_stream_card.tscn")
const COST_ICON: Texture2D = preload("res://Assets/images/live_stream/cards/icons/stat_stress.svg")
const RISK_ICON: Texture2D = preload("res://Assets/images/live_stream/cards/icons/stat_risk.svg")

@onready var card_flow: Container = %CardFlow
@onready var empty_label: Label = %EmptyLabel
@onready var owned_count_label: Label = %OwnedCount
@onready var detail_icon: TextureRect = %DetailIcon
@onready var detail_name: Label = %DetailName
@onready var detail_category: Label = %DetailCategory
@onready var detail_description: Label = %DetailDescription
@onready var detail_left_stat: HBoxContainer = %DetailLeftStat
@onready var detail_left_icon: TextureRect = %DetailLeftIcon
@onready var detail_left_value: Label = %DetailLeftValue
@onready var detail_right_stat: HBoxContainer = %DetailRightStat
@onready var detail_right_icon: TextureRect = %DetailRightIcon
@onready var detail_right_value: Label = %DetailRightValue
@onready var unlock_source: Label = %UnlockSource

@onready var filter_buttons: Dictionary = {
	&"": %FilterAll,
	&"behavior": %FilterPersona,
	&"modifier": %FilterMaterial,
	&"locked": %FilterEvent,
}

var _filter: StringName = &""
var _selected_card_id: StringName = &""


func _ready() -> void:
	for filter_key: StringName in filter_buttons:
		var button: Button = filter_buttons[filter_key]
		button.pressed.connect(_on_filter_pressed.bind(filter_key))
	CardLibraryManager.library_changed.connect(_rebuild)
	SkillTreeManager.skill_tree_changed.connect(_rebuild)
	_rebuild()


func refresh() -> void:
	_rebuild()


func _rebuild() -> void:
	for child: Node in card_flow.get_children():
		child.queue_free()

	var cards: Array[LiveStreamCardResource] = _get_filtered_cards()
	empty_label.visible = cards.is_empty()
	owned_count_label.text = "已解锁 %d / %d" % [CardLibraryManager.get_unlocked_count(), CardLibraryManager.get_total_count()]
	_update_filter_styles()

	var selected_card: LiveStreamCardResource = _find_card(cards, _selected_card_id)
	if selected_card == null:
		selected_card = cards[0] if not cards.is_empty() else null
	_selected_card_id = selected_card.content_id if selected_card != null else &""

	for card: LiveStreamCardResource in cards:
		var is_unlocked: bool = CardLibraryManager.is_card_unlocked(card.content_id)
		var card_view: LiveStreamCardView = CARD_SCENE.instantiate()
		card_view.configure(card, card.content_id == _selected_card_id, not is_unlocked)
		card_view.tooltip_text = card.description if is_unlocked else CardLibraryManager.get_unlock_reason(card.content_id)
		if is_unlocked:
			card_view.pressed.connect(_on_card_selected.bind(card.content_id))
		card_flow.add_child(card_view)

	_render_detail(selected_card)


func _get_filtered_cards() -> Array[LiveStreamCardResource]:
	var result: Array[LiveStreamCardResource] = []
	for card: LiveStreamCardResource in CardLibraryManager.get_all_cards():
		if _filter == &"behavior" and not card is BehaviorCardResource:
			continue
		if _filter == &"modifier" and not card is ModifierCardResource:
			continue
		if _filter == &"locked" and CardLibraryManager.is_card_unlocked(card.content_id):
			continue
		result.append(card)
	return result


func _find_card(cards: Array[LiveStreamCardResource], card_id: StringName) -> LiveStreamCardResource:
	for card: LiveStreamCardResource in cards:
		if card.content_id == card_id:
			return card
	return null


func _render_detail(card: LiveStreamCardResource) -> void:
	var has_card: bool = card != null
	detail_icon.visible = has_card
	detail_name.text = card.display_name if has_card else "这个分类暂时没有卡牌"
	detail_category.text = _get_category_text(card) if has_card else ""
	detail_description.text = _get_description_text(card) if has_card else ""
	detail_left_stat.visible = has_card
	detail_right_stat.visible = has_card
	if not has_card:
		detail_icon.texture = null
		unlock_source.text = ""
		return
	detail_icon.texture = card.icon
	detail_left_icon.texture = COST_ICON
	detail_left_value.text = "预算 %d" % card.budget_cost
	detail_right_icon.texture = RISK_ICON
	var risk: float = (card as BehaviorCardResource).axes.risk if card is BehaviorCardResource else 0.0
	detail_right_value.text = "风险 %+.0f" % risk
	unlock_source.text = CardLibraryManager.get_unlock_reason(card.content_id)
	if card.required_skill_family != &"":
		unlock_source.text += "　·　%s力 Lv.%d" % [card.get_family_display_name(), card.required_skill_level]


func _get_category_text(card: LiveStreamCardResource) -> String:
	var kind_text: String = "行为卡" if card is BehaviorCardResource else "修饰卡"
	return "%s　·　%s系　·　Tier %d" % [kind_text, card.get_family_display_name(), card.tier]


func _get_description_text(card: LiveStreamCardResource) -> String:
	if card is BehaviorCardResource:
		var behavior := card as BehaviorCardResource
		return "%s\n\n情绪接口：%s → %s\n四轴：噱头 %+.0f　质量 %+.0f　效果 %+.0f　风险 %+.0f\n压力：%+.0f" % [
			behavior.description,
			_get_mood_name(behavior.mood_in),
			_get_mood_name(behavior.mood_out),
			behavior.axes.hook,
			behavior.axes.quality,
			behavior.axes.impact,
			behavior.axes.risk,
			behavior.stress_cost,
		]
	var modifier := card as ModifierCardResource
	return "%s\n\n全场修正：噱头 %+.0f%%　质量 %+.0f%%　效果 %+.0f%%　风险 %+.0f%%\n压力：%+.0f" % [
		modifier.description,
		modifier.axis_multiplier_bonus.hook * 100.0,
		modifier.axis_multiplier_bonus.quality * 100.0,
		modifier.axis_multiplier_bonus.impact * 100.0,
		modifier.axis_multiplier_bonus.risk * 100.0,
		modifier.stress_cost,
	]


func _get_mood_name(mood: StringName) -> String:
	match mood:
		BehaviorCardResource.MOOD_OPEN:
			return "平齐"
		BehaviorCardResource.MOOD_HOT:
			return "热烈"
		BehaviorCardResource.MOOD_CALM:
			return "冷静"
		BehaviorCardResource.MOOD_WARM:
			return "温和"
		BehaviorCardResource.MOOD_GLOOM:
			return "丧气"
	return "未知"


func _update_filter_styles() -> void:
	for filter_key: StringName in filter_buttons:
		var button: Button = filter_buttons[filter_key]
		button.theme_type_variation = &"FilterButtonSelected" if filter_key == _filter else &"FilterButton"


func _on_filter_pressed(filter_key: StringName) -> void:
	if _filter == filter_key:
		return
	_filter = filter_key
	_selected_card_id = &""
	_rebuild()


func _on_card_selected(card_id: StringName) -> void:
	_selected_card_id = card_id
	_rebuild()
