class_name LiveStreamCardResource extends StreamContentResource
## 行为卡和修饰卡的公共卡面与解锁字段。

const FAMILY_GAME: StringName = &"game"
const FAMILY_TALK: StringName = &"talk"
const FAMILY_SONG: StringName = &"song"
const FAMILY_ACT: StringName = &"act"
const FAMILY_TECH: StringName = &"tech"
const FAMILIES: Array[StringName] = [FAMILY_GAME, FAMILY_TALK, FAMILY_SONG, FAMILY_ACT, FAMILY_TECH]

@export var family: StringName = FAMILY_TALK
@export_range(1, 3, 1) var tier: int = 1
@export_range(0, 20, 1) var budget_cost: int = 2
@export_range(-20.0, 50.0, 0.5) var stress_cost: float = 0.0
@export var fan_bias: StreamFanBias = null
@export var required_skill_family: StringName = &""
@export_range(1, 5, 1) var required_skill_level: int = 1
@export var special_effects: Array[StreamSpecialEffect] = []


func get_card_kind() -> StringName:
	return &"card"


func get_family_display_name() -> String:
	match family:
		FAMILY_GAME:
			return "游戏"
		FAMILY_TALK:
			return "杂谈"
		FAMILY_SONG:
			return "歌唱"
		FAMILY_ACT:
			return "演出"
		FAMILY_TECH:
			return "杂项"
	return "未知"


func is_valid() -> bool:
	if not is_valid_base() or family not in FAMILIES or tier < 1 or tier > 3 or budget_cost < 0:
		return false
	if required_skill_family != &"" and required_skill_family not in FAMILIES:
		return false
	for effect: StreamSpecialEffect in special_effects:
		if effect == null or not effect.is_valid():
			return false
	return true
