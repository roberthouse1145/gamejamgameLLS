extends MarginContainer

@onready var title_label: Label = $Root/TitleLabel
@onready var url_label: Label = $Root/UrlLabel
@onready var status_label: Label = $Root/StatusLabel

var _browser_app: Node = null
var _page_payload: Dictionary = {}


func configure_browser_page(browser_app: Node, page_payload: Dictionary) -> void:
	_browser_app = browser_app
	_page_payload = page_payload.duplicate(true)
	if title_label != null:
		title_label.text = str(page_payload.get("title", "Browser Scene Demo"))
	if url_label != null:
		url_label.text = str(page_payload.get("page_url", ""))


func _on_ping_button_pressed() -> void:
	status_label.text = "这个页面是预制场景，按钮逻辑直接写在 scene 脚本里。"
	if _browser_app != null and _browser_app.has_method("_set_status"):
		_browser_app.call("_set_status", "场景页按钮已触发")


func _on_home_button_pressed() -> void:
	status_label.text = "已请求返回首页。"
	if _browser_app != null and _browser_app.has_method("_on_page_action"):
		_browser_app.call("_on_page_action", {"action": "go_home"})
