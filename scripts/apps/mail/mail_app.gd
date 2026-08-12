class_name MailApp extends Control
## 轻量叙事邮件阅读器：收件箱、未读状态与正文阅读。

const MailListItemScene: PackedScene = preload("res://scenes/apps/mail/mail_list_item.tscn")

@onready var unread_status: Label = %UnreadStatus
@onready var message_count: Label = %MessageCount
@onready var mail_list: VBoxContainer = %MailList
@onready var reader_empty: CenterContainer = %ReaderEmpty
@onready var empty_title: Label = %EmptyTitle
@onready var empty_hint: Label = %EmptyHint
@onready var reader_scroll: ScrollContainer = %ReaderScroll
@onready var subject_label: Label = %SubjectLabel
@onready var sender_label: Label = %SenderLabel
@onready var address_label: Label = %AddressLabel
@onready var received_label: Label = %ReceivedLabel
@onready var body_label: Label = %BodyLabel

var _manager: Node = null
var _selected_mail_id: String = ""


func _ready() -> void:
	_manager = get_node_or_null("/root/MailManager")
	if _manager != null:
		if not _manager.mail_received.is_connected(_on_mail_received):
			_manager.mail_received.connect(_on_mail_received)
		if not _manager.mail_read_changed.is_connected(_on_mail_read_changed):
			_manager.mail_read_changed.connect(_on_mail_read_changed)
		if not _manager.mailbox_reloaded.is_connected(_refresh):
			_manager.mailbox_reloaded.connect(_refresh)
	_refresh()


func _refresh() -> void:
	for child: Node in mail_list.get_children():
		mail_list.remove_child(child)
		child.queue_free()

	var messages: Array[Dictionary] = []
	if _manager != null:
		var raw_messages: Variant = _manager.call("get_messages")
		if raw_messages is Array:
			messages.assign(raw_messages)
	var selected_mail: Dictionary = {}
	for mail: Dictionary in messages:
		var item := MailListItemScene.instantiate() as MailListItem
		item.configure(mail, _format_received_time(mail))
		item.set_mail_selected(str(mail.get("mail_id", "")) == _selected_mail_id)
		item.open_requested.connect(_open_mail)
		mail_list.add_child(item)
		if str(mail.get("mail_id", "")) == _selected_mail_id:
			selected_mail = mail

	message_count.text = "%d 封" % messages.size()
	var unread_count: int = int(_manager.call("get_unread_count")) if _manager != null else 0
	unread_status.text = "暂无未读" if unread_count == 0 else "%d 封未读" % unread_count
	empty_title.text = "还没有收到邮件" if messages.is_empty() else "选择一封邮件"
	empty_hint.text = "新的来信会显示在收件箱中" if messages.is_empty() else "来信内容会显示在这里"

	if not selected_mail.is_empty():
		_display_mail(selected_mail)
	elif not _selected_mail_id.is_empty():
		_selected_mail_id = ""
		_show_empty_reader()
	else:
		_show_empty_reader()


func _open_mail(mail_id: String) -> void:
	if _manager == null:
		return
	_selected_mail_id = mail_id
	_manager.call("mark_read", mail_id, true)
	var mail: Dictionary = _manager.call("get_mail", mail_id)
	if not mail.is_empty():
		_display_mail(mail)
	_refresh()


func _display_mail(mail: Dictionary) -> void:
	reader_empty.visible = false
	reader_scroll.visible = true
	subject_label.text = str(mail.get("subject", ""))
	sender_label.text = str(mail.get("sender_name", ""))
	var sender_address: String = str(mail.get("sender_address", "")).strip_edges()
	address_label.visible = not sender_address.is_empty()
	address_label.text = sender_address
	received_label.text = _format_received_time(mail)
	body_label.text = str(mail.get("body", ""))
	reader_scroll.scroll_vertical = 0


func _show_empty_reader() -> void:
	reader_empty.visible = true
	reader_scroll.visible = false


func _format_received_time(mail: Dictionary) -> String:
	var authored_time: String = str(mail.get("sent_at", "")).strip_edges()
	if not authored_time.is_empty():
		return authored_time
	var time_slot_text: String = "上午"
	match int(mail.get("received_time_slot", 0)):
		1:
			time_slot_text = "下午"
		2:
			time_slot_text = "晚上"
	return "第%d天 · %s" % [int(mail.get("received_game_day", 1)), time_slot_text]


func _on_mail_received(_mail: Dictionary) -> void:
	_refresh()


func _on_mail_read_changed(_mail_id: String, _is_read: bool) -> void:
	_refresh()
