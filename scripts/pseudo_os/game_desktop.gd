class_name GameDesktop extends Desktop

const TEMPLATE_SYNC_SHORTCUT_TEXT: String = "Ctrl+Alt+M"
const LEGACY_PURGE_SHORTCUT_TEXT: String = "Ctrl+Alt+L"


func _after_desktop_ready() -> void:
	await get_tree().create_timer(1.0).timeout
	_show_dev_storage_hint_if_needed()
	var run_manager: Node = get_node_or_null("/root/CampaignRunManager")
	if run_manager != null and run_manager.has_method("ensure_campaign_started"):
		# 导出版里部分 autoload 在 _ready 阶段会发起异步请求（如 DateManager 生成次日事件），
		# 首次 ensure_campaign_started 可能因 runtime systems busy 被拒绝。循环重试直到成功或超时。
		var attempts: int = 0
		while attempts < 15:
			if run_manager.ensure_campaign_started("day1"):
				if pre_generate_activity_catalogs_on_ready:
					pre_generate_activity_catalogs()
				return
			attempts += 1
			await get_tree().create_timer(1.0).timeout
		push_error("[GameDesktop] ensure_campaign_started failed after %d retries" % attempts)
		return
	var story_director: Node = get_node_or_null("/root/StoryDirector")
	if story_director != null and story_director.has_method("start_chapter"):
		story_director.start_chapter("day1")
	if pre_generate_activity_catalogs_on_ready:
		pre_generate_activity_catalogs()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return

	var storage: Node = get_node_or_null("/root/StorageManager")
	if storage == null or not bool(storage.get("developer_mode")):
		return

	if key_event.ctrl_pressed and key_event.alt_pressed:
		match key_event.keycode:
			KEY_M:
				_sync_current_project_to_template(storage)
				get_viewport().set_input_as_handled()
			KEY_L:
				_purge_legacy_editor_projects(storage)
				get_viewport().set_input_as_handled()


func _show_dev_storage_hint_if_needed() -> void:
	var storage: Node = get_node_or_null("/root/StorageManager")
	if storage == null or not bool(storage.get("developer_mode")):
		return
	if not storage.has_method("list_legacy_editor_projects"):
		return
	var legacy_projects: Array[String] = storage.list_legacy_editor_projects()
	if legacy_projects.is_empty():
		return
	show_system_notification(
		"检测到旧项目目录",
		"发现 %d 个 res://projects 旧项目，可按 %s 直接清理。" % [legacy_projects.size(), LEGACY_PURGE_SHORTCUT_TEXT],
		"i",
		7.0
	)


func _sync_current_project_to_template(storage: Node) -> void:
	if not storage.has_method("merge_current_project_to_template"):
		return
	var err: Error = storage.merge_current_project_to_template()
	if err == OK:
		show_system_notification(
			"模板已同步",
			"当前项目内容已回灌到默认模板，之后新开局会继承这份范例。",
			"M",
			5.5
		)
	else:
		show_system_notification(
			"模板同步失败",
			"无法执行模板回灌，错误码：%d" % err,
			"!",
			6.0
		)


func _purge_legacy_editor_projects(storage: Node) -> void:
	if not storage.has_method("purge_legacy_editor_projects"):
		return
	var result: Dictionary = storage.purge_legacy_editor_projects()
	var deleted_count: int = (result.get("deleted", []) as Array).size()
	var failed_count: int = (result.get("failed", []) as Array).size()
	var body: String = "已删除 %d 个，失败 %d 个。" % [deleted_count, failed_count]
	show_system_notification("旧项目清理完成", body, "L", 6.0)
