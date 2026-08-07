class_name StreamerSkillTreeCanvas extends Control
## 技能树画布：只负责节点排布、连线与选择反馈。

signal skill_selected(skill_id: StringName)
signal zoom_requested(direction: float, canvas_anchor: Vector2)

const NODE_SIZE: Vector2 = Vector2(340, 176)
const CELL_SIZE: Vector2 = Vector2(440, 230)
const ORIGIN: Vector2 = Vector2(80, 70)
const LINE_LOCKED: Color = Color("#AEB8C8")
const LINE_UNLOCKED: Color = Color("#59BFA4")

var _buttons: Dictionary = {}
var _selected_skill_id: StringName = &""


func _ready() -> void:
	rebuild()


func set_selected_skill(skill_id: StringName) -> void:
	_selected_skill_id = skill_id
	if skill_id == &"":
		for value: Variant in _buttons.values():
			var candidate := value as Button
			if candidate != null and candidate.has_focus():
				candidate.release_focus()
		return
	var button := _buttons.get(skill_id) as Button
	if button != null:
		button.grab_focus()


func rebuild() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	_buttons.clear()

	var max_position := Vector2.ZERO
	for skill: StreamerSkill in SkillTreeManager.get_skills():
		max_position.x = maxf(max_position.x, skill.tree_position.x)
		max_position.y = maxf(max_position.y, skill.tree_position.y)
		var button := Button.new()
		button.name = "Skill_%s" % String(skill.skill_id)
		button.position = ORIGIN + Vector2(skill.tree_position) * CELL_SIZE
		button.size = NODE_SIZE
		button.icon = skill.icon
		button.add_theme_constant_override("icon_max_width", 92)
		button.expand_icon = true
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text = _skill_button_text(skill)
		button.tooltip_text = skill.description
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.mouse_filter = Control.MOUSE_FILTER_STOP
		button.theme_type_variation = _skill_button_variation(skill)
		button.pressed.connect(_on_skill_pressed.bind(skill.skill_id))
		button.gui_input.connect(_on_skill_button_gui_input.bind(button))
		add_child(button)
		_buttons[skill.skill_id] = button

	var content_size: Vector2 = ORIGIN * 2.0 + Vector2(max_position) * CELL_SIZE + NODE_SIZE
	custom_minimum_size = Vector2(maxf(content_size.x, 1500.0), maxf(content_size.y, 960.0))
	queue_redraw()
	if _selected_skill_id != &"":
		set_selected_skill(_selected_skill_id)


func _draw() -> void:
	for skill: StreamerSkill in SkillTreeManager.get_skills():
		var target_button := _buttons.get(skill.skill_id) as Button
		if target_button == null:
			continue
		for required_id: StringName in skill.required_skill_ids:
			var source_button := _buttons.get(required_id) as Button
			if source_button == null:
				continue
			var source: Vector2 = source_button.position + Vector2(source_button.size.x, source_button.size.y * 0.5)
			var target: Vector2 = target_button.position + Vector2(0, target_button.size.y * 0.5)
			var midpoint_x: float = (source.x + target.x) * 0.5
			var points := PackedVector2Array([
				source,
				Vector2(midpoint_x, source.y),
				Vector2(midpoint_x, target.y),
				target,
			])
			var color: Color = LINE_UNLOCKED if SkillTreeManager.is_unlocked(required_id) else LINE_LOCKED
			draw_polyline(points, color, 7.0, true)


func _skill_button_text(skill: StreamerSkill) -> String:
	if SkillTreeManager.is_unlocked(skill.skill_id):
		return "%s\n已掌握" % skill.display_name
	if SkillTreeManager.can_unlock(skill.skill_id):
		return "%s\n消耗 %d 成长点" % [skill.display_name, skill.point_cost]
	return "%s\n%s" % [skill.display_name, SkillTreeManager.get_unlock_reason(skill.skill_id)]


func _skill_button_variation(skill: StreamerSkill) -> StringName:
	if SkillTreeManager.is_unlocked(skill.skill_id):
		return &"SkillNodeUnlocked"
	if SkillTreeManager.can_unlock(skill.skill_id):
		return &"SkillNodeAvailable"
	return &"SkillNodeLocked"


func _on_skill_pressed(skill_id: StringName) -> void:
	_selected_skill_id = skill_id
	skill_selected.emit(skill_id)


func _on_skill_button_gui_input(event: InputEvent, button: Button) -> void:
	if event is not InputEventMouseButton:
		return
	var mouse_button := event as InputEventMouseButton
	if not mouse_button.pressed or mouse_button.button_index not in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		return
	var direction: float = 1.0 if mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
	zoom_requested.emit(direction, button.position + mouse_button.position)
	button.accept_event()
