extends "res://autoload/activity_session_manager.gd"

# =============================================================================
# SbeamManager — Sbeam 游戏活动管理器
#
# 继承 ActivitySessionManager，额外提供：
# - Seed pool → weekly catalog 轮换
# - 购买扣钱 + stat_changes
# - Moment 支持（修复原先缺失的 bug）
# =============================================================================

signal catalog_refreshed(catalog: Array)
signal play_session_started(session_id: String, payload: Dictionary)
signal download_started(session_id: String, payload: Dictionary)
signal download_progress_updated(session_id: String, progress: float, scene_ready: bool)
signal play_session_completed(session_id: String, payload: Dictionary)
signal play_session_failed(error_message: String)

const SEED_POOL_PATH: String = "res://resources/data/sbeam/game_seed_pool.json"
const WEEKLY_CATALOG_SIZE: int = 4
const DEFAULT_DOWNLOAD_DURATION: float = 8.0

var _seed_pool: Array[Dictionary] = []
var _weekly_catalog: Array[Dictionary] = []
var _catalog_week_index: int = -1


# =============================================================================
# Overrides
# =============================================================================

func _on_manager_ready() -> void:
	_load_seed_pool()
	_refresh_catalog_if_needed()


func _get_activity_type() -> String:
	return "sbeam"


func _get_chat_stage_key() -> String:
	return "sbeam_stage"


func _find_entry(entry_id: String) -> Dictionary:
	_refresh_catalog_if_needed()
	return _find_catalog_entry(entry_id)


## Override begin_session to handle price/stat checks before AP consumption.
## We do this by overriding the full public API method instead.
func begin_play_session(game_id: String) -> Dictionary:
	_refresh_catalog_if_needed()
	var entry: Dictionary = _find_catalog_entry(game_id)
	if entry.is_empty():
		var err := "未找到对应的游戏条目"
		play_session_failed.emit(err)
		session_failed.emit(err)
		return {"success": false, "error": err}

	var gm: Node = get_node_or_null("/root/GameManager")
	if gm == null:
		var err := "GameManager 不可用"
		play_session_failed.emit(err)
		session_failed.emit(err)
		return {"success": false, "error": err}

	var price: int = int(entry.get("price", 0))
	if int(gm.money) < price:
		var err := "钱不够，今晚先别冲动消费"
		play_session_failed.emit(err)
		session_failed.emit(err)
		return {"success": false, "error": err}

	# Deduct money and apply stat changes before starting the session
	gm.modify_stat("money", -price)
	var stat_changes: Dictionary = _build_stat_changes(entry)
	gm.modify_stats(stat_changes)

	# Store pre-computed data for _build_session to pick up
	_pending_sbeam_context = {
		"price": price,
		"stat_changes": stat_changes,
		"reaction_summary": _build_reaction_summary(entry),
	}

	var result := begin_session(game_id, _build_download_duration(entry))
	_pending_sbeam_context = {}

	if result.get("success", false):
		var sid: String = str(result.get("session_id", ""))
		play_session_started.emit(sid, result)
	else:
		# Refund on failure
		gm.modify_stat("money", price)
		var reverse_stats: Dictionary = {}
		for key in stat_changes:
			reverse_stats[key] = -int(stat_changes[key])
		gm.modify_stats(reverse_stats)
	return result

var _pending_sbeam_context: Dictionary = {}


func _build_session(_session_id: String, _entry_id: String, entry: Dictionary) -> Dictionary:
	var ctx: Dictionary = _pending_sbeam_context
	return {
		"game_id": str(entry.get("game_id", _entry_id)),
		"game": entry.duplicate(true),
		"price": int(ctx.get("price", entry.get("price", 0))),
		"stat_changes": (ctx.get("stat_changes", {}) as Dictionary).duplicate(true),
		"reaction_summary": str(ctx.get("reaction_summary", _build_reaction_summary(entry))),
		"scene_window_title": "一起玩: %s" % str(entry.get("title", "今晚游戏时间")),
		"scene_review_label": "sbeam co-op scene",
	}


func _on_session_begin(session: Dictionary) -> void:
	_send_player_game_panel(session.get("game", session.get("entry", {})))


func _get_display_label(session: Dictionary) -> String:
	return str(session.get("game", {}).get("title", "sbeam"))


func _get_moment_hint(session: Dictionary) -> String:
	return str(session.get("game", {}).get("moment_hint", ""))


func _build_completed_payload(session: Dictionary) -> Dictionary:
	return {
		"game": session.get("game", {}),
		"reaction_summary": str(session.get("reaction_summary", "")),
		"stat_changes": session.get("stat_changes", {}),
	}


# =============================================================================
# Signal Bridges
# =============================================================================

func _ready() -> void:
	super._ready()
	progress_phase_started.connect(func(sid: String, p: Dictionary) -> void: download_started.emit(sid, p))
	progress_updated.connect(func(sid: String, prog: float, sr: bool) -> void: download_progress_updated.emit(sid, prog, sr))
	session_completed.connect(func(sid: String, p: Dictionary) -> void: play_session_completed.emit(sid, p))


# =============================================================================
# Topic / Prompt Building
# =============================================================================

func _build_topic_prompt(session: Dictionary, stage: String) -> String:
	var game: Dictionary = session.get("game", {})
	var title := str(game.get("title", "未命名游戏")).strip_edges()
	var pitch := str(game.get("pitch", "")).strip_edges()
	var hook_moment := str(game.get("hook_moment", "")).strip_edges()
	var reaction_summary := str(session.get("reaction_summary", "")).strip_edges()
	var include_scene_context: bool = stage != "departure"
	var scene_outline := str(session.get("scene_outline", "")).strip_edges()
	var scene_result: Dictionary = session.get("scene_result", {})
	var parts: Array[String] = [
		"你是林夏。",
		"今晚玩家通过 SBEAM 发来了一款一起玩的游戏邀请。",
		"游戏标题: %s" % title,
	]
	if not pitch.is_empty():
		parts.append("作品印象: %s" % pitch)
	if not hook_moment.is_empty():
		parts.append("最容易触发情绪的片段: %s" % hook_moment)
	if not reaction_summary.is_empty():
		parts.append("整体体验基调: %s" % reaction_summary)
	if include_scene_context and not scene_result.is_empty():
		parts.append("刚才场景里玩家的接话选择: %s" % str(scene_result.get("choice_text", "")))
	if include_scene_context and not scene_outline.is_empty():
		parts.append("刚才 AVG 场景的文本摘要:\n%s" % scene_outline)
	match stage:
		"departure":
			parts.append("当前时刻: 玩家刚发来游戏面板，准备拉你一起玩。")
			parts.append("你现在只需要回一条准备开始前的即时短消息。")
			parts.append("不要提前总结游玩结果，也不要把话题扯去项目开发。")
		"followup":
			parts.append("当前时刻: 这一轮一起玩的过程已经结束。")
			parts.append("你现在只需要发一条玩完后的 followup 短消息。")
			parts.append("不要写评测，不要讲系统术语，不要像任务汇报。")
		_:
			parts.append("请发送一条自然短消息。")
	return "\n".join(parts)


func _build_topic_goal(stage: String) -> String:
	if stage == "departure":
		return "发送一条准备一起玩的短消息"
	if stage == "followup":
		return "发送一条玩完后的 followup"
	return "发送一条简短自然的消息"


func _build_seed_message(stage: String) -> String:
	if stage == "departure":
		return "请直接根据当前话题发送准备开始前的回复。"
	if stage == "followup":
		return "请直接根据当前话题发送玩完后的回复。"
	return "请根据当前话题直接回复。"


# =============================================================================
# Moment Prompt Building (NEW — fixes missing moment bug)
# =============================================================================

func _build_moment_system_prompt() -> String:
	return "你是林夏。你要发一条刚和搭档一起玩完游戏后的朋友圈。只返回一条中文纯文本动态，不要 JSON，不要解释，不要加引号，不要超过 36 字。"


func _build_moment_user_prompt(session: Dictionary) -> String:
	var game: Dictionary = session.get("game", {})
	var title := str(game.get("title", "今晚的游戏")).strip_edges()
	var pitch := str(game.get("pitch", "")).strip_edges()
	var reaction_summary := str(session.get("reaction_summary", "")).strip_edges()
	var scene_outline := str(session.get("scene_outline", "")).strip_edges()
	var scene_result: Dictionary = session.get("scene_result", {})
	var parts: Array[String] = [
		"刚一起玩完的游戏: 《%s》" % title,
	]
	if not pitch.is_empty():
		parts.append("作品印象: %s" % pitch)
	if not reaction_summary.is_empty():
		parts.append("整体体验基调: %s" % reaction_summary)
	if not scene_result.is_empty():
		parts.append("玩的时候的互动选择: %s" % str(scene_result.get("choice_text", "")))
	if not scene_outline.is_empty():
		parts.append("AVG 场景文本摘要:\n%s" % scene_outline)
	parts.append("请根据上面的游戏信息和体验，自行判断最自然的朋友圈语气。")
	parts.append("输出一条像随手发出的朋友圈，不要提系统，不要写成长文。")
	return "\n".join(parts)


# =============================================================================
# Local Fallback Text
# =============================================================================

func _build_local_departure_reply(session: Dictionary) -> String:
	var game: Dictionary = session.get("game", {})
	var title: String = str(game.get("title", "这个游戏")).strip_edges()
	return "好啊，等我这边把《%s》下好，我们就开。" % title


func _build_local_followup_reply(session: Dictionary) -> String:
	var game: Dictionary = session.get("game", {})
	var title: String = str(game.get("title", "这个游戏")).strip_edges()
	var choice_text: String = str((session.get("scene_result", {}) as Dictionary).get("choice_text", "")).strip_edges()
	if not choice_text.is_empty():
		return "刚才玩《%s》的时候，你那句「%s」还挺犯规的。下次我们再找个差不多的继续。" % [title, choice_text]
	return "今晚的《%s》挺值的。比起游戏本身，我更喜欢刚才一起玩的感觉。" % title


func _build_local_moment_text(session: Dictionary) -> String:
	var game: Dictionary = session.get("game", {})
	var title: String = str(game.get("title", "今晚的游戏")).strip_edges()
	var scene_outline: String = str(session.get("scene_outline", "")).strip_edges()
	var variant: int = posmod(abs(hash(str(session.get("session_id", "")) + "_moment")), 3)
	if not scene_outline.is_empty() and variant == 0:
		return "刚和人一起通关了《%s》，脑子里还留着余韵。" % title
	match variant:
		0:
			return "今晚的《%s》，值得再回味一阵。" % title
		1:
			return "和人一起玩《%s》的夜晚，比想象中安静。" % title
		_:
			return "《%s》打完了，但今晚的感觉还没散。" % title


# =============================================================================
# Player Game Panel
# =============================================================================

func _send_player_game_panel(game: Dictionary) -> void:
	var chat: Node = ActivityUtilsClass.get_chat_manager()
	if chat == null or not chat.has_method("store_player_message_data"):
		return
	var subtitle := "%s · %s" % [str(game.get("genre", "未知类型")), str(game.get("publisher", "独立发行"))]
	var footer := "¥ %d · 今晚一起玩" % int(game.get("price", 0))
	chat.store_player_message_data(ActivityChatClass.DM_CHANNEL_ID, {
		"speaker": "player",
		"card": {
			"type": "game",
			"title": str(game.get("title", "未命名作品")),
			"subtitle": subtitle,
			"body": str(game.get("pitch", "今晚来玩这个。")),
			"footer": footer,
			"badge": "SBEAM 邀请",
			"accent_color": "#66c0f4",
		}
	})


# =============================================================================
# Catalog
# =============================================================================

func get_catalog() -> Array[Dictionary]:
	_refresh_catalog_if_needed()
	var result: Array[Dictionary] = []
	for cat_entry in _weekly_catalog:
		result.append((cat_entry as Dictionary).duplicate(true))
	return result


func get_featured_game() -> Dictionary:
	_refresh_catalog_if_needed()
	if _weekly_catalog.is_empty():
		return {}
	var day: int = ActivityUtilsClass.get_current_day()
	var index: int = posmod(day - 1, _weekly_catalog.size())
	return (_weekly_catalog[index] as Dictionary).duplicate(true)


func get_run_state() -> Dictionary:
	return {
		"catalog_week_index": _catalog_week_index,
		"weekly_catalog": _weekly_catalog.duplicate(true),
	}


func load_run_state(data: Dictionary) -> bool:
	_weekly_catalog.clear()
	for item in data.get("weekly_catalog", []):
		if item is Dictionary:
			_weekly_catalog.append((item as Dictionary).duplicate(true))
	_catalog_week_index = int(data.get("catalog_week_index", -1))
	if _weekly_catalog.is_empty():
		_refresh_catalog_if_needed()
	else:
		var restored_catalog: Array = []
		for cat_entry in _weekly_catalog:
			restored_catalog.append((cat_entry as Dictionary).duplicate(true))
		catalog_refreshed.emit(restored_catalog)
	return true


func _on_reset_runtime_state() -> void:
	_weekly_catalog.clear()
	_catalog_week_index = -1
	_refresh_catalog_if_needed()


func refresh_weekly_catalog(force: bool = false) -> Array[Dictionary]:
	if _seed_pool.is_empty():
		_load_seed_pool()
	if _seed_pool.is_empty():
		_weekly_catalog.clear()
		catalog_refreshed.emit([])
		return []

	var week_index: int = _get_current_week_index()
	if not force and week_index == _catalog_week_index and not _weekly_catalog.is_empty():
		return get_catalog()

	_catalog_week_index = week_index
	_weekly_catalog = _build_weekly_catalog(week_index)
	catalog_refreshed.emit(get_catalog())
	return get_catalog()


func _refresh_catalog_if_needed() -> void:
	if _weekly_catalog.is_empty() or _catalog_week_index != _get_current_week_index():
		refresh_weekly_catalog()


func _load_seed_pool() -> void:
	_seed_pool.clear()
	if not FileAccess.file_exists(SEED_POOL_PATH):
		push_warning("[SbeamManager] Missing seed pool: %s" % SEED_POOL_PATH)
		return
	var file := FileAccess.open(SEED_POOL_PATH, FileAccess.READ)
	if file == null:
		push_warning("[SbeamManager] Failed to open seed pool")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Array:
		push_warning("[SbeamManager] Seed pool format invalid")
		return
	for item in parsed:
		if item is Dictionary:
			_seed_pool.append((item as Dictionary).duplicate(true))


func _build_weekly_catalog(week_index: int) -> Array[Dictionary]:
	var ordered_pool: Array[Dictionary] = []
	for seed_data in _seed_pool:
		ordered_pool.append((seed_data as Dictionary).duplicate(true))

	var result: Array[Dictionary] = []
	var start_index: int = posmod((week_index - 1) * WEEKLY_CATALOG_SIZE, ordered_pool.size())
	for offset in range(mini(WEEKLY_CATALOG_SIZE, ordered_pool.size())):
		var pool_index: int = posmod(start_index + offset, ordered_pool.size())
		var cat_entry: Dictionary = ordered_pool[pool_index]
		cat_entry["game_id"] = str(cat_entry.get("game_id", "sbeam_%02d" % pool_index))
		cat_entry["is_featured_today"] = false
		result.append(cat_entry)

	if not result.is_empty():
		var featured_index: int = posmod(ActivityUtilsClass.get_current_day() - 1, result.size())
		result[featured_index]["is_featured_today"] = true
	return result


func _find_catalog_entry(game_id: String) -> Dictionary:
	for cat_entry in _weekly_catalog:
		if str((cat_entry as Dictionary).get("game_id", "")) == game_id:
			return (cat_entry as Dictionary).duplicate(true)
	return {}


func _build_stat_changes(cat_entry: Dictionary) -> Dictionary:
	var bias: String = str(cat_entry.get("reaction_bias", "cozy")).strip_edges()
	var stat_map: Dictionary = {
		"laugh": {"affection": 2, "stress": -1},
		"complain": {"affection": 1, "stress": -1},
		"hyped": {"affection": 1, "passion": 2},
		"aftertaste": {"affection": 1, "passion": 1},
	}
	return stat_map.get(bias, {"affection": 2, "stress": -2})


func _build_reaction_summary(cat_entry: Dictionary) -> String:
	var title: String = str(cat_entry.get("title", "这款游戏")).strip_edges()
	return "你们一起玩了《%s》。" % title


func _build_download_duration(cat_entry: Dictionary) -> float:
	var price_factor: float = clampf(float(int(cat_entry.get("price", 0))) / 68.0, 0.0, 1.6)
	return DEFAULT_DOWNLOAD_DURATION + price_factor


func _get_current_week_index() -> int:
	return int(floor(float(ActivityUtilsClass.get_current_day() - 1) / 7.0)) + 1
