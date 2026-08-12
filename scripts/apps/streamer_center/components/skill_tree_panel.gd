extends Control
## 成长路线：选择节点、查看奖励并执行解锁。

@onready var points_label: Label = %PointsLabel
@onready var tree_layer: Control = %TreeLayer
@onready var tree_viewport: Control = %TreeViewport
@onready var skill_canvas: StreamerSkillTreeCanvas = tree_viewport.get_node("SkillCanvas") as StreamerSkillTreeCanvas
@onready var detail_sidebar: PanelContainer = %DetailSidebar
@onready var detail_icon: TextureRect = %DetailIcon
@onready var detail_name: Label = %DetailName
@onready var detail_description: Label = %DetailDescription
@onready var reward_label: Label = %RewardLabel
@onready var status_label: Label = %StatusLabel
@onready var unlock_button: Button = %UnlockButton
@onready var sidebar_close_button: Button = %SidebarCloseButton

var _selected_skill_id: StringName = &""
var _sidebar_tween: Tween = null


func _ready() -> void:
	skill_canvas.skill_selected.connect(_on_skill_selected)
	unlock_button.pressed.connect(_on_unlock_pressed)
	sidebar_close_button.pressed.connect(_close_sidebar)
	SkillTreeManager.skill_tree_changed.connect(refresh)
	refresh()


func refresh() -> void:
	points_label.text = "%d 成长点" % SkillTreeManager.get_skill_points()
	tree_viewport.call("rebuild")
	skill_canvas.set_selected_skill(_selected_skill_id)
	if _selected_skill_id != &"":
		_render_detail()


func _render_detail() -> void:
	var skill: StreamerSkill = SkillTreeManager.get_skill(_selected_skill_id)
	if skill == null:
		detail_icon.texture = null
		detail_name.text = "选择一个成长节点"
		detail_description.text = ""
		reward_label.text = ""
		status_label.text = ""
		unlock_button.visible = false
		return

	detail_icon.texture = skill.icon
	detail_name.text = skill.display_name
	detail_description.text = skill.description
	reward_label.text = "提升主播基础能力"
	status_label.text = SkillTreeManager.get_unlock_reason(skill.skill_id)
	unlock_button.visible = true
	unlock_button.disabled = not SkillTreeManager.can_unlock(skill.skill_id)
	unlock_button.text = "已掌握" if SkillTreeManager.is_unlocked(skill.skill_id) else "解锁（%d 成长点）" % skill.point_cost


func _on_skill_selected(skill_id: StringName) -> void:
	_selected_skill_id = skill_id
	_render_detail()
	_open_sidebar()


func _on_unlock_pressed() -> void:
	SkillTreeManager.unlock_skill(_selected_skill_id)


func _open_sidebar() -> void:
	var was_visible: bool = detail_sidebar.visible
	_stop_sidebar_tween()
	if was_visible:
		detail_sidebar.modulate.a = 1.0
		return
	detail_sidebar.visible = true
	detail_sidebar.modulate.a = 0.0
	_sidebar_tween = create_tween()
	_sidebar_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_sidebar_tween.tween_property(detail_sidebar, "modulate:a", 1.0, 0.18)


func _close_sidebar() -> void:
	_stop_sidebar_tween()
	_sidebar_tween = create_tween()
	_sidebar_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_sidebar_tween.tween_property(detail_sidebar, "modulate:a", 0.0, 0.14)
	_sidebar_tween.tween_callback(_finish_closing_sidebar)


func _finish_closing_sidebar() -> void:
	detail_sidebar.visible = false
	detail_sidebar.modulate.a = 1.0
	_selected_skill_id = &""
	skill_canvas.set_selected_skill(&"")


func _stop_sidebar_tween() -> void:
	if _sidebar_tween != null and _sidebar_tween.is_valid():
		_sidebar_tween.kill()
	_sidebar_tween = null
