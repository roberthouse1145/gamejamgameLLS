@tool
class_name LiveStreamCardView extends Button
## 直播素材与人设的统一卡框。

const TOOLTIP_DELAY: float = 0.35

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

## 本场不可用（素材不兼容等）：置灰显示但不可交互，不显示锁定标。
@export var unavailable: bool = false:
	set(value):
		unavailable = value
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
var _interaction: CardInteraction = null
var _left_stat_override: String = ""
var _right_stat_override: String = ""
var _tooltip_override: String = ""
var _tooltip_text: String = ""
var _tooltip_serial: int = 0

## 拖拽负载；非空时该素材视图可被拖起。常用键：kind / id / title。
var drag_payload: Dictionary = {}:
	set(value):
		drag_payload = value
		_sync_interaction_drag()


func get_card_payload() -> Dictionary:
	return drag_payload


func set_card_shadow_strength(strength: float) -> void:
	if slot_edges != null:
		slot_edges.set_glow_strength(strength)


func _process(_delta: float) -> void:
	if _hovered and TooltipLayer.is_tooltip_visible():
		TooltipLayer.move_tooltip(get_global_mouse_position())


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
	_left_stat_override = left_stat_text
	_right_stat_override = right_stat_text
	_tooltip_override = tooltip_override
	content_resource = resource
	selected = is_selected
	locked = is_locked


func _render_card() -> void:
	var empty_slots: Array[int] = []
	if content_resource == null:
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

	if content_resource is StreamPersonaResource:
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
			_stat_text(_left_stat_override, material_res.get_material_type_label())
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


func override_tooltip(tooltip_copy: String) -> void:
	_tooltip_override = tooltip_copy
	_tooltip_text = tooltip_copy
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
	TooltipLayer.show_tooltip(_tooltip_text, get_global_mouse_position())


func _hide_tooltip() -> void:
	_tooltip_serial += 1
	TooltipLayer.hide_tooltip()


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
	return resource.description.strip_edges()


func _refresh_interaction_state() -> void:
	if slot_edges == null or stats_bar == null or locked_label == null:
		return
	disabled = content_resource == null or locked or unavailable
	locked_label.visible = locked and content_resource != null
	var content_modulate := Color.WHITE
	if locked:
		content_modulate = Color(1.0, 1.0, 1.0, 0.34)
	elif unavailable:
		content_modulate = Color(1.0, 1.0, 1.0, 0.5)
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


func _on_visual_state_changed(hovered_now: bool, is_dragging: bool) -> void:
	_hovered = hovered_now or is_dragging
	_refresh_interaction_state()
	if hovered_now and not is_dragging:
		_schedule_tooltip()
	else:
		_hide_tooltip()
