extends Node
## Property-based test for AIConfigManager
## Property 1: 角色配置往返一致性
## For any role-to-profile mapping written in ai_config.cfg, loading the config
## and then querying get_config_for_role(role) should return a dictionary
## containing the correct base_url, api_key, and model matching the profile
## definition.
## **Validates: Requirements 1.1, 1.2**

const ITERATIONS: int = 100

## Expected role -> profile mappings from ai_config.cfg
const ROLE_TO_PROFILE: Dictionary = {
	"boss": "doubao-pro",
	"writer": "deepseek-v3",
	"worker": "doubao-mini",
	"lookup": "doubao-mini",
}

## Expected profile data from ai_config.cfg
const EXPECTED_PROFILES: Dictionary = {
	"doubao-pro": {
		"type": "chat",
		"base_url": "https://ark.cn-beijing.volces.com/api",
		"api_key": "1638253e-e12e-4bbc-a4d0-f6b48f430317",
		"model": "doubao-seed-2-0-pro-260215",
	},
	"deepseek-v3": {
		"type": "chat",
		"base_url": "https://ark.cn-beijing.volces.com/api",
		"api_key": "1638253e-e12e-4bbc-a4d0-f6b48f430317",
		"model": "deepseek-v3-2-251201",
	},
	"doubao-mini": {
		"type": "chat",
		"base_url": "https://ark.cn-beijing.volces.com/api",
		"api_key": "1638253e-e12e-4bbc-a4d0-f6b48f430317",
		"model": "doubao-seed-2-0-mini-260215",
	},
}

const REQUIRED_ROLES: Array = ["boss", "writer", "worker", "lookup"]

var _runner: PropertyTestRunner
var _all_passed: bool = true
var _results: Array[Dictionary] = []


func _ready() -> void:
	_runner = PropertyTestRunner.new()

	print("========== AIConfigManager Property Tests ==========")
	print("Iterations per property: %d" % ITERATIONS)
	print("")

	_run_property1_role_config_round_trip()

	print("")
	print("========== Summary ==========")
	for r: Dictionary in _results:
		print(r["summary"])

	print("")
	if _all_passed:
		print("ALL AI CONFIG MANAGER PROPERTY TESTS PASSED")
	else:
		print("SOME AI CONFIG MANAGER PROPERTY TESTS FAILED")


## Helper: record a property test result
func _record_property(result: Dictionary) -> void:
	_results.append(result)
	print(result["summary"])
	if not result["success"]:
		_all_passed = false


## ============================================================
## Property 1: 角色配置往返一致性
## For any role-to-profile mapping written in ai_config.cfg, loading the config
## and then querying get_config_for_role(role) should return a dictionary
## containing the correct base_url, api_key, and model matching the profile
## definition.
## **Validates: Requirements 1.1, 1.2**
## ============================================================
func _run_property1_role_config_round_trip() -> void:
	var result: Dictionary = _runner.run_property(
		"Property 1: 角色配置往返一致性", ITERATIONS,
		func(rng: RandomNumberGenerator, _i: int) -> String:
			# Create a fresh AIConfigManager and load config each iteration
			var config_mgr: AIConfigManager = AIConfigManager.new()
			var loaded: bool = config_mgr.load_config()
			if not loaded:
				return "load_config() returned false — ai_config.cfg not found"

			# Randomly select one of the 4 required roles
			var role_index: int = rng.randi_range(0, REQUIRED_ROLES.size() - 1)
			var role: String = REQUIRED_ROLES[role_index]

			# Query the config for this role
			var config: Dictionary = config_mgr.get_config_for_role(role)

			# Verify the returned dictionary is not empty
			if config.is_empty():
				return "get_config_for_role('%s') returned empty dictionary" % role

			# Verify required fields exist
			for field: String in ["base_url", "api_key", "model"]:
				if not config.has(field):
					return "Config for role '%s' missing field '%s'. Got keys: %s" % [
						role, field, str(config.keys())]

			# Get expected profile name and data
			var expected_profile: String = ROLE_TO_PROFILE[role]
			var expected: Dictionary = EXPECTED_PROFILES[expected_profile]

			# Verify base_url matches
			if config["base_url"] != expected["base_url"]:
				return "Role '%s' base_url mismatch: expected '%s', got '%s'" % [
					role, expected["base_url"], config["base_url"]]

			# Verify api_key matches
			if config["api_key"] != expected["api_key"]:
				return "Role '%s' api_key mismatch: expected '%s', got '%s'" % [
					role, expected["api_key"], config["api_key"]]

			# Verify model matches
			if config["model"] != expected["model"]:
				return "Role '%s' model mismatch: expected '%s', got '%s'" % [
					role, expected["model"], config["model"]]

			# Also verify that querying a non-existent role returns empty
			var fake_role: String = "nonexistent_" + AVGResourceGenerators.random_string(rng, 3, 10)
			var empty_config: Dictionary = config_mgr.get_config_for_role(fake_role)
			if not empty_config.is_empty():
				return "get_config_for_role('%s') should return empty dict, got: %s" % [
					fake_role, str(empty_config)]

			return ""
	)
	_record_property(result)
