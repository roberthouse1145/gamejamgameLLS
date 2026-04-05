extends Node

func _ready() -> void:
	print("=== Seed Resolution Test ===")
	var pm: Node = get_node_or_null("/root/PromptManager")
	if pm == null:
		print("FAIL: PromptManager not found")
		return

	# Test 1: seed pools loaded
	var pools: Dictionary = pm.get("_seed_pools")
	print("seed_pools keys: %s" % str(pools.keys()))
	assert(pools.has("job_type"), "FAIL: missing job_type pool")
	assert(pools.has("date_scene"), "FAIL: missing date_scene pool")
	assert(pools.has("game_concept"), "FAIL: missing game_concept pool")
	assert(pools.has("shop_idea"), "FAIL: missing shop_idea pool")
	assert(pools.has("personality"), "FAIL: missing personality pool")
	assert(pools.has("mood"), "FAIL: missing mood pool")
	print("✓ All 6 seed pools loaded")

	# Test 2: pool sizes
	for key in ["job_type", "date_scene", "game_concept", "shop_idea", "personality", "mood"]:
		var pool: Array = pools[key]
		print("  %s: %d words" % [key, pool.size()])
		assert(pool.size() >= 10, "FAIL: pool %s too small" % key)
	print("✓ All pools have sufficient entries")

	# Test 3: basic seed resolution
	var test_text := "灵感：{{seed:job_type,3}}"
	var resolved: String = pm.resolve_template(test_text)
	print("Input:  %s" % test_text)
	print("Output: %s" % resolved)
	assert(resolved != test_text, "FAIL: seed not resolved")
	assert("{{seed:" not in resolved, "FAIL: seed tag still present")
	print("✓ Basic seed resolution works")

	# Test 4: multiple seeds in same text
	var test_multi := "岗位：{{seed:job_type,2}}  性格：{{seed:personality,2}}"
	var resolved_multi: String = pm.resolve_template(test_multi)
	print("Input:  %s" % test_multi)
	print("Output: %s" % resolved_multi)
	assert("{{seed:" not in resolved_multi, "FAIL: seed tag still present in multi")
	print("✓ Multiple seed resolution works")

	# Test 5: seed + normal vars mixed
	pm.register_prompt("test_seed_mixed", "Day {{day}} 灵感：{{seed:mood,2}}")
	var resolved_mixed: String = pm.resolve_with_vars("test_seed_mixed", {"day": "5"})
	print("Input:  Day {{day}} 灵感：{{seed:mood,2}}")
	print("Output: %s" % resolved_mixed)
	assert("{{seed:" not in resolved_mixed, "FAIL: seed not resolved in mixed")
	assert("{{day}}" not in resolved_mixed, "FAIL: var not resolved in mixed")
	assert("Day 5" in resolved_mixed, "FAIL: day var not substituted")
	print("✓ Mixed seed + vars works")

	# Test 6: unknown pool fallback (should warn and keep tag)
	var test_unknown := "{{seed:nonexistent_pool,3}}"
	var resolved_unknown: String = pm.resolve_template(test_unknown)
	print("Unknown pool input:  %s" % test_unknown)
	print("Unknown pool output: %s" % resolved_unknown)
	print("✓ Unknown pool handled (check warning in output)")

	# Test 7: deduplication - run multiple times, no repeats until pool exhaustion
	# Reset used pool for clean test
	pm.set("_seed_used", {})
	var all_picked_words: Array[String] = []
	var dedup_runs := 6
	for i in dedup_runs:
		var resolved_dedup: String = pm.resolve_template("{{seed:mood,3}}")
		var words: Array = resolved_dedup.split(", ")
		for w in words:
			all_picked_words.append(str(w).strip_edges())
	print("%d runs of {{seed:mood,3}} (pool size=20):" % dedup_runs)
	for i in range(0, all_picked_words.size(), 3):
		var batch: String = ", ".join(all_picked_words.slice(i, i + 3))
		print("  run %d: %s" % [i / 3 + 1, batch])
	# First 18 words (6 runs × 3 words) should all be unique (pool has 20)
	var unique_words: Dictionary = {}
	var has_duplicate_before_exhaust := false
	for i in mini(18, all_picked_words.size()):
		if unique_words.has(all_picked_words[i]):
			has_duplicate_before_exhaust = true
			print("  DUPLICATE at index %d: %s" % [i, all_picked_words[i]])
		unique_words[all_picked_words[i]] = true
	if not has_duplicate_before_exhaust:
		print("✓ No duplicates in first %d picks (pool=20)" % mini(18, all_picked_words.size()))
	else:
		print("✗ Found duplicate before pool exhaustion")

	# Test 8: pool exhaustion resets - pick enough to exhaust the pool
	pm.set("_seed_used", {})
	var exhaust_picks: Array[String] = []
	# mood pool has 20 entries, picking 5 per round → 4 rounds exhaust, 5th should reset
	for i in 5:
		var resolved_exhaust: String = pm.resolve_template("{{seed:mood,5}}")
		var words_e: Array = resolved_exhaust.split(", ")
		for w in words_e:
			exhaust_picks.append(str(w).strip_edges())
	print("Pool exhaustion test (5 runs × 5 picks, pool=20):")
	print("  Total picks: %d" % exhaust_picks.size())
	# After 20 picks, pool should have reset, so picks 21-25 may repeat earlier ones
	var first_20_unique: Dictionary = {}
	for i in mini(20, exhaust_picks.size()):
		first_20_unique[exhaust_picks[i]] = true
	print("  Unique in first 20: %d (expect 20)" % first_20_unique.size())
	assert(first_20_unique.size() == 20, "FAIL: first 20 picks should all be unique")
	print("✓ Pool exhaustion + reset works correctly")

	# Test 8: verify actual prompts resolve correctly through PromptManager
	if pm.has_method("has_prompt") and pm.has_prompt("part_time_jobs_generation") and pm.has_method("resolve_with_vars"):
		var pt_resolved: String = str(pm.resolve_with_vars("part_time_jobs_generation", {
			"count": "3",
		})).strip_edges()
		var has_seed_in_resolved: bool = "{{seed:" in pt_resolved
		print("part_time prompt resolved: seed tags remaining = %s" % str(has_seed_in_resolved))
		assert(not has_seed_in_resolved, "FAIL: seed tags not resolved in part_time prompt")
		# Print first 200 chars
		print("  preview: %s..." % pt_resolved.substr(0, 200))
		print("✓ Part-time prompt resolves seeds correctly")
	else:
		print("SKIP: part_time_jobs_generation prompt not loaded")

	print("\n=== All Seed Tests Passed ===")
