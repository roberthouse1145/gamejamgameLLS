class_name BrowserHomePage extends Control
## Browser 的新标签页：首页场景只承载搜索和已注册 Web 快捷入口。

signal search_requested(query: String)
signal url_requested(url: String)

const SHORTCUT_SCENE: PackedScene = preload("res://scenes/apps/browser/browser_home_shortcut.tscn")

@onready var search_input: LineEdit = %SearchInput
@onready var shortcut_row: HBoxContainer = %ShortcutRow
@onready var empty_label: Label = %EmptyLabel


func _ready() -> void:
	search_input.text_submitted.connect(_on_search_submitted)
	_connect_app_manager()
	_refresh_shortcuts()
	search_input.grab_focus.call_deferred()


func _connect_app_manager() -> void:
	var app_manager: Node = get_node_or_null("/root/AppManager")
	if app_manager == null:
		return
	_connect_manager_signal(app_manager, "app_registered", "_on_app_registered")
	_connect_manager_signal(app_manager, "app_unregistered", "_on_app_unregistered")
	_connect_manager_signal(app_manager, "app_access_changed", "_on_app_access_changed")


func _connect_manager_signal(app_manager: Node, signal_name: String, method_name: String) -> void:
	if not app_manager.has_signal(signal_name):
		return
	var callback := Callable(self, method_name)
	if not app_manager.is_connected(signal_name, callback):
		app_manager.connect(signal_name, callback)


func _refresh_shortcuts() -> void:
	for child: Node in shortcut_row.get_children():
		child.queue_free()

	var entries: Array[Dictionary] = []
	var app_manager: Node = get_node_or_null("/root/AppManager")
	if app_manager != null and app_manager.has_method("get_registered_apps"):
		var registered_apps: Variant = app_manager.call("get_registered_apps")
		if registered_apps is Array:
			for app_value: Variant in registered_apps:
				if not app_value is AppDefinition:
					continue
				var app_definition: AppDefinition = app_value as AppDefinition
				var launch_url: String = app_definition.launch_url.strip_edges()
				if launch_url.is_empty():
					continue
				if app_manager.has_method("is_app_accessible") \
					and not bool(app_manager.call("is_app_accessible", app_definition.app_id)):
					continue
				entries.append({
					"app_id": app_definition.app_id,
					"title": app_definition.app_name,
					"url": launch_url,
					"icon": app_definition.icon,
				})

	entries.sort_custom(_shortcut_before)
	for entry: Dictionary in entries:
		_add_shortcut(entry)
	empty_label.visible = entries.is_empty()


func _add_shortcut(entry: Dictionary) -> void:
	var button: Button = SHORTCUT_SCENE.instantiate() as Button
	if button == null:
		return
	var icon_rect: TextureRect = button.get_node("Body/Column/IconCenter/IconSurface/IconMargin/Icon") as TextureRect
	var title_label: Label = button.get_node("Body/Column/Title") as Label
	var title: String = str(entry.get("title", ""))
	var url: String = str(entry.get("url", ""))
	if icon_rect != null:
		icon_rect.texture = entry.get("icon") as Texture2D
	if title_label != null:
		title_label.text = title
	button.tooltip_text = "%s\n%s" % [title, url]
	button.pressed.connect(_on_shortcut_pressed.bind(url))
	shortcut_row.add_child(button)


func _shortcut_before(left: Dictionary, right: Dictionary) -> bool:
	var left_id: String = str(left.get("app_id", ""))
	var right_id: String = str(right.get("app_id", ""))
	if left_id == "linkposta":
		return right_id != "linkposta"
	if right_id == "linkposta":
		return false
	return str(left.get("title", "")).naturalnocasecmp_to(str(right.get("title", ""))) < 0


func _on_search_submitted(value: String) -> void:
	var query: String = value.strip_edges()
	if query.is_empty():
		return
	search_requested.emit(query)


func _on_shortcut_pressed(url: String) -> void:
	if not url.is_empty():
		url_requested.emit(url)


func _on_app_registered(_app_id: String, _definition: Resource) -> void:
	_refresh_shortcuts()


func _on_app_unregistered(_app_id: String) -> void:
	_refresh_shortcuts()


func _on_app_access_changed(_mode: String, _apps: Array[String]) -> void:
	_refresh_shortcuts()
