class_name ChatContactItem extends PanelContainer
## LinkChat 联系人条目：脚本只绑定角色数据与状态，布局由同名 TSCN 维护。

const LCTheme := preload("res://scripts/apps/linkchat/style/linkchat_theme.gd")
const PREVIEW_MAX_CHARS: int = 42

signal selected(channel_id: String)

@onready var background: Panel = %Background
@onready var selection_rail: Panel = %SelectionRail
@onready var avatar: RoundedAvatar = %Avatar
@onready var name_label: Label = %NameLabel
@onready var preview_label: Label = %PreviewLabel
@onready var time_label: Label = %TimeLabel

var channel_id: String = ""
var _display_name: String = ""
var _avatar: Texture2D = null
var _background_style: StyleBoxFlat = null
var _selection_tween: Tween = null
var _is_selected: bool = false


func setup(resolved_channel_id: String, display_name: String, avatar: Texture2D = null) -> void:
	channel_id = resolved_channel_id
	_display_name = display_name
	_avatar = avatar
	if is_node_ready():
		_apply_identity()


func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_background_style = LCTheme.rounded_flat(Color.TRANSPARENT, LCTheme.RADIUS_SM)
	background.add_theme_stylebox_override("panel", _background_style)
	selection_rail.add_theme_stylebox_override("panel", LCTheme.rounded_flat(LCTheme.COLOR_ACCENT, 6))
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	_apply_identity()


func _apply_identity() -> void:
	name_label.text = _display_name
	avatar.set_avatar(_avatar, _display_name)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		selected.emit(channel_id)


func set_selected(value: bool) -> void:
	if _background_style == null:
		return
	_is_selected = value
	var target_color: Color = LCTheme.COLOR_CONTACT_SELECTED if value else Color.TRANSPARENT
	var target_rail_alpha: float = 1.0 if value else 0.0
	_background_style.border_width_left = 2 if value else 0
	_background_style.border_width_top = 2 if value else 0
	_background_style.border_width_right = 2 if value else 0
	_background_style.border_width_bottom = 2 if value else 0
	_background_style.border_color = Color("#BCD0EA")
	_background_style.shadow_color = Color(0.1, 0.16, 0.26, 0.14) if value else Color.TRANSPARENT
	_background_style.shadow_size = 7 if value else 0
	_background_style.shadow_offset = Vector2(0, 3)
	selection_rail.visible = value
	if _selection_tween != null and _selection_tween.is_valid():
		_selection_tween.kill()
	_selection_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_selection_tween.tween_property(_background_style, "bg_color", target_color, 0.15)
	_selection_tween.parallel().tween_property(selection_rail, "modulate:a", target_rail_alpha, 0.15)


func _on_mouse_entered() -> void:
	if not _is_selected:
		_background_style.bg_color = LCTheme.COLOR_CONTACT_HOVER


func _on_mouse_exited() -> void:
	if not _is_selected:
		_background_style.bg_color = Color.TRANSPARENT


func update_preview(sender_name: String, content: String, is_player: bool) -> void:
	var normalized: String = content.replace("\r", " ").replace("\n", " ").replace("\t", " ").strip_edges()
	var preview: String = normalized if is_player else "%s: %s" % [sender_name, normalized]
	preview_label.text = preview if preview.length() <= PREVIEW_MAX_CHARS else "%s…" % preview.substr(0, PREVIEW_MAX_CHARS)
	time_label.text = "刚刚"
