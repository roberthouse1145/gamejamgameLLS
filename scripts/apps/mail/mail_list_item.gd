class_name MailListItem extends Button
## 收件箱中的单封邮件条目，只呈现 MailManager 提供的数据。

signal open_requested(mail_id: String)

@onready var unread_badge: Label = %UnreadBadge
@onready var sender_label: Label = %SenderLabel
@onready var date_label: Label = %DateLabel
@onready var subject_label: Label = %SubjectLabel
@onready var preview_label: Label = %PreviewLabel

var _mail_id: String = ""
var _pending_mail: Dictionary = {}
var _pending_date_text: String = ""


func _ready() -> void:
	pressed.connect(_on_pressed)
	_apply_configuration()


func configure(mail: Dictionary, date_text: String) -> void:
	_pending_mail = mail.duplicate(true)
	_pending_date_text = date_text
	_mail_id = str(_pending_mail.get("mail_id", ""))
	if is_node_ready():
		_apply_configuration()


func _apply_configuration() -> void:
	if _pending_mail.is_empty():
		return
	var is_read: bool = bool(_pending_mail.get("is_read", false))
	unread_badge.visible = not is_read
	sender_label.text = str(_pending_mail.get("sender_name", ""))
	sender_label.add_theme_color_override(
		"font_color",
		Color("#20283A") if not is_read else Color("#58657A")
	)
	date_label.text = _pending_date_text
	subject_label.text = str(_pending_mail.get("subject", ""))
	subject_label.add_theme_color_override(
		"font_color",
		Color("#20283A") if not is_read else Color("#4F5D72")
	)
	preview_label.text = str(_pending_mail.get("body", ""))


func set_mail_selected(is_selected: bool) -> void:
	set_pressed_no_signal(is_selected)


func _on_pressed() -> void:
	if not _mail_id.is_empty():
		open_requested.emit(_mail_id)
