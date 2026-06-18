extends Node

const BithubAppScene = preload("res://scenes/apps/bithub/bithub_app.tscn")

var _original_dev_settings: Dictionary = {}
var _original_project: Resource = null
var _original_project_path: String = ""
var _test_project_path: String = ""


func _ready() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var manager: Node = get_node_or_null("/root/BithubManager")
	var wom: Node = get_node_or_null("/root/WorkOrderManager")
	if manager == null or wom == null:
		print("[FAIL] Bithub test missing required autoloads")
		return

	_prepare_test_state(manager, wom)
	await get_tree().process_frame
	if not _run_parse_tests(manager):
		_cleanup_test_state(manager, wom)
		return

	var order: Resource = wom.create_order("加入标题界面", "让玩家能从标题界面开始试玩 Demo。")
	order.metadata = {
		"bithub_milestone": true,
		"bithub_milestone_name": "第一次可玩 Demo",
	}
	wom.set_order_status(order.id, "completed")
	await get_tree().process_frame

	var commits: Array = manager.call("get_commits")
	if commits.size() != 1:
		print("[FAIL] Bithub should record one commit after order completion, got %d" % commits.size())
		_cleanup_test_state(manager, wom)
		return
	var commit: Dictionary = commits[0]
	if str(commit.get("order_id", "")) != order.id or str(commit.get("title", "")).is_empty():
		print("[FAIL] Bithub commit payload is incomplete: %s" % str(commit))
		_cleanup_test_state(manager, wom)
		return
	print("[OK] Bithub records narrative commit on completed work order")

	var milestones: Array = manager.call("get_milestones")
	if milestones.size() != 1:
		print("[FAIL] Bithub should create a milestone from order metadata, got %d" % milestones.size())
		_cleanup_test_state(manager, wom)
		return
	var milestone: Dictionary = milestones[0]
	var snapshot_path: String = str(milestone.get("snapshot_path", ""))
	if snapshot_path.is_empty() or not FileAccess.file_exists(snapshot_path + "project.tres"):
		print("[FAIL] Bithub milestone snapshot missing project.tres: %s" % snapshot_path)
		_cleanup_test_state(manager, wom)
		return
	print("[OK] Bithub creates playable project snapshot for milestones")

	var story_director: Node = get_node_or_null("/root/StoryDirector")
	if story_director == null or not story_director.has_method("_execute_action"):
		print("[FAIL] StoryDirector unavailable for Bithub milestone action")
		_cleanup_test_state(manager, wom)
		return
	story_director.call("_execute_action", {
		"type": "create_bithub_milestone",
		"name": "剧情触发 Demo",
		"entry_scene_id": "",
	})
	await get_tree().process_frame
	milestones = manager.call("get_milestones")
	if milestones.size() != 2:
		print("[FAIL] StoryDirector should create a Bithub milestone, got %d" % milestones.size())
		_cleanup_test_state(manager, wom)
		return
	print("[OK] StoryDirector can create Bithub milestone without player action")

	var app: Control = BithubAppScene.instantiate()
	add_child(app)
	await get_tree().process_frame
	if app == null or not is_instance_valid(app):
		print("[FAIL] Bithub App scene failed to instantiate")
		_cleanup_test_state(manager, wom)
		return
	print("[OK] Bithub App scene instantiates and renders initial UI")

	_cleanup_test_state(manager, wom)


func _run_parse_tests(manager: Node) -> bool:
	var draft: Dictionary = {
		"title": "原始工单",
		"message": "原始说明",
	}
	if not _assert_commit_parse(manager, "standard DSL",
		"title: 推进标题界面\nmessage: 玩家能开始试玩。",
		draft, "推进标题界面", "玩家能开始试玩。"):
		return false
	if not _assert_commit_parse(manager, "full-width colon",
		"title：完成入口\nmessage：标题界面已经接入。",
		draft, "完成入口", "标题界面已经接入。"):
		return false
	if not _assert_commit_parse(manager, "multiline message",
		"title: 扩展剧情\nmessage:\n第一句。\n第二句。",
		draft, "扩展剧情", "第一句。\n第二句。"):
		return false
	if not _assert_commit_parse(manager, "fenced DSL",
		"```dsl\ntitle: 记录里程碑\nmessage: 已生成可玩版本。\n```",
		draft, "记录里程碑", "已生成可玩版本。"):
		return false
	if not _assert_commit_parse(manager, "plain quotes",
		"title: 修复\"标题\"按钮\nmessage: 玩家点击\"开始\"后进入 Demo。",
		draft, "修复\"标题\"按钮", "玩家点击\"开始\"后进入 Demo。"):
		return false
	if not _assert_commit_parse(manager, "fallback for non DSL",
		"好的，下面是提交信息：\n完成标题界面",
		draft, "原始工单", "原始说明"):
		return false
	return true


func _assert_commit_parse(
	manager: Node,
	case_name: String,
	raw_text: String,
	draft: Dictionary,
	expected_title: String,
	expected_message: String
) -> bool:
	var parsed: Dictionary = manager.call("_parse_commit_message", raw_text, draft)
	var actual_title: String = str(parsed.get("title", ""))
	var actual_message: String = str(parsed.get("message", ""))
	if actual_title != expected_title or actual_message != expected_message:
		print("[FAIL] Bithub commit DSL parse %s expected title=%s message=%s, got %s" % [
			case_name,
			expected_title,
			expected_message,
			str(parsed),
		])
		return false
	print("[OK] Bithub commit DSL parse %s" % case_name)
	return true


func _prepare_test_state(manager: Node, wom: Node) -> void:
	_original_project = StorageManager.current_project
	_original_project_path = StorageManager.current_project_path

	var cfg := AIConfigManager.get_instance()
	_original_dev_settings = cfg.get("_dev_settings").duplicate(true)
	var dev_settings: Dictionary = _original_dev_settings.duplicate(true)
	dev_settings["disable_background_llm"] = true
	cfg.set("_dev_settings", dev_settings)

	var project: Resource = StorageManager.create_project("bithub_test_project")
	_test_project_path = "user://tests/bithub_project_%d/" % Time.get_ticks_msec()
	StorageManager.current_project_path = _test_project_path
	StorageManager.set_current_project(project)
	StorageManager.save_project(project)
	if wom.has_method("reset_runtime_state"):
		wom.reset_runtime_state()

	manager.set("_state", {
		"repo_key": "test",
		"commits": [],
		"milestones": [],
	})
	manager.set("_repo_dir", "user://tests/bithub_repo/")
	manager.set("_state_path", "user://tests/bithub_repo/state.json")


func _cleanup_test_state(manager: Node, wom: Node) -> void:
	var cfg := AIConfigManager.get_instance()
	cfg.set("_dev_settings", _original_dev_settings)
	if wom.has_method("reset_runtime_state"):
		wom.reset_runtime_state()
	manager.set("_state", {
		"repo_key": "test",
		"commits": [],
		"milestones": [],
	})
	StorageManager.current_project_path = _original_project_path
	StorageManager.set_current_project(_original_project)
