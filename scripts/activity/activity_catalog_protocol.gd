class_name ActivityCatalogProtocol
extends RefCounted

const ActivityBlockParserClass = preload("res://scripts/activity/activity_block_parser.gd")

const JOB_TAG: String = "JOB"
const DATE_EVENT_TAG: String = "DATE_EVENT"
const VALID_PHASES: PackedStringArray = ["MORNING", "AFTERNOON", "NIGHT"]

const DATE_LOCATION_DEFAULTS := {
	"park": {
		"title": "中央公园",
		"map_position": Vector2(0.2, 0.3),
		"accent_color": "#72C28C",
	},
	"commercial": {
		"title": "商业区",
		"map_position": Vector2(0.55, 0.35),
		"accent_color": "#F2A65A",
	},
	"school": {
		"title": "蓝鲸大学",
		"map_position": Vector2(0.4, 0.55),
		"accent_color": "#7D8FE8",
	},
	"harbor": {
		"title": "旧港区",
		"map_position": Vector2(0.8, 0.7),
		"accent_color": "#5B9BD5",
	},
	"gate": {
		"title": "校门口",
		"map_position": Vector2(0.3, 0.6),
		"accent_color": "#9DC183",
	},
}


static func parse_part_time_catalog(raw_text: String, max_count: int, week_index: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var local_index: int = 0
	for raw_job in ActivityBlockParserClass.parse_blocks(raw_text, JOB_TAG):
		if not raw_job is Dictionary:
			continue
		var normalized := normalize_part_time_job(raw_job as Dictionary, week_index, local_index)
		if normalized.is_empty():
			continue
		result.append(normalized)
		local_index += 1
		if result.size() >= max_count:
			break
	return result


static func normalize_part_time_job(raw_job: Dictionary, week_index: int, local_index: int = 0) -> Dictionary:
	var title: String = _clean_text(raw_job.get("job_title", raw_job.get("title", "")))
	if title.is_empty():
		return {}

	var job_id: String = _clean_id(raw_job.get("job_id", ""))
	if job_id.is_empty():
		job_id = "llm_job_w%d_%02d" % [maxi(0, week_index), local_index]

	var company_name: String = _clean_text(raw_job.get("company_name", "双人兼职"))
	var district: String = _clean_text(raw_job.get("district", "城市边缘"))
	var subtitle: String = _clean_text(raw_job.get("subtitle", "双人短班"))
	var description: String = _clean_text(raw_job.get("description", raw_job.get("detail_prompt", "")))
	var detail_prompt: String = _clean_text(raw_job.get("detail_prompt", description))
	var zone_path: String = _normalize_zone_path(str(raw_job.get("zone_path", "")))
	var accent_color: String = _normalize_color(str(raw_job.get("accent_color", "")), "#10B981")
	var reward_money: int = maxi(0, int(raw_job.get("reward_money", raw_job.get("money", 0))))
	if reward_money <= 0:
		var rewards_data: Variant = raw_job.get("rewards", {})
		if rewards_data is Dictionary:
			reward_money = maxi(0, int((rewards_data as Dictionary).get("money", 0)))
	if reward_money <= 0:
		reward_money = 120
	var reward_stress: int = int(raw_job.get("reward_stress", raw_job.get("stress", _default_job_stress(reward_money))))
	var reward_passion: int = int(raw_job.get("reward_passion", raw_job.get("passion", _default_job_passion(reward_money))))

	var valid_phases: Array[String] = _normalize_valid_phases(raw_job.get("valid_phases", []))
	if valid_phases.is_empty():
		valid_phases = ["AFTERNOON", "NIGHT"]

	return {
		"job_id": job_id,
		"job_title": title,
		"company_name": company_name,
		"district": district,
		"rewards": {
			"money": reward_money,
			"stress": reward_stress,
			"passion": reward_passion,
		},
		"subtitle": subtitle,
		"description": description,
		"zone_path": zone_path,
		"accent_color": accent_color,
		"detail_prompt": detail_prompt,
		"valid_phases": valid_phases,
		"enabled": true,
		"source_type": "llm_block",
	}


static func parse_date_events(raw_text: String, target_day: int, max_count: int = 4) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var local_index: int = 0
	for raw_event in ActivityBlockParserClass.parse_blocks(raw_text, DATE_EVENT_TAG):
		if not raw_event is Dictionary:
			continue
		var normalized := normalize_date_event(raw_event as Dictionary, target_day, local_index)
		if normalized.is_empty():
			continue
		result.append(normalized)
		local_index += 1
		if result.size() >= max_count:
			break
	return result


static func normalize_date_event(raw_event: Dictionary, target_day: int, local_index: int = 0) -> Dictionary:
	var title: String = _clean_text(raw_event.get("title", ""))
	if title.is_empty():
		return {}

	var location_id: String = _normalize_location_id(str(raw_event.get("location_id", "")))
	var defaults: Dictionary = DATE_LOCATION_DEFAULTS.get(location_id, {
		"title": "城市一角",
		"map_position": Vector2(0.5, 0.5),
		"accent_color": "#7D8FE8",
	})

	var event_id: String = _clean_id(raw_event.get("event_id", ""))
	if event_id.is_empty():
		event_id = "day%d_evt_%02d" % [maxi(1, target_day), local_index]

	var valid_phases: Array[String] = _normalize_valid_phases(raw_event.get("valid_phases", []))
	if valid_phases.is_empty():
		valid_phases = ["AFTERNOON"]

	var rewards: Dictionary = _collect_reward_fields(raw_event)
	rewards.erase("affection")
	if not rewards.has("stress"):
		rewards["stress"] = _default_date_stress(location_id)
	if not rewards.has("passion"):
		rewards["passion"] = _default_date_passion(location_id)
	var map_position: Vector2 = _normalize_map_position(raw_event.get("map_position", null), defaults.get("map_position", Vector2(0.5, 0.5)))
	var accent_color: String = _normalize_color(str(raw_event.get("accent_color", "")), str(defaults.get("accent_color", "#7D8FE8")))

	return {
		"event_id": event_id,
		"title": title,
		"location_title": _clean_text(raw_event.get("location_title", defaults.get("title", ""))),
		"location_id": location_id,
		"subtitle": _clean_text(raw_event.get("subtitle", "")),
		"description": _clean_text(raw_event.get("description", "")),
		"detail_prompt": _clean_text(raw_event.get("detail_prompt", "")),
		"activity_hint": _clean_text(raw_event.get("activity_hint", "")),
		"valid_phases": valid_phases,
		"map_position": map_position,
		"accent_color": accent_color,
		"rewards": rewards,
		"source_type": "llm_block",
	}


static func _collect_reward_fields(raw_data: Dictionary) -> Dictionary:
	var rewards: Dictionary = {}
	for key_variant in raw_data.keys():
		var key: String = str(key_variant)
		if not key.begins_with("reward_"):
			continue
		var reward_name: String = key.trim_prefix("reward_").strip_edges()
		if reward_name.is_empty():
			continue
		rewards[reward_name] = int(raw_data.get(key_variant, 0))

	var nested_rewards: Variant = raw_data.get("rewards", {})
	if nested_rewards is Dictionary:
		for reward_key in (nested_rewards as Dictionary).keys():
			rewards[str(reward_key)] = int((nested_rewards as Dictionary).get(reward_key, 0))
	return rewards


static func _default_job_stress(reward_money: int) -> int:
	if reward_money >= 180:
		return 18
	if reward_money >= 150:
		return 12
	return 10


static func _default_job_passion(reward_money: int) -> int:
	if reward_money >= 180:
		return -8
	if reward_money >= 150:
		return -5
	return -3


static func _default_date_stress(location_id: String) -> int:
	match location_id:
		"harbor":
			return -22
		"commercial", "gate":
			return -20
		_:
			return -18


static func _default_date_passion(location_id: String) -> int:
	match location_id:
		"harbor":
			return 3
		"commercial", "gate":
			return 2
		_:
			return 1


static func _normalize_valid_phases(raw_value: Variant) -> Array[String]:
	var result: Array[String] = []
	if raw_value is Array:
		for phase in raw_value:
			var normalized := str(phase).strip_edges().to_upper()
			if VALID_PHASES.has(normalized) and not result.has(normalized):
				result.append(normalized)
	elif raw_value is String:
		for part in str(raw_value).split("|", false):
			var normalized := str(part).strip_edges().to_upper()
			if VALID_PHASES.has(normalized) and not result.has(normalized):
				result.append(normalized)
	return result


static func _normalize_map_position(raw_value: Variant, fallback: Vector2) -> Vector2:
	if raw_value is Vector2:
		var vec := raw_value as Vector2
		return Vector2(clampf(vec.x, 0.0, 1.0), clampf(vec.y, 0.0, 1.0))
	if raw_value is Array and (raw_value as Array).size() >= 2:
		return Vector2(
			clampf(float((raw_value as Array)[0]), 0.0, 1.0),
			clampf(float((raw_value as Array)[1]), 0.0, 1.0)
		)
	if raw_value is String:
		var parts := str(raw_value).split("|", false)
		if parts.size() >= 2:
			return Vector2(
				clampf(float(str(parts[0]).strip_edges()), 0.0, 1.0),
				clampf(float(str(parts[1]).strip_edges()), 0.0, 1.0)
			)
	return fallback


static func _normalize_location_id(raw_value: String) -> String:
	var normalized: String = raw_value.strip_edges().to_lower()
	if DATE_LOCATION_DEFAULTS.has(normalized):
		return normalized
	return "school"


static func _normalize_zone_path(raw_value: String) -> String:
	var normalized: String = raw_value.strip_edges()
	var allowed := {
		"res://resources/maps/zone_school.tres": true,
		"res://resources/maps/zone_commercial.tres": true,
		"res://resources/maps/zone_residential.tres": true,
	}
	if allowed.has(normalized):
		return normalized
	return "res://resources/maps/zone_school.tres"


static func _normalize_color(raw_value: String, fallback: String) -> String:
	var normalized: String = raw_value.strip_edges()
	if normalized.is_empty():
		return fallback
	if normalized.begins_with("#") and (normalized.length() == 7 or normalized.length() == 9):
		return normalized
	return fallback


static func _clean_text(raw_value: Variant) -> String:
	return str(raw_value).strip_edges()


static func _clean_id(raw_value: Variant) -> String:
	var cleaned: String = str(raw_value).strip_edges().to_lower()
	if cleaned.is_empty():
		return ""
	var result: String = ""
	for i in range(cleaned.length()):
		var ch: String = cleaned.substr(i, 1)
		var is_valid: bool = (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "_"
		if is_valid:
			result += ch
		elif ch == "-" or ch == " ":
			result += "_"
	return result.strip_edges()
