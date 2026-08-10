extends Node
## 通用外出活动编排器。MAP 只是调用方，判定、事务与剧情链路均在此处。

signal session_changed(snapshot: Dictionary)
signal session_failed(stage: String, error: String, snapshot: Dictionary)
signal session_completed(snapshot: Dictionary)

const CATALOG: OutingCatalog = preload("res://resources/outing/outing_catalog.tres")
const ChatTopicClass = preload("res://scripts/chat/resources/chat_topic.gd")
const AVGSceneGeneratorClass = preload("res://scripts/avg/generation/avg_scene_generator.gd")

const MODE_SOLO: String = "solo"
const MODE_DATE: String = "date"
const LOCK_OWNER: String = "outing_session"
const MAP_APP_ID: String = "cityhop"
const LINKCHAT_APP_ID: String = "linkchat"
const AVG_APP_ID: String = "avg_player"
const INVITATION_PROMPT_KEY: String = "outing/invitation"
const FEEDBACK_PROMPT_KEY: String = "outing/feedback"
const AVG_SOLO_CONTEXT_PROMPT_KEY: String = "outing/avg_solo_context"
const AVG_DATE_CONTEXT_PROMPT_KEY: String = "outing/avg_date_context"
const AVG_CONSTRAINTS_PROMPT_KEY: String = "outing/avg_constraints"
const AVG_GUIDANCE_PROMPT_KEY: String = "outing/avg_guidance"

var _topic_manager: TopicManager = null
var _avg_generator: Node = null
var _pending_scene_package: Dictionary = {}
var _active_transit_id: String = ""


func _ready() -> void:
	_avg_generator = AVGSceneGeneratorClass.new()
	_avg_generator.name = "OutingAVGGenerator"
	add_child(_avg_generator)
	_avg_generator.scene_generated.connect(_on_scene_generated)
	_avg_generator.scene_failed.connect(_on_scene_failed)
	call_deferred("_connect_dependencies")


func get_catalog() -> OutingCatalog:
	return CATALOG


func get_activity(activity_id: String) -> OutingActivity:
	return CATALOG.get_activity(activity_id)


func get_place(place_id: String) -> MapPlace:
	return CATALOG.get_place(place_id)


func get_available_activities() -> Array[OutingActivity]:
	return CATALOG.get_available_activities(GameState.day, GameState.time_slot)


func get_datable_friends(activity_id: String = "") -> Array[CharacterProfile]:
	var result: Array[CharacterProfile] = []
	var activity: OutingActivity = get_activity(activity_id) if not activity_id.is_empty() else null
	if activity != null and not activity.supports_date:
		return result
	for character: CharacterProfile in LinkChatManager.get_friend_characters():
		if character == null or not character.datable:
			continue
		if character.avg_character == null or character.linkchat_profile == null:
			continue
		if has_failed_invite_today(character.character_id):
			continue
		result.append(character)
	return result


func has_failed_invite_today(character_id: String) -> bool:
	var day_key: String = str(GameState.day)
	var failed_value: Variant = GameState.failed_date_invites.get(day_key, [])
	if not failed_value is Array:
		return false
	return character_id in failed_value


func get_active_session() -> Dictionary:
	return GameState.active_outing_session.duplicate(true)


func has_active_session() -> bool:
	return not GameState.active_outing_session.is_empty()


func validate_start(activity_id: String, mode: String, character_id: String = "") -> Dictionary:
	if has_active_session():
		return _validation(false, "已有外出剧情正在进行")
	var activity: OutingActivity = get_activity(activity_id)
	if activity == null or not activity.is_valid():
		return _validation(false, "活动不存在")
	if not activity.is_available(GameState.day, GameState.time_slot):
		return _validation(false, "当前时段无法参加")
	if mode == MODE_SOLO and not activity.supports_solo:
		return _validation(false, "该活动不支持单人前往")
	if mode == MODE_DATE and not activity.supports_date:
		return _validation(false, "该活动不支持约会外出")
	var cost: int = activity.solo_cost if mode == MODE_SOLO else activity.date_cost
	if GameState.money < cost:
		return _validation(false, "余额不足")
	if mode == MODE_DATE:
		var character: CharacterProfile = LinkChatManager.get_character(character_id)
		if character == null or not character.datable or not LinkChatManager.is_friend(character_id):
			return _validation(false, "该角色当前不可邀请")
		if character.avg_character == null or character.linkchat_profile == null:
			return _validation(false, "该角色缺少约会演出资料")
		if has_failed_invite_today(character_id):
			return _validation(false, "今天已经邀请过该角色")
		if _topic_manager == null or not _topic_manager.can_auto_generate_llm():
			return _validation(false, "LinkChat LLM 当前不可用")
	if _avg_generator == null or not bool(_avg_generator.call("is_available")):
		return _validation(false, "AVG LLM 当前不可用")
	return _validation(true, "")


func start_solo_outing(activity_id: String) -> bool:
	var validation: Dictionary = validate_start(activity_id, MODE_SOLO)
	if not bool(validation.get("ok", false)):
		return false
	var activity: OutingActivity = get_activity(activity_id)
	_create_session(activity, MODE_SOLO, "")
	if not _reserve_current_transaction(activity.solo_cost, activity.duration_slots):
		_clear_session()
		return false
	_acquire_stage_lock("generating")
	_start_avg_generation()
	return true


func start_date_outing(activity_id: String, character_id: String) -> bool:
	var validation: Dictionary = validate_start(activity_id, MODE_DATE, character_id)
	if not bool(validation.get("ok", false)):
		return false
	var activity: OutingActivity = get_activity(activity_id)
	_create_session(activity, MODE_DATE, character_id)
	if not _reserve_current_transaction(activity.date_cost, activity.duration_slots):
		_clear_session()
		return false
	_roll_invitation(activity, character_id)
	_acquire_stage_lock("inviting")
	_open_linkchat(character_id)
	return _start_invitation_topic()


func retry_failed_stage() -> bool:
	var session: Dictionary = GameState.active_outing_session
	if session.is_empty() or str(session.get("status", "")) != "failed":
		return false
	var failed_stage: String = str(session.get("failed_stage", ""))
	session["error"] = ""
	match failed_stage:
		"invite":
			session["status"] = "inviting"
			_sync_session()
			_acquire_stage_lock("inviting")
			_open_linkchat(str(session.get("character_id", "")))
			return _start_invitation_topic()
		"generation":
			session["status"] = "generating"
			_sync_session()
			_acquire_stage_lock("generating")
			_start_avg_generation()
			return true
		"avg":
			session["status"] = "playing_avg"
			_sync_session()
			_acquire_stage_lock("playing_avg")
			return _play_pending_avg()
		"feedback":
			session["status"] = "feedback"
			_sync_session()
			_acquire_stage_lock("feedback")
			_open_linkchat(str(session.get("character_id", "")))
			return _start_feedback_topic()
	return false


func _connect_dependencies() -> void:
	var story_director: Node = get_node_or_null("/root/StoryDirector")
	if story_director != null and story_director.has_method("get_topic_manager"):
		_topic_manager = story_director.call("get_topic_manager") as TopicManager
	if _topic_manager != null:
		if not _topic_manager.topic_completed.is_connected(_on_topic_completed):
			_topic_manager.topic_completed.connect(_on_topic_completed)
		if not _topic_manager.topic_cancelled.is_connected(_on_topic_cancelled):
			_topic_manager.topic_cancelled.connect(_on_topic_cancelled)
	if not TransitManager.transit_finished.is_connected(_on_transit_finished):
		TransitManager.transit_finished.connect(_on_transit_finished)
	if not TransitManager.transit_cancelled.is_connected(_on_transit_cancelled):
		TransitManager.transit_cancelled.connect(_on_transit_cancelled)


func _create_session(activity: OutingActivity, mode: String, character_id: String) -> void:
	var serial: int = GameState.outing_history.size() + 1
	var session_id: String = "outing_d%03d_s%d_%03d" % [GameState.day, GameState.time_slot, serial]
	GameState.active_outing_session = {
		"session_id": session_id,
		"transaction_id": "action_%s" % session_id,
		"activity_id": activity.activity_id,
		"place_id": activity.place_id,
		"mode": mode,
		"character_id": character_id,
		"day_started": GameState.day,
		"slot_started": GameState.time_slot,
		"status": "created",
		"failed_stage": "",
		"error": "",
		"effects_applied": false,
	}
	_sync_session()


func _reserve_current_transaction(cost: int, time_slots: int) -> bool:
	var session: Dictionary = GameState.active_outing_session
	return ActionTransactionManager.reserve(
		str(session.get("transaction_id", "")),
		LOCK_OWNER,
		cost,
		time_slots
	)


func _roll_invitation(activity: OutingActivity, character_id: String) -> void:
	var character: CharacterProfile = LinkChatManager.get_character(character_id)
	GameState.init_relationship(character)
	var relationship: Dictionary = GameState.get_relationship(character_id)
	var relationship_modifier: int = int(round(
		float(relationship.get("favor", 0)) * 0.25 \
		+ float(relationship.get("trust", 0)) * 0.35
	))
	var preference_modifier: int = 0
	for tag: String in activity.tags:
		if tag in character.outing_preference_tags:
			preference_modifier += 8
		if tag in character.outing_avoid_tags:
			preference_modifier -= 10
	var threshold: int = clampi(
		activity.base_acceptance + character.base_date_acceptance_modifier \
		+ relationship_modifier + preference_modifier,
		5,
		95
	)
	var seed_source: String = "%d:%d:%s:%s" % [GameState.day, GameState.time_slot, activity.activity_id, character_id]
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(seed_source.hash())
	var roll: int = rng.randi_range(1, 100)
	GameState.active_outing_session["invitation"] = {
		"seed": rng.seed,
		"roll": roll,
		"threshold": threshold,
		"relationship_modifier": relationship_modifier,
		"preference_modifier": preference_modifier,
		"accepted": roll <= threshold,
	}
	_sync_session()


func _build_invitation_location_card_message(activity: OutingActivity, place: MapPlace) -> String:
	var cost_text: String = "免费" if activity.date_cost <= 0 else "约会合计 ¥%d" % activity.date_cost
	return "player: [card:location|%s|%s|%s|%s|%s]" % [
		activity.activity_id,
		activity.place_id,
		activity.title,
		place.display_name if place != null else activity.place_id,
		cost_text,
	]


func _build_invitation_conversation_context(channel_id: String) -> String:
	var messages: Array[Dictionary] = LinkChatManager.get_thread_messages(channel_id)
	if messages.is_empty():
		return "当前私聊没有历史消息。这次邀约是该会话的开场。"

	var recent_messages: Array[Dictionary] = []
	var start_index: int = maxi(0, messages.size() - 12)
	for index: int in range(start_index, messages.size()):
		var message: Dictionary = messages[index]
		var history_entry: Dictionary = {
			"sender_id": str(message.get("sender_id", "")),
			"content": str(message.get("content", "")),
		}
		var attachment_value: Variant = message.get("attachment", {})
		if attachment_value is Dictionary and not (attachment_value as Dictionary).is_empty():
			history_entry["attachment"] = (attachment_value as Dictionary).duplicate(true)
		recent_messages.append(history_entry)
	return "当前私聊已有历史消息。以下是最近消息，按原顺序排列：\n%s" % JSON.stringify(recent_messages, "  ")


func _build_invitation_conversation_structure(accepted: bool, invited_speaker_id: String) -> String:
	if accepted:
		return """1. `player` 发送唯一一轮邀约：连续 2 至 3 个气泡，其中包含简短邀请文字和指定地点卡片，并在这一轮内完整表达“一起参加本次活动”的意图。
2. `%s` 发送唯一一轮回复：连续 1 至 2 个气泡，直接、正面地接受邀请。
3. 回复后立即输出 `END accepted`，不再追加任何消息。""" % invited_speaker_id
	return """1. `player` 发送唯一一轮邀约：连续 2 至 3 个气泡，其中包含简短邀请文字和指定地点卡片，并在这一轮内完整表达“一起参加本次活动”的意图。
2. `%s` 发送唯一一轮回复：连续 1 至 2 个气泡，明确拒绝邀请。
3. `player` 发送 1 个简短气泡回应这次拒绝。
4. 立即输出 `END rejected`，不再追加任何消息。""" % invited_speaker_id


func _start_invitation_topic() -> bool:
	if _topic_manager == null:
		_fail("invite", "TopicManager 不可用")
		return false
	var session: Dictionary = GameState.active_outing_session
	var activity: OutingActivity = get_activity(str(session.get("activity_id", "")))
	var place: MapPlace = get_place(str(session.get("place_id", "")))
	var character: CharacterProfile = LinkChatManager.get_character(str(session.get("character_id", "")))
	var invitation: Dictionary = session.get("invitation", {}) as Dictionary
	var accepted: bool = bool(invitation.get("accepted", false))
	var expected_result: String = "accepted" if accepted else "rejected"
	var topic: ChatTopic = ChatTopicClass.new()
	topic.topic_id = "%s_invite_%d" % [str(session.get("session_id", "")), Time.get_ticks_msec()]
	topic.channel_id = character.character_id
	topic.mode = ChatTopic.Mode.LLM
	topic.auto_advance = true
	topic.prompt = _resolve_outing_prompt(INVITATION_PROMPT_KEY, {
		"player_profile": _player_prompt(),
		"invited_display_name": character.display_name,
		"invited_persona": character.persona_prompt,
		"activity_title": activity.title,
		"place_name": place.display_name if place != null else activity.place_id,
		"location_card_message": _build_invitation_location_card_message(activity, place),
		"conversation_context": _build_invitation_conversation_context(character.character_id),
		"conversation_structure": _build_invitation_conversation_structure(accepted, character.character_id),
		"authoritative_result": "接受邀约" if accepted else "拒绝邀约",
		"invited_speaker_id": character.character_id,
		"expected_result": expected_result,
	})
	if topic.prompt.is_empty():
		_fail("invite", "邀约 Prompt 模板不可用")
		return false
	session["topic_id"] = topic.topic_id
	session["invitation_topic_id"] = topic.topic_id
	session["status"] = "inviting"
	_sync_session()
	var allowed_speakers: Array[String] = []
	allowed_speakers.append(character.character_id)
	return _topic_manager.activate_topic(topic, {
		"outing": _session_prompt_snapshot(),
		"authoritative_result": expected_result,
	}, allowed_speakers)


func _start_avg_generation() -> void:
	var session: Dictionary = GameState.active_outing_session
	var activity: OutingActivity = get_activity(str(session.get("activity_id", "")))
	if activity == null:
		_fail("generation", "活动资源不存在")
		return
	var character: CharacterProfile = LinkChatManager.get_character(str(session.get("character_id", "")))
	var context_vars: Dictionary = {
		"player_profile": _player_prompt(),
		"companion_profile": character.persona_prompt if character != null else "",
		"relationship": JSON.stringify(GameState.get_relationship(character.character_id)) if character != null else "{}",
		"invitation_transcript": str(session.get("invitation_transcript", "")),
	}
	var context_key: String = AVG_SOLO_CONTEXT_PROMPT_KEY if str(session.get("mode", "")) == MODE_SOLO else AVG_DATE_CONTEXT_PROMPT_KEY
	var setting_context: String = _resolve_outing_prompt(context_key, context_vars)
	var constraints: String = _resolve_outing_prompt(AVG_CONSTRAINTS_PROMPT_KEY)
	var guidance: String = _resolve_outing_prompt(AVG_GUIDANCE_PROMPT_KEY)
	if setting_context.is_empty() or constraints.is_empty() or guidance.is_empty():
		_fail("generation", "外出 AVG Prompt 模板不可用")
		return
	_pending_scene_package.clear()
	_active_transit_id = TransitManager.play_gated_transit({
		"id": "%s_transit" % str(session.get("session_id", "")),
		"window_title": "正在出发",
		"title": "前往 %s" % activity.title,
		"activity": "outing",
		"minimum_duration": 3.2,
	})
	if _active_transit_id.is_empty():
		_fail("generation", "无法开始行程转场")
		return
	session["status"] = "generating"
	_sync_session()
	var prompt: String = activity.solo_scene_prompt if str(session.get("mode", "")) == MODE_SOLO else activity.date_scene_prompt
	var generation_session: Dictionary = {
		"title": activity.title,
		"scene_prompt": prompt,
		"setting_context": setting_context,
		"constraints": constraints,
		"story_guidance_prompt": guidance,
		"scene_id_prefix": "outing",
		"scene_window_title": activity.title,
	}
	if not bool(_avg_generator.call("generate_for_session", str(session.get("session_id", "")), generation_session)):
		TransitManager.cancel_transit(_active_transit_id)
		_active_transit_id = ""
		_fail("generation", "AVG LLM 请求未能启动")


func _on_scene_generated(session_id: String, package: Dictionary) -> void:
	var session: Dictionary = GameState.active_outing_session
	if str(session.get("session_id", "")) != session_id or str(session.get("status", "")) != "generating":
		return
	_pending_scene_package = package.duplicate(true)
	if not ActionTransactionManager.commit(str(session.get("transaction_id", ""))):
		if not _active_transit_id.is_empty():
			TransitManager.cancel_transit(_active_transit_id)
			_active_transit_id = ""
		_fail("generation", "时段与费用提交失败")
		return
	session["status"] = "transit_ready"
	_sync_session()
	TransitManager.mark_transit_ready(_active_transit_id)


func _on_scene_failed(session_id: String, error: String) -> void:
	if str(GameState.active_outing_session.get("session_id", "")) != session_id:
		return
	if not _active_transit_id.is_empty() and TransitManager.has_active_transit():
		TransitManager.cancel_transit(_active_transit_id)
	_active_transit_id = ""
	_fail("generation", error)


func _on_transit_finished(transit_id: String, _payload: Dictionary) -> void:
	if transit_id != _active_transit_id:
		return
	_active_transit_id = ""
	if str(GameState.active_outing_session.get("status", "")) == "transit_ready":
		_play_pending_avg()


func _on_transit_cancelled(transit_id: String, _payload: Dictionary) -> void:
	if transit_id == _active_transit_id:
		_active_transit_id = ""


func _play_pending_avg() -> bool:
	if _pending_scene_package.is_empty():
		_fail("avg", "动态 AVG 场景包不存在")
		return false
	_acquire_stage_lock("playing_avg")
	var window: Control = AppManager.focus_app(AVG_APP_ID, true)
	if window == null:
		_fail("avg", "无法打开 AVG 播放器")
		return false
	var players: Array[Node] = window.find_children("*", "AVGPlayer", true, false)
	if players.is_empty():
		_fail("avg", "AVG 播放器节点不存在")
		return false
	var player: Node = players[0]
	var callback := Callable(self, "_on_avg_playback_finished")
	if not player.playback_finished.is_connected(callback):
		player.playback_finished.connect(callback)
	GameState.active_outing_session["status"] = "playing_avg"
	_sync_session()
	player.call("play_scene_package", str(GameState.active_outing_session.get("session_id", "")), _pending_scene_package)
	return true


func _on_avg_playback_finished(session_id: String, outcome: Dictionary) -> void:
	var session: Dictionary = GameState.active_outing_session
	if str(session.get("session_id", "")) != session_id:
		return
	AppManager.close_app(AVG_APP_ID, true)
	if not bool(outcome.get("success", false)):
		_fail("avg", str(outcome.get("error", "AVG 播放失败")))
		return
	session["avg_outcome"] = outcome.duplicate(true)
	session["avg_narrative_text"] = str(outcome.get("narrative_text", "")).strip_edges()
	_apply_effects_once()
	if str(session.get("mode", "")) == MODE_DATE:
		_acquire_stage_lock("feedback")
		_open_linkchat(str(session.get("character_id", "")))
		_start_feedback_topic()
	else:
		_complete_session()


func _start_feedback_topic() -> bool:
	if _topic_manager == null:
		_fail("feedback", "TopicManager 不可用")
		return false
	var session: Dictionary = GameState.active_outing_session
	var character: CharacterProfile = LinkChatManager.get_character(str(session.get("character_id", "")))
	var activity: OutingActivity = get_activity(str(session.get("activity_id", "")))
	var topic: ChatTopic = ChatTopicClass.new()
	topic.topic_id = "%s_feedback_%d" % [str(session.get("session_id", "")), Time.get_ticks_msec()]
	topic.channel_id = character.character_id
	topic.mode = ChatTopic.Mode.LLM
	topic.auto_advance = true
	topic.prompt = _resolve_outing_prompt(FEEDBACK_PROMPT_KEY, {
		"character_display_name": character.display_name,
		"character_persona": character.persona_prompt,
		"activity_title": activity.title,
		"avg_narrative_text": str(session.get("avg_narrative_text", "")),
		"choice_text": str((session.get("avg_outcome", {}) as Dictionary).get("choice_text", "")),
		"character_speaker_id": character.character_id,
	})
	if topic.prompt.is_empty():
		_fail("feedback", "返程寒暄 Prompt 模板不可用")
		return false
	session["topic_id"] = topic.topic_id
	session["status"] = "feedback"
	_sync_session()
	var allowed_speakers: Array[String] = []
	allowed_speakers.append(character.character_id)
	return _topic_manager.activate_topic(topic, {
		"outing": _session_prompt_snapshot(),
		"avg_narrative_text": session.get("avg_narrative_text", ""),
		"choice_text": str((session.get("avg_outcome", {}) as Dictionary).get("choice_text", "")),
	}, allowed_speakers)


func _on_topic_completed(topic: Resource, _result: Dictionary) -> void:
	var session: Dictionary = GameState.active_outing_session
	if session.is_empty() or topic == null or str(topic.topic_id) != str(session.get("topic_id", "")):
		return
	match str(session.get("status", "")):
		"inviting":
			session["invitation_transcript"] = LinkChatManager.get_topic_transcript(str(topic.topic_id))
			_sync_session()
			var invitation: Dictionary = session.get("invitation", {}) as Dictionary
			if bool(invitation.get("accepted", false)):
				_acquire_stage_lock("generating")
				_start_avg_generation()
			else:
				_record_failed_invite(str(session.get("character_id", "")))
				ActionTransactionManager.cancel(str(session.get("transaction_id", "")))
				session["status"] = "rejected"
				_complete_session()
		"feedback":
			_complete_session()


func _on_topic_cancelled(topic: Resource, reason: String) -> void:
	var session: Dictionary = GameState.active_outing_session
	if session.is_empty() or topic == null or str(topic.topic_id) != str(session.get("topic_id", "")):
		return
	var failed_stage: String = "feedback" if str(session.get("status", "")) == "feedback" else "invite"
	_fail(failed_stage, reason)


func _apply_effects_once() -> void:
	var session: Dictionary = GameState.active_outing_session
	if bool(session.get("effects_applied", false)):
		return
	var activity: OutingActivity = get_activity(str(session.get("activity_id", "")))
	if activity == null:
		return
	GameState.adjust_attribute(GameState.ATTR_STRESS, activity.stress_delta)
	GameState.adjust_attribute(GameState.ATTR_LONELINESS, activity.loneliness_delta)
	if str(session.get("mode", "")) == MODE_DATE:
		GameState.change_relationship(
			str(session.get("character_id", "")),
			activity.relationship_favor_gain,
			activity.relationship_trust_gain,
			0
		)
	session["effects_applied"] = true
	_sync_session()


func _record_failed_invite(character_id: String) -> void:
	var day_key: String = str(GameState.day)
	var failed: Array[String] = []
	var current_value: Variant = GameState.failed_date_invites.get(day_key, [])
	if current_value is Array:
		for value: Variant in current_value:
			var normalized_id: String = str(value).strip_edges()
			if not normalized_id.is_empty() and normalized_id not in failed:
				failed.append(normalized_id)
	if character_id not in failed:
		failed.append(character_id)
	GameState.failed_date_invites[day_key] = failed


func _complete_session() -> void:
	var snapshot: Dictionary = GameState.active_outing_session.duplicate(true)
	snapshot["completed_at"] = int(Time.get_unix_time_from_system())
	GameState.outing_history.append(snapshot)
	StoryLockManager.release_lock(LOCK_OWNER)
	GameState.active_outing_session.clear()
	_pending_scene_package.clear()
	_active_transit_id = ""
	session_completed.emit(snapshot)
	session_changed.emit({})


func _fail(stage: String, error: String) -> void:
	if GameState.active_outing_session.is_empty():
		return
	GameState.active_outing_session["status"] = "failed"
	GameState.active_outing_session["failed_stage"] = stage
	GameState.active_outing_session["error"] = error
	_acquire_stage_lock("failed")
	var snapshot: Dictionary = get_active_session()
	session_failed.emit(stage, error, snapshot)
	session_changed.emit(snapshot)
	AppManager.focus_app(MAP_APP_ID, true)


func _acquire_stage_lock(stage: String) -> void:
	var protected_apps: Array[String] = []
	match stage:
		"inviting", "feedback":
			protected_apps = [LINKCHAT_APP_ID]
		"playing_avg":
			protected_apps = [AVG_APP_ID]
		"failed":
			protected_apps = [MAP_APP_ID]
	StoryLockManager.acquire_lock(LOCK_OWNER, {
		"block_time_actions": true,
		"restrict_apps": true,
		"allowed_apps": [MAP_APP_ID, LINKCHAT_APP_ID, AVG_APP_ID],
		"protected_apps": protected_apps,
		"reason": _stage_reason(stage),
	})


func _stage_reason(stage: String) -> String:
	match stage:
		"inviting": return "邀约消息尚未结束"
		"generating": return "正在生成本次外出剧情"
		"playing_avg": return "外出剧情尚未结束"
		"feedback": return "返程消息尚未结束"
		"failed": return "外出剧情生成失败，请先重试"
	return "外出剧情尚未结束"


func _open_linkchat(channel_id: String) -> void:
	var window: Control = AppManager.focus_app(LINKCHAT_APP_ID, true)
	if window == null:
		return
	var content: Node = window.get("content") as Node
	if content != null and content.has_method("open_topic_channel"):
		content.call_deferred("open_topic_channel", channel_id)


func _player_prompt() -> String:
	var player: CharacterProfile = LinkChatManager.get_player_character()
	if player == null:
		return "player"
	return "%s。%s" % [player.display_name, player.persona_prompt]


func _resolve_outing_prompt(key: String, variables: Dictionary = {}) -> String:
	if not PromptManager.has_prompt(key):
		push_error("OutingManager: prompt key '%s' not found" % key)
		return ""
	return PromptManager.resolve_with_vars(key, variables).strip_edges()


func _session_prompt_snapshot() -> Dictionary:
	var session: Dictionary = GameState.active_outing_session
	return {
		"session_id": session.get("session_id", ""),
		"activity_id": session.get("activity_id", ""),
		"place_id": session.get("place_id", ""),
		"mode": session.get("mode", ""),
		"character_id": session.get("character_id", ""),
		"invitation": session.get("invitation", {}),
	}


func _sync_session() -> void:
	session_changed.emit(get_active_session())


func _clear_session() -> void:
	StoryLockManager.release_lock(LOCK_OWNER)
	GameState.active_outing_session.clear()
	_pending_scene_package.clear()
	_active_transit_id = ""
	session_changed.emit({})


func _validation(ok: bool, reason: String) -> Dictionary:
	return {"ok": ok, "reason": reason}
