class_name LiveStreamPostGenerator extends Node
## 直播 DSL 通过校验后预生成 LinkPosta 动态；直播提交成功后才发布。

signal post_prefetched(session_id: StringName, post: Dictionary)
signal post_prefetch_failed(session_id: StringName, error: String)
signal post_published(session_id: StringName, post: SocialPostRecord)

const PostDSLParserClass = preload("res://scripts/social/post_dsl_parser.gd")

const PROMPT_KEY: String = "live_stream/posts"
const POST_WRITER_ROLE: String = "live_stream_post_writer"
const MAX_ATTEMPTS: int = 2

var _post_service: AIService = null
var _post_service_ready: bool = false
var _post_parser: RefCounted = PostDSLParserClass.new()
var _jobs_by_session: Dictionary = {}
var _request_context_by_id: Dictionary = {}


func _ready() -> void:
	_post_service = AIService.new()
	_post_service.name = "LiveStreamPostWriter"
	add_child(_post_service)
	_post_service.request_completed.connect(_on_post_request_completed)
	_post_service.request_failed.connect(_on_post_request_failed)
	var config_manager := AIConfigManager.get_instance()
	if not config_manager.get_config_for_role(POST_WRITER_ROLE).is_empty():
		_post_service_ready = config_manager.apply_to_service(_post_service, POST_WRITER_ROLE)
	if not _post_service_ready:
		_post_service_ready = config_manager.apply_to_service(_post_service, "chat_default")


func prefetch(plan: StreamPlanSnapshot, show: Dictionary) -> bool:
	if plan == null or not _post_service_ready or _post_service == null:
		return false
	var session_id: String = String(plan.session_id).strip_edges()
	var dsl_text: String = str(show.get("dsl_text", "")).strip_edges()
	if session_id.is_empty() or dsl_text.is_empty():
		return false
	var existing_job: Dictionary = _jobs_by_session.get(session_id, {}) as Dictionary
	if str(existing_job.get("state", "")) in ["requesting", "ready", "published"]:
		return false
	var account: SocialAccountProfile = SocialMediaManager.get_active_player_streamer_account()
	if account == null or account.account_id.strip_edges().is_empty():
		_fail_job(session_id, "当前人设没有可用的 LinkPosta 主播账号")
		return false
	var prompt: String = _build_prompt(plan, show, account)
	if prompt.is_empty():
		_fail_job(session_id, "直播动态提示词不可用")
		return false
	_jobs_by_session[session_id] = {
		"session_id": session_id,
		"state": "requesting",
		"authorized": false,
		"account_id": account.account_id,
		"post": {},
	}
	if not _request_post(session_id, account.account_id, prompt, prompt, 1):
		_fail_job(session_id, "直播动态请求未能启动")
		return false
	return true


func authorize_publication(session_id: StringName) -> bool:
	var key: String = String(session_id).strip_edges()
	var job: Dictionary = _jobs_by_session.get(key, {}) as Dictionary
	if job.is_empty() or str(job.get("state", "")) == "failed":
		return false
	job["authorized"] = true
	_jobs_by_session[key] = job
	if str(job.get("state", "")) == "ready":
		_publish_post.call_deferred(key)
	return true


func cancel_session(session_id: StringName) -> void:
	var key: String = String(session_id).strip_edges()
	if key.is_empty():
		return
	_clear_request_contexts(key)
	_jobs_by_session.erase(key)


func get_job_snapshot(session_id: StringName) -> Dictionary:
	var job: Dictionary = _jobs_by_session.get(String(session_id), {}) as Dictionary
	return job.duplicate(true)


func _build_prompt(
	plan: StreamPlanSnapshot,
	show: Dictionary,
	account: SocialAccountProfile
) -> String:
	if not PromptManager.has_prompt(PROMPT_KEY):
		return ""
	var persona: StreamPersonaResource = account.streamer_persona
	var persona_prompt: String = ""
	if persona != null:
		persona_prompt = _resolve_prompt_fragment(persona.prompt_fragment)
	var title: String = str(show.get("title", plan.title)).strip_edges()
	return PromptManager.resolve_with_vars(PROMPT_KEY, {
		"target_account": _build_account_prompt(account, persona_prompt),
		"stream_title": title,
		"stream_dsl": str(show.get("dsl_text", "")).strip_edges(),
	}).strip_edges()


func _resolve_prompt_fragment(fragment: String) -> String:
	var normalized: String = fragment.strip_edges()
	if normalized.is_empty():
		return ""
	return PromptManager.resolve_template(normalized).strip_edges()


func _build_account_prompt(
	account: SocialAccountProfile,
	persona_prompt: String
) -> String:
	return """account_id: %s
display_name: %s
handle: %s
bio: %s
主播公开人设：
%s""" % [
		account.account_id,
		account.get_resolved_display_name(),
		account.handle,
		account.bio,
		persona_prompt,
	]


func _request_post(
	session_id: String,
	account_id: String,
	prompt: String,
	base_prompt: String,
	attempt: int
) -> bool:
	var request_id: String = _post_service.chat([{"role": "system", "content": prompt}], {
		"temperature": 1.0,
		"max_tokens": 1024,
		"thinking": "disabled",
		"enable_thinking": false,
		"reasoning_effort": "",
		"prompt_key": PROMPT_KEY,
	})
	if request_id.is_empty():
		return false
	_request_context_by_id[request_id] = {
		"session_id": session_id,
		"account_id": account_id,
		"base_prompt": base_prompt,
		"attempt": attempt,
	}
	return true


func _on_post_request_completed(request_id: String, response: Dictionary) -> void:
	if not _request_context_by_id.has(request_id):
		return
	var context: Dictionary = _request_context_by_id[request_id] as Dictionary
	_request_context_by_id.erase(request_id)
	var session_id: String = str(context.get("session_id", ""))
	var account_id: String = str(context.get("account_id", ""))
	var job: Dictionary = _jobs_by_session.get(session_id, {}) as Dictionary
	if job.is_empty() or str(job.get("state", "")) != "requesting":
		return
	var parsed: Dictionary = _post_parser.call(
		"parse", AIService.extract_content(response).strip_edges()
	) as Dictionary
	var validation: Dictionary = _validate_generated_post(parsed, account_id)
	if not bool(validation.get("success", false)):
		var attempt: int = int(context.get("attempt", 1))
		var base_prompt: String = str(context.get("base_prompt", ""))
		var errors: Array[String] = []
		errors.assign(validation.get("errors", []))
		if attempt < MAX_ATTEMPTS and not base_prompt.is_empty():
			var repair_prompt: String = base_prompt + (
				"\n\n## 本次输出未通过校验\n\n只修正这些已定位的问题并重新输出完整 POST 块：\n- "
				+ "\n- ".join(errors)
			)
			if _request_post(session_id, account_id, repair_prompt, base_prompt, attempt + 1):
				return
		_fail_job(session_id, "直播动态未通过结构校验：%s" % "；".join(errors))
		return
	var post: Dictionary = (validation.get("post", {}) as Dictionary).duplicate(true)
	job["post"] = post
	job["state"] = "ready"
	_jobs_by_session[session_id] = job
	post_prefetched.emit(StringName(session_id), post.duplicate(true))
	if bool(job.get("authorized", false)):
		_publish_post.call_deferred(session_id)


func _on_post_request_failed(request_id: String, error: String, _error_code: int) -> void:
	if not _request_context_by_id.has(request_id):
		return
	var context: Dictionary = _request_context_by_id[request_id] as Dictionary
	_request_context_by_id.erase(request_id)
	_fail_job(str(context.get("session_id", "")), error)


func _validate_generated_post(payload: Dictionary, expected_account_id: String) -> Dictionary:
	var errors: Array[String] = []
	var parser_errors: Array[String] = []
	parser_errors.assign(payload.get("errors", []))
	if not bool(payload.get("success", false)):
		errors.append_array(parser_errors)
		if errors.is_empty():
			errors.append("POST DSL 解析失败")
		return {"success": false, "post": {}, "errors": errors}
	var posts: Array[Dictionary] = []
	posts.assign(payload.get("posts", []))
	if posts.size() != 1:
		errors.append("必须且只能输出一个 POST 块")
		return {"success": false, "post": {}, "errors": errors}
	var post: Dictionary = posts[0]
	if str(post.get("account_id", "")).strip_edges() != expected_account_id:
		errors.append("POST 必须使用指定主播 account_id：%s" % expected_account_id)
	if str(post.get("text", "")).strip_edges().is_empty():
		errors.append("TEXT 不能为空")
	if str(post.get("media_mode", "")) != PostDSLParserClass.MEDIA_NONE:
		errors.append("当前直播动态只能使用 MEDIA NONE")
	if not PostDSLParserClass.REACH_VALUES.has(str(post.get("reach", ""))):
		errors.append("REACH 必须是 LOW、NORMAL 或 HIGH")
	var comments: Array[Dictionary] = []
	comments.assign(post.get("comments", []))
	if comments.is_empty():
		errors.append("至少需要一条有效 COMMENT")
	for comment: Dictionary in comments:
		if str(comment.get("author_ref", "")).strip_edges().is_empty() \
			or str(comment.get("text", "")).strip_edges().is_empty():
			errors.append("COMMENT 的作者和正文都不能为空")
			break
	return {
		"success": errors.is_empty(),
		"post": post.duplicate(true) if errors.is_empty() else {},
		"errors": errors,
	}


func _publish_post(session_id: String) -> void:
	var job: Dictionary = _jobs_by_session.get(session_id, {}) as Dictionary
	if job.is_empty() or not bool(job.get("authorized", false)) \
		or str(job.get("state", "")) != "ready":
		return
	var post: Dictionary = job.get("post", {}) as Dictionary
	var account_id: String = str(post.get("account_id", "")).strip_edges()
	if account_id.is_empty():
		_fail_job(session_id, "直播动态缺少发布账号")
		return
	if SocialMediaManager.has_source_session_post(account_id, session_id):
		job["state"] = "published"
		_jobs_by_session[session_id] = job
		return
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
	if published == null:
		_fail_job(session_id, "直播动态未能写入 LinkPosta")
		return
	job["state"] = "published"
	job["post_id"] = published.post_id
	_jobs_by_session[session_id] = job
	post_published.emit(StringName(session_id), published)


func _fail_job(session_id: String, error: String) -> void:
	if session_id.is_empty():
		return
	_clear_request_contexts(session_id)
	var job: Dictionary = _jobs_by_session.get(session_id, {}) as Dictionary
	job["session_id"] = session_id
	job["state"] = "failed"
	job["error"] = error.strip_edges()
	_jobs_by_session[session_id] = job
	push_warning("LiveStreamPostGenerator: %s" % error)
	post_prefetch_failed.emit(StringName(session_id), error)


func _clear_request_contexts(session_id: String) -> void:
	for request_id: Variant in _request_context_by_id.keys():
		var context: Dictionary = _request_context_by_id.get(request_id, {}) as Dictionary
		if str(context.get("session_id", "")) == session_id:
			_request_context_by_id.erase(request_id)
