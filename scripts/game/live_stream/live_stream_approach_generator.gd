class_name LiveStreamApproachGenerator extends Node
## 为所选素材临时生成 2～3 个直播构思的真实 LLM 生成器。
## 质量达标前由 LiveStreamManager 显式调用，默认开播流程仍使用内置构思（策划案 §6.4 过渡）。

signal approaches_generated(request_id: String, approaches: Array[Dictionary])
signal approaches_failed(request_id: String, error: String)

const PROMPT_KEY: String = "live_stream/approach"
const APPROACH_ROLE: String = "live_stream_approach"
const MAX_ATTEMPTS: int = 2
const MIN_APPROACHES: int = 2
const MAX_APPROACHES: int = 3

var _service: AIService = null
var _service_ready: bool = false
var _request_contexts: Dictionary = {}


func _ready() -> void:
	_service = AIService.new()
	_service.name = "LiveStreamApproachWriter"
	add_child(_service)
	_service.request_completed.connect(_on_request_completed)
	_service.request_failed.connect(_on_request_failed)
	var config_manager := AIConfigManager.get_instance()
	if not config_manager.get_config_for_role(APPROACH_ROLE).is_empty():
		_service_ready = config_manager.apply_to_service(_service, APPROACH_ROLE)
	if not _service_ready:
		_service_ready = config_manager.apply_to_service(_service, "chat_default")


func is_ready() -> bool:
	return _service_ready and _service != null


## 渲染完整构思生成 prompt；context 由调用方按素材、人设、技能与状态组装。
func build_prompt(material: LiveStreamMaterialResource, context: Dictionary) -> String:
	if material == null or not PromptManager.has_prompt(PROMPT_KEY):
		return ""
	return PromptManager.resolve_with_vars(PROMPT_KEY, {
		"persona_block": str(context.get("persona_block", "")),
		"skill_block": str(context.get("skill_block", "")),
		"state_block": str(context.get("state_block", "")),
		"material_block": _format_material(material),
		"history_block": str(context.get("history_block", "")),
	}).strip_edges()


## 发起一次异步构思生成；返回 request_id，空串表示未能启动。
func request_approaches(material: LiveStreamMaterialResource, context: Dictionary) -> String:
	if material == null or not is_ready():
		return ""
	var prompt: String = build_prompt(material, context)
	if prompt.is_empty():
		return ""
	var request_id: String = _request_generation(prompt, 1)
	if request_id.is_empty():
		return ""
	_request_contexts[request_id] = {
		"material_id": String(material.content_id),
		"base_prompt": prompt,
		"attempt": 1,
	}
	return request_id


func cancel_all() -> void:
	_request_contexts.clear()


func _request_generation(prompt: String, attempt: int) -> String:
	return _service.chat([{"role": "system", "content": prompt}], {
		"temperature": 0.9,
		"max_tokens": 2048,
		"thinking": "disabled",
		"enable_thinking": false,
		"reasoning_effort": "",
		"prompt_key": PROMPT_KEY,
		"source": "live_stream_approach",
	})


func _on_request_completed(request_id: String, response: Dictionary) -> void:
	if not _request_contexts.has(request_id):
		return
	var context: Dictionary = _request_contexts[request_id] as Dictionary
	_request_contexts.erase(request_id)
	var raw_text: String = AIService.extract_content(response).strip_edges()
	var validation: Dictionary = _validate_generated(raw_text)
	if not bool(validation.get("success", false)):
		var attempt: int = int(context.get("attempt", 1))
		var base_prompt: String = str(context.get("base_prompt", ""))
		var errors: Array[String] = []
		errors.assign(validation.get("errors", []))
		if attempt < MAX_ATTEMPTS and not base_prompt.is_empty():
			var repair_prompt: String = base_prompt + (
				"\n\n## 本次输出未通过校验\n\n只修正以下已定位问题，重新输出完整 JSON 数组：\n- "
				+ "\n- ".join(errors)
			)
			var retry_id: String = _request_generation(repair_prompt, attempt + 1)
			if not retry_id.is_empty():
				_request_contexts[retry_id] = {
					"material_id": str(context.get("material_id", "")),
					"base_prompt": base_prompt,
					"attempt": attempt + 1,
				}
				return
		approaches_failed.emit(request_id, "直播构思未通过校验：%s" % "；".join(errors))
		return
	var approaches: Array[Dictionary] = []
	approaches.assign(validation.get("approaches", []))
	approaches_generated.emit(request_id, approaches)


func _on_request_failed(request_id: String, error: String, _error_code: int) -> void:
	if not _request_contexts.has(request_id):
		return
	_request_contexts.erase(request_id)
	approaches_failed.emit(request_id, error)


func _validate_generated(text: String) -> Dictionary:
	var errors: Array[String] = []
	var payload: Variant = _extract_json_array(text)
	if not (payload is Array):
		return {"success": false, "approaches": [], "errors": ["输出必须是 JSON 数组"]}
	var entries: Array = payload
	if entries.size() < MIN_APPROACHES or entries.size() > MAX_APPROACHES:
		errors.append("构思数量必须是 %d～%d 个，实际 %d 个" % [MIN_APPROACHES, MAX_APPROACHES, entries.size()])
	var approaches: Array[Dictionary] = []
	var seen_types: Dictionary = {}
	var seen_ids: Dictionary = {}
	for index: int in range(entries.size()):
		var entry: Variant = entries[index]
		if not (entry is Dictionary):
			errors.append("第 %d 个构思不是对象" % (index + 1))
			continue
		var approach := StreamApproach.from_dict(entry as Dictionary)
		if not approach.is_valid(LiveStreamBalance.APPROACH_TYPES):
			errors.append("第 %d 个构思缺少字段或类型不在白名单" % (index + 1))
			continue
		var type_key: String = String(approach.approach_type)
		if seen_types.has(type_key):
			errors.append("构思类型重复：%s" % type_key)
			continue
		seen_types[type_key] = true
		var normalized_id: String = "llm_%s_%02d" % [type_key, approaches.size() + 1]
		if seen_ids.has(normalized_id):
			errors.append("构思标识重复：%s" % normalized_id)
			continue
		seen_ids[normalized_id] = true
		approach.approach_id = StringName(normalized_id)
		approaches.append(approach.to_dict())
	if not errors.is_empty():
		return {"success": false, "approaches": [], "errors": errors}
	return {"success": true, "approaches": approaches, "errors": []}


func _extract_json_array(text: String) -> Variant:
	var normalized: String = text.strip_edges()
	var start: int = normalized.find("[")
	var end: int = normalized.rfind("]")
	if start < 0 or end <= start:
		return null
	var json := JSON.new()
	if json.parse(normalized.substr(start, end - start + 1)) != OK:
		return null
	return json.data


func _format_material(material: LiveStreamMaterialResource) -> String:
	var lines: Array[String] = []
	var type_label: String = "商单型" if material.material_type == LiveStreamMaterialResource.TYPE_SPONSOR else "消耗型"
	lines.append("《%s》（%s）" % [material.display_name, type_label])
	if not material.description.strip_edges().is_empty():
		lines.append("描述：%s" % material.description.strip_edges())
	var activity_names: Array[String] = []
	for activity: StringName in material.activities:
		activity_names.append(String(activity))
	if not activity_names.is_empty():
		lines.append("活动：%s" % ", ".join(activity_names))
	var affinity_lines: Array[String] = []
	if material.affinity != null:
		for family: StringName in GameState.SKILL_FAMILIES:
			var value: float = material.affinity.get_value(family)
			if value != 0.0:
				affinity_lines.append("%s %s" % [String(family), str(value)])
	if not affinity_lines.is_empty():
		lines.append("领域适配：%s" % ", ".join(affinity_lines))
	var fragment: String = material.prompt_fragment.strip_edges()
	if not fragment.is_empty():
		lines.append("导演资料：%s" % fragment)
	return "\n".join(lines)
