extends Node

const AIServiceClass = preload("res://scripts/llm/AIService.gd")


func _ready() -> void:
	print("=== AIService URL Normalization Test ===")
	_test_chat_url_defaults_to_v1()
	_test_chat_url_preserves_existing_version()
	_test_chat_url_preserves_full_endpoint()
	_test_chat_url_handles_nonstandard_version_segment()
	_test_completion_url_defaults_to_v1()
	print("=== All tests passed ===")


func _test_chat_url_defaults_to_v1() -> void:
	var ai := AIServiceClass.new()
	ai.api_base_url = "https://api.deepseek.com"
	assert(ai._resolve_chat_api_url() == "https://api.deepseek.com/v1/chat/completions")
	print("  PASS: _test_chat_url_defaults_to_v1")


func _test_chat_url_preserves_existing_version() -> void:
	var ai := AIServiceClass.new()
	ai.api_base_url = "https://open.bigmodel.cn/api/paas/v4"
	assert(ai._resolve_chat_api_url() == "https://open.bigmodel.cn/api/paas/v4/chat/completions")
	print("  PASS: _test_chat_url_preserves_existing_version")


func _test_chat_url_preserves_full_endpoint() -> void:
	var ai := AIServiceClass.new()
	ai.api_base_url = "https://open.bigmodel.cn/api/paas/v4/chat/completions"
	assert(ai._resolve_chat_api_url() == "https://open.bigmodel.cn/api/paas/v4/chat/completions")
	print("  PASS: _test_chat_url_preserves_full_endpoint")


func _test_chat_url_handles_nonstandard_version_segment() -> void:
	var ai := AIServiceClass.new()
	ai.api_base_url = "https://generativelanguage.googleapis.com/v1beta/openai"
	assert(ai._resolve_chat_api_url() == "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")
	print("  PASS: _test_chat_url_handles_nonstandard_version_segment")


func _test_completion_url_defaults_to_v1() -> void:
	var ai := AIServiceClass.new()
	ai.api_base_url = "https://api.example.com/custom"
	assert(ai._resolve_completion_api_url() == "https://api.example.com/custom/v1/completions")
	print("  PASS: _test_completion_url_defaults_to_v1")
