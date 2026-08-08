@tool
class_name LiveStreamCardView extends Button
## 直播内容卡统一展示层：行为 / 修饰 / 人设 / 素材共用同一卡框。

const COST_ICON: Texture2D = preload("res://Assets/images/live_stream/cards/icons/stat_stress.svg")
const RISK_ICON: Texture2D = preload("res://Assets/images/live_stream/cards/icons/stat_risk.svg")
const CARD_TOOLTIP_SCENE: PackedScene = preload("res://scenes/apps/obs_live/components/card_tooltip.tscn")
const TOOLTIP_DELAY: float = 0.35
const TOOLTIP_GAP: float = 12.0
const TOOLTIP_VIEWPORT_MARGIN: float = 8.0

@export var content_resource: StreamContentResource = null:
	set(value):
		content_resource = value
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
@onready var stats_bar: HBoxContainer = %Stats
@onready var left_stat: HBoxContainer = %LeftStat
@onready var left_stat_icon: TextureRect = %LeftStatIcon
@onready var left_stat_value: Label = %LeftStatValue
@onready var right_stat: HBoxContainer = %RightStat
@onready var right_stat_icon: TextureRect = %RightStatIcon
@onready var right_stat_value: Label = %RightStatValue
@onready var locked_label: Label = %LockedLabel
@onready var slot_edges: CardSlotEdges = %SlotEdges

var _hovered: bool = false
var _connected_left_slots: Array[int] = []
var _connected_right_slots: Array[int] = []
var _show_connection_state: bool = false
var _interaction: CardInteraction = null
var _left_stat_override: String = ""
var _right_stat_override: String = ""
var _tooltip_override: String = ""
var _tooltip_text: String = ""
var _tooltip: CardTooltipView = null
var _tooltip_serial: int = 0

## 拖拽负载；非空时本卡可被拖起。常用键：kind / card_id / id / from_slot / title。
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


func configure(
	resource: StreamContentResource,
	is_selected: bool = false,
	is_locked: bool = false,
	left_stat_text: String = "",
	right_stat_text: String = "",
	tooltip_override: String = ""
) -> void:
	_connected_left_slots.clear()
	_connected_right_slots.clear()
	_show_connection_state = false
	_left_stat_override = left_stat_text
	_right_stat_override = right_stat_text
	_tooltip_override = tooltip_override
	content_resource = resource
	selected = is_selected
	locked = is_locked


func configure_connection_state(left_connected: Array[int], right_connected: Array[int]) -> void:
	_connected_left_slots.assign(left_connected)
	_connected_right_slots.assign(right_connected)
	_show_connection_state = true
	if is_node_ready():
		slot_edges.set_connected_slots(_connected_left_slots, _connected_right_slots)


func _render_card() -> void:
	if content_resource == null:
		var empty_slots: Array[int] = []
		title_label.text = ""
		_hide_stat(left_stat)
		_hide_stat(right_stat)
		slot_edges.configure(empty_slots, empty_slots, false)
		slot_edges.set_face_texture(null)
		disabled = true
		_tooltip_text = ""
		_hide_tooltip()
		_refresh_interaction_state()
		return

	title_label.text = content_resource.display_name
	slot_edges.set_face_texture(CardFaceCatalog.face_for(content_resource))

	var empty_slots: Array[int] = []
	if content_resource is BehaviorCardResource:
		var behavior := content_resource as BehaviorCardResource
		slot_edges.configure(behavior.left_slots, behavior.right_slots, true)
		if _show_connection_state:
			slot_edges.set_connected_slots(_connected_left_slots, _connected_right_slots)
		_render_stat(left_stat, left_stat_icon, left_stat_value, COST_ICON, _stat_text(_left_stat_override, "%d" % behavior.budget_cost))
		_render_stat(right_stat, right_stat_icon, right_stat_value, RISK_ICON, _stat_text(_right_stat_override, "%+.0f" % behavior.axes.risk))
	elif content_resource is ModifierCardResource:
		var modifier := content_resource as ModifierCardResource
		slot_edges.configure(empty_slots, empty_slots, false)
		_render_stat(left_stat, left_stat_icon, left_stat_value, COST_ICON, _stat_text(_left_stat_override, "%d" % modifier.budget_cost))
		_render_stat(right_stat, right_stat_icon, right_stat_value, RISK_ICON, _stat_text(_right_stat_override, "+0"))
	elif content_resource is StreamPersonaResource:
		slot_edges.configure(empty_slots, empty_slots, false)
		_render_stat(left_stat, left_stat_icon, left_stat_value, null, _stat_text(_left_stat_override, "形象"))
		_render_stat(right_stat, right_stat_icon, right_stat_value, null, _stat_text(_right_stat_override, "本场出镜"))
	elif content_resource is LiveStreamMaterialResource:
		var material_res := content_resource as LiveStreamMaterialResource
		slot_edges.configure(empty_slots, empty_slots, false)
		_render_stat(
			left_stat,
			left_stat_icon,
			left_stat_value,
			null,
			_stat_text(_left_stat_override, "槽 %d" % material_res.program_slot_count)
		)
		_render_stat(
			right_stat,
			right_stat_icon,
			right_stat_value,
			null,
			_stat_text(_right_stat_override, "素材")
		)
	else:
		slot_edges.configure(empty_slots, empty_slots, false)
		_hide_stat(left_stat)
		_hide_stat(right_stat)

	disabled = locked
	tooltip_text = ""
	_tooltip_text = _tooltip_override if not _tooltip_override.is_empty() else _build_tooltip(content_resource)
	_refresh_interaction_state()


func _stat_text(override_text: String, default_text: String) -> String:
	return override_text if not override_text.is_empty() else default_text


func override_tooltip(text: String) -> void:
	_tooltip_override = text
	_tooltip_text = text
	if is_node_ready():
		tooltip_text = ""


func _schedule_tooltip() -> void:
	if _tooltip_text.is_empty() or content_resource == null:
		return
	_tooltip_serial += 1
	var serial: int = _tooltip_serial
	await get_tree().create_timer(TOOLTIP_DELAY).timeout
	if serial != _tooltip_serial or not _hovered or not is_inside_tree():
		return
	_show_tooltip()


func _show_tooltip() -> void:
	if _tooltip == null:
		_tooltip = CARD_TOOLTIP_SCENE.instantiate()
		_tooltip.visible = false
		_tooltip.z_index = 100
		add_child(_tooltip)
	_tooltip.configure(_tooltip_text)
	_tooltip.reset_size()
	var tip_size: Vector2 = _tooltip.get_combined_minimum_size()
	var pos := Vector2((size.x - tip_size.x) * 0.5, -tip_size.y - TOOLTIP_GAP)
	var card_global: Vector2 = get_global_rect().position
	# 顶部放不下则改放卡片下方。
	if card_global.y + pos.y < TOOLTIP_VIEWPORT_MARGIN:
		pos.y = size.y + TOOLTIP_GAP
	# 水平方向限制在视口内。
	var viewport_width: float = get_viewport_rect().size.x
	var clamped_x: float = clampf(
		card_global.x + pos.x,
		TOOLTIP_VIEWPORT_MARGIN,
		maxf(TOOLTIP_VIEWPORT_MARGIN, viewport_width - tip_size.x - TOOLTIP_VIEWPORT_MARGIN)
	)
	pos.x += clamped_x - (card_global.x + pos.x)
	_tooltip.position = pos
	_tooltip.visible = true


func _hide_tooltip() -> void:
	_tooltip_serial += 1
	if _tooltip != null:
		_tooltip.visible = false


func _hide_stat(container: HBoxContainer) -> void:
	var stat_panel := container.get_parent() as Control
	if stat_panel != null:
		stat_panel.visible = false
	container.visible = false


func _render_stat(
	container: HBoxContainer,
	icon_rect: TextureRect,
	value_label: Label,
	icon_texture: Texture2D,
	value_text: String
) -> void:
	container.visible = true
	var stat_panel := container.get_parent() as Control
	if stat_panel != null:
		stat_panel.visible = true
	icon_rect.visible = icon_texture != null
	icon_rect.texture = icon_texture
	value_label.text = value_text


func _build_tooltip(resource: StreamContentResource) -> String:
	if resource is LiveStreamCardResource:
		var card := resource as LiveStreamCardResource
		var lines: PackedStringArray = []
		if not card.description.strip_edges().is_empty():
			lines.append(card.description.strip_edges())
		var summary: String = _get_effect_summary(card)
		if not summary.is_empty():
			lines.append(summary)
		return "\n".join(lines)
	return resource.description.strip_edges()


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
	if slot_edges == null or stats_bar == null or locked_label == null:
		return
	disabled = content_resource == null or locked
	locked_label.visible = locked and content_resource != null
	var content_modulate := Color(1.0, 1.0, 1.0, 0.34) if locked else Color.WHITE
	title_label.modulate = content_modulate
	stats_bar.modulate = content_modulate
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
	_interaction.drag_enabled = not drag_payload.is_empty() and content_resource != null and not locked


func _on_interaction_clicked() -> void:
	if locked or content_resource == null:
		return
	_hide_tooltip()
	pressed.emit()


func _on_visual_state_changed(is_hovered: bool, is_dragging: bool) -> void:
	_hovered = is_hovered or is_dragging
	_refresh_interaction_state()
	if is_hovered and not is_dragging:
		_schedule_tooltip()
	else:
		_hide_tooltip()
