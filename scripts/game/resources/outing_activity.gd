class_name OutingActivity extends Resource
## 玩家实际选择的一次外出内容；常驻地点与限时事件共享此契约。

const KIND_PLACE: String = "place"
const KIND_EVENT: String = "event"
const NARRATIVE_LLM: String = "llm_avg"

@export var activity_id: String = ""
@export var place_id: String = ""
@export var listing_kind: String = KIND_PLACE
@export var title: String = ""
@export_multiline var description: String = ""
@export var available_slots: Array[int] = [0, 1, 2]
@export var available_from_day: int = 1
@export var available_until_day: int = 999
@export var duration_slots: int = 1
@export var solo_cost: int = 0
@export var date_cost: int = 0
@export var supports_solo: bool = true
@export var supports_date: bool = true
@export var tags: Array[String] = []
@export_range(5, 95, 1) var base_acceptance: int = 45
@export var relationship_favor_gain: int = 4
@export var relationship_trust_gain: int = 2
@export var stress_delta: int = -8
@export var loneliness_delta: int = -10
@export var narrative_mode: String = NARRATIVE_LLM
@export_multiline var solo_scene_prompt: String = ""
@export_multiline var date_scene_prompt: String = ""


func is_available(day: int, time_slot: int) -> bool:
	return day >= available_from_day and day <= available_until_day and time_slot in available_slots


func is_valid() -> bool:
	return not activity_id.strip_edges().is_empty() \
		and not place_id.strip_edges().is_empty() \
		and not title.strip_edges().is_empty() \
		and duration_slots > 0
