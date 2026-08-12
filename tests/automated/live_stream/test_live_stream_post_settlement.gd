extends Node
## 直播结束后：先展示预生成 Post，展示完成信号到达后才提交数值与时段。


func _ready() -> void:
	var manager: Node = get_node_or_null("/root/LiveStreamManager")
	var material_inventory: Node = get_node_or_null("/root/MaterialInventoryManager")
	assert(manager != null and material_inventory != null)

	GameState.day = 1
	GameState.time_slot = GameState.TIME_SLOT_MORNING
	GameState.completed_stream_sessions.clear()
	GameState.completed_action_transactions.clear()
	GameState.action_transaction_history.clear()
	GameState.stream_history.clear()
	SocialMediaManager.reset_runtime_state()
	material_inventory.reset_to_defaults()
	manager.reset_draft()
	var material_instance_id: StringName = _find_material_instance(
		material_inventory,
		&"material_trash_hunter"
	)
	assert(material_instance_id != &"")
	assert(manager.select_material(material_instance_id))
	assert(manager.advance_step())
	var approaches: Array[Dictionary] = manager.get_approaches()
	assert(not approaches.is_empty())
	assert(manager.select_approach(StringName(str(approaches[0].get("approach_id", "")))))
	assert(manager.advance_step())

	var money_before: int = GameState.money
	var fans_before: int = GameState.fans
	var stress_before: int = GameState.stress
	var exp_before: int = GameState.streamer_exp
	var plan: StreamPlanSnapshot = manager.request_broadcast(8642)
	assert(plan != null and manager.is_broadcast_pending())
	var result: StreamSettlementResult = manager.get_pending_result()
	assert(result != null)

	var account: SocialAccountProfile = SocialMediaManager.get_active_player_streamer_account()
	var post_generator: LiveStreamPostGenerator = manager.get_node_or_null(
		"LiveStreamPostGenerator"
	) as LiveStreamPostGenerator
	assert(account != null and post_generator != null)
	var jobs: Dictionary = post_generator.get("_jobs_by_session") as Dictionary
	jobs[String(plan.session_id)] = {
		"session_id": String(plan.session_id),
		"state": "ready",
		"authorized": false,
		"account_id": account.account_id,
		"post": {
			"account_id": account.account_id,
			"text": "下播。最后一刀忍住了，居然真的过了。",
			"media_mode": "none",
			"reach": "normal",
			"comments": [
				{"author_ref": "夜班观众", "text": "最后那一下确实稳。"},
			],
		},
	}
	post_generator.set("_jobs_by_session", jobs)

	var published_posts: Array[SocialPostRecord] = []
	manager.stream_post_published.connect(
		func(_session_id: StringName, post: SocialPostRecord) -> void:
			published_posts.append(post),
		CONNECT_ONE_SHOT
	)
	assert(manager.begin_post_settlement(plan.session_id, false))
	await get_tree().process_frame
	assert(published_posts.size() == 1)
	var published: SocialPostRecord = published_posts[0]
	assert(published.source_session_id == String(plan.session_id))
	assert(manager.is_broadcast_pending())
	assert(GameState.day == 1 and GameState.time_slot == GameState.TIME_SLOT_MORNING)
	assert(GameState.money == money_before and GameState.fans == fans_before)
	assert(GameState.stress == stress_before and GameState.streamer_exp == exp_before)

	assert(not SocialMediaManager.consume_post_presentation(published.post_id).is_empty())
	assert(SocialMediaManager.complete_post_presentation(published.post_id))
	assert(not manager.is_broadcast_pending())
	assert(GameState.time_slot == GameState.TIME_SLOT_AFTERNOON)
	assert(GameState.money == money_before + result.revenue)
	assert(GameState.fans == fans_before + result.fan_delta)
	assert(GameState.streamer_exp == exp_before + result.streamer_exp_gain)
	assert(GameState.completed_stream_sessions.has(String(plan.session_id)))
	assert(GameState.action_transaction_history.size() == 1)
	assert(not StoryLockManager.has_lock("live_stream"))
	print("LIVE_STREAM_POST_SETTLEMENT_TEST_PASS")


func _find_material_instance(material_inventory: Node, definition_id: StringName) -> StringName:
	for instance: Dictionary in material_inventory.get_instances():
		if StringName(str(instance.get("definition_id", ""))) == definition_id:
			return StringName(str(instance.get("instance_id", "")))
	return &""
