extends Control

const MessageCardClass = preload("res://scripts/apps/linkchat/components/message_card.gd")


func _ready() -> void:
	print("=== Part Time Job Field Test ===")
	var manager: Node = get_node_or_null("/root/PartTimeJobManager")
	var chat: Node = get_node_or_null("/root/ChatManager")
	if manager == null or chat == null:
		_assert(false, "required autoloads available")
		return

	manager.reset_runtime_state()
	chat.reset_runtime_state()

	var legacy_job := {
		"job_id": "legacy_reward_money_shift",
		"job_title": "Legacy Reward Shift",
		"company_name": "Old Format Cafe",
		"district": "School Gate",
		"reward_money": 160,
		"subtitle": "old schema",
		"description": "A legacy job entry that only has reward_money.",
		"valid_phases": "MORNING|AFTERNOON|NIGHT",
		"accent_color": "#10B981",
	}
	var pending_legacy_job := legacy_job.duplicate(true)
	pending_legacy_job["job_id"] = "pending_reward_money_shift"
	pending_legacy_job["reward_money"] = 140

	manager.load_run_state({
		"catalog": [legacy_job],
		"pending_next_day_catalog": [pending_legacy_job],
	})

	var entry: Dictionary = _find_job(manager.get_catalog(), "legacy_reward_money_shift")
	_assert(not entry.is_empty(), "legacy job appears in catalog")
	var rewards: Dictionary = entry.get("rewards", {}) as Dictionary
	_assert(int(rewards.get("money", 0)) == 160, "legacy reward_money normalized to rewards.money")

	var run_state: Dictionary = manager.get_run_state()
	var saved_catalog: Array = run_state.get("catalog", []) as Array
	var saved_entry: Dictionary = _find_job(saved_catalog, "legacy_reward_money_shift")
	var saved_rewards: Dictionary = saved_entry.get("rewards", {}) as Dictionary
	_assert(int(saved_rewards.get("money", 0)) == 160, "saved catalog stores normalized rewards.money")

	var saved_pending: Array = run_state.get("pending_next_day_catalog", []) as Array
	var pending_entry: Dictionary = _find_job(saved_pending, "pending_reward_money_shift")
	var pending_rewards: Dictionary = pending_entry.get("rewards", {}) as Dictionary
	_assert(int(pending_rewards.get("money", 0)) == 140, "pending catalog stores normalized rewards.money")

	var before_count := _get_chat_message_count(chat)
	manager.call("_send_player_activity_card", {"job": entry})
	var after_count := _get_chat_message_count(chat)
	_assert(after_count == before_count + 1, "job card appended to chat")
	var card: Dictionary = _get_last_chat_card(chat)
	_assert(str(card.get("salary", "")) == "160元 / 班", "job card salary uses normalized money")

	var rendered_card: Control = MessageCardClass.create(card, 0)
	add_child(rendered_card)
	await get_tree().process_frame
	_assert(_find_label_with_text(rendered_card, "160元 / 班") != null, "linkchat job card renders salary")
	rendered_card.queue_free()


func _find_job(jobs: Array, job_id: String) -> Dictionary:
	for item in jobs:
		if item is Dictionary and str((item as Dictionary).get("job_id", "")) == job_id:
			return (item as Dictionary).duplicate(true)
	return {}


func _get_chat_message_count(chat: Node) -> int:
	var channel = chat.get_channel("dm_lin_xia")
	if channel == null:
		return 0
	return channel.messages.size()


func _get_last_chat_card(chat: Node) -> Dictionary:
	var channel = chat.get_channel("dm_lin_xia")
	if channel == null or channel.messages.is_empty():
		return {}
	var message: Dictionary = channel.messages[channel.messages.size() - 1]
	return message.get("card", {}) as Dictionary


func _find_label_with_text(root: Node, target_text: String) -> Label:
	for child in root.get_children():
		if child is Label:
			var label := child as Label
			if label.text == target_text:
				return label
		var nested := _find_label_with_text(child, target_text)
		if nested != null:
			return nested
	return null


func _assert(condition: bool, label: String) -> void:
	if condition:
		print("[OK] %s" % label)
	else:
		print("[FAIL] %s" % label)