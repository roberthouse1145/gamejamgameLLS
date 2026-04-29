class_name DesktopNotificationUtils
extends RefCounted


static func show_system_notification(
		title: String,
		body: String,
		icon_token: String = "info",
		duration: float = 4.0,
		play_sound: bool = true) -> void:
	var safe_title := title.strip_edges()
	var safe_body := body.strip_edges()
	if safe_title.is_empty() and safe_body.is_empty():
		return
	if safe_title.is_empty():
		safe_title = "提示"

	var desktop := Desktop.instance()
	if desktop == null:
		return

	desktop.show_system_notification(safe_title, safe_body, icon_token, duration)

	if not play_sound:
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	var audio := tree.root.get_node_or_null("AudioManager")
	if audio != null and audio.has_method("play_sfx_key"):
		audio.play_sfx_key("sys_notify")


static func show_hint(
		title: String,
		body: String,
		icon_token: String = "info",
		duration: float = 4.0) -> void:
	show_system_notification(title, body, icon_token, duration, true)
