extends Node
## GameState Autoload
## 《家里蹲主播》运行时状态唯一真相源（对应策划案 §4.1 四分法）。
## 属性/资源/成长/关系/跨场数值全部经由此处读写；存档通过 to_dict/from_dict。

## 属性跨越阈值时发出（crossed_up: 向上跨为 true，回落为 false）
signal attribute_threshold_crossed(attr_name: String, threshold: int, crossed_up: bool)
signal attribute_changed(attr_name: String, value: int)
signal money_changed(value: int)
signal fans_changed(value: int)
signal day_changed(value: int)
signal time_slot_changed(value: int)
signal streamer_progress_changed(level: int, exp: int, growth_points: int)
signal skill_levels_changed(family: StringName, level: int)
signal skill_experience_changed(family: StringName, experience: int, level: int)
signal skill_nodes_changed()
## 当前人设切换（毕业转生，策划案 §4.10）后发出。
signal persona_changed(old_persona_id: String, new_persona_id: String)
signal state_loaded()

const ATTR_STRESS: String = "stress"
const ATTR_OTAKU_DESIRE: String = "otaku_desire"
const ATTR_LONELINESS: String = "loneliness"

## 属性阈值（策划案 §4.2）：压力 >60 演出降质 / >80 摆烂 / 100 坏结局；
## 宅欲 >70 演出打折 / >90 摆烂；孤独 >70 日记变丧 / >90 关系状态恶化
const ATTRIBUTE_THRESHOLDS: Dictionary = {
	ATTR_STRESS: [60, 80, 100],
	ATTR_OTAKU_DESIRE: [70, 90],
	ATTR_LONELINESS: [70, 90],
}

const TIME_SLOT_MORNING: int = 0
const TIME_SLOT_AFTERNOON: int = 1
const TIME_SLOT_NIGHT: int = 2
const GAME_TIME_PROMPT_PROVIDER_KEY: String = "current_game_time"
const GAME_START_YEAR: int = 2026
const GAME_START_MONTH: int = 8
const GAME_START_DAY: int = 7
const SECONDS_PER_DAY: int = 86_400
const WEEKDAY_NAMES: Array[String] = [
	"星期日",
	"星期一",
	"星期二",
	"星期三",
	"星期四",
	"星期五",
	"星期六",
]
const TIME_SLOT_NAMES: Array[String] = ["上午", "下午", "晚上"]
const TIME_SLOT_HOURS: Array[int] = [9, 14, 20]

const FAN_VECTOR_KEYS: Array[String] = ["r", "m", "w", "c", "b"]

const SKILL_FAMILIES: Array[StringName] = [&"game", &"talk", &"song", &"act", &"tech"]
const DEFAULT_SKILL_LEVELS: Dictionary = {
	"game": 1,
	"talk": 1,
	"song": 1,
	"act": 1,
	"tech": 1,
}
const DEFAULT_SKILL_EXPERIENCE: Dictionary = {
	"game": 0,
	"talk": 0,
	"song": 0,
	"act": 0,
	"tech": 0,
}

## 属性（0~100）：压力 / 宅欲 / 孤独
var stress: int = 0
var otaku_desire: int = 0
var loneliness: int = 0

## 资源：金钱 / 粉丝总数 / 天数（1~90）/ 时段
var money: int = 0
var fans: int = 0
var day: int = 1
var time_slot: int = TIME_SLOT_MORNING

## 通用行动事务与外出运行态。只保存可序列化快照。
var completed_action_transactions: Array[String] = []
var action_transaction_history: Array[Dictionary] = []
var active_outing_session: Dictionary = {}
var outing_history: Array[Dictionary] = []
## day -> Array[character_id]。邀约失败只锁定当日该角色。
var failed_date_invites: Dictionary = {}

## 中之人成长：素材提供领域熟练度；其总和推进主播等级并授予公共成长点。
var streamer_level: int = 1
var streamer_exp: int = 0
var growth_points: int = 2
var skill_levels: Dictionary = DEFAULT_SKILL_LEVELS.duplicate(true)
var skill_experience: Dictionary = DEFAULT_SKILL_EXPERIENCE.duplicate(true)
var unlocked_skill_ids: Array[StringName] = []
## 素材运行态：instance_id -> definition_id/depth/progress/freshness/use_count。
var material_instances: Dictionary = {}
var material_serial: int = 0
## 人设运行态：persona_id -> proficiency/fixation。
var persona_progress: Dictionary = {}
## 当前扮演中的人设（开播前不可切换；切换走毕业转生，见策划案 §4.10）。
var active_persona_id: String = "persona_default"
## 已毕业（转生）皮套，不可再扮演。
var graduated_personas: Array[String] = []
## 已提交直播的事务 ID，保证结算幂等。
var completed_stream_sessions: Array[String] = []
## 直播记录保存为可序列化快照；运行时由直播领域的 StreamHistoryStore 转为 Resource。
var stream_history: Array[Dictionary] = []

## 关系：character_id -> {"favor": int, "trust": int, "dependence": int}
var relationships: Dictionary = {}

## LinkChat 运行态：好友关系与私聊消息进入存档。
var linkchat_initialized: bool = false
var linkchat_friend_ids: Array[String] = []
var linkchat_messages: Array[Dictionary] = []
var linkchat_message_serial: int = 0

## 叙事邮件运行态：邮件正文与已读状态进入存档。
var mail_messages: Array[Dictionary] = []
var mail_message_serial: int = 0

## 公开社交平台运行态：实际发布记录。账号与预制内容仍由角色资源拥有。
var social_posts: Array[Dictionary] = []
var social_post_serial: int = 0

## 跨场：粉丝构成五类互斥向量（归一化百分比）/ 炎上值 / 契约进度
var fan_vector: Dictionary = {"r": 100.0, "m": 0.0, "w": 0.0, "c": 0.0, "b": 0.0}
var flame_value: float = 0.0
var contract: Dictionary = {"debt": 0, "period_results": []}


func _ready() -> void:
	PromptManager.register_provider(
		GAME_TIME_PROMPT_PROVIDER_KEY,
		Callable(self, "get_game_time_prompt_context")
	)


func get_current_datetime() -> Dictionary:
	return get_game_datetime_for(day, time_slot)


func get_game_datetime_for(game_day_value: int, time_slot_value: int) -> Dictionary:
	var game_day: int = maxi(game_day_value, 1)
	var slot: int = clampi(time_slot_value, TIME_SLOT_MORNING, TIME_SLOT_NIGHT)
	var start_unix: int = Time.get_unix_time_from_datetime_dict({
		"year": GAME_START_YEAR,
		"month": GAME_START_MONTH,
		"day": GAME_START_DAY,
		"hour": 0,
		"minute": 0,
		"second": 0,
	})
	var result: Dictionary = Time.get_datetime_dict_from_unix_time(
		start_unix + (game_day - 1) * SECONDS_PER_DAY
	)
	result["hour"] = TIME_SLOT_HOURS[slot]
	result["minute"] = 0
	result["second"] = 0
	result["game_day"] = game_day
	result["time_slot"] = slot
	result["time_slot_name"] = TIME_SLOT_NAMES[slot]
	result["weekday_name"] = WEEKDAY_NAMES[clampi(int(result.get("weekday", 0)), 0, WEEKDAY_NAMES.size() - 1)]
	return result


func get_game_time_text() -> String:
	return get_game_time_text_for(day, time_slot)


func get_game_time_text_for(game_day: int, slot: int) -> String:
	var value: Dictionary = get_game_datetime_for(game_day, slot)
	return "%d年%d月%d日（%s）%02d:%02d · %s" % [
		int(value.get("year", GAME_START_YEAR)),
		int(value.get("month", GAME_START_MONTH)),
		int(value.get("day", GAME_START_DAY)),
		str(value.get("weekday_name", "")),
		int(value.get("hour", 0)),
		int(value.get("minute", 0)),
		str(value.get("time_slot_name", "")),
	]


func get_game_time_prompt_context() -> String:
	return "当前游戏时间：%s（游戏第%d天）。本次生成中的今天、现在、日期、星期和时段均以这个时间点为事实基准；当前行动发生在当天的当前时段。" % [
		get_game_time_text(),
		maxi(day, 1),
	]


func get_attribute(attr_name: String) -> int:
	match attr_name:
		ATTR_STRESS:
			return stress
		ATTR_OTAKU_DESIRE:
			return otaku_desire
		ATTR_LONELINESS:
			return loneliness
	push_error("GameState: unknown attribute '%s'" % attr_name)
	return 0


func set_attribute(attr_name: String, value: int) -> void:
	var old_value: int = get_attribute(attr_name)
	var new_value: int = clampi(value, 0, 100)
	match attr_name:
		ATTR_STRESS:
			stress = new_value
		ATTR_OTAKU_DESIRE:
			otaku_desire = new_value
		ATTR_LONELINESS:
			loneliness = new_value
		_:
			return
	if new_value == old_value:
		return
	attribute_changed.emit(attr_name, new_value)
	for threshold: int in ATTRIBUTE_THRESHOLDS.get(attr_name, []):
		if old_value < threshold and new_value >= threshold:
			attribute_threshold_crossed.emit(attr_name, threshold, true)
		elif old_value >= threshold and new_value < threshold:
			attribute_threshold_crossed.emit(attr_name, threshold, false)


func adjust_attribute(attr_name: String, delta: int) -> void:
	set_attribute(attr_name, get_attribute(attr_name) + delta)


func add_money(amount: int) -> void:
	money += amount
	money_changed.emit(money)


func set_fans(value: int) -> void:
	var new_value: int = maxi(value, 0)
	if new_value == fans:
		return
	fans = new_value
	fans_changed.emit(fans)


func get_skill_level(family: StringName) -> int:
	if family not in SKILL_FAMILIES:
		push_error("GameState: unknown skill family '%s'" % String(family))
		return 1
	return clampi(int(skill_levels.get(String(family), 1)), 1, 5)


func get_skill_experience(family: StringName) -> int:
	if family not in SKILL_FAMILIES:
		push_error("GameState: unknown skill family '%s'" % String(family))
		return 0
	return maxi(int(skill_experience.get(String(family), 0)), 0)


func set_skill_level(family: StringName, value: int) -> void:
	if family not in SKILL_FAMILIES:
		push_error("GameState: unknown skill family '%s'" % String(family))
		return
	var normalized_value: int = clampi(value, 1, 5)
	if get_skill_level(family) == normalized_value:
		return
	skill_levels[String(family)] = normalized_value
	skill_levels_changed.emit(family, normalized_value)


func set_unlocked_skill_ids(skill_ids: Array[StringName]) -> void:
	unlocked_skill_ids.clear()
	for skill_id: StringName in skill_ids:
		if skill_id != &"" and skill_id not in unlocked_skill_ids:
			unlocked_skill_ids.append(skill_id)
	skill_nodes_changed.emit()


func add_unlocked_skill_id(skill_id: StringName) -> void:
	if skill_id == &"" or skill_id in unlocked_skill_ids:
		return
	unlocked_skill_ids.append(skill_id)
	skill_nodes_changed.emit()


func set_growth_points(value: int) -> void:
	growth_points = maxi(value, 0)
	streamer_progress_changed.emit(streamer_level, streamer_exp, growth_points)


func add_streamer_exp(amount: int, balance: LiveStreamBalance) -> int:
	if amount <= 0 or balance == null:
		return 0
	var old_level: int = streamer_level
	streamer_exp += amount
	streamer_level = balance.get_level_for_exp(streamer_exp)
	var gained_levels: int = maxi(streamer_level - old_level, 0)
	if gained_levels > 0:
		growth_points += gained_levels
	streamer_progress_changed.emit(streamer_level, streamer_exp, growth_points)
	return gained_levels


func apply_skill_experience(rewards: Dictionary, balance: LiveStreamBalance) -> Dictionary:
	var applied: Dictionary = {}
	var level_gains: Dictionary = {}
	var total_exp: int = 0
	if balance == null:
		return {
			"applied": applied,
			"level_gains": level_gains,
			"total_exp": total_exp,
			"streamer_levels_gained": 0,
		}
	for family: StringName in SKILL_FAMILIES:
		var family_key := String(family)
		var amount: int = maxi(int(rewards.get(family_key, 0)), 0)
		if amount <= 0:
			continue
		var old_level: int = get_skill_level(family)
		var new_experience: int = get_skill_experience(family) + amount
		var new_level: int = balance.get_skill_level_for_exp(new_experience)
		skill_experience[family_key] = new_experience
		skill_levels[family_key] = new_level
		applied[family_key] = amount
		total_exp += amount
		if new_level > old_level:
			level_gains[family_key] = new_level - old_level
			skill_levels_changed.emit(family, new_level)
		skill_experience_changed.emit(family, new_experience, new_level)
	var streamer_levels_gained: int = add_streamer_exp(total_exp, balance)
	return {
		"applied": applied,
		"level_gains": level_gains,
		"total_exp": total_exp,
		"streamer_levels_gained": streamer_levels_gained,
	}


## 用角色资源初值建档；已存在则不覆盖
func init_relationship(character: CharacterProfile) -> void:
	if character == null or character.character_id.is_empty():
		push_error("GameState: init_relationship requires a character with character_id")
		return
	if relationships.has(character.character_id):
		return
	relationships[character.character_id] = {
		"favor": character.initial_favor,
		"trust": character.initial_trust,
		"dependence": character.initial_dependence,
	}


func change_relationship(character_id: String, favor: int = 0, trust: int = 0, dependence: int = 0) -> void:
	if not relationships.has(character_id):
		push_warning("GameState: relationship '%s' not initialized, creating with zeros" % character_id)
		relationships[character_id] = {"favor": 0, "trust": 0, "dependence": 0}
	var entry: Dictionary = relationships[character_id]
	entry["favor"] += favor
	entry["trust"] += trust
	entry["dependence"] += dependence


func get_relationship(character_id: String) -> Dictionary:
	return relationships.get(character_id, {})


## 设置粉丝构成向量；缺失键补 0，总和归一化到 100
func set_fan_vector(vector: Dictionary) -> void:
	var normalized: Dictionary = {}
	var total: float = 0.0
	for key: String in FAN_VECTOR_KEYS:
		var value: float = maxf(0.0, float(vector.get(key, 0.0)))
		normalized[key] = value
		total += value
	if total <= 0.0:
		push_error("GameState: fan_vector total must be positive")
		return
	for key: String in FAN_VECTOR_KEYS:
		normalized[key] = normalized[key] / total * 100.0
	fan_vector = normalized


## 毕业转生残留比例（策划案 §4.10，基准待测试）：
## R×0.5 继承 / M·W×0.2 跟随 / C：0.1 认出来、0.3 回踩、0.6 流失 / B×0.5 跟随。
const GRADUATION_RETAIN: Dictionary = {
	"r": 0.5, "m": 0.2, "w": 0.2, "c": 0.1, "b": 0.5,
}
const GRADUATION_CORE_BACKLASH: float = 0.3


## 毕业转生状态转换（策划案 §4.10）：冻结当前人设、按残留规则重建粉丝、
## 记录毕业历史并切换到新人设。纯状态操作，门控与资源读取由调用方负责。
func graduation_transform(
	new_persona_id: String,
	initial_proficiency: float,
	initial_fixation: float
) -> bool:
	if new_persona_id.is_empty() or new_persona_id == active_persona_id:
		return false
	if new_persona_id in graduated_personas:
		return false
	var old_persona_id: String = active_persona_id
	var current_vector: Dictionary = fan_vector
	var retained_sum: float = 0.0
	var residual: Dictionary = {}
	for key: String in FAN_VECTOR_KEYS:
		var value: float = maxf(0.0, float(current_vector.get(key, 0.0)))
		residual[key] = value * float(GRADUATION_RETAIN.get(key, 0.0))
		retained_sum += residual[key]
	var core_backlash: float = maxf(0.0, float(current_vector.get("c", 0.0))) * GRADUATION_CORE_BACKLASH
	residual["b"] = float(residual.get("b", 0.0)) + core_backlash
	retained_sum += core_backlash
	var old_fans: int = fans
	var retained_fraction: float = retained_sum / 100.0
	set_fans(maxi(int(round(float(old_fans) * retained_fraction)), 0))
	if retained_sum <= 0.0:
		residual = {"r": 100.0, "m": 0.0, "w": 0.0, "c": 0.0, "b": 0.0}
	set_fan_vector(residual)
	graduated_personas.append(old_persona_id)
	active_persona_id = new_persona_id
	persona_progress[new_persona_id] = {
		"proficiency": initial_proficiency,
		"fixation": initial_fixation,
	}
	persona_changed.emit(old_persona_id, new_persona_id)
	return true


func to_dict() -> Dictionary:
	return {
		"stress": stress,
		"otaku_desire": otaku_desire,
		"loneliness": loneliness,
		"money": money,
		"fans": fans,
		"day": day,
		"time_slot": time_slot,
		"completed_action_transactions": completed_action_transactions.duplicate(),
		"action_transaction_history": action_transaction_history.duplicate(true),
		"active_outing_session": active_outing_session.duplicate(true),
		"outing_history": outing_history.duplicate(true),
		"failed_date_invites": failed_date_invites.duplicate(true),
		"streamer_level": streamer_level,
		"streamer_exp": streamer_exp,
		"growth_points": growth_points,
		"skill_levels": skill_levels.duplicate(true),
		"skill_experience": skill_experience.duplicate(true),
		"unlocked_skill_ids": unlocked_skill_ids.duplicate(),
		"material_instances": material_instances.duplicate(true),
		"material_serial": material_serial,
		"persona_progress": persona_progress.duplicate(true),
		"active_persona_id": active_persona_id,
		"graduated_personas": graduated_personas.duplicate(),
		"completed_stream_sessions": completed_stream_sessions.duplicate(),
		"stream_history": stream_history.duplicate(true),
		"relationships": relationships.duplicate(true),
		"linkchat_initialized": linkchat_initialized,
		"linkchat_friend_ids": linkchat_friend_ids.duplicate(),
		"linkchat_messages": linkchat_messages.duplicate(true),
		"linkchat_message_serial": linkchat_message_serial,
		"mail_messages": mail_messages.duplicate(true),
		"mail_message_serial": mail_message_serial,
		"social_posts": social_posts.duplicate(true),
		"social_post_serial": social_post_serial,
		"fan_vector": fan_vector.duplicate(true),
		"flame_value": flame_value,
		"contract": contract.duplicate(true),
	}


func from_dict(data: Dictionary) -> void:
	stress = clampi(int(data.get("stress", 0)), 0, 100)
	otaku_desire = clampi(int(data.get("otaku_desire", 0)), 0, 100)
	loneliness = clampi(int(data.get("loneliness", 0)), 0, 100)
	money = int(data.get("money", 0))
	fans = maxi(int(data.get("fans", 0)), 0)
	day = int(data.get("day", 1))
	time_slot = int(data.get("time_slot", TIME_SLOT_MORNING))
	completed_action_transactions.clear()
	for transaction_value: Variant in data.get("completed_action_transactions", []):
		var transaction_id: String = str(transaction_value).strip_edges()
		if not transaction_id.is_empty() and transaction_id not in completed_action_transactions:
			completed_action_transactions.append(transaction_id)
	action_transaction_history.clear()
	for history_value: Variant in data.get("action_transaction_history", []):
		if history_value is Dictionary:
			action_transaction_history.append((history_value as Dictionary).duplicate(true))
	var loaded_outing: Variant = data.get("active_outing_session", {})
	active_outing_session = (loaded_outing as Dictionary).duplicate(true) if loaded_outing is Dictionary else {}
	outing_history.clear()
	for outing_value: Variant in data.get("outing_history", []):
		if outing_value is Dictionary:
			outing_history.append((outing_value as Dictionary).duplicate(true))
	var loaded_failed_invites: Variant = data.get("failed_date_invites", {})
	failed_date_invites = (loaded_failed_invites as Dictionary).duplicate(true) if loaded_failed_invites is Dictionary else {}
	streamer_level = clampi(int(data.get("streamer_level", 1)), 1, 10)
	streamer_exp = maxi(int(data.get("streamer_exp", 0)), 0)
	growth_points = maxi(int(data.get("growth_points", 2)), 0)
	skill_levels = DEFAULT_SKILL_LEVELS.duplicate(true)
	skill_experience = DEFAULT_SKILL_EXPERIENCE.duplicate(true)
	var loaded_experience: Variant = data.get("skill_experience", {})
	if loaded_experience is Dictionary:
		for family: StringName in SKILL_FAMILIES:
			skill_experience[String(family)] = maxi(int((loaded_experience as Dictionary).get(String(family), 0)), 0)
	var loaded_levels: Variant = data.get("skill_levels", {})
	if loaded_levels is Dictionary:
		for family: StringName in SKILL_FAMILIES:
			skill_levels[String(family)] = clampi(int((loaded_levels as Dictionary).get(String(family), 1)), 1, 5)
	unlocked_skill_ids.clear()
	for skill_id: Variant in data.get("unlocked_skill_ids", []):
		var normalized_skill_id := StringName(str(skill_id))
		if normalized_skill_id != &"" and normalized_skill_id not in unlocked_skill_ids:
			unlocked_skill_ids.append(normalized_skill_id)
	material_instances = data.get("material_instances", {}).duplicate(true)
	material_serial = maxi(int(data.get("material_serial", 0)), 0)
	persona_progress = data.get("persona_progress", {}).duplicate(true)
	active_persona_id = str(data.get("active_persona_id", "persona_default"))
	graduated_personas.clear()
	for persona_id: Variant in data.get("graduated_personas", []):
		var normalized_id: String = str(persona_id)
		if not normalized_id.is_empty() and normalized_id not in graduated_personas:
			graduated_personas.append(normalized_id)
	completed_stream_sessions.clear()
	for session_id: Variant in data.get("completed_stream_sessions", []):
		var normalized_session_id: String = str(session_id)
		if not normalized_session_id.is_empty() and normalized_session_id not in completed_stream_sessions:
			completed_stream_sessions.append(normalized_session_id)
	stream_history.clear()
	var loaded_history: Variant = data.get("stream_history", [])
	if loaded_history is Array:
		for entry: Variant in loaded_history:
			if entry is Dictionary:
				stream_history.append((entry as Dictionary).duplicate(true))
	relationships = data.get("relationships", {}).duplicate(true)
	linkchat_initialized = bool(data.get("linkchat_initialized", false))
	linkchat_friend_ids.clear()
	for character_id: Variant in data.get("linkchat_friend_ids", []):
		var normalized_character_id: String = str(character_id).strip_edges()
		if not normalized_character_id.is_empty() and normalized_character_id not in linkchat_friend_ids:
			linkchat_friend_ids.append(normalized_character_id)
	linkchat_messages.clear()
	for message_value: Variant in data.get("linkchat_messages", []):
		if message_value is Dictionary:
			linkchat_messages.append((message_value as Dictionary).duplicate(true))
	linkchat_message_serial = maxi(int(data.get("linkchat_message_serial", 0)), 0)
	mail_messages.clear()
	for mail_value: Variant in data.get("mail_messages", []):
		if mail_value is Dictionary:
			mail_messages.append((mail_value as Dictionary).duplicate(true))
	mail_message_serial = maxi(int(data.get("mail_message_serial", 0)), 0)
	social_posts.clear()
	for social_post_value: Variant in data.get("social_posts", []):
		if social_post_value is Dictionary:
			social_posts.append((social_post_value as Dictionary).duplicate(true))
	social_post_serial = maxi(int(data.get("social_post_serial", 0)), 0)
	var loaded_vector: Variant = data.get("fan_vector", {})
	if loaded_vector is Dictionary and not loaded_vector.is_empty():
		set_fan_vector(loaded_vector)
	flame_value = float(data.get("flame_value", 0.0))
	contract = data.get("contract", {"debt": 0, "period_results": []}).duplicate(true)
	state_loaded.emit()
