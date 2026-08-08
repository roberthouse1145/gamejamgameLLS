extends Node
## 技能图稳定契约：独立节点状态、任意分支、真实前置与存档往返。


func _ready() -> void:
	_test_extensible_graph_schema()
	var manager: Node = get_node_or_null("/root/SkillTreeManager")
	assert(manager != null)
	var tree: StreamerSkillTree = manager.get_skill_tree()
	assert(tree.is_valid(), "authored skill graph should be a valid DAG")
	assert(tree.skills.size() == 20, "the first authored graph should expose five real forks")

	manager.reset_to_defaults()
	assert(manager.get_unlocked_skill_ids().size() == 5, "all authored entry nodes should start unlocked")
	assert(manager.is_unlocked(&"game_lv1"))
	assert(manager.can_unlock(&"game_lv2"))
	assert(not manager.can_unlock(&"game_lv3"), "a descendant must require its authored prerequisite")
	assert(not manager.can_unlock(&"game_content_lv3"), "sibling descendants share the same real prerequisite")

	assert(manager.unlock_skill(&"game_lv2"))
	assert(manager.can_unlock(&"game_lv3"))
	assert(manager.can_unlock(&"game_content_lv3"))
	assert(manager.unlock_skill(&"game_lv3"))
	assert(GameState.get_skill_level(&"game") == 3)
	assert(not manager.can_unlock(&"game_content_lv3"), "growth point cost still applies independently per node")
	manager.grant_skill_points(1)
	assert(manager.unlock_skill(&"game_content_lv3"), "both branches must remain independently investable")
	assert(GameState.get_skill_level(&"game") == 4, "each authored branch contribution should affect the derived ability level")

	var saved_state: Dictionary = manager.get_run_state()
	manager.reset_to_defaults()
	assert(not manager.is_unlocked(&"game_lv3"))
	manager.load_run_state({"growth_points": 0, "unlocked_skill_ids": [&"game_lv3"]})
	assert(not manager.is_unlocked(&"game_lv3"), "loaded descendants without their prerequisites must be rejected")
	manager.load_run_state(saved_state)
	assert(manager.is_unlocked(&"game_lv3"))
	assert(manager.is_unlocked(&"game_content_lv3"))
	assert(GameState.get_skill_level(&"game") == 4)
	print("SKILL_TREE_GRAPH_TEST_PASS")


func _test_extensible_graph_schema() -> void:
	var root_a: StreamerSkill = _make_skill(&"root_a", [])
	var root_b: StreamerSkill = _make_skill(&"root_b", [])
	var branch: StreamerSkill = _make_skill(&"branch", [&"root_a"])
	var leaf_a: StreamerSkill = _make_skill(&"leaf_a", [&"branch"])
	var leaf_b: StreamerSkill = _make_skill(&"leaf_b", [&"branch"])
	var merge: StreamerSkill = _make_skill(&"merge", [&"leaf_b", &"root_b"])
	var custom_tree := StreamerSkillTree.new()
	custom_tree.initially_unlocked_skill_ids.assign([&"root_a", &"root_b"])
	custom_tree.skills.assign([root_a, root_b, branch, leaf_a, leaf_b, merge])
	assert(custom_tree.is_valid(), "schema must allow arbitrary roots, recursive forks and multi-parent convergence")


func _make_skill(skill_id: StringName, prerequisites: Array[StringName]) -> StreamerSkill:
	var skill := StreamerSkill.new()
	skill.skill_id = skill_id
	skill.family = &"custom"
	skill.display_name = String(skill_id)
	skill.required_skill_ids = prerequisites
	return skill
