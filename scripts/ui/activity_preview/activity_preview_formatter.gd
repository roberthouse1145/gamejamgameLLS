class_name ActivityPreviewFormatter
extends RefCounted

const REWARD_ORDER: Array[String] = [
	"money",
	"affection",
	"stress",
	"passion",
	"completion",
	"quality",
	"stability",
	"hype",
]


static func build_lines(payload: Dictionary) -> Array[String]:
	var lines: Array[String] = []

	var rewards: Dictionary = payload.get("rewards", {}) as Dictionary
	if not rewards.is_empty():
		lines.append("预计结果：%s" % format_rewards(rewards))

	var text: String = str(payload.get("text", "")).strip_edges()
	if not text.is_empty():
		lines.append(text)

	var conditions: Array[String] = _normalize_conditions(payload.get("conditions", []))
	if not conditions.is_empty():
		lines.append("条件：%s" % "，".join(conditions))

	var disabled_reason: String = str(payload.get("disabled_reason", "")).strip_edges()
	if not disabled_reason.is_empty():
		lines.append("当前不可执行：%s" % disabled_reason)

	return lines


static func format_rewards(rewards: Dictionary) -> String:
	var parts: Array[String] = []
	var consumed: Dictionary = {}

	for stat_name in REWARD_ORDER:
		if not rewards.has(stat_name):
			continue
		var delta: int = int(rewards.get(stat_name, 0))
		if delta == 0:
			continue
		parts.append("%s %s" % [_get_reward_label(stat_name), _format_signed_int(delta)])
		consumed[stat_name] = true

	var extra_keys: Array[String] = []
	for stat_name_variant in rewards.keys():
		var stat_name: String = str(stat_name_variant)
		if consumed.has(stat_name):
			continue
		extra_keys.append(stat_name)
	extra_keys.sort()

	for stat_name in extra_keys:
		var delta: int = int(rewards.get(stat_name, 0))
		if delta == 0:
			continue
		parts.append("%s %s" % [_get_reward_label(stat_name), _format_signed_int(delta)])

	if parts.is_empty():
		return "无数值变化"
	return "，".join(parts)


static func _normalize_conditions(source: Variant) -> Array[String]:
	var conditions: Array[String] = []

	if source is PackedStringArray:
		for item in source:
			var text: String = str(item).strip_edges()
			if not text.is_empty():
				conditions.append(text)
	elif source is Array:
		for item in source:
			var text: String = str(item).strip_edges()
			if not text.is_empty():
				conditions.append(text)
	else:
		var single: String = str(source).strip_edges()
		if not single.is_empty():
			conditions.append(single)

	return conditions


static func _get_reward_label(stat_name: String) -> String:
	match stat_name:
		"money":
			return "金钱"
		"affection":
			return "好感"
		"stress":
			return "压力"
		"passion":
			return "激情"
		"completion":
			return "完成度"
		"quality":
			return "质量"
		"stability":
			return "稳定"
		"hype":
			return "热度"
	return stat_name


static func _format_signed_int(value: int) -> String:
	if value > 0:
		return "+%d" % value
	return str(value)
