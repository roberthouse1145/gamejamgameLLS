extends Node
## 主播中心画布交互的稳定契约：成长路线缩放边界、平移与详情侧栏。

const SKILL_VIEWPORT_SCENE: PackedScene = preload("res://scenes/apps/streamer_center/components/skill_tree_viewport.tscn")
const SKILL_TREE_PANEL_SCENE: PackedScene = preload("res://scenes/apps/streamer_center/components/skill_tree_panel.tscn")


func _ready() -> void:
	await _test_skill_viewport_transform()
	await _test_skill_detail_sidebar()
	print("STREAMER_CENTER_CANVAS_INTERACTIONS_TEST_PASS")


func _test_skill_viewport_transform() -> void:
	var tree_viewport := SKILL_VIEWPORT_SCENE.instantiate() as Control
	assert(tree_viewport != null, "skill tree viewport scene should instantiate")
	add_child(tree_viewport)
	tree_viewport.size = Vector2(1000, 600)
	await get_tree().process_frame
	tree_viewport.call("rebuild")
	await get_tree().process_frame

	tree_viewport.call("set_zoom", 99.0, Vector2(500, 300))
	assert(is_equal_approx(float(tree_viewport.call("get_zoom")), 1.8), "zoom should stop at its maximum")
	tree_viewport.call("set_zoom", 0.01, Vector2(500, 300))
	assert(is_equal_approx(float(tree_viewport.call("get_zoom")), 0.6), "zoom should stop at its minimum")

	var canvas := tree_viewport.get_node("SkillCanvas") as Control
	var position_before_pan: Vector2 = canvas.position
	tree_viewport.call("pan_by", Vector2(40, 20))
	assert(canvas.position != position_before_pan, "left-drag pan should move the skill canvas")
	tree_viewport.queue_free()
	await get_tree().process_frame


func _test_skill_detail_sidebar() -> void:
	var skill_tree_panel := SKILL_TREE_PANEL_SCENE.instantiate() as Control
	assert(skill_tree_panel != null, "skill tree panel scene should instantiate")
	add_child(skill_tree_panel)
	skill_tree_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	skill_tree_panel.size = Vector2(1800, 1200)
	await get_tree().process_frame

	var detail_sidebar := skill_tree_panel.find_child("DetailSidebar", true, false) as Control
	var tree_layer := skill_tree_panel.find_child("TreeLayer", true, false) as Control
	var page_margin := skill_tree_panel.find_child("PageMargin", true, false) as MarginContainer
	var tree_panel := skill_tree_panel.find_child("TreePanel", true, false) as PanelContainer
	var grid_backdrop := skill_tree_panel.find_child("GridBackdrop", true, false) as ColorRect
	var tree_viewport := skill_tree_panel.find_child("TreeViewport", true, false) as Control
	var skill_canvas := skill_tree_panel.find_child("SkillCanvas", true, false) as StreamerSkillTreeCanvas
	var close_button := skill_tree_panel.find_child("SidebarCloseButton", true, false) as Button
	var detail_name := skill_tree_panel.find_child("DetailName", true, false) as Label
	assert(detail_sidebar != null, "skill detail sidebar should exist")
	assert(skill_tree_panel.find_child("DetailPanel", true, false) == null, "persistent bottom detail panel should be removed")
	assert(page_margin != null, "growth page should preserve its outer margin")
	assert(tree_panel != null, "skill tree should remain inside the rounded card panel")
	assert(tree_layer.get_parent() == tree_panel, "skill tree layer should be contained by the rounded card")
	assert(tree_viewport.anchor_right == 1.0 and tree_viewport.anchor_bottom == 1.0, "skill tree viewport should fill the rounded card")
	assert(grid_backdrop.material is ShaderMaterial, "rounded card should use the visible grid material")
	assert(grid_backdrop.anchor_right == 1.0 and grid_backdrop.anchor_bottom == 1.0, "grid should fill the rounded card")
	var grid_material := grid_backdrop.material as ShaderMaterial
	var grid_color: Color = grid_material.get_shader_parameter("grid_color") as Color
	assert(grid_color.a >= 0.2, "grid lines should remain visibly distinct on the white card")
	assert(not detail_sidebar.visible, "skill detail sidebar should stay hidden until a skill is selected")

	var skills: Array[StreamerSkill] = SkillTreeManager.get_skills()
	assert(not skills.is_empty(), "skill tree should provide at least one skill")
	var skill_button := skill_canvas.find_child("Skill_%s" % String(skills[0].skill_id), false, false) as Button
	assert(skill_button != null, "skill button should exist for real pointer input")
	assert(skill_button.mouse_filter == Control.MOUSE_FILTER_STOP, "skill click should not bubble into canvas dragging")
	skill_button.pressed.emit()
	await get_tree().create_timer(0.2).timeout
	assert(detail_sidebar.visible, "selecting a skill should open the detail sidebar")
	assert(detail_name.text == skills[0].display_name, "real skill click should render the selected skill")
	assert(close_button.is_visible_in_tree(), "skill detail sidebar should expose a visible close button")
	assert(detail_sidebar.get_global_rect().encloses(close_button.get_global_rect()), "close button should stay inside the visible sidebar")

	close_button.pressed.emit()
	await get_tree().create_timer(0.18).timeout
	assert(not detail_sidebar.visible, "closing the skill detail should restore the full canvas")
	skill_tree_panel.queue_free()
