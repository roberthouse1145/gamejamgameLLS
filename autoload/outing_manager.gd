extends Node
## 通用外出活动编排器。MAP 只是调用方，判定、事务与剧情链路均在此处。

signal session_changed(snapshot: Dictionary)
signal session_failed(stage: String, error: String, snapshot: Dictionary)
signal session_completed(snapshot: Dictionary)

const CATALOG: OutingCatalog = preload("res://resources/outing/outing_catalog.tres")
const ChatTopicClass = preload("res://scripts/chat/resources/chat_topic.gd")
const AVGSceneGeneratorClass = preload("res://scripts/avg/generation/avg_scene_generator.gd")
const PostDSLParserClass = preload("res://scripts/social/post_dsl_parser.gd")

const MODE_SOLO: String = "solo"
const MODE_DATE: String = "date"
const LOCK_OWNER: String = "outing_session"
const MAP_APP_ID: String = "cityhop"
const LINKCHAT_APP_ID: String = "linkchat"
const LINKPOSTA_APP_ID: String = "linkposta"
const BROWSER_APP_ID: String = "browser"
const AVG_APP_ID: String = "avg_player"
const INVITATION_PROMPT_KEY: String = "outing/invitation"
const POST_PROMPT_KEY: String = "outing/posts"
const POST_WRITER_ROLE: String = "outing_post_writer"
const AVG_SOLO_CONTEXT_PROMPT_KEY: String = "outing/avg_solo_context"
const AVG_DATE_CONTEXT_PROMPT_KEY: String = "outing/avg_date_context"
const AVG_SOLO_RUNTIME_CONTEXT_PROMPT_KEY: String = "outing/avg_solo_runtime_context"
const AVG_DATE_RUNTIME_CONTEXT_PROMPT_KEY: String = "outing/avg_date_runtime_context"
const AVG_CONSTRAINTS_PROMPT_KEY: String = "outing/avg_constraints"
const AVG_GUIDANCE_PROMPT_KEY: String = "outing/avg_guidance"
const RECENT_OUTING_LIMIT: int = 2
const RECENT_OUTING_TEXT_LIMIT: int = 500
const POST_SETTLEMENT_DELAY_SECONDS: float = 2.0
const POST_MAX_ATTEMPTS: int = 2

var _topic_manager: TopicManager = null
var _avg_generator: Node = null
var _post_service: AIService = null
var _post_service_ready: bool = false
var _post_parser: RefCounted = PostDSLParserClass.new()
var _post_jobs_by_session: Dictionary = {}
var _post_request_context_by_id: Dictionary = {}
var _pending_scene_package: Dictionary = {}
var _active_transit_id: String = ""


func _ready() -> void:
	_avg_generator = AVGSceneGeneratorClass.new()
	_avg_generator.name = "OutingAVGGenerator"
	add_child(_avg_generator)
	_avg_generator.scene_generated.connect(_on_scene_generated)
	_avg_generator.scene_failed.connect(_on_scene_failed)
	_setup_post_service()
	call_deferred("_connect_dependencies")


func get_catalog() -> OutingCatalog:
	return CATALOG


func get_activity(activity_id: String) -> OutingActivity:
	return CATALOG.get_activity(activity_id)


func get_place(place_id: String) -> MapPlace:
	return CATALOG.get_place(place_id)


func get_available_activities() -> Array[OutingActivity]:
	return CATALOG.get_available_activities(GameState.day, GameState.time_slot)


func get_daily_activities() -> Array[OutingActivity]:
	return CATALOG.get_daily_activities(GameState.day)


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


func validate_action_availability(activity_id: String, mode: String) -> Dictionary:
	if has_active_session():
		return _validation(false, "请先完成正在进行的外出")
	var activity: OutingActivity = get_activity(activity_id)
	if activity == null or not activity.is_valid():
		return _validation(false, "活动不存在")
	if activity not in get_daily_activities():
		return _validation(false, "今天没有安排这项活动")
	if mode == MODE_SOLO and not activity.supports_solo:
		return _validation(false, "这项活动不支持单人前往")
	if mode == MODE_DATE and not activity.supports_date:
		return _validation(false, "这项活动不支持邀请好友")
	if mode not in [MODE_SOLO, MODE_DATE]:
		return _validation(false, "未知的出行方式")
	if not activity.is_available(GameState.day, GameState.time_slot):
		return _validation(false, _activity_schedule_reason(activity))
	var cost: int = activity.solo_cost if mode == MODE_SOLO else activity.date_cost
	if GameState.money < cost:
		return _validation(false, "余额不足，还差 ¥%d" % (cost - GameState.money))
	if mode == MODE_DATE and get_datable_friends(activity_id).is_empty():
		return _validation(false, "当前没有可以邀请的好友")
	return _validation(true, "")


func validate_start(activity_id: String, mode: String, character_id: String = "") -> Dictionary:
	var availability: Dictionary = validate_action_availability(activity_id, mode)
	if not bool(availability.get("ok", false)):
		return availability
	var activity: OutingActivity = get_activity(activity_id)
	if mode == MODE_DATE:
		var character: CharacterProfile = LinkChatManager.get_character(character_id)
		if character == null or not character.datable or not LinkChatManager.is_friend(character_id):
			return _validation(false, "该角色当前不可邀请")
		if character.avg_character == null or character.linkchat_profile == null:
			return _validation(false, "该角色缺少约会演出资料")
		if has_failed_invite_today(character_id):
			return _validation(false, "今天已经邀请过该角色")
		if _topic_manager == null or not _topic_manager.can_auto_generate_llm():
			return _validation(false, "邀约消息暂时无法发送，请稍后再试")
	if _avg_generator == null or not bool(_avg_generator.call("is_available")):
		return _validation(false, "外出剧情暂时无法准备，请稍后再试")
	if not _post_service_ready or _post_service == null:
		return _validation(false, "外出后的动态暂时无法生成，请稍后再试")
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
		"posts":
			session["status"] = "publishing_posts"
			_sync_session()
			_acquire_stage_lock("publishing_posts")
			_post_jobs_by_session.erase(str(session.get("session_id", "")))
			_start_outing_post_prefetch()
			return _authorize_outing_post_publication(str(session.get("session_id", "")))
		"settlement":
			return _complete_session()
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
	if not SocialMediaManager.post_presentation_completed.is_connected(_on_post_presentation_completed):
		SocialMediaManager.post_presentation_completed.connect(_on_post_presentation_completed)


func _setup_post_service() -> void:
	_post_service = AIService.new()
	_post_service.name = "OutingPostWriter"
	add_child(_post_service)
	_post_service.request_completed.connect(_on_post_request_completed)
	_post_service.request_failed.connect(_on_post_request_failed)
	var config_manager := AIConfigManager.get_instance()
	_post_service_ready = config_manager.apply_to_service(_post_service, POST_WRITER_ROLE)
	if not _post_service_ready:
		_post_service_ready = config_manager.apply_to_service(_post_service, "chat_default")


func _start_outing_post_prefetch() -> void:
	if not _post_service_ready or _post_service == null:
		push_warning("OutingManager: LinkPosta post writer is unavailable")
		return
	var session: Dictionary = GameState.active_outing_session
	var session_id: String = str(session.get("session_id", "")).strip_edges()
	if session_id.is_empty():
		return
	var existing_job: Dictionary = _post_jobs_by_session.get(session_id, {}) as Dictionary
	if str(existing_job.get("state", "")) in ["requesting", "ready", "published"]:
		return
	var accounts: Array[Dictionary] = _build_outing_post_accounts(session)
	if accounts.is_empty():
		push_warning("OutingManager: no LinkPosta account is available for %s" % session_id)
		return
	var activity: OutingActivity = get_activity(str(session.get("activity_id", "")))
	_post_jobs_by_session[session_id] = {
		"session_id": session_id,
		"state": "requesting",
		"authorized": false,
		"accounts": accounts,
		"posts_by_account": {},
		"posts": [],
	}
	_post_service.max_concurrent_requests = maxi(_post_service.max_concurrent_requests, accounts.size())
	for account: Dictionary in accounts:
		var account_id: String = str(account.get("account_id", "")).strip_edges()
		var prompt: String = _resolve_outing_prompt(POST_PROMPT_KEY, {
			"activity_title": activity.title if activity != null else "外出",
			"target_account": _build_post_account_prompt([account]),
			"current_identity_policy": _build_post_identity_policy(account),
			"registered_comment_accounts": _build_post_comment_account_prompt(accounts, account_id),
			"outing_scene_outline": str(_pending_scene_package.get("scene_outline", "")).strip_edges(),
		})
		if prompt.is_empty():
			_handle_post_job_failure(session_id, "LinkPosta 动态提示词不可用")
			return
		if not _request_outing_post(session_id, account_id, prompt, 1):
			_handle_post_job_failure(session_id, "LinkPosta 动态请求未能启动")
			return


func _request_outing_post(
	session_id: String,
	account_id: String,
	prompt: String,
	attempt: int
) -> bool:
	var request_id: String = _post_service.chat([{"role": "system", "content": prompt}], {
			"temperature": 1.0,
			"max_tokens": 1024,
			"thinking": "disabled",
			"enable_thinking": false,
			"reasoning_effort": "",
			"prompt_key": POST_PROMPT_KEY,
		})
	if request_id.is_empty():
		return false
	_post_request_context_by_id[request_id] = {
		"session_id": session_id,
		"account_id": account_id,
		"prompt": prompt,
		"attempt": attempt,
	}
	return true


func _build_outing_post_accounts(session: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var player: CharacterProfile = LinkChatManager.get_player_character()
	var player_account: SocialAccountProfile = SocialMediaManager.get_active_player_streamer_account()
	if player_account == null and player != null:
		player_account = SocialMediaManager.get_character_account(
			player.character_id,
			SocialAccountProfile.IDENTITY_STREAMER
		)
	if player_account == null and player != null:
		player_account = SocialMediaManager.get_character_account(
			player.character_id,
			SocialAccountProfile.IDENTITY_PERSONAL
		)
	_append_post_account_context(result, player, player_account)

	if str(session.get("mode", "")) == MODE_DATE:
		var companion: CharacterProfile = LinkChatManager.get_character(str(session.get("character_id", "")))
		var companion_account: SocialAccountProfile = null
		if companion != null:
			companion_account = SocialMediaManager.get_character_account(
				companion.character_id,
				SocialAccountProfile.IDENTITY_PERSONAL
			)
			if companion_account == null:
				companion_account = SocialMediaManager.get_character_account(
					companion.character_id,
					SocialAccountProfile.IDENTITY_STREAMER
				)
		_append_post_account_context(result, companion, companion_account)
	return result


func _append_post_account_context(
	result: Array[Dictionary],
	character: CharacterProfile,
	account: SocialAccountProfile
) -> void:
	if character == null or account == null or account.account_id.strip_edges().is_empty():
		return
	result.append({
		"account_id": account.account_id,
		"character_name": character.display_name,
		"display_name": account.get_resolved_display_name(),
		"handle": account.handle,
		"identity_type": account.identity_type,
		"bio": account.bio,
		"writing_persona": _post_writing_persona(character, account),
	})


func _post_writing_persona(character: CharacterProfile, account: SocialAccountProfile) -> String:
	if account.identity_type == SocialAccountProfile.IDENTITY_STREAMER \
		and account.streamer_persona != null:
		return """主播公开人设：
%s

扮演者的长期性格与表达习惯：
%s""" % [
			account.streamer_persona.prompt_fragment.strip_edges(),
			character.persona_prompt.strip_edges(),
		]
	return character.persona_prompt.strip_edges()


func _build_post_account_prompt(accounts: Array[Dictionary]) -> String:
	var blocks: Array[String] = []
	for account: Dictionary in accounts:
		blocks.append("""account_id: %s
character_name: %s
display_name: %s
handle: %s
identity_type: %s
bio: %s
writing_persona:
%s""" % [
			str(account.get("account_id", "")),
			str(account.get("character_name", "")),
			str(account.get("display_name", "")),
			str(account.get("handle", "")),
			str(account.get("identity_type", "")),
			str(account.get("bio", "")),
			str(account.get("writing_persona", "")),
		])
	return "\n\n".join(blocks)


func _build_post_comment_account_prompt(
	accounts: Array[Dictionary],
	target_account_id: String
) -> String:
	var lines: Array[String] = []
	var target_identity_type: String = ""
	for target_account: Dictionary in accounts:
		if str(target_account.get("account_id", "")) == target_account_id:
			target_identity_type = str(target_account.get("identity_type", ""))
			break
	for account: Dictionary in accounts:
		var account_id: String = str(account.get("account_id", "")).strip_edges()
		if account_id.is_empty() or account_id == target_account_id:
			continue
		# 主播公开身份不作为本次同行者私人帖的预设评论者，避免反向暴露私人联系。
		if target_identity_type == SocialAccountProfile.IDENTITY_PERSONAL \
			and str(account.get("identity_type", "")) == SocialAccountProfile.IDENTITY_STREAMER:
			continue
		lines.append(account_id)
	return "\n".join(lines) if not lines.is_empty() else "无"


func _build_post_identity_policy(account: Dictionary) -> String:
	if str(account.get("identity_type", "")) == SocialAccountProfile.IDENTITY_STREAMER:
		return """当前是主播公开账号。主播人设决定对外身份、公开边界和粉丝关系；扮演者的长期性格决定自然的用词、停顿、兴趣与反应。两者共同形成这个账号。可以省略或改写真实经过，也可以主动编一个自洽的公开说法；这个说法本身是角色经营身份的行动，不必逐句映射真实经过。守住现实恋爱关系、伴侣身份、私密空间和亲密行为，不让公开内容确认这些隐私。日常帖无需为了证明主播身份而硬加开播、设备或工作安排。""".strip_edges()
	return """当前是角色本人的个人账号。写她此刻愿意给个人社交圈看的东西；关系体验和私人感受可以出现，但是否直说、炫耀、抱怨或遮掩由人物性格与当下发帖动机决定。""".strip_edges()


func _on_post_request_completed(request_id: String, response: Dictionary) -> void:
	if not _post_request_context_by_id.has(request_id):
		return
	var request_context: Dictionary = _post_request_context_by_id[request_id] as Dictionary
	_post_request_context_by_id.erase(request_id)
	var session_id: String = str(request_context.get("session_id", ""))
	var account_id: String = str(request_context.get("account_id", ""))
	var job: Dictionary = _post_jobs_by_session.get(session_id, {}) as Dictionary
	if job.is_empty() or str(job.get("state", "")) != "requesting":
		return
	var parse_result: Dictionary = _post_parser.call(
		"parse",
		_strip_complete_code_fence(AIService.extract_content(response))
	) as Dictionary
	var account_contexts: Array[Dictionary] = []
	for account_value: Variant in job.get("accounts", []):
		if account_value is Dictionary \
			and str((account_value as Dictionary).get("account_id", "")) == account_id:
			account_contexts.append(account_value as Dictionary)
			break
	var validated_posts: Array[Dictionary] = _validate_generated_posts(parse_result, account_contexts)
	if validated_posts.is_empty():
		var attempt: int = int(request_context.get("attempt", 1))
		var prompt: String = str(request_context.get("prompt", ""))
		if attempt < POST_MAX_ATTEMPTS and not prompt.is_empty() \
			and _request_outing_post(session_id, account_id, prompt, attempt + 1):
			return
		var parse_errors: Array[String] = []
		parse_errors.assign(parse_result.get("errors", []))
		var error_summary: String = "动态内容未通过结构校验"
		if not parse_errors.is_empty():
			error_summary += "：" + "；".join(parse_errors)
		_handle_post_job_failure(session_id, error_summary)
		return
	var posts_by_account: Dictionary = job.get("posts_by_account", {}) as Dictionary
	posts_by_account[account_id] = validated_posts[0]
	job["posts_by_account"] = posts_by_account
	var accounts: Array[Dictionary] = []
	accounts.assign(job.get("accounts", []))
	if posts_by_account.size() >= accounts.size():
		var ordered_posts: Array[Dictionary] = []
		for account: Dictionary in accounts:
			var ordered_account_id: String = str(account.get("account_id", ""))
			if not posts_by_account.has(ordered_account_id):
				_handle_post_job_failure(session_id, "LinkPosta 动态汇总缺少账号 %s" % ordered_account_id)
				return
			ordered_posts.append((posts_by_account[ordered_account_id] as Dictionary).duplicate(true))
		job["posts"] = ordered_posts
		job["state"] = "ready"
	_post_jobs_by_session[session_id] = job
	if str(job.get("state", "")) == "ready" and bool(job.get("authorized", false)):
		_publish_outing_posts.call_deferred(session_id)


func _on_post_request_failed(request_id: String, error: String, _error_code: int) -> void:
	if not _post_request_context_by_id.has(request_id):
		return
	var request_context: Dictionary = _post_request_context_by_id[request_id] as Dictionary
	_post_request_context_by_id.erase(request_id)
	var session_id: String = str(request_context.get("session_id", ""))
	_handle_post_job_failure(session_id, error)


func _validate_generated_posts(payload: Variant, account_values: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not payload is Dictionary or not bool((payload as Dictionary).get("success", false)) \
		or not account_values is Array:
		return result
	var raw_posts: Variant = (payload as Dictionary).get("posts", [])
	if not raw_posts is Array or raw_posts.size() != account_values.size():
		return result
	var allowed_accounts: Dictionary = {}
	for account_value: Variant in account_values:
		if account_value is Dictionary:
			allowed_accounts[str((account_value as Dictionary).get("account_id", ""))] = true
	var seen_accounts: Dictionary = {}
	for value: Variant in raw_posts:
		if not value is Dictionary:
			result.clear()
			return result
		var post: Dictionary = value as Dictionary
		var account_id: String = str(post.get("account_id", "")).strip_edges()
		var text_content: String = str(post.get("text", "")).strip_edges()
		var media_mode: String = str(post.get("media_mode", "none"))
		var reach: String = str(post.get("reach", ""))
		var comments_value: Variant = post.get("comments", [])
		if not allowed_accounts.has(account_id) or seen_accounts.has(account_id) \
			or text_content.is_empty() or media_mode != PostDSLParserClass.MEDIA_NONE \
			or not PostDSLParserClass.REACH_VALUES.has(reach) \
			or not comments_value is Array or comments_value.is_empty():
			result.clear()
			return result
		for comment_value: Variant in comments_value:
			if not comment_value is Dictionary:
				result.clear()
				return result
			var comment: Dictionary = comment_value as Dictionary
			if str(comment.get("author_ref", "")).strip_edges().is_empty() \
				or str(comment.get("text", "")).strip_edges().is_empty():
				result.clear()
				return result
		seen_accounts[account_id] = true
		result.append(post.duplicate(true))
	return result


func _authorize_outing_post_publication(session_id: String) -> bool:
	var job: Dictionary = _post_jobs_by_session.get(session_id, {}) as Dictionary
	if job.is_empty():
		_fail("posts", "外出动态生成任务不存在")
		return false
	if str(job.get("state", "")) == "failed":
		_fail("posts", "外出动态生成失败")
		return false
	if AppManager.focus_app(LINKPOSTA_APP_ID, true) == null:
		_fail("posts", "无法打开 LinkPosta")
		return false
	job["authorized"] = true
	_post_jobs_by_session[session_id] = job
	if str(job.get("state", "")) == "ready":
		_publish_outing_posts.call_deferred(session_id)
	return true


func _publish_outing_posts(session_id: String) -> void:
	var job: Dictionary = _post_jobs_by_session.get(session_id, {}) as Dictionary
	if job.is_empty() or not bool(job.get("authorized", false)) \
		or str(job.get("state", "")) != "ready":
		return
	var post_values: Variant = job.get("posts", [])
	if not post_values is Array:
		return
	var published_post_ids: Array[String] = []
	for value: Variant in post_values:
		if not value is Dictionary:
			continue
		var post: Dictionary = value as Dictionary
		var account_id: String = str(post.get("account_id", ""))
		if SocialMediaManager.has_source_session_post(account_id, session_id):
			continue
		var comments: Array[Dictionary] = []
		comments.assign(post.get("comments", []))
		var published: SocialPostRecord = SocialMediaManager.publish_generated_post(
			account_id,
			str(post.get("text", "")),
			str(post.get("reach", PostDSLParserClass.REACH_NORMAL)),
			comments,
			session_id,
			true
		)
		if published != null:
			published_post_ids.append(published.post_id)
	if published_post_ids.is_empty():
		_fail("posts", "外出动态未能发布")
		return
	job["state"] = "published"
	job["post_ids"] = published_post_ids
	job["presented_post_ids"] = []
	_post_jobs_by_session[session_id] = job


func _on_post_presentation_completed(post: SocialPostRecord) -> void:
	if post == null or post.source_session_id.is_empty():
		return
	var session_id: String = post.source_session_id
	var session: Dictionary = GameState.active_outing_session
	if str(session.get("session_id", "")) != session_id:
		return
	var job: Dictionary = _post_jobs_by_session.get(session_id, {}) as Dictionary
	if str(job.get("state", "")) != "published":
		return
	var post_ids: Array[String] = []
	post_ids.assign(job.get("post_ids", []))
	if post.post_id not in post_ids:
		return
	var presented_post_ids: Array[String] = []
	presented_post_ids.assign(job.get("presented_post_ids", []))
	if post.post_id not in presented_post_ids:
		presented_post_ids.append(post.post_id)
	job["presented_post_ids"] = presented_post_ids
	_post_jobs_by_session[session_id] = job
	if presented_post_ids.size() >= post_ids.size():
		_begin_post_settlement_delay(session_id)


func _begin_post_settlement_delay(session_id: String) -> void:
	var job: Dictionary = _post_jobs_by_session.get(session_id, {}) as Dictionary
	if str(job.get("state", "")) != "published":
		return
	job["state"] = "settling"
	_post_jobs_by_session[session_id] = job
	GameState.active_outing_session["status"] = "post_settling"
	_sync_session()
	_acquire_stage_lock("post_settling")
	await get_tree().create_timer(POST_SETTLEMENT_DELAY_SECONDS).timeout
	_settle_completed_post_chain(session_id)


func _settle_completed_post_chain(session_id: String) -> bool:
	if str(GameState.active_outing_session.get("session_id", "")) != session_id:
		return false
	var completed: bool = _complete_session()
	if completed:
		_post_jobs_by_session.erase(session_id)
	return completed


func _handle_post_job_failure(session_id: String, error: String) -> void:
	_clear_post_request_contexts_for_session(session_id)
	var job: Dictionary = _post_jobs_by_session.get(session_id, {}) as Dictionary
	if not job.is_empty():
		job["state"] = "failed"
		_post_jobs_by_session[session_id] = job
	push_warning("OutingManager: LinkPosta post request failed for %s: %s" % [session_id, error])
	if str(GameState.active_outing_session.get("session_id", "")) == session_id \
		and str(GameState.active_outing_session.get("status", "")) == "publishing_posts":
		_fail("posts", error)


func _clear_post_request_contexts_for_session(session_id: String) -> void:
	var request_ids: Array = _post_request_context_by_id.keys()
	for request_id_value: Variant in request_ids:
		var request_id: String = str(request_id_value)
		var context: Dictionary = _post_request_context_by_id.get(request_id, {}) as Dictionary
		if str(context.get("session_id", "")) == session_id:
			_post_request_context_by_id.erase(request_id)


func _strip_complete_code_fence(text: String) -> String:
	var normalized: String = text.strip_edges()
	if not normalized.begins_with("```") or not normalized.ends_with("```"):
		return normalized
	var first_newline: int = normalized.find("\n")
	if first_newline < 0:
		return normalized
	return normalized.substr(first_newline + 1, normalized.length() - first_newline - 4).strip_edges()


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
	var threshold: int = clampi(
		activity.base_acceptance + character.base_date_acceptance_modifier \
		+ relationship_modifier,
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
		"accepted": roll <= threshold,
	}
	_sync_session()


func _build_invitation_location_card_message(activity: OutingActivity, _place: MapPlace) -> String:
	return "[card:location|%s]" % activity.activity_id


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
		var message_day: int = int(message.get("game_day", 0))
		if message_day > 0:
			history_entry["sent_at"] = GameState.get_game_time_text_for(
				message_day,
				int(message.get("time_slot", GameState.TIME_SLOT_MORNING))
			)
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
	return _topic_manager.activate_topic(topic, {}, allowed_speakers)


func _start_avg_generation() -> void:
	var session: Dictionary = GameState.active_outing_session
	var activity: OutingActivity = get_activity(str(session.get("activity_id", "")))
	if activity == null:
		_fail("generation", "活动资源不存在")
		return
	var character: CharacterProfile = LinkChatManager.get_character(str(session.get("character_id", "")))
	var context_vars: Dictionary = {
		"player_profile": _player_prompt(),
		"companion_name": character.display_name if character != null else "",
		"companion_profile": character.persona_prompt if character != null else "",
		"relationship": JSON.stringify(GameState.get_relationship(character.character_id)) if character != null else "{}",
		"invitation_transcript": str(session.get("invitation_transcript", "")),
		"recent_outings": _build_recent_outing_context(),
	}
	var context_key: String = AVG_SOLO_CONTEXT_PROMPT_KEY if str(session.get("mode", "")) == MODE_SOLO else AVG_DATE_CONTEXT_PROMPT_KEY
	var runtime_context_key: String = AVG_SOLO_RUNTIME_CONTEXT_PROMPT_KEY if str(session.get("mode", "")) == MODE_SOLO else AVG_DATE_RUNTIME_CONTEXT_PROMPT_KEY
	var setting_context: String = _resolve_outing_prompt(context_key, context_vars)
	var runtime_context: String = _resolve_outing_prompt(runtime_context_key, context_vars)
	var constraints: String = _resolve_outing_prompt(AVG_CONSTRAINTS_PROMPT_KEY)
	var guidance: String = _resolve_outing_prompt(AVG_GUIDANCE_PROMPT_KEY)
	if setting_context.is_empty() or runtime_context.is_empty() or constraints.is_empty() or guidance.is_empty():
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
	var prompt: String = _build_scene_prompt(activity, get_place(activity.place_id), str(session.get("mode", "")), character)
	var generation_session: Dictionary = {
		"title": activity.title,
		"scene_prompt": prompt,
		"setting_context": setting_context,
		"runtime_context": runtime_context,
		"constraints": constraints,
		"story_guidance_prompt": guidance,
		"scene_id_prefix": "outing",
		"scene_window_title": activity.title,
	}
	if not bool(_avg_generator.call("generate_for_session", str(session.get("session_id", "")), generation_session)):
		TransitManager.cancel_transit(_active_transit_id)
		_active_transit_id = ""
		_fail("generation", "AVG LLM 请求未能启动")


func _build_scene_prompt(
	activity: OutingActivity,
	place: MapPlace,
	mode: String,
	companion: CharacterProfile = null
) -> String:
	if activity == null:
		return ""
	var place_name: String = place.display_name if place != null else activity.place_id
	var companion_name: String = companion.display_name if companion != null else "同行角色"
	var participants: String = "玩家角色独自参加" if mode == MODE_SOLO else "玩家角色与%s同行" % companion_name
	return """## 已确定的外出内容
参与方式：%s
活动地点：%s
活动名称：%s
出发前计划：%s
现场事件引子：%s

## 本次场景目标
从抵达活动地点开始，让角色先进行原本计划的活动，再在过程中遇到事件引子。通过具体行动和对话确认现场情况、处理这次小变化并完成活动，最后在当前时段内自然散场。""" % [
		participants,
		place_name,
		activity.title,
		activity.description,
		activity.story_hook,
	]


func _build_recent_outing_context() -> String:
	var entries: Array[String] = []
	for index: int in range(GameState.outing_history.size() - 1, -1, -1):
		var snapshot: Dictionary = GameState.outing_history[index]
		var narrative: String = str(snapshot.get("avg_narrative_text", "")).strip_edges().replace("\n", " ")
		if narrative.is_empty():
			continue
		if narrative.length() > RECENT_OUTING_TEXT_LIMIT:
			narrative = narrative.substr(0, RECENT_OUTING_TEXT_LIMIT) + "……"
		var previous_activity: OutingActivity = get_activity(str(snapshot.get("activity_id", "")))
		var previous_title: String = previous_activity.title if previous_activity != null else "此前外出"
		entries.append("- %s：%s" % [previous_title, narrative])
		if entries.size() >= RECENT_OUTING_LIMIT:
			break
	if entries.is_empty():
		return "这是第一次有可参考记录的外出。"
	return "最近完成的外出如下，本次采用不同的具体插曲：\n%s" % "\n".join(entries)


func _on_scene_generated(session_id: String, package: Dictionary) -> void:
	var session: Dictionary = GameState.active_outing_session
	if str(session.get("session_id", "")) != session_id or str(session.get("status", "")) != "generating":
		return
	_pending_scene_package = package.duplicate(true)
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
	_start_outing_post_prefetch()
	return true


func _on_avg_playback_finished(session_id: String, outcome: Dictionary) -> void:
	var session: Dictionary = GameState.active_outing_session
	if str(session.get("session_id", "")) != session_id:
		return
	AppManager.close_app(AVG_APP_ID, true)
	if not bool(outcome.get("success", false)):
		_fail("avg", str(outcome.get("error", "AVG 播放失败")))
		return
	if _prepare_post_stage_after_avg(session_id, outcome):
		_authorize_outing_post_publication(session_id)


func _prepare_post_stage_after_avg(session_id: String, outcome: Dictionary) -> bool:
	var session: Dictionary = GameState.active_outing_session
	if str(session.get("session_id", "")) != session_id or not bool(outcome.get("success", false)):
		return false
	session["avg_outcome"] = outcome.duplicate(true)
	session["avg_narrative_text"] = str(outcome.get("narrative_text", "")).strip_edges()
	_apply_effects_once()
	session["status"] = "publishing_posts"
	_sync_session()
	_acquire_stage_lock("publishing_posts")
	return true


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
				_complete_session(false)


func _on_topic_cancelled(topic: Resource, reason: String) -> void:
	var session: Dictionary = GameState.active_outing_session
	if session.is_empty() or topic == null or str(topic.topic_id) != str(session.get("topic_id", "")):
		return
	_fail("invite", reason)


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


func _complete_session(commit_reserved_action: bool = true) -> bool:
	var session: Dictionary = GameState.active_outing_session
	if session.is_empty():
		return false
	if commit_reserved_action \
		and not ActionTransactionManager.commit(str(session.get("transaction_id", ""))):
		_fail("settlement", "外出结束，但时段与费用结算失败")
		return false
	var snapshot: Dictionary = GameState.active_outing_session.duplicate(true)
	snapshot["completed_at"] = int(Time.get_unix_time_from_system())
	GameState.outing_history.append(snapshot)
	StoryLockManager.release_lock(LOCK_OWNER)
	GameState.active_outing_session.clear()
	_pending_scene_package.clear()
	_active_transit_id = ""
	session_completed.emit(snapshot)
	session_changed.emit({})
	return true


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
		"inviting":
			protected_apps = [LINKCHAT_APP_ID]
		"playing_avg":
			protected_apps = [AVG_APP_ID]
		"publishing_posts", "post_settling":
			protected_apps = [BROWSER_APP_ID]
		"failed":
			protected_apps = [MAP_APP_ID]
	StoryLockManager.acquire_lock(LOCK_OWNER, {
		"block_time_actions": true,
		"restrict_apps": true,
		"allowed_apps": [MAP_APP_ID, LINKCHAT_APP_ID, LINKPOSTA_APP_ID, BROWSER_APP_ID, AVG_APP_ID],
		"protected_apps": protected_apps,
		"reason": _stage_reason(stage),
	})


func _stage_reason(stage: String) -> String:
	match stage:
		"inviting": return "邀约消息尚未结束"
		"generating": return "正在生成本次外出剧情"
		"playing_avg": return "外出剧情尚未结束"
		"publishing_posts": return "外出动态正在发布"
		"post_settling": return "外出动态正在更新"
		"failed": return "行程暂时中断，请从中断处继续"
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


func _activity_schedule_reason(activity: OutingActivity) -> String:
	if GameState.day < activity.available_from_day:
		return "第 %d 天起开放" % activity.available_from_day
	if GameState.day > activity.available_until_day:
		return "这项活动已经结束"
	var slot_names: PackedStringArray = []
	for slot: int in activity.available_slots:
		if slot >= 0 and slot < GameState.TIME_SLOT_NAMES.size():
			slot_names.append(GameState.TIME_SLOT_NAMES[slot])
	if slot_names.is_empty():
		return "当前没有开放时段"
	return "开放时段：%s" % "、".join(slot_names)
