extends Node

## 活动目录 LLM 内容质量预览场景。
## 运行 res://tests/lab/llm/activity_catalog_llm_preview.tscn 后，会直接打印活动/目录类 prompt 的原始 LLM 输出。
## 注意：这是人工审稿用场景，会真实调用 LLM API，不会自动退出。

const AIServiceClass = preload("res://scripts/llm/AIService.gd")
const ShopCatalogStaticDataClass = preload("res://scripts/shop/shop_catalog_static_data.gd")

@export var preview_part_time: bool = true
@export var preview_sbeam: bool = true
@export var preview_shop: bool = true
@export var preview_date: bool = true
@export var preview_count: int = 4
@export var target_day: int = 2

var _pending: Dictionary = {}


func _ready() -> void:
	call_deferred("_run_preview")


func _run_preview() -> void:
	print("\n=== Activity Catalog LLM Preview ===")
	print("This scene sends real LLM requests and prints raw outputs. It will not auto-exit.\n")

	var pm: Node = get_node_or_null("/root/PromptManager")
	if pm == null:
		push_error("[ActivityCatalogLLMPreview] PromptManager not found")
		return

	if preview_part_time:
		_request_part_time(pm)
	if preview_sbeam:
		_request_sbeam(pm)
	if preview_shop:
		_request_shop(pm)
	if preview_date:
		_request_date(pm)

	if _pending.is_empty():
		print("[ActivityCatalogLLMPreview] No preview requests enabled.")


func _request_part_time(pm: Node) -> void:
	var prompt := _resolve_prompt(pm, "part_time_jobs_generation", {
		"count": str(preview_count),
	})
	var system_prompt := "Output only [JOB] ... [/JOB] blocks. No JSON. No markdown. No explanations."
	_start_request(
		"part_time_jobs_generation",
		"part_time_generator",
		prompt,
		system_prompt,
		{"temperature": 0.95}
	)


func _request_sbeam(pm: Node) -> void:
	var prompt := _resolve_prompt(pm, "sbeam_catalog_generation", {
		"count": str(preview_count),
		"target_day": str(target_day),
	})
	var system_prompt := "Output only [SBEAM_GAME] ... [/SBEAM_GAME] blocks. No JSON. No markdown. No explanations."
	_start_request(
		"sbeam_catalog_generation",
		"sbeam_catalog_generator",
		prompt,
		system_prompt,
		{"temperature": 0.95}
	)


func _request_shop(pm: Node) -> void:
	var prompt := _resolve_prompt(pm, "shop/catalog_generation_user", {
		"shop_target_count": str(preview_count),
		"shop_day": str(target_day),
		"shop_effect_whitelist": ", ".join(ShopCatalogStaticDataClass.get_effect_archetype_keys()),
		"shop_state_block": "当前游戏状态：好感 100，压力 10，激情 100，金钱 500，GameJam 初期。",
	})
	var system_prompt := _resolve_prompt(pm, "shop/catalog_generation_system", {})
	_start_request(
		"shop/catalog_generation_user",
		"shop_generator",
		prompt,
		system_prompt,
		{"temperature": 0.9}
	)


func _request_date(pm: Node) -> void:
	var prompt := _resolve_prompt(pm, "date_event_generation", {
		"next_day": str(target_day),
		"game_state": "好感 100；压力 10；激情 100；金钱 500；比赛刚开始，二人仍在熟悉开发节奏。",
		"recent_history": "暂无约会历史。",
	})
	var system_prompt := "Output only [DATE_EVENT] ... [/DATE_EVENT] blocks. No JSON. No markdown. No explanations."
	_start_request(
		"date_event_generation",
		"date_event",
		prompt,
		system_prompt,
		{"temperature": 0.95}
	)


func _resolve_prompt(pm: Node, prompt_key: String, vars: Dictionary) -> String:
	if not pm.has_method("has_prompt") or not pm.has_prompt(prompt_key):
		push_error("[ActivityCatalogLLMPreview] Missing prompt key: %s" % prompt_key)
		return ""
	if not pm.has_method("resolve_with_vars"):
		push_error("[ActivityCatalogLLMPreview] PromptManager has no resolve_with_vars")
		return ""
	return str(pm.resolve_with_vars(prompt_key, vars)).strip_edges()


func _start_request(prompt_key: String, role: String, prompt: String, system_prompt: String, options: Dictionary) -> void:
	if prompt.is_empty():
		push_error("[ActivityCatalogLLMPreview] Empty prompt: %s" % prompt_key)
		return

	var ai: AIService = AIServiceClass.new()
	ai.name = "Preview_%s" % prompt_key.replace("/", "_")
	ai.max_history_messages = 0
	ai.auto_execute_tools = false
	ai.max_concurrent_requests = 1
	add_child(ai)

	var cfg := AIConfigManager.get_instance()
	var enabled := false
	if cfg != null and not cfg.get_config_for_role(role).is_empty():
		enabled = cfg.apply_to_service(ai, role)
	if not enabled and cfg != null and not cfg.get_config_for_role("chat_default").is_empty():
		enabled = cfg.apply_to_service(ai, "chat_default")
	if not enabled:
		push_error("[ActivityCatalogLLMPreview] No AI config for role: %s" % role)
		ai.queue_free()
		return

	options = options.duplicate(true)
	options["prompt_key"] = prompt_key
	options["source"] = "ActivityCatalogLLMPreview"
	options["max_tokens"] = int(options.get("max_tokens", 4096))

	ai.request_completed.connect(_on_request_completed.bind(prompt_key, ai))
	ai.request_failed.connect(_on_request_failed.bind(prompt_key, ai))

	var request_id := ai.chat_simple(prompt, system_prompt, options)
	if request_id.is_empty():
		push_error("[ActivityCatalogLLMPreview] Failed to send request: %s" % prompt_key)
		ai.queue_free()
		return

	_pending[request_id] = prompt_key
	print("[ActivityCatalogLLMPreview] sent prompt_key=%s role=%s req=%s chars=%d" % [
		prompt_key,
		role,
		request_id,
		prompt.length(),
	])


func _on_request_completed(request_id: String, response: Dictionary, prompt_key: String, ai: AIService) -> void:
	_pending.erase(request_id)
	var raw_text := AIServiceClass.extract_content(response).strip_edges()
	print("\n================ LLM RAW OUTPUT: %s ================" % prompt_key)
	print(raw_text)
	print("================ END: %s ================\n" % prompt_key)
	_cleanup_ai(ai)
	_print_done_if_finished()


func _on_request_failed(request_id: String, error: String, error_code: int, prompt_key: String, ai: AIService) -> void:
	_pending.erase(request_id)
	push_error("[ActivityCatalogLLMPreview] request failed prompt_key=%s req=%s code=%d error=%s" % [
		prompt_key,
		request_id,
		error_code,
		error,
	])
	_cleanup_ai(ai)
	_print_done_if_finished()


func _cleanup_ai(ai: AIService) -> void:
	if is_instance_valid(ai):
		ai.queue_free()


func _print_done_if_finished() -> void:
	if _pending.is_empty():
		print("[ActivityCatalogLLMPreview] All preview requests finished. Review the raw outputs above.")
