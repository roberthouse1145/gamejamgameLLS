class_name LinkPostaReplyItem extends HBoxContainer
## 帖子回复层中的一条真实回复预览。

@onready var avatar: RoundedAvatar = %Avatar
@onready var depth_spacer: Control = %DepthSpacer
@onready var name_label: Label = %NameLabel
@onready var handle_label: Label = %HandleLabel
@onready var time_label: Label = %TimeLabel
@onready var reply_context_label: Label = %ReplyContextLabel
@onready var reply_body: Label = %ReplyBody

var _reply: Dictionary = {}


func _ready() -> void:
	_apply_reply()


func configure(reply: Dictionary) -> void:
	_reply = reply.duplicate(true)
	if is_node_ready():
		_apply_reply()


func _apply_reply() -> void:
	if _reply.is_empty():
		return
	var display_name: String = str(_reply.get("display_name", "未知账号"))
	var avatar_value: Variant = _reply.get("avatar")
	avatar.set_avatar(avatar_value as Texture2D if avatar_value is Texture2D else null, display_name)
	name_label.text = display_name
	handle_label.text = str(_reply.get("handle", ""))
	time_label.text = str(_reply.get("time", ""))
	var depth: int = clampi(int(_reply.get("depth", 0)), 0, 2)
	depth_spacer.custom_minimum_size.x = depth * 64.0
	depth_spacer.visible = depth > 0
	var reply_to_handle: String = str(_reply.get("reply_to_handle", "")).strip_edges()
	var reply_to_name: String = str(_reply.get("reply_to_display_name", "")).strip_edges()
	reply_context_label.visible = not reply_to_handle.is_empty() or not reply_to_name.is_empty()
	reply_context_label.text = "回复 %s" % (
		reply_to_handle if not reply_to_handle.is_empty() else reply_to_name
	)
	reply_body.text = str(_reply.get("content", ""))
