extends Node
## Property-based test for AIConfigManager
## Property 1: 角色配置往返一致性
## For any role-to-profile mapping written in ai_config.cfg, loading the config
## and then querying get_config_for_role(role) should return a dictionary
## containing the correct base_url, api_key, and model matching the profile
## definition.
## **Validates: Requirements 1.1, 1.2**

const ITERATIONS: int = 100

const EXPECTED_CHAT_BASE_URL: String = "https://api.deepseek.com"
const EXPECTED_CHAT_MODEL: String = "deepseek-v4-flash"
const FORBIDDEN_MODEL_MARKERS: PackedStringArray = ["doubao", "gemini", "deepseek-v3", "deepseek-chat", "deepseek-reasoner"]

const REQUIRED_ROLES: Array = [
	"chat_default",
	"linkchat",
	"input_guard",
	"memory_summarizer",
	"file_viewer",
	"browser",
	"dev_planner",
	"signup_review",
	"creative_brief_outline",
	"date_event",
	"sbeam_catalog_generator",
	"shop_generator",
	"avg_dev_main",
	"avg_dev_writer",
	"avg_dev_executor",
	"date_scene_writer",
	"dsl_repair",
	"part_time_generator",
	"minigame",
	"creative_decision",
	"date_scene_reviewer",
	"work_order",
	"work_order_controller",
	"work_order_planner",
	"work_order_writer",
	"work_order_executor",
]

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

			# Verify base_url matches
			if config["base_url"] != EXPECTED_CHAT_BASE_URL:
				return "Role '%s' base_url mismatch: expected '%s', got '%s'" % [
					role, EXPECTED_CHAT_BASE_URL, config["base_url"]]

			# Verify api_key is configured without pinning a real secret in source.
			if str(config["api_key"]).strip_edges().is_empty():
				return "Role '%s' api_key is empty" % role

			# Verify model matches
			if config["model"] != EXPECTED_CHAT_MODEL:
				return "Role '%s' model mismatch: expected '%s', got '%s'" % [
					role, EXPECTED_CHAT_MODEL, config["model"]]

			var model_lower: String = str(config["model"]).to_lower()
			for marker in FORBIDDEN_MODEL_MARKERS:
				if model_lower.find(marker) >= 0:
					return "Role '%s' uses forbidden legacy model marker '%s': %s" % [role, marker, config["model"]]

			# Also verify that querying a non-existent role returns empty
			var fake_role: String = "nonexistent_%d" % rng.randi_range(100000, 999999)
			var empty_config: Dictionary = config_mgr.get_config_for_role(fake_role)
			if not empty_config.is_empty():
				return "get_config_for_role('%s') should return empty dict, got: %s" % [
					fake_role, str(empty_config)]

			return ""
	)
	_record_property(result)
