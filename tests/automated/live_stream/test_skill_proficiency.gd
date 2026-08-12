extends Node
## 领域熟练度推进领域等级，并以总熟练度推进中之人等级和公共成长点。

const SKILL_DOMAINS: StreamerSkillDomainCatalog = preload(
	"res://resources/live_stream/skills/streamer_skill_domains.tres"
)


func _ready() -> void:
	assert(SKILL_DOMAINS.domains.size() == GameState.SKILL_FAMILIES.size())
	assert(SKILL_DOMAINS.validate_content().is_empty())
	for family: StringName in GameState.SKILL_FAMILIES:
		var domain: StreamerSkillDomainResource = SKILL_DOMAINS.get_domain(family)
		assert(domain != null)
		assert(not domain.get_level_prompt(1).is_empty())
		assert(not domain.get_level_prompt(5).is_empty())

	var balance := LiveStreamBalance.new()
	balance.level_exp_thresholds = PackedInt32Array([0, 50, 120])
	balance.skill_exp_thresholds = PackedInt32Array([0, 40, 100, 200, 400])

	GameState.streamer_level = 1
	GameState.streamer_exp = 0
	GameState.growth_points = 0
	GameState.skill_levels = GameState.DEFAULT_SKILL_LEVELS.duplicate(true)
	GameState.skill_experience = GameState.DEFAULT_SKILL_EXPERIENCE.duplicate(true)

	var growth: Dictionary = GameState.apply_skill_experience({
		"game": 40,
		"song": 15,
	}, balance)
	assert(GameState.get_skill_experience(&"game") == 40)
	assert(GameState.get_skill_level(&"game") == 2)
	assert(GameState.get_skill_experience(&"song") == 15)
	assert(GameState.get_skill_level(&"song") == 1)
	assert(int(growth.get("total_exp", 0)) == 55)
	assert(GameState.streamer_exp == 55)
	assert(GameState.streamer_level == 2)
	assert(GameState.growth_points == 1)

	var saved: Dictionary = GameState.to_dict()
	GameState.skill_experience = GameState.DEFAULT_SKILL_EXPERIENCE.duplicate(true)
	GameState.skill_levels = GameState.DEFAULT_SKILL_LEVELS.duplicate(true)
	GameState.from_dict(saved)
	assert(GameState.get_skill_experience(&"game") == 40)
	assert(GameState.get_skill_level(&"game") == 2)
	print("SKILL_PROFICIENCY_TEST_PASS")
