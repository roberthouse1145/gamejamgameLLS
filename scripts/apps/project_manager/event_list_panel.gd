class_name EventListPanel extends VBoxContainer
## Event List Panel Component
## 槽位制公共事件列表 - 显示所有槽位（1~max），点击空槽创建，点击已有事件编辑
## event_id = "event_NNN" 由槽位号决定

signal event_selected(event: Resource)

const AVGEventClass = preload("res://scripts/avg/resources/avg_event.gd")

## 槽位数量上限
const DEFAULT_MAX_SLOTS: int = 100

var _project: Resource = null
## 当前选中的槽位号（1-based）
var _selected_slot: int = -1
var _max_slots: int = DEFAULT_MAX_SLOTS
var _current_command_index: int = -1
var _pending_add_meta: Dictionary = {}

const COMMAND_TYPES: Array = [
	{"id": "DIALOGUE", "name": "对话"},
	{"id": "SHOW_CHARACTER", "name": "显示角色"},
	{"id": "HIDE_CHARACTER", "name": "隐藏角色"},
	{"id": "STAGE_SET", "name": "舞台排位"},
	{"id": "STAGE_ENTER", "name": "舞台入场"},
	{"id": "STAGE_EXIT", "name": "舞台离场"},
	{"id": "WAIT_CLICK", "name": "等待点击"},
	{"id": "WAIT_TIME", "name": "等待时间"},
	{"id": "CHOICE", "name": "选项"},
	{"id": "LABEL", "name": "标签"},
	{"id": "JUMP_LABEL", "name": "跳转标签"},
	{"id": "JUMP_SCENE", "name": "跳转场景"},
	{"id": "SET_VARIABLE", "name": "设置变量"},
	{"id": "CALL_EVENT", "name": "调用事件"},
	{"id": "PLAY_BGM", "name": "播放BGM"},
	{"id": "STOP_BGM", "name": "停止BGM"},
	{"id": "PLAY_SFX", "name": "播放音效"},
	{"id": "CHANGE_BACKGROUND", "name": "切换背景"},
	{"id": "IF", "name": "条件分支"},
]

# UI - resolved in _ready
var clear_button: Button = null
var event_list: ItemList = null
var property_editor_container: VBoxContainer = null
var command_tree: Tree = null
var delete_command_button: Button = null
var add_command_dialog: Window = null
var command_button_grid: GridContainer = null

var _property_editor: Control = null


func _ready() -> void:
	_resolve_ui_references()
	_setup_connections()
	_setup_property_editor()
	_setup_command_buttons()


func _resolve_ui_references() -> void:
	clear_button = find_child("DeleteButton", true, false) as Button
	event_list = find_child("EventList", true, false) as ItemList
	property_editor_container = find_child("PropertyEditor", true, false) as VBoxContainer
	command_tree = find_child("CommandTree", true, false) as Tree
	delete_command_button = find_child("DeleteCommandButton", true, false) as Button
	add_command_dialog = find_child("AddCommandDialog", true, false) as Window
	command_button_grid = find_child("CommandButtonGrid", true, false) as GridContainer
	var cancel_btn: Button = find_child("CancelButton", true, false) as Button
	if cancel_btn:
		cancel_btn.pressed.connect(_on_add_command_dialog_closed)


func _setup_connections() -> void:
	if clear_button:
		clear_button.text = "清空"
		clear_button.pressed.connect(_on_clear_pressed)
	if event_list:
		event_list.item_selected.connect(_on_item_selected)
	if command_tree:
		command_tree.item_selected.connect(_on_command_tree_item_selected)
		command_tree.item_activated.connect(_on_command_tree_item_activated)
	if delete_command_button:
		delete_command_button.pressed.connect(_on_delete_command_pressed)
	if add_command_dialog:
		add_command_dialog.close_requested.connect(_on_add_command_dialog_closed)


func _setup_property_editor() -> void:
	if property_editor_container == null:
		return
	# Remove old children (e.g. old PropertyEditor script node from scene)
	for child in property_editor_container.get_children():
		child.queue_free()
	var PropertyEditorClass = load("res://scripts/editor/property_editor.gd")
	_property_editor = PropertyEditorClass.new()
	property_editor_container.add_child(_property_editor)
	_property_editor.property_changed.connect(_on_property_changed)


func _setup_command_buttons() -> void:
	if command_button_grid == null:
		return
	for child in command_button_grid.get_children():
		child.queue_free()
	for cmd_def in COMMAND_TYPES:
		var btn := Button.new()
		btn.text = cmd_def["name"]
		btn.custom_minimum_size = Vector2(100, 32)
		btn.pressed.connect(_on_command_type_button_pressed.bind(cmd_def["id"]))
		command_button_grid.add_child(btn)


# ============ Project / List ============

func set_project(project: Resource) -> void:
	_project = project
	_selected_slot = -1
	_refresh_list()
	_clear_editors()


## 根据槽位号获取事件
func get_event_by_slot(slot: int) -> Resource:
	if _project == null:
		return null
	var evt_id: String = AVGEventClass.make_id(slot)
	for e in _project.events:
		if e.event_id == evt_id:
			return e
	return null


func get_selected_event() -> Resource:
	if _selected_slot < 1:
		return null
	return get_event_by_slot(_selected_slot)


func _refresh_list() -> void:
	if event_list == null:
		return
	event_list.clear()
	if _project == null:
		_update_button_states()
		return
	
	for slot in range(1, _max_slots + 1):
		var evt_id: String = AVGEventClass.make_id(slot)
		var event: Resource = get_event_by_slot(slot)
		
		var display_text: String
		if event != null:
			var cmd_count: int = event.commands.size()
			display_text = "%s: %s [%d]" % [evt_id, event.event_name, cmd_count]
		else:
			display_text = "%s: (空)" % evt_id
		
		event_list.add_item(display_text)
		
		if event == null:
			event_list.set_item_custom_fg_color(slot - 1, Color(0.5, 0.5, 0.5))
	
	if _selected_slot >= 1 and _selected_slot <= _max_slots:
		event_list.select(_selected_slot - 1)
	_update_button_states()


func _update_button_states() -> void:
	var has_event: bool = get_selected_event() != null
	if clear_button:
		clear_button.disabled = not has_event
	if delete_command_button:
		delete_command_button.disabled = not has_event


func _clear_editors() -> void:
	if _property_editor and _property_editor.has_method("set_target"):
		_property_editor.set_target(null)
	_refresh_command_list()


func _on_item_selected(index: int) -> void:
	_selected_slot = index + 1
	
	var event: Resource = get_selected_event()
	
	if event == null:
		_create_event_at_slot(_selected_slot)
		event = get_selected_event()
	
	if event:
		if _property_editor and _property_editor.has_method("set_target"):
			_property_editor.set_target(event)
		event_selected.emit(event)
	
	_update_button_states()
	_refresh_command_list()


## 在指定槽位创建事件
func _create_event_at_slot(slot: int) -> void:
	if _project == null:
		return
	
	var new_event: Resource = AVGEventClass.new()
	new_event.event_id = AVGEventClass.make_id(slot)
	new_event.event_name = "事件%03d" % slot
	new_event.commands = []
	
	_project.events.append(new_event)
	_refresh_list()
	
	if event_list and slot >= 1 and slot <= _max_slots:
		event_list.select(slot - 1)
	
	StorageManager.notify_content_changed()


## 清空当前槽位
func _on_clear_pressed() -> void:
	if _project == null or _selected_slot < 1:
		return
	
	var event: Resource = get_selected_event()
	if event == null:
		return
	
	var idx: int = _project.events.find(event)
	if idx >= 0:
		_project.events.remove_at(idx)
	
	_refresh_list()
	_clear_editors()
	_update_button_states()
	StorageManager.notify_content_changed()


func _on_property_changed(_prop_name: String, _old_value: Variant, _new_value: Variant) -> void:
	_refresh_list()
	if _selected_slot >= 1 and _selected_slot <= _max_slots:
		event_list.select(_selected_slot - 1)
	StorageManager.notify_content_changed()


# ============ Command Tree (same logic as SceneEditor) ============

func _refresh_command_list() -> void:
	if command_tree == null:
		return
	command_tree.clear()
	_current_command_index = -1
	var tree_root: TreeItem = command_tree.create_item()
	var event: Resource = get_selected_event()
	if event == null:
		return
	var commands: Array = event.commands
	_build_command_tree(tree_root, commands, "")
	_add_empty_item(tree_root, commands.size(), "")


func _build_command_tree(parent: TreeItem, commands: Array, prefix: String) -> void:
	for i in range(commands.size()):
		var cmd = commands[i]
		var cmd_type: String
		if cmd is Dictionary:
			cmd_type = cmd.get("command_type", "unknown")
		elif cmd != null:
			cmd_type = cmd.command_type
		else:
			cmd_type = "unknown"
		var index_str: String = "%d" % (i + 1) if prefix.is_empty() else "%s.%d" % [prefix, i + 1]
		if cmd_type == "IF":
			_build_if_block(parent, cmd, i, index_str)
		else:
			var item: TreeItem = command_tree.create_item(parent)
			item.set_text(0, "%s. %s" % [index_str, _get_command_display(cmd)])
			item.set_metadata(0, {"type": "command", "index": i, "path": prefix})


func _build_if_block(parent: TreeItem, cmd: Resource, index: int, index_str: String) -> void:
	var condition: String = cmd.params.get("condition", "")
	var if_item: TreeItem = command_tree.create_item(parent)
	if_item.set_text(0, "%s. 如果 [%s]" % [index_str, condition])
	if_item.set_metadata(0, {"type": "IF", "index": index, "path": ""})
	var if_commands: Array = cmd.params.get("if_commands", [])
	_build_command_tree(if_item, if_commands, index_str)
	_add_empty_item(if_item, if_commands.size(), index_str)
	if cmd.params.get("has_else", false):
		var else_label: TreeItem = command_tree.create_item(if_item)
		else_label.set_text(0, "[否则]")
		else_label.set_metadata(0, {"type": "else_label", "index": index, "path": ""})
		else_label.set_selectable(0, false)
		else_label.set_custom_color(0, Color(0.7, 0.7, 0.5))
		var else_commands: Array = cmd.params.get("else_commands", [])
		for j in range(else_commands.size()):
			var else_cmd = else_commands[j]
			var else_cmd_type: String
			if else_cmd is Dictionary:
				else_cmd_type = else_cmd.get("command_type", "unknown")
			elif else_cmd != null:
				else_cmd_type = else_cmd.command_type
			else:
				else_cmd_type = "unknown"
			var else_index_str: String = "%s.%d" % [index_str, if_commands.size() + j + 1]
			if else_cmd_type == "IF":
				_build_if_block(if_item, else_cmd, j, else_index_str)
			else:
				var item: TreeItem = command_tree.create_item(if_item)
				item.set_text(0, "%s. %s" % [else_index_str, _get_command_display(else_cmd)])
				item.set_metadata(0, {"type": "command", "index": j, "path": index_str + "_else"})
		_add_empty_item(if_item, if_commands.size() + else_commands.size(), index_str + "_else")


func _add_empty_item(parent: TreeItem, index: int, prefix: String) -> void:
	var item: TreeItem = command_tree.create_item(parent)
	item.set_text(0, "[空白 - 双击添加]")
	item.set_metadata(0, {"type": "empty", "index": index, "path": prefix})
	item.set_custom_color(0, Color(0.5, 0.5, 0.5))


func _get_command_display(cmd: Variant) -> String:
	if cmd == null:
		return "unknown"
	var p: Dictionary
	var cmd_type: String
	if cmd is Dictionary:
		cmd_type = cmd.get("command_type", "unknown")
		p = cmd.get("params", {})
	else:
		cmd_type = cmd.command_type
		p = cmd.params
	match cmd_type:
		"DIALOGUE":
			var t: String = p.get("text", "")
			if t.length() > 15: t = t.substr(0, 15) + "..."
			var s: String = p.get("speaker", "")
			if s.is_empty():
				return "旁白 \"%s\"" % t
			return "对话 %s: \"%s\"" % [s, t]
		"SHOW_CHARACTER": return "显示角色 %s" % p.get("character_id", "")
		"HIDE_CHARACTER": return "隐藏角色 %s" % p.get("character_id", "")
		"STAGE_SET":
			var raw_stage_characters: Variant = p.get("characters", [])
			var stage_characters: Array[String] = []
			if raw_stage_characters is Array:
				for entry in raw_stage_characters:
					var trimmed: String = str(entry).strip_edges()
					if trimmed.is_empty():
						continue
					stage_characters.append(trimmed)
			if stage_characters.is_empty():
				var characters_csv: String = str(p.get("characters_csv", "")).strip_edges()
				if not characters_csv.is_empty():
					for entry in characters_csv.split(","):
						var trimmed_csv: String = entry.strip_edges()
						if trimmed_csv.is_empty():
							continue
						stage_characters.append(trimmed_csv)
			if stage_characters.is_empty():
				return "舞台清场"
			return "舞台排位 [%s]" % " / ".join(PackedStringArray(stage_characters))
		"STAGE_ENTER":
			var stage_enter_characters: Array[String] = []
			var raw_stage_enter_characters: Variant = p.get("characters", [])
			if raw_stage_enter_characters is Array:
				for entry in raw_stage_enter_characters:
					var trimmed: String = str(entry).strip_edges()
					if trimmed.is_empty():
						continue
					stage_enter_characters.append(trimmed)
			if stage_enter_characters.is_empty():
				for entry in str(p.get("characters_csv", "")).split(","):
					var trimmed_csv: String = entry.strip_edges()
					if trimmed_csv.is_empty():
						continue
					stage_enter_characters.append(trimmed_csv)
			return "舞台入场 [%s]" % " / ".join(PackedStringArray(stage_enter_characters))
		"STAGE_EXIT":
			var stage_exit_characters: Array[String] = []
			var raw_stage_exit_characters: Variant = p.get("characters", [])
			if raw_stage_exit_characters is Array:
				for entry in raw_stage_exit_characters:
					var trimmed_exit: String = str(entry).strip_edges()
					if trimmed_exit.is_empty():
						continue
					stage_exit_characters.append(trimmed_exit)
			if stage_exit_characters.is_empty():
				for entry in str(p.get("characters_csv", "")).split(","):
					var trimmed_exit_csv: String = entry.strip_edges()
					if trimmed_exit_csv.is_empty():
						continue
					stage_exit_characters.append(trimmed_exit_csv)
			return "舞台离场 [%s]" % " / ".join(PackedStringArray(stage_exit_characters))
		"WAIT_CLICK": return "等待点击"
		"WAIT_TIME": return "等待 %.1f秒" % p.get("duration", 1.0)
		"CHOICE": return "选项 (%d个)" % p.get("choices", []).size()
		"LABEL": return "标签 [%s]" % p.get("name", "")
		"JUMP_LABEL": return "跳转标签 %s" % p.get("target", "")
		"JUMP_SCENE": return "跳转场景 %s" % p.get("scene_id", "")
		"SET_VARIABLE":
			var var_id: String = p.get("variable_id", "")
			var var_name: String = p.get("variable_name", "")
			var display_name: String = _resolve_variable_display(var_id, var_name)
			return "设置变量 %s %s %s" % [display_name, p.get("operation", "set"), str(p.get("value", ""))]
		"CALL_EVENT": return "调用事件 %s" % p.get("event_id", "")
		"PLAY_BGM": return "播放BGM %s" % p.get("audio_path", "")
		"STOP_BGM": return "停止BGM"
		"PLAY_SFX": return "播放音效 %s" % p.get("audio_path", "")
		"CHANGE_BACKGROUND": return "切换背景"
		"IF": return "如果 [%s]" % p.get("condition", "")
		"CHECK_VAR":
			var var_id: String = p.get("variable_id", "")
			var vn: String = p.get("variable_name", "?")
			var display_name: String = _resolve_variable_display(var_id, vn)
			return "%s %s %s" % [display_name, p.get("operator", ">="), str(p.get("value", "0"))]
		_: return cmd_type


## 解析变量显示名称：优先用 variable_id 查找名称，显示为 "ID(名称)" 格式
func _resolve_variable_display(var_id: String, var_name: String) -> String:
	if _project == null or not "variables" in _project:
		if not var_id.is_empty():
			return var_id
		return var_name if not var_name.is_empty() else "?"
	
	if not var_id.is_empty():
		for v in _project.variables:
			if v.variable_id == var_id:
				return "%s(%s)" % [var_id, v.variable_name]
		return "%s(?)" % var_id
	
	if not var_name.is_empty():
		for v in _project.variables:
			if v.variable_name == var_name:
				var vid: String = v.variable_id if "variable_id" in v else ""
				if not vid.is_empty():
					return "%s(%s)" % [vid, var_name]
				return var_name
		return var_name
	
	return "?"


# ============ Command Events ============

func _on_command_tree_item_selected() -> void:
	var selected: TreeItem = command_tree.get_selected()
	if selected == null:
		_current_command_index = -1
		return
	var meta: Dictionary = selected.get_metadata(0)
	_current_command_index = -1 if meta.get("type") == "empty" else meta.get("index", -1)


func _on_command_tree_item_activated() -> void:
	var selected: TreeItem = command_tree.get_selected()
	if selected == null:
		return
	var meta: Dictionary = selected.get_metadata(0)
	if meta.get("type") == "empty":
		_pending_add_meta = meta
		if add_command_dialog:
			add_command_dialog.popup_centered()


func _on_delete_command_pressed() -> void:
	var selected: TreeItem = command_tree.get_selected() if command_tree else null
	if selected == null:
		return
	var meta: Dictionary = selected.get_metadata(0)
	if meta.get("type") == "empty" or meta.get("type") == "else_label":
		return
	var event: Resource = get_selected_event()
	if event == null:
		return
	var commands: Array = event.commands
	var path: String = meta.get("path", "")
	var index: int = meta.get("index", -1)
	if index < 0:
		return
	if path.is_empty() and index < commands.size():
		commands.remove_at(index)
	_current_command_index = -1
	_refresh_command_list()
	_refresh_list()
	if _selected_slot >= 1 and _selected_slot <= _max_slots:
		event_list.select(_selected_slot - 1)
	StorageManager.notify_content_changed()


func _on_command_type_button_pressed(command_type: String) -> void:
	_add_command_of_type(command_type)
	if add_command_dialog:
		add_command_dialog.hide()


func _on_add_command_dialog_closed() -> void:
	if add_command_dialog:
		add_command_dialog.hide()


func _add_command_of_type(command_type: String) -> void:
	var event: Resource = get_selected_event()
	if event == null:
		return
	var commands: Array = event.commands
	var AVGCommandClass = load("res://scripts/avg/resources/avg_command.gd")
	var new_cmd: Resource = AVGCommandClass.new()
	new_cmd.command_type = command_type
	_init_command_params(new_cmd)
	var path: String = _pending_add_meta.get("path", "")
	var insert_index: int = _pending_add_meta.get("index", commands.size())
	if path.is_empty():
		if insert_index >= commands.size():
			commands.append(new_cmd)
		else:
			commands.insert(insert_index, new_cmd)
	_pending_add_meta = {}
	_refresh_command_list()
	_refresh_list()
	if _selected_slot >= 1 and _selected_slot <= _max_slots:
		event_list.select(_selected_slot - 1)
	StorageManager.notify_content_changed()


func _init_command_params(cmd: Resource) -> void:
	match cmd.command_type:
		"DIALOGUE": cmd.params = {"text": "", "speaker": "", "emotion": "", "text_speed": -1.0, "position": "default", "transparent": false}
		"SHOW_CHARACTER": cmd.params = {"character_id": "", "position": "center", "emotion": "", "fade_duration": 0.3}
		"HIDE_CHARACTER": cmd.params = {"character_id": "", "fade_duration": 0.3}
		"STAGE_SET": cmd.params = {"characters_csv": "", "emotions": "", "outfits": "", "duration": 0.35, "enter_effect": "fade", "exit_effect": "fade"}
		"STAGE_ENTER": cmd.params = {"characters_csv": "", "emotions": "", "outfits": "", "duration": 0.35, "enter_effect": "fade"}
		"STAGE_EXIT": cmd.params = {"characters_csv": "", "duration": 0.35, "exit_effect": "fade"}
		"WAIT_CLICK": cmd.params = {}
		"WAIT_TIME": cmd.params = {"duration": 1.0}
		"CHOICE": cmd.params = {"choices": []}
		"LABEL": cmd.params = {"name": ""}
		"JUMP_LABEL": cmd.params = {"target": ""}
		"JUMP_SCENE": cmd.params = {"scene_id": ""}
		"SET_VARIABLE": cmd.params = {"variable_id": "", "variable_name": "", "value": 0, "operation": "set"}
		"CALL_EVENT": cmd.params = {"event_id": ""}
		"PLAY_BGM": cmd.params = {"audio_path": "", "fade_duration": 1.0, "volume": 1.0}
		"STOP_BGM": cmd.params = {"fade_duration": 1.0}
		"PLAY_SFX": cmd.params = {"audio_path": "", "volume": 1.0}
		"CHANGE_BACKGROUND": cmd.params = {"texture": null, "fade_duration": 0.5}
		"IF": cmd.params = {"condition_commands": [], "if_commands": [], "has_else": false, "else_commands": []}
		"CHECK_VAR": cmd.params = {"variable_id": "", "variable_name": "", "operator": ">=", "value": "0"}
		_: cmd.params = {}
