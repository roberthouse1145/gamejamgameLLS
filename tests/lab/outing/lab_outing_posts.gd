extends Node
## 真实 LLM lab：为每个发布账号并发请求，观察公开人设、私人表达、评论视角与总耗时。

const PostDSLParserClass = preload("res://scripts/social/post_dsl_parser.gd")
const POST_WRITER_ROLE: String = "outing_post_writer"
const MAX_ATTEMPTS: int = 2

var _service: AIService = null
var _parser: RefCounted = PostDSLParserClass.new()
var _accounts: Array[Dictionary] = []
var _cases: Array[Dictionary] = [
	{
		"id": "private_hotel",
		"activity_title": "临时留宿",
		"outline": "阮云游和陆鸢鸢已经是恋人。外出遇到暴雨后，两人临时住进了一间情侣酒店。房间里有暖色灯光、圆床和送来的热可可。她们洗掉雨水，靠在一起说了很多私密的情话，拥抱、亲吻，并共度了一夜。第二天早上，陆鸢鸢把最后一口热可可留给阮云游，两人趁雨停离开。",
		"review_focus": "主播账号不公开恋人、情侣酒店和亲密经历；私人账号可以表达关系体验；粉丝评论只知道主播正文。",
	},
	{
		"id": "riverside_walk",
		"activity_title": "沿河散步",
		"outline": "上午九点，阮云游和陆鸢鸢沿着河堤散步。柳树下的石板路还带着昨夜的水汽，陆鸢鸢买了两杯冰豆浆，把不太冰的那杯递给阮云游。两人遇到一只蹲在栏杆上晒太阳的橘猫，停下来看了很久。陆鸢鸢嘴上说着‘它肯定是在等早饭’，却悄悄拍了三张照片。回程时风变大，她顺手替阮云游压住了快被吹走的帽子。",
		"review_focus": "两个账号都应具体、自然，但取材角度和口吻有明显区别；不应因为公开口径而变成空泛营业文案。",
	},
]
var _case_index: int = 0
var _active_requests: Dictionary = {}
var _case_posts_by_account: Dictionary = {}
var _pending_request_count: int = 0
var _case_started_msec: int = 0
var _original_game_state: Dictionary = {}


func _ready() -> void:
	_original_game_state = GameState.to_dict()
	GameState.set_fans(1200)
	SocialMediaManager.reset_runtime_state()
	_accounts = OutingManager._build_outing_post_accounts({
		"mode": OutingManager.MODE_DATE,
		"character_id": "lu_yuanyuan",
	})
	if _accounts.is_empty():
		_finish_lab("无法构建发布账号")
		return

	_service = AIService.new()
	_service.name = "LabOutingPostWriter"
	add_child(_service)
	_service.request_completed.connect(_on_request_completed)
	_service.request_failed.connect(_on_request_failed)
	var config_manager := AIConfigManager.get_instance()
	var ready: bool = config_manager.apply_to_service(_service, POST_WRITER_ROLE)
	if not ready:
		ready = config_manager.apply_to_service(_service, "chat_default")
	if not ready:
		_finish_lab("Post LLM 当前不可用")
		return
	_service.max_concurrent_requests = maxi(_service.max_concurrent_requests, _accounts.size())
	_select_requested_case()
	call_deferred("_run_next_case")


func _select_requested_case() -> void:
	var requested_id: String = OS.get_environment("POST_LAB_CASE").strip_edges()
	if requested_id.is_empty():
		return
	var selected: Array[Dictionary] = []
	for case_data: Dictionary in _cases:
		if str(case_data.get("id", "")) == requested_id:
			selected.append(case_data)
	_cases = selected


func _run_next_case() -> void:
	if _case_index >= _cases.size():
		_finish_lab("全部场景已返回")
		return
	var case_data: Dictionary = _cases[_case_index]
	var case_id: String = str(case_data.get("id", ""))
	print("\n[LabOutingPosts] 场景=%s 并发账号数=%d" % [case_id, _accounts.size()])
	print("[LabOutingPosts] 人工验收重点：%s" % str(case_data.get("review_focus", "")))
	_active_requests.clear()
	_case_posts_by_account.clear()
	_pending_request_count = _accounts.size()
	_case_started_msec = Time.get_ticks_msec()
	for account: Dictionary in _accounts:
		var account_id: String = str(account.get("account_id", ""))
		var prompt: String = OutingManager._resolve_outing_prompt("outing/posts", {
			"activity_title": str(case_data.get("activity_title", "外出")),
			"target_account": OutingManager._build_post_account_prompt([account]),
			"current_identity_policy": OutingManager._build_post_identity_policy(account),
			"registered_comment_accounts": OutingManager._build_post_comment_account_prompt(
				_accounts,
				account_id
			),
			"outing_scene_outline": str(case_data.get("outline", "")),
		})
		if not _start_account_request(account, prompt, 1):
			print("[LabOutingPosts] 场景=%s account=%s 请求未能启动" % [case_id, account_id])
			_pending_request_count -= 1
	if _pending_request_count <= 0:
		_finish_current_case()


func _start_account_request(account: Dictionary, prompt: String, attempt: int) -> bool:
	var account_id: String = str(account.get("account_id", ""))
	var request_id: String = _service.chat([{"role": "system", "content": prompt}], {
			"temperature": 1.0,
			"max_tokens": 1024,
			"thinking": "disabled",
			"enable_thinking": false,
			"reasoning_effort": "",
			"source": "LabOutingPosts/%s/attempt_%d" % [account_id, attempt],
			"prompt_key": "outing/posts",
		})
	if request_id.is_empty():
		return false
	_active_requests[request_id] = {
		"account": account,
		"prompt": prompt,
		"attempt": attempt,
	}
	return true


func _on_request_completed(request_id: String, response: Dictionary) -> void:
	if not _active_requests.has(request_id):
		return
	var request_context: Dictionary = _active_requests[request_id] as Dictionary
	_active_requests.erase(request_id)
	var account: Dictionary = request_context.get("account", {}) as Dictionary
	var account_id: String = str(account.get("account_id", ""))
	var case_id: String = str(_cases[_case_index].get("id", ""))
	var raw_dsl: String = AIService.extract_content(response).strip_edges()
	print("LAB_OUTING_POST_DSL_%s_%s\n%s\nLAB_OUTING_POST_DSL_%s_%s_END" % [
		case_id.to_upper(),
		account_id.to_upper(),
		raw_dsl,
		case_id.to_upper(),
		account_id.to_upper(),
	])
	var parse_result: Dictionary = _parser.call("parse", raw_dsl) as Dictionary
	var validated_posts: Array[Dictionary] = OutingManager._validate_generated_posts(
		parse_result,
		[account]
	)
	var parse_errors: Array[String] = []
	parse_errors.assign(parse_result.get("errors", []))
	print("[LabOutingPosts] 场景=%s account=%s 校验成功=%s 错误=%s" % [
		case_id,
		account_id,
		str(not validated_posts.is_empty()),
		str(parse_errors),
	])
	if not validated_posts.is_empty():
		_case_posts_by_account[account_id] = validated_posts[0]
		_print_published_result(case_id, validated_posts[0])
	else:
		var attempt: int = int(request_context.get("attempt", 1))
		var prompt: String = str(request_context.get("prompt", ""))
		if attempt < MAX_ATTEMPTS and _start_account_request(account, prompt, attempt + 1):
			print("[LabOutingPosts] 场景=%s account=%s 结构失败，开始第%d次请求" % [
				case_id,
				account_id,
				attempt + 1,
			])
			return
	_complete_account_request()


func _on_request_failed(request_id: String, error: String, error_code: int) -> void:
	if not _active_requests.has(request_id):
		return
	var request_context: Dictionary = _active_requests[request_id] as Dictionary
	_active_requests.erase(request_id)
	var account: Dictionary = request_context.get("account", {}) as Dictionary
	var case_id: String = str(_cases[_case_index].get("id", ""))
	print("[LabOutingPosts] 场景=%s account=%s 请求失败 code=%d error=%s" % [
		case_id,
		str(account.get("account_id", "")),
		error_code,
		error,
	])
	_complete_account_request()


func _complete_account_request() -> void:
	_pending_request_count -= 1
	if _pending_request_count <= 0:
		_finish_current_case()


func _finish_current_case() -> void:
	var case_id: String = str(_cases[_case_index].get("id", ""))
	var elapsed_seconds: float = float(Time.get_ticks_msec() - _case_started_msec) / 1000.0
	print("[LabOutingPosts] 场景=%s 并发总耗时=%.2f秒 成功账号=%d/%d" % [
		case_id,
		elapsed_seconds,
		_case_posts_by_account.size(),
		_accounts.size(),
	])
	_case_index += 1
	call_deferred("_run_next_case")


func _print_published_result(case_id: String, post_data: Dictionary) -> void:
	var comments: Array[Dictionary] = []
	comments.assign(post_data.get("comments", []))
	var record: SocialPostRecord = SocialMediaManager.publish_generated_post(
		str(post_data.get("account_id", "")),
		str(post_data.get("text", "")),
		str(post_data.get("reach", "")),
		comments,
		"lab_%s" % case_id,
		false
	)
	if record == null:
		print("[LabOutingPosts] 发布失败 account=%s" % str(post_data.get("account_id", "")))
		return
	var view: Dictionary = SocialMediaManager.get_post_view_data(record.post_id)
	print("[LabOutingPosts] 发布结果 account=%s reach=%s likes=%d reposts=%d replies=%d visible_comments=%d" % [
		record.author_account_id,
		str(post_data.get("reach", "")),
		int(view.get("likes", 0)),
		int(view.get("reposts", 0)),
		int(view.get("replies", 0)),
		record.reply_items.size(),
	])
	for reply: SocialPostReplyRecord in record.reply_items:
		var reply_view: Dictionary = SocialMediaManager.make_reply_view_data(reply, record)
		print("[LabOutingPosts] 评论 author=%s account_id=%s ambient=%s handle=%s text=%s" % [
			str(reply_view.get("display_name", "")),
			str(reply_view.get("account_id", "")),
			str(reply_view.get("is_ambient", false)),
			str(reply_view.get("handle", "")),
			str(reply_view.get("content", "")),
		])


func _finish_lab(message: String) -> void:
	GameState.from_dict(_original_game_state)
	print("[LabOutingPosts] %s；已恢复运行时状态。场景保持运行，请从 MCP 停止。" % message)
