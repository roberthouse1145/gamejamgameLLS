class_name CityHopApp extends Control
## CityHop 仅负责发现与发起外出，完整流程由 OutingManager 编排。

const ContactItemScene = preload("res://scenes/apps/linkchat/contact_item.tscn")

const COLOR_TEXT: Color = Color("#182238")
const COLOR_MUTED: Color = Color("#68748A")
const COLOR_ACCENT: Color = Color("#F64055")
const COLOR_ACCENT_SOFT: Color = Color("#FFF0F2")
const COLOR_DISABLED_TEXT: Color = Color("#667085")
const SLOT_NAMES: Array[String] = ["上午", "下午", "晚上"]
const MAP_ZOOM: float = 1.22
const MAP_DRAG_THRESHOLD: float = 10.0
const DETAIL_WIDTH: float = 820.0
const DETAIL_MARGIN: float = 18.0
const DETAIL_TWEEN_DURATION: float = 0.24
const MAP_FOCUS_DURATION: float = 0.38

@onready var day_label: Label = %DayLabel
@onready var money_label: Label = %MoneyLabel
@onready var search_input: LineEdit = %SearchInput
@onready var all_filter: Button = %AllFilter
@onready var now_filter: Button = %NowFilter
@onready var free_filter: Button = %FreeFilter
@onready var date_filter: Button = %DateFilter
@onready var activity_list: VBoxContainer = %ActivityList
@onready var content: Control = %Content
@onready var map_canvas: Control = %MapCanvas
@onready var map_content: Control = %MapContent
@onready var map_texture: TextureRect = %MapTexture
@onready var pin_layer: Control = %PinLayer
@onready var detail_panel: PanelContainer = %DetailPanel
@onready var detail_scroll: ScrollContainer = %DetailScroll
@onready var detail_cover: TextureRect = %DetailCover
@onready var detail_kind: Label = %DetailKind
@onready var detail_title: Label = %DetailTitle
@onready var detail_meta: Label = %DetailMeta
@onready var detail_description: Label = %DetailDescription
@onready var action_status_panel: PanelContainer = %ActionStatusPanel
@onready var action_status_label: Label = %ActionStatusLabel
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
var _map_initialized: bool = false
var _map_pointer_down: bool = false
var _map_dragging: bool = false
var _map_press_position: Vector2 = Vector2.ZERO
var _map_press_content_position: Vector2 = Vector2.ZERO
var _map_focus_tween: Tween
var _detail_tween: Tween


func _ready() -> void:
	map_texture.texture = preload("res://Assets/images/cityhop/city_map.png")
	_connect_controls()
	_connect_managers()
	_apply_control_theme()
	_sync_detail_geometry()
	_refresh_all()
	call_deferred("_refresh_map_geometry")


func open_activity(activity_id: String) -> void:
	var activity: OutingActivity = OutingManager.get_activity(activity_id)
	if activity == null:
		return
	_selected_activity_id = activity.activity_id
	_render_detail(activity)
	detail_scroll.scroll_vertical = 0
	_show_detail()
	_update_selection_styles()
	_focus_activity(activity)


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
	map_canvas.gui_input.connect(_on_map_gui_input)
	map_canvas.resized.connect(_refresh_map_geometry)
	content.resized.connect(_sync_detail_geometry)
	map_content.resized.connect(_layout_pins)


func _connect_managers() -> void:
	OutingManager.session_changed.connect(_on_session_changed)
	OutingManager.session_failed.connect(_on_session_failed)
	OutingManager.session_completed.connect(_on_session_completed)
	GameState.money_changed.connect(_on_money_changed)
	GameState.day_changed.connect(func(_value: int) -> void: _refresh_all())
	GameState.time_slot_changed.connect(func(_value: int) -> void: _refresh_all())


func _apply_control_theme() -> void:
	for button: Button in [all_filter, now_filter, free_filter, date_filter, solo_button, date_button, friend_close_button, retry_button]:
		button.add_theme_color_override("font_color", COLOR_TEXT)
		button.add_theme_color_override("font_hover_color", COLOR_TEXT)
		button.add_theme_color_override("font_pressed_color", COLOR_TEXT)
		button.add_theme_color_override("font_disabled_color", Color("#A6ADBA"))
	for button: Button in [solo_button, date_button]:
		button.add_theme_color_override("font_disabled_color", COLOR_DISABLED_TEXT)


func _refresh_all() -> void:
	_refresh_header()
	_build_activity_list()
	_build_pins()
	var selected: OutingActivity = OutingManager.get_activity(_selected_activity_id)
	if selected != null and selected in OutingManager.get_daily_activities():
		_render_detail(selected)
	else:
		_selected_activity_id = ""
		_hide_detail_immediate()
	_update_failure_overlay(OutingManager.get_active_session())


func _refresh_header() -> void:
	var slot_index: int = clampi(GameState.time_slot, 0, SLOT_NAMES.size() - 1)
	day_label.text = "第 %d 天 · %s" % [GameState.day, SLOT_NAMES[slot_index]]
	money_label.text = "¥ %s" % _format_number(GameState.money)


func _on_money_changed(_value: int) -> void:
	_refresh_header()
	var activity: OutingActivity = OutingManager.get_activity(_selected_activity_id)
	if activity != null:
		_render_detail(activity)


func _build_activity_list() -> void:
	for child: Node in activity_list.get_children():
		child.queue_free()
	var catalog: OutingCatalog = OutingManager.get_catalog()
	for activity: OutingActivity in OutingManager.get_daily_activities():
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
		button.add_theme_stylebox_override("normal", _list_style(activity.activity_id == _selected_activity_id, false))
		button.add_theme_stylebox_override("hover", _list_style(true, true))
		button.add_theme_stylebox_override("pressed", _list_style(true, true))
		button.pressed.connect(open_activity.bind(activity.activity_id))
		activity_list.add_child(button)


func _build_pins() -> void:
	for child: Node in pin_layer.get_children():
		child.queue_free()
	_pin_buttons.clear()
	var catalog: OutingCatalog = OutingManager.get_catalog()
	for activity: OutingActivity in OutingManager.get_daily_activities():
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


func _refresh_map_geometry() -> void:
	if map_canvas == null or map_texture.texture == null:
		return
	if map_canvas.size.x <= 0.0 or map_canvas.size.y <= 0.0:
		return
	var source_size: Vector2 = map_texture.texture.get_size()
	if source_size.x <= 0.0 or source_size.y <= 0.0:
		return
	var cover_ratio: float = maxf(map_canvas.size.x / source_size.x, map_canvas.size.y / source_size.y)
	var content_size: Vector2 = (source_size * cover_ratio * MAP_ZOOM).ceil()
	map_content.size = content_size
	if not _map_initialized:
		map_content.position = (map_canvas.size - content_size) * 0.5
		_map_initialized = true
	else:
		map_content.position = _clamp_map_position(map_content.position)
	_layout_pins()
	if not _selected_activity_id.is_empty():
		var selected: OutingActivity = OutingManager.get_activity(_selected_activity_id)
		if selected != null:
			_focus_activity(selected, false)


func _on_map_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_button: InputEventMouseButton = event as InputEventMouseButton
		if mouse_button.button_index != MOUSE_BUTTON_LEFT:
			return
		if mouse_button.pressed:
			_map_pointer_down = true
			_map_dragging = false
			_map_press_position = mouse_button.position
			_map_press_content_position = map_content.position
			_stop_map_focus_tween()
		else:
			if _map_pointer_down and not _map_dragging:
				_clear_selection_and_hide_detail()
			_map_pointer_down = false
			_map_dragging = false
		map_canvas.accept_event()
		return
	if event is InputEventMouseMotion and _map_pointer_down:
		var mouse_motion: InputEventMouseMotion = event as InputEventMouseMotion
		var pointer_delta: Vector2 = mouse_motion.position - _map_press_position
		if not _map_dragging and pointer_delta.length() >= MAP_DRAG_THRESHOLD:
			_map_dragging = true
		if _map_dragging:
			map_content.position = _clamp_map_position(_map_press_content_position + pointer_delta)
		map_canvas.accept_event()


func _focus_activity(activity: OutingActivity, animated: bool = true) -> void:
	if not _map_initialized:
		return
	var place: MapPlace = OutingManager.get_place(activity.place_id)
	if place == null:
		return
	_stop_map_focus_tween()
	var drawer_occupied_width: float = DETAIL_WIDTH + DETAIL_MARGIN * 2.0 if detail_panel.visible else 0.0
	var visible_center: Vector2 = Vector2(
		(map_canvas.size.x - drawer_occupied_width) * 0.5,
		map_canvas.size.y * 0.5
	)
	var map_point: Vector2 = Vector2(
		place.map_position.x * map_content.size.x,
		place.map_position.y * map_content.size.y
	)
	var target_position: Vector2 = _clamp_map_position(visible_center - map_point)
	if not animated:
		map_content.position = target_position
		return
	_map_focus_tween = create_tween()
	_map_focus_tween.tween_property(map_content, "position", target_position, MAP_FOCUS_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)


func _clamp_map_position(candidate: Vector2) -> Vector2:
	var minimum: Vector2 = Vector2(
		minf(0.0, map_canvas.size.x - map_content.size.x),
		minf(0.0, map_canvas.size.y - map_content.size.y)
	)
	return Vector2(
		clampf(candidate.x, minimum.x, 0.0),
		clampf(candidate.y, minimum.y, 0.0)
	)


func _stop_map_focus_tween() -> void:
	if _map_focus_tween != null and _map_focus_tween.is_valid():
		_map_focus_tween.kill()
	_map_focus_tween = null


func _show_detail() -> void:
	_sync_detail_geometry()
	var target_x: float = content.size.x - DETAIL_WIDTH - DETAIL_MARGIN
	if _detail_tween != null and _detail_tween.is_valid():
		_detail_tween.kill()
	if not detail_panel.visible:
		detail_panel.position.x = content.size.x + DETAIL_MARGIN
		detail_panel.visible = true
	_detail_tween = create_tween()
	_detail_tween.tween_property(detail_panel, "position:x", target_x, DETAIL_TWEEN_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _clear_selection_and_hide_detail() -> void:
	_selected_activity_id = ""
	_update_selection_styles()
	status_label.text = "选择活动，或拖动地图探索"
	if not detail_panel.visible:
		return
	if _detail_tween != null and _detail_tween.is_valid():
		_detail_tween.kill()
	_detail_tween = create_tween()
	_detail_tween.tween_property(detail_panel, "position:x", content.size.x + DETAIL_MARGIN, DETAIL_TWEEN_DURATION * 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_detail_tween.tween_callback(func() -> void: detail_panel.visible = false)


func _hide_detail_immediate() -> void:
	if detail_panel == null or content == null:
		return
	if _detail_tween != null and _detail_tween.is_valid():
		_detail_tween.kill()
	detail_panel.visible = false
	detail_panel.position.x = content.size.x + DETAIL_MARGIN


func _sync_detail_geometry() -> void:
	if detail_panel == null or content == null:
		return
	# 面板宽度由场景中的最小尺寸与左右 offset 约束；这里只同步抽屉位置。
	if detail_panel.visible and (_detail_tween == null or not _detail_tween.is_valid()):
		detail_panel.position.x = content.size.x - DETAIL_WIDTH - DETAIL_MARGIN
	elif not detail_panel.visible:
		detail_panel.position.x = content.size.x + DETAIL_MARGIN


func _render_detail(activity: OutingActivity) -> void:
	var place: MapPlace = OutingManager.get_place(activity.place_id)
	detail_cover.texture = place.cover if place != null else null
	detail_kind.text = "外出计划"
	detail_title.text = activity.title
	detail_meta.text = "%s\n★ %.1f（%d 条点评）\n%s" % [
		place.display_name if place != null else activity.place_id,
		place.rating if place != null else 0.0,
		place.review_count if place != null else 0,
		place.district if place != null else "",
	]
	detail_description.text = activity.description
	solo_button.text = "一个人去  ·  %s" % ("免费" if activity.solo_cost <= 0 else "¥%d" % activity.solo_cost)
	date_button.text = "邀请好友  ·  %s" % ("免费" if activity.date_cost <= 0 else "¥%d" % activity.date_cost)
	var solo_availability: Dictionary = OutingManager.validate_action_availability(activity.activity_id, OutingManager.MODE_SOLO)
	var date_availability: Dictionary = OutingManager.validate_action_availability(activity.activity_id, OutingManager.MODE_DATE)
	_apply_action_availability(solo_button, solo_availability)
	_apply_action_availability(date_button, date_availability)
	_update_action_status(solo_availability, date_availability)


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


func _date_profile_text(_character: CharacterProfile) -> String:
	return "可以邀请一起参加这次外出"


func _on_retry_pressed() -> void:
	retry_button.disabled = true
	failure_error_label.text = "正在重新连接行程…"
	if not OutingManager.retry_failed_stage():
		retry_button.disabled = false
		failure_error_label.text = "这段行程暂时无法继续，请稍后再试。"


func _on_session_changed(snapshot: Dictionary) -> void:
	_update_failure_overlay(snapshot)
	var activity: OutingActivity = OutingManager.get_activity(_selected_activity_id)
	if activity != null:
		_render_detail(activity)


func _on_session_failed(stage: String, error: String, _snapshot: Dictionary) -> void:
	push_warning("CityHop outing interrupted at %s: %s" % [stage, error])
	failure_stage_label.text = _failure_title(stage)
	failure_error_label.text = _failure_message(stage)
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
		var failed_stage: String = str(snapshot.get("failed_stage", ""))
		failure_stage_label.text = _failure_title(failed_stage)
		failure_error_label.text = _failure_message(failed_stage)
		retry_button.disabled = false


func _show_local_error(title: String, error: String) -> void:
	status_label.text = "%s：%s" % [title, error]
	action_status_label.text = error
	action_status_panel.visible = true


func _apply_action_availability(button: Button, availability: Dictionary) -> void:
	var available: bool = bool(availability.get("ok", false))
	var reason: String = str(availability.get("reason", ""))
	button.disabled = not available
	button.tooltip_text = reason if not available else ""


func _update_action_status(solo_availability: Dictionary, date_availability: Dictionary) -> void:
	var solo_available: bool = bool(solo_availability.get("ok", false))
	var date_available: bool = bool(date_availability.get("ok", false))
	action_status_panel.visible = not solo_available or not date_available
	if solo_available and date_available:
		status_label.text = "当前可以出发"
		return
	var solo_reason: String = str(solo_availability.get("reason", ""))
	var date_reason: String = str(date_availability.get("reason", ""))
	if not solo_available and not date_available and solo_reason == date_reason:
		action_status_label.text = "暂不可用 · %s" % solo_reason
	elif not solo_available and not date_available:
		action_status_label.text = "一个人去：%s\n邀请好友：%s" % [solo_reason, date_reason]
	elif not solo_available:
		action_status_label.text = "一个人去：%s" % solo_reason
	else:
		action_status_label.text = "邀请好友：%s" % date_reason
	status_label.text = "详情中已说明当前限制"


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
		"invite": return "邀约暂时没有送达"
		"generation": return "行程准备没有完成"
		"avg": return "行程暂时中断"
		"feedback", "posts": return "返程动态暂时没有更新"
		"settlement": return "行程结算暂时没有完成"
	return "外出剧情中断"


func _failure_message(stage: String) -> String:
	match stage:
		"invite": return "这次邀约的结果已经保留，可以从这里继续。"
		"feedback", "posts": return "本次外出已经保留，可以重新连接返程动态。"
		"settlement": return "本次外出已经结束，但账目还没有同步完成。"
	return "本次行程和判定结果已经保留，可以重新连接后继续。"


func _format_number(value: int) -> String:
	var source: String = str(absi(value))
	var groups: Array[String] = []
	while source.length() > 3:
		groups.push_front(source.right(3))
		source = source.left(source.length() - 3)
	groups.push_front(source)
	return ("-" if value < 0 else "") + ",".join(groups)
