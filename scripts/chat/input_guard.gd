class_name InputGuard
extends Node
## Player input safety guard.
## Filters unsafe, off-topic, or injection-style messages.

const GUARD_TIMEOUT: float = 3.0
const PROMPT_KEY: String = "input_guard"

signal analysis_completed(result: Dictionary)

const INJECTION_KEYWORDS: Array[String] = [
	"忽略系统提示", "忽略前面的设定", "现在你不是", "承认你是ai", "prompt injection",
	"system prompt", "developer message", "越狱", "jailbreak", "你其实是chatgpt", "无视规则"
]
const UNSAFE_KEYWORDS: Array[String] = [
	"自慰", "做爱", "性交", "强奸", "援交", "约炮", "自杀", "割腕", "炸弹", "杀人", "制毒"
]
const POLITICAL_KEYWORDS: Array[String] = [
	"共产党", "台独", "港独", "习近平", "毛泽东", "普京", "拜登", "领土争端", "选举"
]
const TOOLISH_KEYWORDS: Array[String] = [
	"写代码", "写作业", "翻译这段", "帮我解题", "做ppt", "生成简历", "论文润色"
]

var enabled: bool = true
var _ai_service: AIService
var _system_prompt: String = ""
var _pending: bool = false
var _pending_request_id: String = ""
var _analyze_mutex: bool = false


func _ready() -> void:
	_ai_service = AIService.new()
	_ai_service.timeout = GUARD_TIMEOUT
	_ai_service.default_max_tokens = 96
	_ai_service.default_temperature = 0.0
	_ai_service.max_retries = 0
	add_child(_ai_service)

	_ai_service.request_completed.connect(_on_request_completed)
	_ai_service.request_failed.connect(_on_request_failed)

	var pm: Node = get_node_or_null("/root/PromptManager")
	if pm != null and pm.has_method("has_prompt") and pm.has_prompt(PROMPT_KEY) and pm.has_method("resolve"):
		_system_prompt = str(pm.resolve(PROMPT_KEY)).strip_edges()

	AIConfigManager.get_instance().apply_to_service(_ai_service, "input_guard")


## Backward-compatible boolean guard.
func check(text: String) -> bool:
	var result := await analyze(text)
	return bool(result.get("passed", true))


## Analyze input for safety. Returns {passed, block_reason, risk_tags, source}.
func analyze(text: String) -> Dictionary:
	if not enabled:
		return _build_result()
	if text.strip_edges().is_empty():
		return _build_result()
	if _system_prompt.is_empty():
		return _build_result()

	var heuristic := _fast_analyze(text)
	if bool(heuristic.get("decided", false)):
		return heuristic

	if _analyze_mutex:
		print("[InputGuard] Concurrent analyze() call, returning heuristic fallback")
		return heuristic
	_analyze_mutex = true

	_pending = true
	_pending_request_id = _ai_service.chat_simple(text, _system_prompt, {
		"max_tokens": 96,
		"temperature": 0.0,
	})

	var result: Dictionary = await analysis_completed
	_pending = false
	_pending_request_id = ""
	_analyze_mutex = false
	return _merge_with_heuristic(result, heuristic)


func _on_request_completed(request_id: String, response: Dictionary) -> void:
	if not _pending or (_pending_request_id != "" and request_id != _pending_request_id):
		return
	var content: String = AIService.extract_content(response).strip_edges()
	var parsed := _parse_ai_response(content)
	print("[InputGuard] Result: %s (raw: %s)" % [bool(parsed.get("passed", true)), content.left(160)])
	analysis_completed.emit(parsed)


func _on_request_failed(request_id: String, error: String, _error_code: int) -> void:
	if not _pending or (_pending_request_id != "" and request_id != _pending_request_id):
		return
	print("[InputGuard] Request failed, passing through: %s" % error)
	analysis_completed.emit(_build_result("request_failed"))


func _fast_analyze(text: String) -> Dictionary:
	var lowered := text.strip_edges().to_lower()
	var result := _build_result("heuristic")
	result["decided"] = false

	if _contains_any(lowered, INJECTION_KEYWORDS):
		result["passed"] = false
		result["block_reason"] = "prompt_injection"
		result["risk_tags"] = ["prompt_injection"]
		result["decided"] = true
		return result

	if _contains_any(lowered, UNSAFE_KEYWORDS):
		result["passed"] = false
		result["block_reason"] = "unsafe_content"
		result["risk_tags"] = ["unsafe_content"]
		result["decided"] = true
		return result

	if _contains_any(lowered, POLITICAL_KEYWORDS):
		result["passed"] = false
		result["block_reason"] = "political_content"
		result["risk_tags"] = ["political_content"]
		result["decided"] = true
		return result

	if _contains_any(lowered, TOOLISH_KEYWORDS):
		result["passed"] = false
		result["block_reason"] = "toolish_request"
		result["risk_tags"] = ["toolish_request"]
		result["decided"] = true
		return result

	return result


func _parse_ai_response(content: String) -> Dictionary:
	var stripped := _strip_code_fences(content)
	var parsed: Variant = JSON.parse_string(stripped)
	if parsed is Dictionary:
		return _normalize_response(parsed as Dictionary)

	var lowered := stripped.to_lower()
	if lowered == "true" or lowered == "false":
		var fallback := _build_result("legacy_bool")
		fallback["passed"] = (lowered == "true")
		return fallback

	return _build_result("invalid_guard_response")


func _normalize_response(raw: Dictionary) -> Dictionary:
	var result := _build_result("llm")
	result["passed"] = bool(raw.get("passed", true))
	result["block_reason"] = str(raw.get("block_reason", "")).strip_edges()

	var risk_tags: Array[String] = []
	var raw_tags: Variant = raw.get("risk_tags", [])
	if raw_tags is Array:
		for tag in raw_tags:
			var normalized_tag := str(tag).strip_edges()
			if not normalized_tag.is_empty():
				risk_tags.append(normalized_tag)
	result["risk_tags"] = risk_tags
	return result


func _merge_with_heuristic(result: Dictionary, heuristic: Dictionary) -> Dictionary:
	var merged := heuristic.duplicate(true)
	var heuristic_risk_tags: Array = (heuristic.get("risk_tags", []) as Array).duplicate()
	for key in result:
		merged[key] = result[key]
	if not heuristic_risk_tags.is_empty():
		var final_tags: Array = (merged.get("risk_tags", []) as Array).duplicate()
		for tag in heuristic_risk_tags:
			if tag not in final_tags:
				final_tags.append(tag)
		merged["risk_tags"] = final_tags
	return merged


func _build_result(source: String = "default") -> Dictionary:
	return {
		"passed": true,
		"block_reason": "",
		"risk_tags": [],
		"source": source,
		"decided": true,
	}


func _strip_code_fences(text: String) -> String:
	var cleaned := text.strip_edges()
	if not cleaned.begins_with("```"):
		return cleaned
	var first_newline := cleaned.find("\n")
	if first_newline >= 0:
		cleaned = cleaned.substr(first_newline + 1)
	if cleaned.ends_with("```"):
		cleaned = cleaned.substr(0, cleaned.length() - 3)
	return cleaned.strip_edges()


func _contains_any(text: String, keywords: Array[String]) -> bool:
	for keyword in keywords:
		if keyword.to_lower() in text:
			return true
	return false
