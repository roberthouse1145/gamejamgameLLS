extends "res://autoload/activity_session_manager.gd"

const ActivityOptionLLMServiceClass = preload("res://scripts/activity/activity_option_llm_service.gd")
const ActivityBlockParserClass = preload("res://scripts/activity/activity_block_parser.gd")

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
const CATALOG_SIZE: int = 4
const DEFAULT_DOWNLOAD_DURATION: float = 20.0
const CATALOG_ROLE: String = "sbeam_catalog_generator"
const FALLBACK_CATALOG_ROLE: String = "chat_default"
const GENERATION_PROMPT_KEY: String = "sbeam_catalog_generation"

var _seed_pool: Array[Dictionary] = []
var _catalog: Array[Dictionary] = []
var _pending_next_day_catalog: Array[Dictionary] = []
var _owned_game_ids: Dictionary = {}
var _catalog_generator: Node = null
var _catalog_llm_enabled: bool = false
var _catalog_request_id: String = ""
var _is_generating_catalog: bool = false


func _is_background_llm_disabled() -> bool:
	return AIConfigManager.get_instance().is_background_llm_disabled()


func _log_debug(message: String) -> void:
	if AIConfigManager.get_instance().is_quiet_logs_enabled():
		return
	print(message)


# =============================================================================
# Overrides
# =============================================================================

func _on_manager_ready() -> void:
	_load_seed_pool()
	_load_initial_catalog()
	_setup_catalog_ai_service()


func _get_activity_type() -> String:
	return "sbeam"


func _get_chat_stage_key() -> String:
	return "sbeam_stage"


func _find_entry(entry_id: String) -> Dictionary:
	return _find_catalog_entry(entry_id)


## Override begin_session to handle price/stat checks before AP consumption.
## We do this by overriding the full public API method instead.
func begin_play_session(game_id: String, skip_departure: bool = false) -> Dictionary:
	var entry: Dictionary = _find_catalog_entry(game_id)
	if entry.is_empty():
		var err := "未找到对应的游戏条目"
		play_session_failed.emit(err)
		session_failed.emit(err)
		return {"success": false, "error": err}

	if is_game_owned(game_id):
		var owned_err := "该游戏已在库存里"
		play_session_failed.emit(owned_err)
		session_failed.emit(owned_err)
		return {"success": false, "error": owned_err}

	var gm: Node = get_node_or_null("/root/GameManager")
	if gm == null:
		var err := "GameManager 不可用"
		play_session_failed.emit(err)
		session_failed.emit(err)
		return {"success": false, "error": err}

	var price: int = _resolve_game_price(entry)
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

	var result := begin_session(game_id, _build_download_duration(entry), skip_departure)
	_pending_sbeam_context = {}

	if result.get("success", false):
		_owned_game_ids[game_id] = true
		catalog_refreshed.emit(get_catalog())
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
	var price: int = int(ctx.get("price", _resolve_game_price(entry)))
	var game: Dictionary = _normalize_catalog_entry(entry)
	return {
		"game_id": str(entry.get("game_id", _entry_id)),
		"game": game,
		"price": price,
		"stat_changes": (ctx.get("stat_changes", {}) as Dictionary).duplicate(true),
		"reaction_summary": str(ctx.get("reaction_summary", _build_reaction_summary(entry))),
		"scene_window_title": "一起玩: %s" % str(entry.get("title", "今晚游戏时间")),
		"scene_review_label": "sbeam co-op scene",
	}


func _on_session_begin(session: Dictionary) -> void:
	var game: Dictionary = session.get("game", session.get("entry", {}))
	if str(session.get("session_origin", "")).strip_edges() == "npc_initiative":
		_send_game_panel(game, "npc_lin_xia", "")
		return
	_send_game_panel(game, "player")


func _get_display_label(session: Dictionary) -> String:
	return str(session.get("game", {}).get("title", "sbeam"))


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
	progress_phase_started.connect(func(sid: String, p: Dictionary) -> void:
		var enriched: Dictionary = p.duplicate(true)
		if _pending_sessions.has(sid):
			enriched["game"] = (_pending_sessions[sid] as Dictionary).get("game", {})
		download_started.emit(sid, enriched)
	)
	progress_updated.connect(func(sid: String, prog: float, sr: bool) -> void: download_progress_updated.emit(sid, prog, sr))
	session_completed.connect(func(sid: String, p: Dictionary) -> void: play_session_completed.emit(sid, p))
	var glm: Node = get_node_or_null("/root/GameLoopManager")
	if glm != null and glm.has_signal("day_changed"):
		glm.day_changed.connect(_on_day_changed)


# =============================================================================
# Topic / Prompt Building
# =============================================================================

func _build_topic_prompt(_session: Dictionary, stage: String) -> String:
	var pm: Node = get_node_or_null("/root/PromptManager")
	if pm == null:
		return ""
	var key := ""
	if stage == "departure":
		key = "activity_topic_departure"
	elif stage == "followup":
		key = "activity_topic_followup"
	else:
		return ""
	return str(pm.resolve_with_vars(key, {
		"activity_type_label": "一起在家玩游戏",
	})).strip_edges()


func _build_topic_goal(stage: String) -> String:
	if stage == "departure":
		return "发送一条准备一起玩的短消息"
	if stage == "followup":
		return "发送一条玩完后的 followup"
	return "发送一条简短自然的消息"


func _build_seed_message(stage: String, session: Dictionary = {}) -> String:
	if stage == "departure":
		return _build_departure_seed_message(session)
	if stage == "followup":
		return _build_followup_seed_message(session)
	return "请根据当前话题直接回复。"


func _build_departure_seed_message(session: Dictionary) -> String:
	var game: Dictionary = session.get("game", {})
	var title: String = str(game.get("title", "")).strip_edges()
	var pitch: String = str(game.get("pitch", "")).strip_edges()
	var hook_moment: String = str(game.get("hook_moment", "")).strip_edges()
	var parts: Array[String] = ["[本次玩家邀请一起玩的游戏卡片公开信息]"]
	if not title.is_empty():
		parts.append("- 游戏标题：《%s》" % title)
	if not pitch.is_empty():
		parts.append("- 商店页简介：%s" % pitch)
	if not hook_moment.is_empty():
		parts.append("- 商店页亮点：%s" % hook_moment)
	parts.append("- 背景：你们同居在校外公寓，玩家在家里拉你一起玩。")
	parts.append("")
	parts.append("请按 departure 规则回一条准备开始前的短消息。")
	return "\n".join(parts)


func _build_followup_seed_message(session: Dictionary) -> String:
	var game: Dictionary = session.get("game", {})
	var title: String = str(game.get("title", "")).strip_edges()
	var reaction_summary: String = str(session.get("reaction_summary", "")).strip_edges()
	var scene_outline: String = str(session.get("scene_outline", "")).strip_edges()
	var scene_result: Dictionary = session.get("scene_result", {})
	var choice_text: String = str(scene_result.get("choice_text", "")).strip_edges()
	var parts: Array[String] = ["[本次刚一起玩完的游戏]"]
	if not title.is_empty():
		parts.append("- 游戏标题：《%s》" % title)
	if not reaction_summary.is_empty():
		parts.append("- 整体体验基调：%s" % reaction_summary)
	if not choice_text.is_empty():
		parts.append("- 玩的时候你的关键接话：%s" % choice_text)
	if not scene_outline.is_empty():
		parts.append("- 实际游玩过程概要：")
		parts.append(scene_outline)
	parts.append("")
	parts.append("请按 followup 规则回一条玩完后的短消息。")
	return "\n".join(parts)


# =============================================================================
# Moment Prompt Building
# =============================================================================

func _build_moment_system_prompt() -> String:
	var pm: Node = get_node_or_null("/root/PromptManager")
	if pm == null:
		return "你是林夏。你要发一条刚和搭档一起玩完游戏后的朋友圈。只返回一条中文纯文本动态，不超过 36 字。"
	return str(pm.resolve_with_vars("activity_moment_system", {
		"activity_type_label": "一起在家玩游戏",
	})).strip_edges()


func _build_moment_user_prompt(session: Dictionary) -> String:
	var game: Dictionary = session.get("game", {})
	var title := str(game.get("title", "今晚的游戏")).strip_edges()
	var pitch := str(game.get("pitch", "")).strip_edges()
	var reaction_summary := str(session.get("reaction_summary", "")).strip_edges()
	var scene_outline := str(session.get("scene_outline", "")).strip_edges()
	var scene_result: Dictionary = session.get("scene_result", {})
	var parts: Array[String] = [
		"刚一起玩完的游戏：《%s》" % title,
	]
	if not pitch.is_empty():
		parts.append("作品印象：%s" % pitch)
	if not reaction_summary.is_empty():
		parts.append("整体体验基调：%s" % reaction_summary)
	if not scene_result.is_empty():
		parts.append("玩的时候的互动选择：%s" % str(scene_result.get("choice_text", "")))
	if not scene_outline.is_empty():
		parts.append("AVG 场景文本摘要：\n%s" % scene_outline)
	parts.append("写一条像随手发出的朋友圈，不超过 36 字。")
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

func send_npc_invite_game_panel(game_id: String, content: String = "") -> void:
	var game := _find_catalog_entry(game_id)
	if game.is_empty():
		return
	_send_game_panel(game, "npc_lin_xia", content)


func _send_game_panel(game: Dictionary, sender_id: String = "player", content: String = "") -> void:
	var chat: Node = ActivityUtilsClass.get_chat_manager()
	if chat == null:
		return
	var subtitle := "%s · %s" % [str(game.get("genre", "未知类型")), str(game.get("publisher", "独立发行"))]
	var price_text := "¥ %d" % _resolve_game_price(game)
	var message_data := {
		"speaker": sender_id,
		"content": content,
		"card": {
			"type": "game",
			"title": str(game.get("title", "未命名作品")),
			"subtitle": subtitle,
			"body": str(game.get("pitch", "来看看这个。")),
			"price": price_text,
			"footer": "推荐给你",
			"badge": "SBEAM 邀请",
			"accent_color": "#66c0f4",
		}
	}
	if sender_id == "player":
		if chat.has_method("store_player_message_data"):
			chat.store_player_message_data(ActivityChatClass.DM_CHANNEL_ID, message_data)
		return
	if chat.has_method("store_npc_message_data"):
		chat.store_npc_message_data(ActivityChatClass.DM_CHANNEL_ID, message_data)


# =============================================================================
# Catalog
# =============================================================================

func get_catalog() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for cat_entry in _catalog:
		var entry: Dictionary = (cat_entry as Dictionary).duplicate(true)
		entry["is_owned"] = is_game_owned(str(entry.get("game_id", "")))
		result.append(entry)
	return result


func pre_generate_next_day_catalog() -> void:
	_generate_next_day_catalog(ActivityUtilsClass.get_current_day() + 1)


func is_game_owned(game_id: String) -> bool:
	var normalized_id := game_id.strip_edges()
	if normalized_id.is_empty():
		return false
	return bool(_owned_game_ids.get(normalized_id, false))


func get_featured_game() -> Dictionary:
	if _catalog.is_empty():
		return {}
	var day: int = ActivityUtilsClass.get_current_day()
	var index: int = posmod(day - 1, _catalog.size())
	return (_catalog[index] as Dictionary).duplicate(true)


func get_run_state() -> Dictionary:
	return {
		"catalog": _catalog.duplicate(true),
		"pending_next_day_catalog": _pending_next_day_catalog.duplicate(true),
		"owned_game_ids": _owned_game_ids.keys(),
	}


func load_run_state(data: Dictionary) -> bool:
	_catalog.clear()
	for item in data.get("catalog", []):
		if item is Dictionary:
			_catalog.append(_normalize_catalog_entry(item as Dictionary))
	_pending_next_day_catalog.clear()
	var saved_pending: Variant = data.get("pending_next_day_catalog", [])
	if saved_pending is Array:
		for item in (saved_pending as Array):
			if item is Dictionary:
				_pending_next_day_catalog.append(_normalize_catalog_entry(item as Dictionary))
	_owned_game_ids.clear()
	var saved_owned: Variant = data.get("owned_game_ids", [])
	if saved_owned is Array:
		for raw_game_id in (saved_owned as Array):
			var owned_game_id := str(raw_game_id).strip_edges()
			if owned_game_id.is_empty():
				continue
			_owned_game_ids[owned_game_id] = true
	_is_generating_catalog = false
	_catalog_request_id = ""
	if _catalog_generator != null and _catalog_generator.has_method("clear_pending_requests"):
		_catalog_generator.clear_pending_requests()
	if _catalog.is_empty():
		_load_initial_catalog()
	else:
		catalog_refreshed.emit(get_catalog())
	return true


func _on_reset_runtime_state() -> void:
	_catalog.clear()
	_pending_next_day_catalog.clear()
	_owned_game_ids.clear()
	_is_generating_catalog = false
	_catalog_request_id = ""
	if _catalog_generator != null and _catalog_generator.has_method("clear_pending_requests"):
		_catalog_generator.clear_pending_requests()
	_load_initial_catalog()


## Backward-compatible alias
func refresh_weekly_catalog(_force: bool = false) -> Array[Dictionary]:
	catalog_refreshed.emit(get_catalog())
	return get_catalog()


func refresh_catalog(force: bool = false) -> void:
	if not force and not _catalog.is_empty():
		catalog_refreshed.emit(get_catalog())
		return
	_load_initial_catalog()


# =============================================================================
# Day Change + LLM Pre-generation
# =============================================================================

func _on_day_changed(new_day: int) -> void:
	if not _pending_next_day_catalog.is_empty():
		_catalog.clear()
		for item in _pending_next_day_catalog:
			_catalog.append(_normalize_catalog_entry(item))
		_pending_next_day_catalog.clear()
		# Mark featured
		_mark_featured_game()
		_log_debug("[SbeamManager] Activated %d pre-generated games for day %d" % [_catalog.size(), new_day])
		catalog_refreshed.emit(get_catalog())
	if new_day >= 1:
		_generate_next_day_catalog(new_day + 1)


func _setup_catalog_ai_service() -> void:
	if _is_background_llm_disabled():
		_catalog_llm_enabled = false
		return
	_catalog_generator = ActivityOptionLLMServiceClass.new()
	add_child(_catalog_generator)
	_catalog_generator.request_completed.connect(_on_catalog_gen_completed)
	_catalog_generator.request_failed.connect(_on_catalog_gen_failed)
	_catalog_llm_enabled = _catalog_generator.configure(
		"SbeamCatalogAIService",
		CATALOG_ROLE,
		[FALLBACK_CATALOG_ROLE] as Array[String],
		{
			"max_history_messages": 0,
			"auto_execute_tools": false,
		}
	)


func _generate_next_day_catalog(target_day: int) -> void:
	if _is_background_llm_disabled():
		return
	if _catalog_generator == null or not _catalog_llm_enabled:
		return
	if _is_generating_catalog:
		return
	_is_generating_catalog = true
	var prompt := _load_generation_prompt(target_day)
	var sys_prompt := "Output only [SBEAM_GAME] ... [/SBEAM_GAME] blocks. No JSON. No markdown. No explanations."
	_catalog_request_id = _catalog_generator.request_text(prompt, sys_prompt, {
		"target_day": target_day,
	}, {
		"prompt_key": GENERATION_PROMPT_KEY,
	})
	if _catalog_request_id.is_empty():
		_is_generating_catalog = false
		push_warning("[SbeamManager] Failed to send LLM catalog request for day %d" % target_day)


func _on_catalog_gen_completed(request_id: String, context: Dictionary, raw_text: String, _response: Dictionary) -> void:
	if request_id != _catalog_request_id:
		return
	_catalog_request_id = ""
	_is_generating_catalog = false
	var target_day: int = int(context.get("target_day", ActivityUtilsClass.get_current_day() + 1))
	var raw_blocks: Array[Dictionary] = ActivityBlockParserClass.parse_blocks(raw_text, "SBEAM_GAME")
	var parsed: Array[Dictionary] = []
	var local_index: int = 0
	for block in raw_blocks:
		var normalized := _normalize_sbeam_item(block, target_day, local_index)
		if normalized.is_empty():
			continue
		parsed.append(normalized)
		local_index += 1
		if parsed.size() >= CATALOG_SIZE:
			break
	if not parsed.is_empty():
		_pending_next_day_catalog.clear()
		for item in parsed:
			_pending_next_day_catalog.append(item.duplicate(true))
		_log_debug("[SbeamManager] Pre-generated %d games (pending activation on next day)" % _pending_next_day_catalog.size())
		return
	push_warning("[SbeamManager] Failed to parse LLM sbeam catalog for day %d" % target_day)


func _on_catalog_gen_failed(request_id: String, _context: Dictionary, error_msg: String, _error_code: int) -> void:
	if request_id != _catalog_request_id:
		return
	_catalog_request_id = ""
	_is_generating_catalog = false
	push_warning("[SbeamManager] Catalog generation failed: %s" % error_msg)


# =============================================================================
# Seed Pool / Initial Catalog
# =============================================================================

func _load_initial_catalog() -> void:
	if _seed_pool.is_empty():
		_load_seed_pool()
	_catalog.clear()
	for i in range(mini(CATALOG_SIZE, _seed_pool.size())):
		var entry := _normalize_catalog_entry(_seed_pool[i], "sbeam_%02d" % i, "seed_pool")
		_catalog.append(entry)
	_mark_featured_game()
	catalog_refreshed.emit(get_catalog())


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


func _mark_featured_game() -> void:
	if _catalog.is_empty():
		return
	for entry in _catalog:
		entry["is_featured_today"] = false
	var day: int = ActivityUtilsClass.get_current_day()
	_catalog[posmod(day - 1, _catalog.size())]["is_featured_today"] = true


# =============================================================================
# Normalize / Prompt
# =============================================================================

func _normalize_sbeam_item(raw: Dictionary, target_day: int, local_index: int) -> Dictionary:
	var title: String = str(raw.get("title", "")).strip_edges()
	if title.is_empty():
		return {}
	var game_id: String = str(raw.get("game_id", "")).strip_edges()
	if game_id.is_empty():
		game_id = "llm_sbeam_d%d_%02d" % [maxi(1, target_day), local_index]
	var price: int = int(raw.get("price", 0))
	# Build user_reviews from review_N fields
	var user_reviews: Array = []
	for i in range(1, 6):
		var key := "review_%d" % i
		var rv: String = str(raw.get(key, "")).strip_edges()
		if rv.is_empty():
			continue
		var parts: PackedStringArray = rv.split("|")
		if parts.size() < 4:
			continue
		user_reviews.append({
			"user": parts[0].strip_edges(),
			"hours": float(parts[1].strip_edges()) if parts[1].strip_edges().is_valid_float() else 1.0,
			"owned_products": randi_range(8, 200),
			"is_recommended": parts[2].strip_edges().to_lower() == "true",
			"upvotes": randi_range(5, 300),
			"review": parts[3].strip_edges(),
		})
	return _normalize_catalog_entry({
		"game_id": game_id,
		"title": title,
		"genre": str(raw.get("genre", "独立游戏")).strip_edges(),
		"publisher": str(raw.get("publisher", "独立发行")).strip_edges(),
		"pitch": str(raw.get("pitch", "")).strip_edges(),
		"hook_moment": str(raw.get("hook_moment", "")).strip_edges(),
		"reaction_bias": str(raw.get("reaction_bias", "cozy")).strip_edges(),
		"review_summary": str(raw.get("review_summary", "")).strip_edges(),
		"price": price,
		"rewards": {"money": -price, "affection": 1, "passion": 1},
		"release_date": str(raw.get("release_date", "2024-01-01")).strip_edges(),
		"recent_reviews_summary": str(raw.get("recent_reviews_summary", "暂无评测")).strip_edges(),
		"all_reviews_summary": str(raw.get("all_reviews_summary", "暂无评测")).strip_edges(),
		"player_count_hint": "单人",
		"user_reviews": user_reviews,
		"is_featured_today": false,
		"source_type": "llm_block",
	})


func _load_generation_prompt(target_day: int) -> String:
	var pm := get_node_or_null("/root/PromptManager")
	if pm != null and pm.has_method("has_prompt") and pm.has_prompt(GENERATION_PROMPT_KEY) and pm.has_method("resolve_with_vars"):
		return str(pm.resolve_with_vars(GENERATION_PROMPT_KEY, {
			"count": str(CATALOG_SIZE),
			"target_day": str(target_day),
		})).strip_edges()
	return "Output %d indie games using [SBEAM_GAME] ... [/SBEAM_GAME] blocks for day %d." % [CATALOG_SIZE, target_day]


func _find_catalog_entry(game_id: String) -> Dictionary:
	for cat_entry in _catalog:
		if str((cat_entry as Dictionary).get("game_id", "")) == game_id:
			return _normalize_catalog_entry(cat_entry as Dictionary)
	return {}


func _normalize_catalog_entry(raw_entry: Dictionary, fallback_game_id: String = "", source_type: String = "") -> Dictionary:
	var entry := raw_entry.duplicate(true)
	if not fallback_game_id.is_empty():
		entry["game_id"] = str(entry.get("game_id", fallback_game_id))
	if not source_type.is_empty():
		entry["source_type"] = str(entry.get("source_type", source_type))
	var price := _resolve_game_price(entry)
	entry["price"] = price
	var rewards: Dictionary = {}
	var raw_rewards: Variant = entry.get("rewards", {})
	if raw_rewards is Dictionary:
		rewards = (raw_rewards as Dictionary).duplicate(true)
	if not rewards.has("money"):
		rewards["money"] = -price
	entry["rewards"] = rewards
	return entry


func _resolve_game_price(entry: Dictionary) -> int:
	var explicit_price := int(entry.get("price", 0))
	if explicit_price > 0:
		return explicit_price
	var raw_rewards: Variant = entry.get("rewards", {})
	if raw_rewards is Dictionary:
		var rewards := raw_rewards as Dictionary
		if rewards.has("money"):
			return maxi(0, -int(rewards.get("money", 0)))
	return maxi(0, explicit_price)


func _build_stat_changes(cat_entry: Dictionary) -> Dictionary:
	var bias: String = str(cat_entry.get("reaction_bias", "cozy")).strip_edges()
	var stat_map: Dictionary = {
		"laugh": {"stress": -10, "passion": 3},
		"complain": {"stress": -6, "passion": 2},
		"hyped": {"stress": -6, "passion": 12},
		"aftertaste": {"stress": -8, "passion": 8},
		"cozy": {"stress": -8, "passion": 6},
	}
	return stat_map.get(bias, {"stress": -8, "passion": 6})


func _build_reaction_summary(cat_entry: Dictionary) -> String:
	var title: String = str(cat_entry.get("title", "这款游戏")).strip_edges()
	return "你们一起玩了《%s》。" % title


func _build_download_duration(cat_entry: Dictionary) -> float:
	var price_factor: float = clampf(float(_resolve_game_price(cat_entry)) / 68.0, 0.0, 1.6)
	return DEFAULT_DOWNLOAD_DURATION + price_factor
