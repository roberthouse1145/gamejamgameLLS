class_name VariableListPanel extends VBoxContainer
## 变量列表面板 — 槽位制
## 显示所有槽位（1~max），点击空槽创建，点击已有变量编辑
## variable_id = "var_NNN" 由槽位号决定

signal variable_selected(variable: Resource)

const AVGVariableClass = preload("res://scripts/avg/resources/avg_variable.gd")

## 槽位数量上限
const DEFAULT_MAX_SLOTS: int = 100

var _project: Resource = null
## 当前选中的槽位号（1-based）
var _selected_slot: int = -1
var _max_slots: int = DEFAULT_MAX_SLOTS

@onready var clear_button: Button = %DeleteButton
@onready var variable_list: ItemList = %VariableList
@onready var property_editor: Control = %PropertyEditor


func _ready() -> void:
	if clear_button:
		clear_button.text = "清空"
		clear_button.pressed.connect(_on_clear_pressed)
	if variable_list:
		variable_list.item_selected.connect(_on_item_selected)


func set_project(project: Resource) -> void:
	_project = project
	_selected_slot = -1
	_refresh_list()
	_clear_editor()


func get_project() -> Resource:
	return _project


## 根据槽位号获取变量
func get_variable_by_slot(slot: int) -> Resource:
	if _project == null:
		return null
	var var_id: String = AVGVariableClass.make_id(slot)
	for v in _project.variables:
		if v.variable_id == var_id:
			return v
	return null


func get_selected_variable() -> Resource:
	if _selected_slot < 1:
		return null
	return get_variable_by_slot(_selected_slot)


func _refresh_list() -> void:
	if variable_list == null:
		return
	variable_list.clear()
	if _project == null:
		_update_buttons()
		return

	for slot in range(1, _max_slots + 1):
		var var_id: String = AVGVariableClass.make_id(slot)
		var v: Resource = get_variable_by_slot(slot)
		
		var display: String
		if v != null:
			display = "%s: %s = %s" % [var_id, v.variable_name, str(v.default_value)]
		else:
			display = "%s: (空)" % var_id
		
		variable_list.add_item(display)
		
		if v == null:
			variable_list.set_item_custom_fg_color(slot - 1, Color(0.5, 0.5, 0.5))

	if _selected_slot >= 1 and _selected_slot <= _max_slots:
		variable_list.select(_selected_slot - 1)
	_update_buttons()


func _update_buttons() -> void:
	if clear_button:
		clear_button.disabled = get_selected_variable() == null


func _clear_editor() -> void:
	if property_editor and property_editor.has_method("set_target"):
		property_editor.set_target(null)


func _on_item_selected(index: int) -> void:
	_selected_slot = index + 1
	
	var v: Resource = get_selected_variable()
	
	if v == null:
		_create_variable_at_slot(_selected_slot)
		v = get_selected_variable()
	
	if v != null:
		if property_editor and property_editor.has_method("set_target_with_properties"):
			# 直接使用资源定义的属性列表
			var props: Array = AVGVariableClass.get_avg_properties()
			property_editor.set_target_with_properties(v, props)
			if not property_editor.is_connected("property_changed", _on_property_changed):
				property_editor.property_changed.connect(_on_property_changed)
		variable_selected.emit(v)
	
	_update_buttons()


func _create_variable_at_slot(slot: int) -> void:
	if _project == null:
		return
	
	var new_var: Resource = AVGVariableClass.new()
	new_var.variable_id = AVGVariableClass.make_id(slot)
	new_var.variable_name = "变量%03d" % slot
	new_var.default_value = 0
	
	_project.variables.append(new_var)
	_refresh_list()
	
	if variable_list and slot >= 1 and slot <= _max_slots:
		variable_list.select(slot - 1)


func _on_clear_pressed() -> void:
	if _project == null or _selected_slot < 1:
		return
	
	var v: Resource = get_selected_variable()
	if v == null:
		return
	
	var idx: int = _project.variables.find(v)
	if idx >= 0:
		_project.variables.remove_at(idx)
	
	_refresh_list()
	_clear_editor()
	_update_buttons()


func _on_property_changed(_prop_name: String, _old_val: Variant, _new_val: Variant) -> void:
	# 变量类型已统一为 int，不再需要复杂的类型转换逻辑
	_refresh_list()
