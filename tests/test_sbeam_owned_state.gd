extends Control

const SBEAM_APP_SCENE: PackedScene = preload("res://scenes/apps/sbeam/sbeam_app.tscn")
const MessageCardClass = preload("res://scripts/apps/linkchat/components/message_card.gd")


func _ready() -> void:
	print("=== Sbeam Owned State Test ===")
	var sbeam: Node = get_node_or_null("/root/SbeamManager")
	var gm: Node = get_node_or_null("/root/GameManager")
	var glm: Node = get_node_or_null("/root/GameLoopManager")
	var chat: Node = get_node_or_null("/root/ChatManager")
	if sbeam == null or gm == null or glm == null or chat == null:
		print("[FAIL] missing required autoload")
		return

	sbeam.reset_runtime_state()
	gm.reset_runtime_state()
	glm.reset_runtime_state()

	var catalog: Array = sbeam.get_catalog()
	_assert(catalog.size() > 0, "catalog available")
	if catalog.is_empty():
		return

	var first_entry: Dictionary = catalog[0] as Dictionary
	var expected_price: int = _get_expected_purchase_cost(first_entry)
	_assert(expected_price > 0, "seed game expected price is non-zero")
	_assert(int(first_entry.get("price", 0)) == expected_price, "seed catalog derives price from rewards")
	var game_id: String = str(first_entry.get("game_id", ""))
	_assert(not game_id.is_empty(), "game id available")
	if game_id.is_empty():
		return

	var raw_state: Dictionary = sbeam.get_run_state()
	raw_state["owned_game_ids"] = [game_id]
	sbeam.load_run_state(raw_state)

	var blocked: Dictionary = sbeam.begin_play_session(game_id, true)
	_assert(not bool(blocked.get("success", false)), "owned game cannot start")
	_assert(str(blocked.get("error", "")) == "该游戏已在库存里", "owned game error message matches")

	var channel = chat.get_channel("dm_lin_xia")
	var before_count: int = 0
	if channel != null:
		before_count = channel.messages.size()
	sbeam.send_npc_invite_game_panel(game_id)
	channel = chat.get_channel("dm_lin_xia")
	var after_count: int = before_count
	var last_message: Dictionary = {}
	if channel != null:
		after_count = channel.messages.size()
		if after_count > 0:
			last_message = channel.messages[after_count - 1]
	_assert(after_count == before_count + 1, "npc invite card appended to chat")
	_assert(str(last_message.get("sender_id", "")) == "npc_lin_xia", "npc invite card sender matches")
	var game_card: Dictionary = last_message.get("card", {}) as Dictionary
	_assert(str(game_card.get("title", "")) == str(first_entry.get("title", "")), "npc invite card shows game title")
	_assert(str(game_card.get("price", "")) == "¥ %d" % expected_price, "npc invite card carries structured price")
	_assert(str(game_card.get("footer", "")).find("¥") == -1, "npc invite card footer does not mix price")

	var rendered_card: Control = MessageCardClass.create(game_card, 0)
	add_child(rendered_card)
	await get_tree().process_frame
	_assert(_find_label_with_text(rendered_card, "¥ %d" % expected_price) != null, "linkchat game card renders price")
	_assert(_find_label_with_text(rendered_card, "推荐给你") != null, "linkchat game card renders footer hint")
	_rendered_card_cleanup(rendered_card)

	var app := SBEAM_APP_SCENE.instantiate() as Control
	_assert(app != null, "sbeam app instantiated")
	if app == null:
		return
	add_child(app)
	await get_tree().process_frame
	await get_tree().process_frame

	if app.has_method("set_active_view"):
		app.call("set_active_view", "store")
	await get_tree().process_frame

	var start_button: Button = _find_button_with_text(app, "该游戏已在库存里")
	_assert(start_button != null, "owned button text rendered")
	_assert(start_button != null and start_button.disabled, "owned button disabled")


func _find_button_with_text(root: Node, target_text: String) -> Button:
	for child in root.get_children():
		if child is Button:
			var button := child as Button
			if button.text == target_text:
				return button
		var nested := _find_button_with_text(child, target_text)
		if nested != null:
			return nested
	return null


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


func _rendered_card_cleanup(card: Control) -> void:
	if card != null:
		card.queue_free()


func _get_expected_purchase_cost(entry: Dictionary) -> int:
	var rewards: Dictionary = entry.get("rewards", {}) as Dictionary
	return maxi(0, -int(rewards.get("money", 0)))


func _assert(condition: bool, label: String) -> void:
	if condition:
		print("[OK] %s" % label)
	else:
		print("[FAIL] %s" % label)