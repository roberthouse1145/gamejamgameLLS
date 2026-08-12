extends Node
## 真实 LLM 实验：两份不同直播 DSL 都应先生成待发布动态，再经授权写入 LinkPosta。

const POST_GENERATOR_SCENE: PackedScene = preload(
	"res://scenes/game/live_stream/live_stream_post_generator.tscn"
)

const CASES: Array[Dictionary] = [
	{
		"id": "game_clear",
		"title": "重返法环！黄金树幽影DLC",
		"dsl": """expression: smile
say: 晚上好，今天把昨天卡住的双月骑士打掉。
chat 4: 来了来了 | 还敢回来 | 今天能过吗 | 坐牢继续
expression: focused
say: 先不贪刀，看清第二段再滚。
wait: 1.0
gesture: fist_pump
say: 过了！最后这下居然真的忍住没补刀！
chat 5: 牛的 | 真过了 | 这波好稳 | 进步了 | 截图留念""",
	},
	{
		"id": "song_retry",
		"title": "窝趣！主播也是进入变声期了呀",
		"dsl": """expression: smile
say: 今晚先唱一首最近一直在练的歌。
say: ♪夜风绕过窗边，星光落在指尖♪
expression: surprised
say: 咳……等一下，刚才那句直接破音了。
chat 5: 听到了 | 没事没事 | 水呢 | 主播红温了 | 再来一次
expression: embarrassed
say: 不许剪！我喝口水，降一个调再来。
say: ♪夜风绕过窗边，星光落在指尖♪
chat 4: 这次稳了 | 好听 | 降调适合你 | 可以可以""",
	},
]

var _generator: LiveStreamPostGenerator = null
var _case_index: int = 0
var _pending_session_id: StringName = &""


func _ready() -> void:
	_generator = POST_GENERATOR_SCENE.instantiate() as LiveStreamPostGenerator
	add_child(_generator)
	_generator.post_prefetched.connect(_on_post_prefetched)
	_generator.post_prefetch_failed.connect(_on_post_prefetch_failed)
	_generator.post_published.connect(_on_post_published)
	call_deferred("_run_next_case")


func _run_next_case() -> void:
	if _case_index >= CASES.size():
		print("LAB_LIVE_STREAM_POST_ALL_DONE ok=1 cases=%d" % CASES.size())
		return
	var case_data: Dictionary = CASES[_case_index]
	var plan := StreamPlanSnapshot.new()
	_pending_session_id = StringName("lab_live_post_%s_%d" % [
		case_data.get("id", ""),
		Time.get_ticks_msec(),
	])
	plan.session_id = _pending_session_id
	plan.title = str(case_data.get("title", ""))
	plan.persona_id = StringName(GameState.active_persona_id)
	var show: Dictionary = {
		"title": plan.title,
		"dsl_text": str(case_data.get("dsl", "")),
	}
	print("LAB_LIVE_STREAM_POST_START case=%s session=%s" % [
		case_data.get("id", ""),
		_pending_session_id,
	])
	if not _generator.prefetch(plan, show):
		print("LAB_LIVE_STREAM_POST_ALL_DONE ok=0 reason=prefetch_not_started")


func _on_post_prefetched(session_id: StringName, post: Dictionary) -> void:
	if session_id != _pending_session_id:
		return
	var case_data: Dictionary = CASES[_case_index]
	var job: Dictionary = _generator.get_job_snapshot(session_id)
	print("LAB_LIVE_STREAM_POST_PREFETCHED case=%s state=%s post=%s" % [
		case_data.get("id", ""),
		job.get("state", ""),
		JSON.stringify(post),
	])
	if not _generator.authorize_publication(session_id):
		print("LAB_LIVE_STREAM_POST_ALL_DONE ok=0 reason=publication_not_authorized")


func _on_post_published(session_id: StringName, post: SocialPostRecord) -> void:
	if session_id != _pending_session_id:
		return
	var case_data: Dictionary = CASES[_case_index]
	var view_data: Dictionary = SocialMediaManager.get_post_view_data(post.post_id)
	print("LAB_LIVE_STREAM_POST_PUBLISHED case=%s source_session=%s text=%s" % [
		case_data.get("id", ""),
		post.source_session_id,
		JSON.stringify(str(view_data.get("content", ""))),
	])
	_case_index += 1
	call_deferred("_run_next_case")


func _on_post_prefetch_failed(session_id: StringName, error: String) -> void:
	if session_id != _pending_session_id:
		return
	print("LAB_LIVE_STREAM_POST_ALL_DONE ok=0 session=%s reason=%s" % [session_id, error])
