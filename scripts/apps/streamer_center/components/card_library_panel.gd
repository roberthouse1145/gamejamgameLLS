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
	&"persona": %FilterPersonaCard,
	&"material": %FilterMaterialCard,
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
	GameState.persona_changed.connect(_on_persona_changed)
	_rebuild()


func refresh() -> void:
	_rebuild()


func _rebuild() -> void:
	for child: Node in card_flow.get_children():
		child.queue_free()

	var cards: Array[StreamContentResource] = _get_filtered_cards()
	empty_label.visible = cards.is_empty()
	owned_count_label.text = "已解锁 %d / %d" % [CardLibraryManager.get_unlocked_count(), CardLibraryManager.get_total_count()]
	_update_filter_styles()

	var selected_card: StreamContentResource = _find_card(cards, _selected_card_id)
	if selected_card == null:
		selected_card = cards[0] if not cards.is_empty() else null
	_selected_card_id = selected_card.content_id if selected_card != null else &""

	for entry: StreamContentResource in cards:
		var card_view: LiveStreamCardView = CARD_SCENE.instantiate()
		var is_game_card: bool = entry is LiveStreamCardResource
		var is_unlocked: bool = (
			CardLibraryManager.is_card_unlocked(entry.content_id) if is_game_card else true
		)
		card_view.configure(entry, entry.content_id == _selected_card_id, not is_unlocked)
		if is_game_card and not is_unlocked:
			card_view.override_tooltip(CardLibraryManager.get_unlock_reason(entry.content_id))
		if is_unlocked:
			card_view.pressed.connect(_on_card_selected.bind(entry.content_id))
		card_flow.add_child(card_view)

	_render_detail(selected_card)


func _get_filtered_cards() -> Array[StreamContentResource]:
	var result: Array[StreamContentResource] = []
	if _filter != &"persona" and _filter != &"material" and _filter != &"locked":
		for card: LiveStreamCardResource in CardLibraryManager.get_all_cards():
			if _filter == &"behavior" and not card is BehaviorCardResource:
				continue
			if _filter == &"modifier" and not card is ModifierCardResource:
				continue
			result.append(card)
	if _filter == &"persona" or _filter == &"":
		for persona: StreamPersonaResource in CardLibraryManager.get_catalog().personas:
			result.append(persona)
	if _filter == &"material" or _filter == &"":
		for stream_material: LiveStreamMaterialResource in CardLibraryManager.get_catalog().materials:
			result.append(stream_material)
	if _filter == &"locked":
		var locked_result: Array[StreamContentResource] = []
		for card: LiveStreamCardResource in CardLibraryManager.get_all_cards():
			if not CardLibraryManager.is_card_unlocked(card.content_id):
				locked_result.append(card)
		return locked_result
	return result


func _find_card(cards: Array[StreamContentResource], card_id: StringName) -> StreamContentResource:
	for card: StreamContentResource in cards:
		if card.content_id == card_id:
			return card
	return null


func _render_detail(card: StreamContentResource) -> void:
	var has_card: bool = card != null
	detail_icon.visible = has_card
	detail_name.text = card.display_name if has_card else "这个分类暂时没有卡牌"
	detail_category.text = _get_category_text(card) if has_card else ""
	detail_description.text = _get_description_text(card) if has_card else ""
	var is_game_card: bool = card is LiveStreamCardResource
	detail_left_stat.visible = is_game_card
	detail_right_stat.visible = is_game_card
	if not has_card:
		detail_icon.texture = null
		unlock_source.text = ""
		return
	detail_icon.texture = CardFaceCatalog.face_for(card)
	unlock_source.text = _get_unlock_text(card)
	if not is_game_card:
		return
	var card_resource := card as LiveStreamCardResource
	detail_left_icon.texture = COST_ICON
	detail_left_value.text = "预算 %d" % card_resource.budget_cost
	detail_right_icon.texture = RISK_ICON
	var risk: float = (card_resource as BehaviorCardResource).axes.risk if card_resource is BehaviorCardResource else 0.0
	detail_right_value.text = "风险 %+.0f" % risk


func _get_category_text(card: StreamContentResource) -> String:
	if card is BehaviorCardResource:
		return "行为卡　·　%s系　·　Tier %d" % [card.get_family_display_name(), card.tier]
	if card is ModifierCardResource:
		return "修饰卡　·　%s系　·　Tier %d" % [card.get_family_display_name(), card.tier]
	if card is StreamPersonaResource:
		return "人设卡　·　出镜形象"
	if card is LiveStreamMaterialResource:
		return "素材卡　·　%s" % (card as LiveStreamMaterialResource).get_material_type_label()
	return ""


func _get_description_text(card: StreamContentResource) -> String:
	if card is BehaviorCardResource:
		var behavior := card as BehaviorCardResource
		return "%s\n\n四轴：噱头 %+.0f　质量 %+.0f　效果 %+.0f　风险 %+.0f\n压力：%+.0f" % [
			behavior.description,
			behavior.axes.hook,
			behavior.axes.quality,
			behavior.axes.impact,
			behavior.axes.risk,
			behavior.stress_cost,
		]
	if card is ModifierCardResource:
		var modifier := card as ModifierCardResource
		return "%s\n\n全场修正：噱头 %+.0f%%　质量 %+.0f%%　效果 %+.0f%%　风险 %+.0f%%\n压力：%+.0f" % [
			modifier.description,
			modifier.axis_multiplier_bonus.hook * 100.0,
			modifier.axis_multiplier_bonus.quality * 100.0,
			modifier.axis_multiplier_bonus.impact * 100.0,
			modifier.axis_multiplier_bonus.risk * 100.0,
			modifier.stress_cost,
		]
	return card.description


func _get_unlock_text(card: StreamContentResource) -> String:
	if card is LiveStreamCardResource:
		var card_resource := card as LiveStreamCardResource
		var text: String = CardLibraryManager.get_unlock_reason(card.content_id)
		if card_resource.required_skill_family != &"":
			text += "　·　%s力 Lv.%d" % [card_resource.get_family_display_name(), card_resource.required_skill_level]
		return text
	if card is StreamPersonaResource:
		var persona := card as StreamPersonaResource
		if String(persona.content_id) == GameState.active_persona_id:
			return "当前扮演中"
		if String(persona.content_id) in GameState.graduated_personas:
			return "已毕业（不可再扮演）"
		return "通过毕业转生解锁"
	if card is LiveStreamMaterialResource:
		return "开播时从素材库存选用"
	return ""


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


## 毕业转生后刷新人设卡状态（当前扮演中 / 已毕业）。
func _on_persona_changed(_old_persona_id: String, _new_persona_id: String) -> void:
	_rebuild()


func _on_card_selected(card_id: StringName) -> void:
	_selected_card_id = card_id
	_rebuild()
