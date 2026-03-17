class_name SceneSelectorDialog extends Window
## 通用场景选择器弹窗
## 左侧：场景列表（显示 scene_name + scene_id）
## 右侧：选中场景的信息预览（背景缩略图、命令数、节点数等）
## 用途：标题设置选择初始场景、JUMP_SCENE 命令选择目标场景等

## 选择确认（返回 scene_id）
signal scene_confirmed(scene_id: String)
## 取消选择
signal cancelled()

# =============================================================================
# State
# =============================================================================

var _project: Resource = null  # AVGProject
var _selected_index: int = -1
var _selected_scene_id: String = ""

# =============================================================================
# 动态创建的 UI 节点
# =============================================================================

var _main_container: HSplitContainer = null
var _scene_list: ItemList = null
var _info_panel: VBoxContainer = null
var _preview_texture: TextureRect = null
var _info_name_label: Label = null
var _info_id_label: Label = null
var _info_nodes_label: Label = null
var _info_commands_label: Label = null
var _info_local_vars_label: Label = null
var _confirm_button: Button = null
var _cancel_button: Button = null


# =============================================================================
# Lifecycle
# =============================================================================

func _ready() -> void:
	title = "选择场景"
	size = Vector2i(700, 450)
	exclusive = true
	unresizable = false
	min_size = Vector2i(500, 300)
	_build_ui()
	close_requested.connect(_on_cancel)


# =============================================================================
# Public API
# =============================================================================

## 打开选择器，传入项目和可选的预选 scene_id
func open(project: Resource, preselect_scene_id: String = "") -> void:
	_project = project
	_selected_scene_id = preselect_scene_id
	_selected_index = -1
	_populate_list()
	_update_info()
	popup_centered()


## 静态便捷方法：创建并弹出选择器
## 调用方 await scene_confirmed 信号获取结果
static func popup_selector(parent: Node, project: Resource, preselect_scene_id: String = "") -> Window:
	var SelfClass: GDScript = load("res://scripts/editor/scene_selector_dialog.gd")
	var dialog: Window = SelfClass.new()
	parent.add_child(dialog)
	dialog.open(project, preselect_scene_id)
	return dialog


# =============================================================================
# UI Construction
# =============================================================================

func _build_ui() -> void:
	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", 8)
	root.add_theme_constant_override("margin_top", 8)
	root.add_theme_constant_override("margin_right", 8)
	root.add_theme_constant_override("margin_bottom", 8)
	add_child(root)

	var vbox := VBoxContainer.new()
	root.add_child(vbox)

	# ---- 主体：左右分栏 ----
	_main_container = HSplitContainer.new()
	_main_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_main_container.split_offset = 280
	vbox.add_child(_main_container)

	# 左侧：场景列表
	var left_panel := VBoxContainer.new()
	left_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_main_container.add_child(left_panel)

	var list_title := Label.new()
	list_title.text = "场景列表"
	list_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left_panel.add_child(list_title)

	_scene_list = ItemList.new()
	_scene_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scene_list.item_selected.connect(_on_item_selected)
	_scene_list.item_activated.connect(_on_item_activated)
	left_panel.add_child(_scene_list)

	# 右侧：信息预览
	var right_panel := VBoxContainer.new()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.custom_minimum_size = Vector2(250, 0)
	_main_container.add_child(right_panel)

	var info_title := Label.new()
	info_title.text = "场景信息"
	info_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right_panel.add_child(info_title)

	# 背景缩略图
	_preview_texture = TextureRect.new()
	_preview_texture.custom_minimum_size = Vector2(0, 160)
	_preview_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview_texture.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.add_child(_preview_texture)

	var sep := HSeparator.new()
	right_panel.add_child(sep)

	# 信息标签
	_info_panel = VBoxContainer.new()
	_info_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_panel.add_child(_info_panel)

	_info_name_label = Label.new()
	_info_name_label.text = "名称: -"
	_info_panel.add_child(_info_name_label)

	_info_id_label = Label.new()
	_info_id_label.text = "ID: -"
	_info_panel.add_child(_info_id_label)

	_info_nodes_label = Label.new()
	_info_nodes_label.text = "节点数: -"
	_info_panel.add_child(_info_nodes_label)

	_info_commands_label = Label.new()
	_info_commands_label.text = "命令数: -"
	_info_panel.add_child(_info_commands_label)

	_info_local_vars_label = Label.new()
	_info_local_vars_label.text = "场景变量: -"
	_info_panel.add_child(_info_local_vars_label)

	# ---- 底部按钮栏 ----
	var btn_bar := HBoxContainer.new()
	btn_bar.alignment = BoxContainer.ALIGNMENT_END
	vbox.add_child(btn_bar)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_bar.add_child(spacer)

	_cancel_button = Button.new()
	_cancel_button.text = "取消"
	_cancel_button.custom_minimum_size = Vector2(80, 0)
	_cancel_button.pressed.connect(_on_cancel)
	btn_bar.add_child(_cancel_button)

	_confirm_button = Button.new()
	_confirm_button.text = "确认"
	_confirm_button.custom_minimum_size = Vector2(80, 0)
	_confirm_button.disabled = true
	_confirm_button.pressed.connect(_on_confirm)
	btn_bar.add_child(_confirm_button)


# =============================================================================
# List Population
# =============================================================================

func _populate_list() -> void:
	if _scene_list == null:
		return
	_scene_list.clear()
	_selected_index = -1

	if _project == null or _project.scenes == null:
		return

	for i in range(_project.scenes.size()):
		var scene = _project.scenes[i]
		if scene == null:
			continue
		var scene_name: String = scene.scene_name if "scene_name" in scene else "Unnamed"
		var scene_id: String = scene.scene_id if "scene_id" in scene else ""
		var display: String = "%d. %s" % [i, scene_name]
		if not scene_id.is_empty():
			display = "%d. %s (%s)" % [i, scene_name, scene_id]
		_scene_list.add_item(display)

		# 预选
		if not _selected_scene_id.is_empty() and scene_id == _selected_scene_id:
			_selected_index = i

	# 应用预选
	if _selected_index >= 0 and _selected_index < _scene_list.item_count:
		_scene_list.select(_selected_index)


# =============================================================================
# Info / Preview
# =============================================================================

func _update_info() -> void:
	var scene: Resource = _get_selected_scene()
	if scene == null:
		_clear_info()
		if _confirm_button:
			_confirm_button.disabled = true
		return

	if _confirm_button:
		_confirm_button.disabled = false

	var scene_name: String = scene.scene_name if "scene_name" in scene else ""
	var scene_id: String = scene.scene_id if "scene_id" in scene else ""

	if _info_name_label:
		_info_name_label.text = "名称: %s" % scene_name
	if _info_id_label:
		_info_id_label.text = "ID: %s" % scene_id

	# 统计节点数
	var node_count: int = _count_nodes(scene)
	if _info_nodes_label:
		_info_nodes_label.text = "节点数: %d" % node_count

	# 统计命令数
	var cmd_count: int = _count_commands(scene)
	if _info_commands_label:
		_info_commands_label.text = "命令数: %d" % cmd_count

	# 场景变量数
	var local_var_count: int = 0
	if "local_variables" in scene and scene.local_variables != null:
		local_var_count = scene.local_variables.size()
	if _info_local_vars_label:
		_info_local_vars_label.text = "场景变量: %d" % local_var_count

	# 背景缩略图
	_update_preview_texture(scene)


func _clear_info() -> void:
	if _info_name_label:
		_info_name_label.text = "名称: -"
	if _info_id_label:
		_info_id_label.text = "ID: -"
	if _info_nodes_label:
		_info_nodes_label.text = "节点数: -"
	if _info_commands_label:
		_info_commands_label.text = "命令数: -"
	if _info_local_vars_label:
		_info_local_vars_label.text = "场景变量: -"
	if _preview_texture:
		_preview_texture.texture = null


func _update_preview_texture(scene: Resource) -> void:
	if _preview_texture == null:
		return
	_preview_texture.texture = null
	if scene == null or not "nodes" in scene:
		return
	# 从 Root 节点获取背景
	for node in scene.nodes:
		if node is AVGRootNode and node.background != null:
			_preview_texture.texture = node.background
			return


func _count_nodes(scene: Resource) -> int:
	if scene == null or not "nodes" in scene:
		return 0
	var count: int = 0
	for node in scene.nodes:
		count += _count_nodes_recursive(node)
	return count


func _count_nodes_recursive(node: Resource) -> int:
	if node == null:
		return 0
	var count: int = 1
	if "children" in node:
		for child in node.children:
			count += _count_nodes_recursive(child)
	return count


func _count_commands(scene: Resource) -> int:
	if scene == null or not "nodes" in scene:
		return 0
	var count: int = 0
	for node in scene.nodes:
		count += _count_commands_recursive(node)
	return count


func _count_commands_recursive(node: Resource) -> int:
	if node == null:
		return 0
	var count: int = 0
	if "command_tabs" in node and node.command_tabs != null:
		for tab in node.command_tabs:
			var cmds: Array = tab.get("commands", [])
			count += cmds.size()
	if "children" in node:
		for child in node.children:
			count += _count_commands_recursive(child)
	return count


func _get_selected_scene() -> Resource:
	if _project == null or _selected_index < 0:
		return null
	if _selected_index >= _project.scenes.size():
		return null
	return _project.scenes[_selected_index]


# =============================================================================
# Callbacks
# =============================================================================

func _on_item_selected(index: int) -> void:
	_selected_index = index
	var scene: Resource = _get_selected_scene()
	if scene != null and "scene_id" in scene:
		_selected_scene_id = scene.scene_id
	_update_info()


func _on_item_activated(_index: int) -> void:
	_on_confirm()


func _on_confirm() -> void:
	if _selected_scene_id.is_empty() and _selected_index >= 0:
		var scene: Resource = _get_selected_scene()
		if scene != null and "scene_id" in scene:
			_selected_scene_id = scene.scene_id
	scene_confirmed.emit(_selected_scene_id)
	_cleanup()


func _on_cancel() -> void:
	cancelled.emit()
	_cleanup()


func _cleanup() -> void:
	hide()
	queue_free()
