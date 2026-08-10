class_name CityHopApp extends Control
## CityHop 仅负责发现与发起外出，完整流程由 OutingManager 编排。

const ContactItemScene = preload("res://scenes/apps/linkchat/contact_item.tscn")

const COLOR_TEXT: Color = Color("#182238")
const COLOR_MUTED: Color = Color("#68748A")
const COLOR_ACCENT: Color = Color("#F64055")
const COLOR_ACCENT_SOFT: Color = Color("#FFF0F2")
const SLOT_NAMES: Array[String] = ["上午", "下午", "晚上"]

@onready var day_label: Label = %DayLabel
@onready var money_label: Label = %MoneyLabel
@onready var search_input: LineEdit = %SearchInput
@onready var all_filter: Button = %AllFilter
@onready var now_filter: Button = %NowFilter
@onready var free_filter: Button = %FreeFilter
@onready var date_filter: Button = %DateFilter
@onready var activity_list: VBoxContainer = %ActivityList
@onready var map_texture: TextureRect = %MapTexture
@onready var pin_layer: Control = %PinLayer
@onready var detail_cover: TextureRect = %DetailCover
@onready var detail_kind: Label = %DetailKind
@onready var detail_title: Label = %DetailTitle
@onready var detail_meta: Label = %DetailMeta
@onready var detail_description: Label = %DetailDescription
@onready var detail_tags: Label = %DetailTags
@onready var solo_button: Button = %SoloButton
@onready var date_button: Button = %DateButton
@onready var status_label: Label = %StatusLabel
@onready var friend_overlay: Control = %FriendOverlay
@onready var friend_list: VBoxContainer = %FriendList
@onready var friend_caption: Label = %FriendCaption
@onready var friend_close_button: Button = %FriendCloseButton
@onready var failure_overlay: Control = %FailureOverlay
@onready var failure_stage_label: Label = %FailureStageLabel
@onready var failure_error_label: Label = %FailureErrorLabel
@onready var retry_button: Button = %RetryButton

var _selected_activity_id: String = ""
var _filter: String = "all"
var _pin_buttons: Dictionary = {}


func _ready() -> void:
	map_texture.texture = preload("res://Assets/images/cityhop/city_map.png")
	_connect_controls()
	_connect_managers()
	_apply_control_theme()
	_refresh_all()
	call_deferred("_layout_pins")


func open_activity(activity_id: String) -> void:
	var activity: OutingActivity = OutingManager.get_activity(activity_id)
	if activity == null:
		return
	_selected_activity_id = activity.activity_id
	_render_detail(activity)
	_update_selection_styles()


func _connect_controls() -> void:
	all_filter.pressed.connect(_set_filter.bind("all"))
	now_filter.pressed.connect(_set_filter.bind("now"))
	free_filter.pressed.connect(_set_filter.bind("free"))
	date_filter.pressed.connect(_set_filter.bind("date"))
	search_input.text_changed.connect(_on_search_changed)
	solo_button.pressed.connect(_on_solo_pressed)
	date_button.pressed.connect(_on_date_pressed)
	friend_close_button.pressed.connect(func() -> void: friend_overlay.visible = false)
	retry_button.pressed.connect(_on_retry_pressed)
	pin_layer.resized.connect(_layout_pins)


func _connect_managers() -> void:
	OutingManager.session_changed.connect(_on_session_changed)
	OutingManager.session_failed.connect(_on_session_failed)
	OutingManager.session_completed.connect(_on_session_completed)
	GameState.money_changed.connect(func(_value: int) -> void: _refresh_header())
	GameState.day_changed.connect(func(_value: int) -> void: _refresh_all())
	GameState.time_slot_changed.connect(func(_value: int) -> void: _refresh_all())


func _apply_control_theme() -> void:
	for button: Button in [all_filter, now_filter, free_filter, date_filter, solo_button, date_button, friend_close_button, retry_button]:
		button.add_theme_color_override("font_color", COLOR_TEXT)
		button.add_theme_color_override("font_hover_color", COLOR_TEXT)
		button.add_theme_color_override("font_pressed_color", COLOR_TEXT)
		button.add_theme_color_override("font_disabled_color", Color("#A6ADBA"))


func _refresh_all() -> void:
	_refresh_header()
	_build_activity_list()
	_build_pins()
	if _selected_activity_id.is_empty():
		var available: Array[OutingActivity] = OutingManager.get_available_activities()
		if not available.is_empty():
			_selected_activity_id = available[0].activity_id
	var selected: OutingActivity = OutingManager.get_activity(_selected_activity_id)
	if selected != null:
		_render_detail(selected)
	_update_failure_overlay(OutingManager.get_active_session())


func _refresh_header() -> void:
	var slot_index: int = clampi(GameState.time_slot, 0, SLOT_NAMES.size() - 1)
	day_label.text = "第 %d 天 · %s" % [GameState.day, SLOT_NAMES[slot_index]]
	money_label.text = "¥ %s" % _format_number(GameState.money)


func _build_activity_list() -> void:
	for child: Node in activity_list.get_children():
		child.queue_free()
	var catalog: OutingCatalog = OutingManager.get_catalog()
	for activity: OutingActivity in catalog.activities:
		if activity == null or not _matches_filter(activity):
			continue
		var place: MapPlace = catalog.get_place(activity.place_id)
		var button := Button.new()
		button.name = "Activity_%s" % activity.activity_id
		button.custom_minimum_size = Vector2(0, 132)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text = "%s\n%s  ·  %s" % [
			activity.title,
			place.display_name if place != null else activity.place_id,
			_cost_text(activity),
		]
		button.add_theme_font_size_override("font_size", 30)
		button.add_theme_color_override("font_color", COLOR_TEXT)
		button.add_theme_color_override("font_hover_color", COLOR_TEXT)
		button.add_theme_color_override("font_pressed_color", COLOR_TEXT)
		button.add_theme_color_override("font_disabled_color", Color("#99A1B0"))
		button.add_theme_stylebox_override("normal", _list_style(activity.activity_id == _selected_activity_id, false))
		button.add_theme_stylebox_override("hover", _list_style(true, true))
		button.add_theme_stylebox_override("pressed", _list_style(true, true))
		button.add_theme_stylebox_override("disabled", _list_style(false, false))
		button.disabled = not activity.is_available(GameState.day, GameState.time_slot)
		button.tooltip_text = "当前时段不可参加" if button.disabled else ""
		button.pressed.connect(open_activity.bind(activity.activity_id))
		activity_list.add_child(button)


func _build_pins() -> void:
	for child: Node in pin_layer.get_children():
		child.queue_free()
	_pin_buttons.clear()
	var catalog: OutingCatalog = OutingManager.get_catalog()
	for activity: OutingActivity in catalog.activities:
		if activity == null:
			continue
		var place: MapPlace = catalog.get_place(activity.place_id)
		if place == null:
			continue
		var pin := Button.new()
		pin.custom_minimum_size = Vector2(252, 84)
		pin.text = activity.title
		pin.add_theme_font_size_override("font_size", 27)
		pin.add_theme_color_override("font_color", Color.WHITE)
		pin.add_theme_color_override("font_hover_color", Color.WHITE)
		pin.add_theme_color_override("font_pressed_color", Color.WHITE)
		pin.add_theme_stylebox_override("normal", _pin_style(false))
		pin.add_theme_stylebox_override("hover", _pin_style(true))
		pin.add_theme_stylebox_override("pressed", _pin_style(true))
		pin.pressed.connect(open_activity.bind(activity.activity_id))
		pin.set_meta("map_position", place.map_position)
		pin_layer.add_child(pin)
		_pin_buttons[activity.activity_id] = pin
	_layout_pins.call_deferred()


func _layout_pins() -> void:
	if pin_layer == null or pin_layer.size.x <= 0.0 or pin_layer.size.y <= 0.0:
		return
	for button_value: Variant in _pin_buttons.values():
		var button: Button = button_value as Button
		if button == null:
			continue
		var normalized: Vector2 = button.get_meta("map_position", Vector2(0.5, 0.5))
		button.position = Vector2(
			normalized.x * pin_layer.size.x - button.custom_minimum_size.x * 0.5,
			normalized.y * pin_layer.size.y - button.custom_minimum_size.y
		)


func _render_detail(activity: OutingActivity) -> void:
	var place: MapPlace = OutingManager.get_place(activity.place_id)
	detail_cover.texture = place.cover if place != null else null
	detail_kind.text = "限时活动" if activity.listing_kind == OutingActivity.KIND_EVENT else (place.category if place != null else "地点")
	detail_title.text = activity.title
	detail_meta.text = "%s\n★ %.1f（%d 条点评）\n%s" % [
		place.display_name if place != null else activity.place_id,
		place.rating if place != null else 0.0,
		place.review_count if place != null else 0,
		place.district if place != null else "",
	]
	detail_description.text = activity.description
	detail_tags.text = "  ".join(activity.tags)
	solo_button.text = "一个人去  ·  %s" % ("免费" if activity.solo_cost <= 0 else "¥%d" % activity.solo_cost)
	date_button.text = "邀请好友  ·  %s" % ("免费" if activity.date_cost <= 0 else "¥%d" % activity.date_cost)
	var available: bool = activity.is_available(GameState.day, GameState.time_slot)
	solo_button.disabled = not available or not activity.supports_solo or OutingManager.has_active_session()
	date_button.disabled = not available or not activity.supports_date or OutingManager.has_active_session()
	status_label.text = "当前时段可以出发" if available else "当前时段不可参加"


func _on_solo_pressed() -> void:
	var validation: Dictionary = OutingManager.validate_start(_selected_activity_id, OutingManager.MODE_SOLO)
	if not bool(validation.get("ok", false)):
		_show_local_error("无法出发", str(validation.get("reason", "当前无法执行")))
		return
	status_label.text = "正在准备外出剧情"
	OutingManager.start_solo_outing(_selected_activity_id)


func _on_date_pressed() -> void:
	friend_caption.text = "选择一位好友，地点卡会通过 LinkChat 发送。"
	friend_caption.add_theme_color_override("font_color", COLOR_MUTED)
	_build_friend_list()
	friend_overlay.visible = true


func _build_friend_list() -> void:
	for child: Node in friend_list.get_children():
		child.queue_free()
	var found: bool = false
	for character: CharacterProfile in LinkChatManager.get_friend_characters():
		if character == null or not character.datable or character.avg_character == null:
			continue
		found = true
		var failed_today: bool = OutingManager.has_failed_invite_today(character.character_id)
		var item: ChatContactItem = ContactItemScene.instantiate() as ChatContactItem
		var account_name: String = character.linkchat_profile.account_name if character.linkchat_profile != null else character.display_name
		var avatar: Texture2D = character.linkchat_profile.avatar if character.linkchat_profile != null else null
		item.setup(character.character_id, account_name, avatar)
		friend_list.add_child(item)
		item.update_preview(character.display_name, _date_profile_text(character), true)
		item.set_trailing_text("今日已邀请" if failed_today else "可邀请")
		item.set_interactable(not failed_today)
		if not failed_today:
			item.selected.connect(_start_date_with)
	if not found:
		var label := Label.new()
		label.text = "当前没有可以邀请的好友"
		label.add_theme_font_size_override("font_size", 30)
		label.add_theme_color_override("font_color", COLOR_MUTED)
		friend_list.add_child(label)


func _start_date_with(character_id: String) -> void:
	var validation: Dictionary = OutingManager.validate_start(_selected_activity_id, OutingManager.MODE_DATE, character_id)
	if not bool(validation.get("ok", false)):
		friend_caption.text = "无法邀请：%s" % str(validation.get("reason", "当前无法邀请"))
		friend_caption.add_theme_color_override("font_color", Color("#B34242"))
		return
	status_label.text = "正在发送地点卡"
	if not OutingManager.start_date_outing(_selected_activity_id, character_id):
		friend_caption.text = "邀约未能启动，请检查当前状态后重试。"
		friend_caption.add_theme_color_override("font_color", Color("#B34242"))
		return
	friend_overlay.visible = false


func _date_profile_text(character: CharacterProfile) -> String:
	var labels: Array[String] = []
	for tag: String in character.outing_preference_tags:
		match tag:
			"music": labels.append("音乐")
			"night": labels.append("夜间活动")
			"cafe": labels.append("咖啡店")
			_: labels.append(tag)
	return "偏好：%s" % "、".join(labels) if not labels.is_empty() else "可以邀请外出"


func _on_retry_pressed() -> void:
	retry_button.disabled = true
	failure_error_label.text = "正在重试同一次剧情生成…"
	if not OutingManager.retry_failed_stage():
		retry_button.disabled = false
		failure_error_label.text = "当前失败状态无法重试"


func _on_session_changed(snapshot: Dictionary) -> void:
	_update_failure_overlay(snapshot)
	var activity: OutingActivity = OutingManager.get_activity(_selected_activity_id)
	if activity != null:
		_render_detail(activity)


func _on_session_failed(stage: String, error: String, _snapshot: Dictionary) -> void:
	failure_stage_label.text = _failure_title(stage)
	failure_error_label.text = error
	retry_button.disabled = false
	failure_overlay.visible = true


func _on_session_completed(snapshot: Dictionary) -> void:
	failure_overlay.visible = false
	var status: String = str(snapshot.get("status", ""))
	status_label.text = "对方这次没有答应" if status == "rejected" else "外出已经结束"
	_refresh_all()


func _update_failure_overlay(snapshot: Dictionary) -> void:
	var failed: bool = str(snapshot.get("status", "")) == "failed"
	failure_overlay.visible = failed
	if failed:
		failure_stage_label.text = _failure_title(str(snapshot.get("failed_stage", "")))
		failure_error_label.text = str(snapshot.get("error", "未知错误"))
		retry_button.disabled = false


func _show_local_error(title: String, error: String) -> void:
	status_label.text = "%s：%s" % [title, error]


func _set_filter(filter_name: String) -> void:
	_filter = filter_name
	_build_activity_list()


func _on_search_changed(_value: String) -> void:
	_build_activity_list()


func _matches_filter(activity: OutingActivity) -> bool:
	var query: String = search_input.text.strip_edges().to_lower()
	var place: MapPlace = OutingManager.get_place(activity.place_id)
	if not query.is_empty():
		var haystack: String = "%s %s %s" % [activity.title, activity.description, place.display_name if place != null else ""]
		if query not in haystack.to_lower():
			return false
	match _filter:
		"now": return activity.is_available(GameState.day, GameState.time_slot)
		"free": return activity.solo_cost <= 0
		"date": return activity.supports_date
	return true


func _update_selection_styles() -> void:
	for child: Node in activity_list.get_children():
		if child is Button:
			var activity_id: String = str(child.name).trim_prefix("Activity_")
			(child as Button).add_theme_stylebox_override("normal", _list_style(activity_id == _selected_activity_id, false))
	for activity_id_value: Variant in _pin_buttons:
		var activity_id: String = str(activity_id_value)
		var button: Button = _pin_buttons[activity_id_value] as Button
		if button != null:
			button.add_theme_stylebox_override("normal", _pin_style(activity_id == _selected_activity_id))


func _list_style(selected: bool, hovered: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_ACCENT_SOFT if selected else (Color("#FFF6F7") if hovered else Color.WHITE)
	style.border_color = Color("#F3B7BE") if selected else Color("#E4E8EF")
	style.set_border_width_all(2)
	style.set_corner_radius_all(22)
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	return style


func _pin_style(selected: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#D93F55") if selected else COLOR_ACCENT
	style.set_corner_radius_all(42)
	style.shadow_color = Color(0.12, 0.16, 0.25, 0.24)
	style.shadow_size = 10
	style.content_margin_left = 24
	style.content_margin_right = 24
	return style


func _cost_text(activity: OutingActivity) -> String:
	return "免费" if activity.solo_cost <= 0 else "¥%d 起" % activity.solo_cost


func _failure_title(stage: String) -> String:
	match stage:
		"invite": return "邀约对话生成失败"
		"generation": return "外出 AVG 生成失败"
		"avg": return "外出 AVG 播放失败"
		"feedback": return "返程消息生成失败"
	return "外出剧情中断"


func _format_number(value: int) -> String:
	var source: String = str(absi(value))
	var groups: Array[String] = []
	while source.length() > 3:
		groups.push_front(source.right(3))
		source = source.left(source.length() - 3)
	groups.push_front(source)
	return ("-" if value < 0 else "") + ",".join(groups)
