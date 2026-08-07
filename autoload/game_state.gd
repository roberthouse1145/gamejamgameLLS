extends Node
## GameState Autoload
## 《家里蹲主播》运行时状态唯一真相源（对应策划案 §4.1 四分法）。
## 属性/资源/成长/关系/跨场数值全部经由此处读写；存档通过 to_dict/from_dict。

## 属性跨越阈值时发出（crossed_up: 向上跨为 true，回落为 false）
signal attribute_threshold_crossed(attr_name: String, threshold: int, crossed_up: bool)
signal attribute_changed(attr_name: String, value: int)
signal money_changed(value: int)
signal fans_changed(value: int)
signal streamer_progress_changed(level: int, exp: int, growth_points: int)
signal skill_levels_changed(family: StringName, level: int)
signal skill_nodes_changed()
signal material_inventory_changed()

const ATTR_STRESS: String = "stress"
const ATTR_OTAKU_DESIRE: String = "otaku_desire"
const ATTR_LONELINESS: String = "loneliness"

## 属性阈值（策划案 §4.2）：压力 >60 演出降质 / >80 摆烂 / 100 坏结局；
## 宅欲 >70 演出打折 / >90 摆烂；孤独 >70 日记变丧 / >90 社交事故
const ATTRIBUTE_THRESHOLDS: Dictionary = {
	ATTR_STRESS: [60, 80, 100],
	ATTR_OTAKU_DESIRE: [70, 90],
	ATTR_LONELINESS: [70, 90],
}

const TIME_SLOT_MORNING: int = 0
const TIME_SLOT_AFTERNOON: int = 1
const TIME_SLOT_NIGHT: int = 2

const FAN_VECTOR_KEYS: Array[String] = ["r", "m", "w", "c", "b"]

const SKILL_FAMILIES: Array[StringName] = [&"game", &"talk", &"song", &"act", &"tech"]
const DEFAULT_SKILL_LEVELS: Dictionary = {
	"game": 1,
	"talk": 1,
	"song": 1,
	"act": 1,
	"tech": 1,
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

## LLM 身份：开局玩家输入的 Vtuber 网名（真名只出现在聊天/合同语境）
var streamer_name: String = ""

## 主播成长：直播产生 EXP，升级授予公共成长点，玩家再投资五条技能分支。
var streamer_level: int = 1
var streamer_exp: int = 0
var growth_points: int = 2
var skill_levels: Dictionary = DEFAULT_SKILL_LEVELS.duplicate(true)
var unlocked_skill_ids: Array[StringName] = []

## 素材运行态：instance_id -> definition_id/depth/progress/freshness/use_count。
var material_instances: Dictionary = {}
var material_serial: int = 0
## 人设运行态：persona_id -> proficiency/fixation。
var persona_progress: Dictionary = {}
## 已提交直播的事务 ID，保证结算幂等。
var completed_stream_sessions: Array[String] = []
## 直播记录保存为可序列化快照；运行时由 StreamHistoryManager 转为 Resource。
var stream_history: Array[Dictionary] = []

## 关系：character_key -> {"favor": int, "trust": int, "dependence": int}
var relationships: Dictionary = {}

## 跨场：粉丝构成五类互斥向量（归一化百分比）/ 炎上值 / 契约进度
var fan_vector: Dictionary = {"r": 100.0, "m": 0.0, "w": 0.0, "c": 0.0, "b": 0.0}
var flame_value: float = 0.0
var contract: Dictionary = {"debt": 0, "period_results": []}


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


## 用角色资源初值建档；已存在则不覆盖
func init_relationship(character: StreamerCharacter) -> void:
	if character == null or character.character_key.is_empty():
		push_error("GameState: init_relationship requires a character with character_key")
		return
	if relationships.has(character.character_key):
		return
	relationships[character.character_key] = {
		"favor": character.initial_favor,
		"trust": character.initial_trust,
		"dependence": character.initial_dependence,
	}


func change_relationship(character_key: String, favor: int = 0, trust: int = 0, dependence: int = 0) -> void:
	if not relationships.has(character_key):
		push_warning("GameState: relationship '%s' not initialized, creating with zeros" % character_key)
		relationships[character_key] = {"favor": 0, "trust": 0, "dependence": 0}
	var entry: Dictionary = relationships[character_key]
	entry["favor"] += favor
	entry["trust"] += trust
	entry["dependence"] += dependence


func get_relationship(character_key: String) -> Dictionary:
	return relationships.get(character_key, {})


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


func to_dict() -> Dictionary:
	return {
		"stress": stress,
		"otaku_desire": otaku_desire,
		"loneliness": loneliness,
		"money": money,
		"fans": fans,
		"day": day,
		"time_slot": time_slot,
		"streamer_name": streamer_name,
		"streamer_level": streamer_level,
		"streamer_exp": streamer_exp,
		"growth_points": growth_points,
		"skill_levels": skill_levels.duplicate(true),
		"unlocked_skill_ids": unlocked_skill_ids.duplicate(),
		"material_instances": material_instances.duplicate(true),
		"material_serial": material_serial,
		"persona_progress": persona_progress.duplicate(true),
		"completed_stream_sessions": completed_stream_sessions.duplicate(),
		"stream_history": stream_history.duplicate(true),
		"relationships": relationships.duplicate(true),
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
	streamer_name = str(data.get("streamer_name", ""))
	streamer_level = clampi(int(data.get("streamer_level", 1)), 1, 10)
	streamer_exp = maxi(int(data.get("streamer_exp", 0)), 0)
	growth_points = maxi(int(data.get("growth_points", 2)), 0)
	skill_levels = DEFAULT_SKILL_LEVELS.duplicate(true)
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
	var loaded_vector: Variant = data.get("fan_vector", {})
	if loaded_vector is Dictionary and not loaded_vector.is_empty():
		set_fan_vector(loaded_vector)
	flame_value = float(data.get("flame_value", 0.0))
	contract = data.get("contract", {"debt": 0, "period_results": []}).duplicate(true)
