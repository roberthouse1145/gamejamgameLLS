extends Control
## Template 项目编辑器 · Test Lab
##
## 把 res://templates/tutorial_project/ 作为活动项目，然后在同一屏幕里挂出
## 四个已有编辑器 App 作为可切换的 tab：
##   - 项目管理器 (project_manager)
##   - 场景编辑器 (scene_editor)
##   - 知识库 (knowledge_base_app)
##   - 游戏预览 (game_previewer)
##
## 保存按钮会调用 StorageManager.save_project_to_path 直接把 project + 子资源
## 写回 res://templates/tutorial_project/，避开正常 user:// 保存路径。
##
## 仅限编辑器 + developer_mode。运行时 build 里这个场景不应该出现。

const TEMPLATE_PATH: String = "res://templates/tutorial_project/"

const TAB_DEFS: Array[Dictionary] = [
	{"id": "project_manager", "label": "项目管理器", "scene": "res://scenes/apps/project_manager/project_manager.tscn"},
	{"id": "scene_editor", "label": "场景编辑器", "scene": "res://scenes/apps/scene_editor/scene_editor.tscn"},
	{"id": "knowledge_base", "label": "知识库", "scene": "res://scenes/apps/knowledge_base/knowledge_base_app.tscn"},
	{"id": "game_previewer", "label": "游戏预览", "scene": "res://scenes/apps/game_previewer/game_previewer.tscn"},
]

var _tab_buttons: Dictionary = {}
var _tab_instances: Dictionary = {}
var _current_tab_id: String = ""

@onready var _tab_bar: HBoxContainer = %TabBar
@onready var _content_host: Control = %ContentHost
@onready var _status_label: Label = %StatusLabel
@onready var _save_button: Button = %SaveButton
@onready var _reload_button: Button = %ReloadButton


func _ready() -> void:
	if not OS.has_feature("editor"):
		_set_status("当前不是编辑器运行环境，Template Lab 只允许在编辑器里用。", true)
		_save_button.disabled = true
		_reload_button.disabled = true

	# 关键：开启 template 编辑模式，让所有 StorageManager 的 save/ensure_writable_project_root
	# 保留 res:// 根，不再物化到 user://。退出时必须关回去。
	if "template_edit_mode" in StorageManager:
		StorageManager.template_edit_mode = true

	_save_button.pressed.connect(_on_save_pressed)
	_reload_button.pressed.connect(_on_reload_pressed)

	_build_tab_buttons()
	_load_template_project()

	if not TAB_DEFS.is_empty():
		_switch_to_tab(str(TAB_DEFS[0].get("id", "")))


func _exit_tree() -> void:
	# 关闭 template 编辑模式，避免影响主游戏流程。
	if "template_edit_mode" in StorageManager:
		StorageManager.template_edit_mode = false


func _build_tab_buttons() -> void:
	for def in TAB_DEFS:
		var btn := Button.new()
		btn.text = str(def.get("label", def.get("id", "")))
		btn.toggle_mode = true
		btn.focus_mode = Control.FOCUS_NONE
		var tab_id: String = str(def.get("id", ""))
		btn.pressed.connect(_switch_to_tab.bind(tab_id))
		_tab_bar.add_child(btn)
		_tab_buttons[tab_id] = btn


func _load_template_project() -> void:
	var project: Resource = StorageManager.load_project(TEMPLATE_PATH)
	if project == null:
		_set_status("加载模板项目失败：%s" % TEMPLATE_PATH, true)
		return
	StorageManager.set_current_project(project)
	# load_project 内部已经把 current_project_path 设成了 TEMPLATE_PATH
	_set_status("已加载模板项目：%s" % str(project.get("project_name") if "project_name" in project else TEMPLATE_PATH), false)


func _switch_to_tab(tab_id: String) -> void:
	if tab_id.is_empty() or tab_id == _current_tab_id:
		_sync_tab_buttons()
		return

	# 隐藏旧 tab
	if _current_tab_id in _tab_instances:
		var prev: Control = _tab_instances[_current_tab_id]
		if is_instance_valid(prev):
			prev.visible = false

	# 懒加载实例
	if not _tab_instances.has(tab_id):
		var scene_path: String = _get_tab_scene_path(tab_id)
		if scene_path.is_empty():
			push_warning("[TestLab] Unknown tab id: %s" % tab_id)
			return
		var packed: PackedScene = load(scene_path)
		if packed == null:
			_set_status("加载 %s 场景失败：%s" % [tab_id, scene_path], true)
			return
		var instance: Node = packed.instantiate()
		if not instance is Control:
			push_warning("[TestLab] %s root is not a Control" % tab_id)
			if instance != null:
				instance.queue_free()
			return
		var ctrl := instance as Control
		ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
		_content_host.add_child(ctrl)
		_tab_instances[tab_id] = ctrl

	var target: Control = _tab_instances[tab_id]
	target.visible = true
	_current_tab_id = tab_id
	_sync_tab_buttons()


func _sync_tab_buttons() -> void:
	for id_key in _tab_buttons.keys():
		var btn: Button = _tab_buttons[id_key]
		btn.button_pressed = (str(id_key) == _current_tab_id)


func _get_tab_scene_path(tab_id: String) -> String:
	for def in TAB_DEFS:
		if str(def.get("id", "")) == tab_id:
			return str(def.get("scene", ""))
	return ""


func _on_save_pressed() -> void:
	var project: Resource = StorageManager.current_project
	if project == null:
		_set_status("没有活动项目，无法保存。", true)
		return
	var err: Error = StorageManager.save_project_to_path(project, TEMPLATE_PATH)
	if err == OK:
		_set_status("已保存到 %s" % TEMPLATE_PATH, false)
	else:
		_set_status("保存失败：%s" % error_string(err), true)


func _on_reload_pressed() -> void:
	# 丢弃当前 tab 实例，重新加载项目并重建活动 tab。
	var remembered: String = _current_tab_id
	for tab_id in _tab_instances.keys():
		var inst: Control = _tab_instances[tab_id]
		if is_instance_valid(inst):
			inst.queue_free()
	_tab_instances.clear()
	_current_tab_id = ""
	_load_template_project()
	if not remembered.is_empty():
		_switch_to_tab(remembered)
	elif not TAB_DEFS.is_empty():
		_switch_to_tab(str(TAB_DEFS[0].get("id", "")))


func _set_status(text: String, is_error: bool) -> void:
	_status_label.text = text
	_status_label.modulate = Color(1.0, 0.55, 0.55) if is_error else Color(0.75, 0.9, 0.75)
