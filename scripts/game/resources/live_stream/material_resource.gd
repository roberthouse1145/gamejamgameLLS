class_name LiveStreamMaterialResource extends StreamContentResource
## 一次性素材定义；播一场烧一张，无含量/进度/新鲜度（见策划案 §6.1）。

const TYPE_CONSUMABLE: StringName = &"consumable"
const TYPE_SPONSOR: StringName = &"sponsor"
const ACTIVITIES: Array[StringName] = [
	&"play",
	&"challenge",
	&"sing",
	&"discuss",
	&"react",
	&"debate",
	&"inspect_visual",
	&"imitate_voice",
	&"voice_performance",
]

@export var material_type: StringName = TYPE_CONSUMABLE
@export_range(0.0, 10000.0, 1.0) var base_popularity: float = 100.0
@export var activities: Array[StringName] = []
@export var skill_exp_rewards: StreamSkillExperience = null
@export var affinity: StreamFamilyValues = null
@export var axes: StreamAxisValues = null
@export var sponsor_terms: MaterialSponsorTerms = null


func is_valid() -> bool:
	if not is_valid_base() or material_type not in [TYPE_CONSUMABLE, TYPE_SPONSOR]:
		return false
	if skill_exp_rewards == null or affinity == null or axes == null:
		return false
	if activities.is_empty():
		return false
	for activity: StringName in activities:
		if activity not in ACTIVITIES:
			return false
	if skill_exp_rewards.get_total() <= 0:
		return false
	if material_type == TYPE_SPONSOR and (sponsor_terms == null or not sponsor_terms.is_valid()):
		return false
	return true


func get_material_type_label() -> String:
	if material_type == TYPE_SPONSOR:
		return "商单型"
	return "消耗型"


func _validate_property(property: Dictionary) -> void:
	# 素材内容形式只由 activities 表达，不再同时维护自由标签。
	if String(property.get("name", "")) == "tags":
		property["usage"] = int(property.get("usage", 0)) & ~PROPERTY_USAGE_EDITOR
