extends Control
## 手动测试入口：直接注入 Day1 企划卡任务并打开 Dev Work。

const WindowManagerClass = preload("res://scripts/pseudo_os/window_manager.gd")

var _wm: Node = null
var _original_window_manager: Node = null
var _window_container: Control = null
var _status: Label = null


func _ready() -> void:
	_build_ui()
	_ensure_window_manager()
	call_deferred("_prepare")


func _exit_tree() -> void:
	var am: Node = get_node_or_null("/root/AppManager")
	if am != null and am.has_method("set_window_manager") and am.get("window_manager") == _wm:
		am.set_window_manager(_original_window_manager)


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color("#101827")
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	var header := Label.new()
	header.text = "Day1 企划卡 Dev Work 快测"
	header.add_theme_font_size_override("font_size", 28)
	header.add_theme_color_override("font_color", Color("#e2e8f0"))
	root.add_child(header)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.text = "准备中..."
	_status.add_theme_font_size_override("font_size", 18)
	_status.add_theme_color_override("font_color", Color("#cbd5e1"))
	root.add_child(_status)

	_window_container = Control.new()
	_window_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_window_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(_window_container)


func _ensure_window_manager() -> void:
	_wm = WindowManagerClass.new()
	_wm.name = "WindowManager"
	add_child(_wm)
	_wm.set_window_container(_window_container)

	var am: Node = get_node_or_null("/root/AppManager")
	if am == null:
		_set_status("AppManager 不可用。")
		return
	_original_window_manager = am.get("window_manager")
	if am.has_method("set_window_manager"):
		am.set_window_manager(_wm)
	else:
		am.window_manager = _wm


func _prepare() -> void:
	_reset_runtime_state()
	var task: Dictionary = _load_task_template("res://resources/dev_work/story_tasks/day1_creative_brief.json")
	if task.is_empty():
		_set_status("读取 Day1 企划卡任务模板失败。")
		return

	var dcm: Node = get_node_or_null("/root/DevCycleManager")
	if dcm == null or not dcm.has_method("add_dynamic_task"):
		_set_status("DevCycleManager 不可用。")
		return

	var added_id: String = dcm.add_dynamic_task(task)
	if added_id.is_empty():
		_set_status("注入 Day1 企划卡任务失败。")
		return

	var am: Node = get_node_or_null("/root/AppManager")
	if am == null or not am.has_method("launch_app"):
		_set_status("AppManager 无法打开 Dev Work。")
		return
	var window: Control = am.launch_app("dev_work", true)
	if window == null:
		_set_status("Dev Work 打开失败。")
		return

	_set_status("已打开 Dev Work。点击「AGJ 2027 · 第一版企划卡」即可进入 structured_form。")


func _reset_runtime_state() -> void:
	var dcm: Node = get_node_or_null("/root/DevCycleManager")
	if dcm != null and dcm.has_method("reset_runtime_state"):
		dcm.reset_runtime_state()
	var wom: Node = get_node_or_null("/root/WorkOrderManager")
	if wom != null and wom.has_method("reset_runtime_state"):
		wom.reset_runtime_state()
	var am: Node = get_node_or_null("/root/AppManager")
	if am != null and am.has_method("clear_app_access_restriction"):
		am.clear_app_access_restriction()


func _load_task_template(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		return (parsed as Dictionary).duplicate(true)
	return {}


func _set_status(text: String) -> void:
	if _status != null:
		_status.text = text
	print("[TestDay1BriefDevWork] %s" % text)
