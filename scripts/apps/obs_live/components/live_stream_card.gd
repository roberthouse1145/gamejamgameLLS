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
@onready var slot_edges: CardSlotEdges = %SlotEdges

var _hovered: bool = false
var _connected_left_slots: Array[int] = []
var _connected_right_slots: Array[int] = []
var _show_connection_state: bool = false
var _interaction: CardInteraction = null

## 拖拽负载；非空时本卡可被拖起。常用键：kind / card_id / from_slot / title。
var drag_payload: Dictionary = {}:
	set(value):
		drag_payload = value
		_sync_interaction_drag()


func get_card_payload() -> Dictionary:
	return drag_payload


func set_card_shadow_strength(strength: float) -> void:
	if slot_edges != null:
		slot_edges.set_glow_strength(strength)


func _ready() -> void:
	custom_minimum_size = CardDisplayMetrics.FULL_SIZE
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	focus_mode = Control.FOCUS_NONE
	_ensure_interaction()
	_render_card()


func configure(resource: LiveStreamCardResource, is_selected: bool = false, is_locked: bool = false) -> void:
	_connected_left_slots.clear()
	_connected_right_slots.clear()
	_show_connection_state = false
	card_resource = resource
	selected = is_selected
	locked = is_locked


func configure_connection_state(left_connected: Array[int], right_connected: Array[int]) -> void:
	_connected_left_slots.assign(left_connected)
	_connected_right_slots.assign(right_connected)
	_show_connection_state = true
	if is_node_ready():
		slot_edges.set_connected_slots(_connected_left_slots, _connected_right_slots)


func _render_card() -> void:
	if card_resource == null:
		var empty_slots: Array[int] = []
		title_label.text = ""
		family_label.text = ""
		main_icon.texture = null
		description_label.text = ""
		left_stat.get_parent().visible = false
		right_stat.get_parent().visible = false
		slot_edges.configure(empty_slots, empty_slots, false)
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
	description_label.text = _get_effect_summary(card_resource)
	_render_stat(left_stat, left_stat_icon, left_stat_value, COST_ICON, "%d" % card_resource.budget_cost)
	var risk_value: float = 0.0
	if card_resource is BehaviorCardResource:
		var behavior := card_resource as BehaviorCardResource
		risk_value = behavior.axes.risk
		slot_edges.configure(behavior.left_slots, behavior.right_slots, true)
		if _show_connection_state:
			slot_edges.set_connected_slots(_connected_left_slots, _connected_right_slots)
	else:
		var empty_slots: Array[int] = []
		slot_edges.configure(empty_slots, empty_slots, false)
	_render_stat(right_stat, right_stat_icon, right_stat_value, RISK_ICON, "%+.0f" % risk_value)
	disabled = locked
	tooltip_text = ""
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
		return "噱头%+.0f　质量%+.0f\n效果%+.0f　风险%+.0f" % [axes.hook, axes.quality, axes.impact, axes.risk]
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
	if slot_edges == null or content_margin == null or locked_label == null:
		return
	disabled = card_resource == null or locked
	locked_label.visible = locked and card_resource != null
	content_margin.modulate = Color(1.0, 1.0, 1.0, 0.34) if locked else Color.WHITE
	slot_edges.set_interaction_state(selected and not disabled, _hovered and not disabled, locked)
	_sync_interaction_drag()


func _ensure_interaction() -> void:
	if _interaction != null or Engine.is_editor_hint():
		return
	_interaction = CardInteraction.new()
	_interaction.name = "CardInteraction"
	add_child(_interaction)
	_interaction.clicked.connect(_on_interaction_clicked)
	_interaction.visual_state_changed.connect(_on_visual_state_changed)
	_sync_interaction_drag()


func _sync_interaction_drag() -> void:
	if _interaction == null:
		return
	_interaction.drag_enabled = not drag_payload.is_empty() and card_resource != null and not locked


func _on_interaction_clicked() -> void:
	if locked or card_resource == null:
		return
	pressed.emit()


func _on_visual_state_changed(is_hovered: bool, is_dragging: bool) -> void:
	_hovered = is_hovered or is_dragging
	_refresh_interaction_state()
