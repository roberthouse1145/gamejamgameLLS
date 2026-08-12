extends ScrollContainer
## 主播中心总览：只呈现长期业务能力、观众结构与成长进度。

const BALANCE: LiveStreamBalance = preload("res://resources/live_stream/balance/vertical_slice_balance.tres")

const ABILITY_LABELS: Dictionary = {
	"game": "游戏力",
	"talk": "杂谈力",
	"song": "歌唱力",
	"act": "演出力",
	"tech": "杂项力",
}

@onready var channel_avatar: RoundedAvatar = %ChannelAvatar
@onready var channel_name_label: Label = %ChannelName
@onready var channel_meta_label: Label = %ChannelMeta
@onready var follower_value: Label = %FollowerValue
@onready var stream_count_value: Label = %StreamCountValue
@onready var material_count_value: Label = %CardCountValue
@onready var skill_count_value: Label = %SkillCountValue
@onready var ability_radar: StreamerAbilityRadar = %AbilityRadar
@onready var ability_hint: Label = %AbilityHint
@onready var fan_breakdown: Label = %FanBreakdown
@onready var fan_hint_label: Label = %FanHint
@onready var material_progress_label: Label = %CardProgress
@onready var skill_progress_label: Label = %SkillProgress
@onready var history_progress_label: Label = %HistoryProgress

@onready var ability_value_labels: Dictionary = {
	"game": %GamingValue,
	"talk": %TalkValue,
	"song": %SingingValue,
	"act": %VarietyValue,
	"tech": %VoiceValue,
}

@onready var fan_segments: Dictionary = {
	"r": %FanR,
	"m": %FanM,
	"w": %FanW,
	"c": %FanC,
	"b": %FanB,
}


func _ready() -> void:
	GameState.fans_changed.connect(_on_fans_changed)
	GameState.skill_levels_changed.connect(_on_skill_level_changed)
	GameState.skill_experience_changed.connect(_on_skill_experience_changed)
	GameState.persona_changed.connect(_on_persona_changed)
	MaterialInventoryManager.inventory_changed.connect(_refresh_growth)
	SkillTreeManager.skill_tree_changed.connect(_refresh_growth)
	LiveStreamManager.history_changed.connect(_refresh_growth)
	refresh()


func refresh() -> void:
	var persona: StreamPersonaResource = _get_active_persona()
	var channel_name: String = persona.channel_name if persona != null else "暂无频道"
	channel_name_label.text = channel_name
	channel_meta_label.text = "频道运营第 %d 天" % GameState.day
	channel_avatar.set_avatar(
		persona.channel_avatar if persona != null else null,
		channel_name
	)
	follower_value.text = _format_number(GameState.fans)
	_refresh_abilities()
	_refresh_fan_vector()
	_refresh_growth()


func _refresh_abilities() -> void:
	ability_radar.set_values(GameState.skill_levels)
	var strongest_key: String = String(GameState.SKILL_FAMILIES[0])
	var weakest_key: String = strongest_key
	for family: StringName in GameState.SKILL_FAMILIES:
		var ability_name := String(family)
		var value: int = GameState.get_skill_level(family)
		var experience: int = GameState.get_skill_experience(family)
		var value_label: Label = ability_value_labels[ability_name]
		if value >= BALANCE.skill_exp_thresholds.size():
			value_label.text = "Lv.%d · MAX" % value
		else:
			value_label.text = "Lv.%d · %d/%d" % [
				value,
				experience,
				BALANCE.skill_exp_thresholds[value],
			]
		if value > GameState.get_skill_level(StringName(strongest_key)):
			strongest_key = ability_name
		if value < GameState.get_skill_level(StringName(weakest_key)):
			weakest_key = ability_name
	ability_hint.text = "当前优势：%s　·　待提升：%s" % [ABILITY_LABELS[strongest_key], ABILITY_LABELS[weakest_key]]


func _refresh_fan_vector() -> void:
	var vector: Dictionary = GameState.fan_vector
	for key: String in fan_segments:
		var segment: Control = fan_segments[key]
		segment.size_flags_stretch_ratio = maxf(float(vector.get(key, 0.0)), 0.5)
	fan_breakdown.text = "路人 %.0f%%　男粉 %.0f%%　女粉 %.0f%%　核心粉 %.0f%%　黑粉 %.0f%%" % [
		float(vector.get("r", 0.0)),
		float(vector.get("m", 0.0)),
		float(vector.get("w", 0.0)),
		float(vector.get("c", 0.0)),
		float(vector.get("b", 0.0)),
	]

	var black_fans: float = float(vector.get("b", 0.0))
	var core_fans: float = float(vector.get("c", 0.0))
	var passerby: float = float(vector.get("r", 0.0))
	if black_fans > 15.0:
		fan_hint_label.text = "黑粉正在聚集，争议性内容更容易收到负面反馈。"
	elif core_fans + black_fans > 60.0:
		fan_hint_label.text = "观众结构开始固化，稳定变现的同时也更难吸引新观众。"
	elif passerby > 60.0:
		fan_hint_label.text = "大多数观众仍在观望，下一场表现会决定他们是否留下。"
	else:
		fan_hint_label.text = "稳定观众正在形成，内容方向会继续改变他们的构成。"


func _refresh_growth() -> void:
	var material_count: int = MaterialInventoryManager.get_instances().size()
	var unlocked_skill_count: int = SkillTreeManager.get_unlocked_skill_ids().size()
	material_progress_label.text = "库存中还有 %d 份可播素材" % material_count
	var skills: Array[StreamerSkill] = SkillTreeManager.get_skills()
	skill_progress_label.text = "已掌握 %d / %d 项 · 剩余 %d 成长点" % [
		unlocked_skill_count,
		skills.size(),
		SkillTreeManager.get_skill_points(),
	]
	var history_count: int = LiveStreamManager.get_history_records().size()
	history_progress_label.text = "暂无直播记录" if history_count == 0 else "已保存 %d 场直播" % history_count
	stream_count_value.text = str(history_count)
	material_count_value.text = str(material_count)
	skill_count_value.text = "%d / %d" % [unlocked_skill_count, skills.size()]


func _format_number(value: int) -> String:
	var raw := str(maxi(value, 0))
	var output := ""
	for index: int in range(raw.length()):
		if index > 0 and (raw.length() - index) % 3 == 0:
			output += ","
		output += raw[index]
	return output


func _get_active_persona() -> StreamPersonaResource:
	var catalog: LiveStreamCatalog = LiveStreamManager.get_catalog()
	if catalog == null:
		return null
	return catalog.get_persona(StringName(GameState.active_persona_id))


func _on_fans_changed(_value: int) -> void:
	refresh()


func _on_skill_level_changed(_family: StringName, _value: int) -> void:
	_refresh_abilities()


func _on_skill_experience_changed(_family: StringName, _experience: int, _level: int) -> void:
	_refresh_abilities()


func _on_persona_changed(_old_persona_id: String, _new_persona_id: String) -> void:
	refresh()
