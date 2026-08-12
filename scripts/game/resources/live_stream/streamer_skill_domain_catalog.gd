class_name StreamerSkillDomainCatalog extends Resource
## 五领域能力描述目录。领域等级属于中之人，不属于当前人设或皮套。

@export var domains: Array[StreamerSkillDomainResource] = []


func get_domain(family: StringName) -> StreamerSkillDomainResource:
	for domain: StreamerSkillDomainResource in domains:
		if domain != null and domain.family == family:
			return domain
	return null


func validate_content() -> PackedStringArray:
	var errors: PackedStringArray = []
	var seen: Dictionary = {}
	for domain: StreamerSkillDomainResource in domains:
		if domain == null or not domain.is_valid():
			errors.append("技能领域配置无效")
			continue
		if seen.has(domain.family):
			errors.append("技能领域重复：%s" % String(domain.family))
		seen[domain.family] = true
	for family: StringName in GameState.SKILL_FAMILIES:
		if not seen.has(family):
			errors.append("缺少技能领域：%s" % String(family))
	return errors
