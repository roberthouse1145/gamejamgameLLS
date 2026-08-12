class_name OutingActivity extends Resource
## 玩家可选择的外出计划；隐藏剧情钩子只在 AVG 生成阶段使用。

@export var activity_id: String = ""
@export var place_id: String = ""
@export var title: String = ""
@export_multiline var description: String = ""
@export_multiline var story_hook: String = ""
@export var available_slots: Array[int] = [0, 1, 2]
@export var available_from_day: int = 1
@export var available_until_day: int = 999
@export var duration_slots: int = 1
@export var solo_cost: int = 0
@export var date_cost: int = 0
@export var supports_solo: bool = true
@export var supports_date: bool = true
@export_range(5, 95, 1) var base_acceptance: int = 45
@export var relationship_favor_gain: int = 4
@export var relationship_trust_gain: int = 2
@export var stress_delta: int = -8
@export var loneliness_delta: int = -10


func is_available(day: int, time_slot: int) -> bool:
	return day >= available_from_day and day <= available_until_day and time_slot in available_slots


func is_valid() -> bool:
	return not activity_id.strip_edges().is_empty() \
		and not place_id.strip_edges().is_empty() \
		and not title.strip_edges().is_empty() \
		and not story_hook.strip_edges().is_empty() \
		and duration_slots > 0
