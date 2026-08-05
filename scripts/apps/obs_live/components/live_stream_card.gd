@tool
class_name LiveStreamCardView extends Button
## 卡牌展示层；内容、拼图槽形状与数值全部来自 Resource。

const COST_ICON: Texture2D = preload("res://Assets/images/live_stream/cards/icons/stat_stress.svg")
const RISK_ICON: Texture2D = preload("res://Assets/images/live_stream/cards/icons/stat_risk.svg")

@export var card_resource: LiveStreamCardResource = null:
	set(value):
		card_resource = value
		if is_node_ready():
			_render_card()

@export var selected: bool = false:
	set(value):
		selected = value
		if is_node_ready():
			_refresh_interaction_state()

@export var locked: bool = false:
	set(value):
		locked = value
		if is_node_ready():
			_refresh_interaction_state()

@onready var title_label: Label = %TitleLabel
@onready var family_label: Label = %FamilyLabel
@onready var main_icon: TextureRect = %MainIcon
@onready var description_label: Label = %DescriptionLabel
@onready var left_stat: HBoxContainer = %LeftStat
@onready var left_stat_icon: TextureRect = %LeftStatIcon
@onready var left_stat_value: Label = %LeftStatValue
@onready var right_stat: HBoxContainer = %RightStat
@onready var right_stat_icon: TextureRect = %RightStatIcon
@onready var right_stat_value: Label = %RightStatValue
@onready var content_margin: MarginContainer = %ContentMargin
@onready var locked_label: Label = %LockedLabel
@onready var mood_edges: CardMoodEdges = %MoodEdges

var _hovered: bool = false


func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	_render_card()


func configure(resource: LiveStreamCardResource, is_selected: bool = false, is_locked: bool = false) -> void:
	card_resource = resource
	selected = is_selected
	locked = is_locked


func _render_card() -> void:
	if card_resource == null:
		var empty_moods: Array[StringName] = []
		title_label.text = ""
		family_label.text = ""
		main_icon.texture = null
		description_label.text = ""
		left_stat.get_parent().visible = false
		right_stat.get_parent().visible = false
		mood_edges.configure(empty_moods, empty_moods, false)
		disabled = true
		_refresh_interaction_state()
		return

	title_label.text = card_resource.display_name
	family_label.text = "%s系 · Tier %d · %s" % [
		card_resource.get_family_display_name(),
		card_resource.tier,
		"行为卡" if card_resource is BehaviorCardResource else "修饰卡",
	]
	main_icon.texture = card_resource.icon
	description_label.text = "%s\n%s" % [card_resource.description, _get_effect_summary(card_resource)]
	_render_stat(left_stat, left_stat_icon, left_stat_value, COST_ICON, "%d" % card_resource.budget_cost)
	var risk_value: float = 0.0
	if card_resource is BehaviorCardResource:
		var behavior := card_resource as BehaviorCardResource
		risk_value = behavior.axes.risk
		mood_edges.configure(behavior.mood_inputs, behavior.mood_outputs, true)
	else:
		var empty_moods: Array[StringName] = []
		mood_edges.configure(empty_moods, empty_moods, false)
	_render_stat(right_stat, right_stat_icon, right_stat_value, RISK_ICON, "%+.0f" % risk_value)
	disabled = locked
	tooltip_text = "%s\n演出预算 %d · 压力 %+.0f" % [card_resource.description, card_resource.budget_cost, card_resource.stress_cost]
	_refresh_interaction_state()


func _render_stat(container: HBoxContainer, icon_rect: TextureRect, value_label: Label, icon_texture: Texture2D, value_text: String) -> void:
	container.visible = true
	var stat_panel := container.get_parent() as Control
	if stat_panel != null:
		stat_panel.visible = true
	icon_rect.texture = icon_texture
	value_label.text = value_text


func _get_effect_summary(card: LiveStreamCardResource) -> String:
	if card is BehaviorCardResource:
		var axes: StreamAxisValues = (card as BehaviorCardResource).axes
		return "噱头%+.0f　质量%+.0f　效果%+.0f　风险%+.0f" % [axes.hook, axes.quality, axes.impact, axes.risk]
	var modifier: ModifierCardResource = card as ModifierCardResource
	if modifier == null:
		return ""
	var values: StreamAxisValues = modifier.axis_multiplier_bonus
	return "全场修正　噱头%+.0f%%　质量%+.0f%%　效果%+.0f%%　风险%+.0f%%" % [
		values.hook * 100.0,
		values.quality * 100.0,
		values.impact * 100.0,
		values.risk * 100.0,
	]


func _refresh_interaction_state() -> void:
	if mood_edges == null or content_margin == null or locked_label == null:
		return
	disabled = card_resource == null or locked
	locked_label.visible = locked and card_resource != null
	content_margin.modulate = Color(1.0, 1.0, 1.0, 0.34) if locked else Color.WHITE
	mood_edges.set_interaction_state(selected and not disabled, _hovered and not disabled, locked)


func _on_mouse_entered() -> void:
	_hovered = true
	_refresh_interaction_state()


func _on_mouse_exited() -> void:
	_hovered = false
	_refresh_interaction_state()
