class_name MinigameContentService
extends Node

const ActivityOptionLLMServiceClass = preload("res://scripts/activity/activity_option_llm_service.gd")

const PRIMARY_ROLE: String = "minigame"
const FALLBACK_ROLES: Array[String] = ["chat_default"]
const DEFAULT_DOCS_PER_CATEGORY: int = 2
const MAX_DOC_CHARS: int = 420
const MAX_TOTAL_CONTEXT_CHARS: int = 1800
const MAX_SLOT_COUNT: int = 5
const MIN_SCRIPT_FILL_BLANKS: int = 2
const MAX_LINE_CHARS: int = 48
const SUGGESTIONS_PER_SLOT: int = 3
const MIN_EMOTION_TAG_ITEMS: int = 6
const MAX_EMOTION_TAG_ITEMS: int = 10
const MIN_EMOTION_TAG_OPTIONS: int = 3
const EMOTION_TAG_OPTIONS_PER_ITEM: int = 5
const EMOTION_TAG_LINE_MAX_CHARS: int = 40
const EMOTION_TAG_LABEL_MAX_CHARS: int = 10
const EMOTION_TAG_FALLBACK_POOL: Array[String] = [
	"期待",
	"欣喜",
	"感激",
	"安心",
	"骄傲",
	"愤怒",
	"委屈",
	"绝望",
	"恐惧",
	"焦虑",
	"冷淡",
	"犹豫",
	"困惑",
	"释然",
	"倦怠",
	"口是心非",
	"故作镇定",
	"担忧",
]
const SCRIPT_FILL_BLANK_MARKERS := [
	"<<<FILL>>>",
	"<<FILL>>",
	"<BLANK>",
	"<blank>",
	"[BLANK]",
	"[blank]",
	"__BLANK__",
	"___",
]

signal content_ready(
	request_id: String,
	task_id: String,
	minigame_type: String,
	content: Dictionary,
	used_fallback: bool,
	error_message: String
)

var _llm_service: ActivityOptionLLMService = null
var _llm_ready: bool = false


func _ready() -> void:
	_llm_service = ActivityOptionLLMServiceClass.new()
	_llm_service.name = "MinigameContentLLMService"
	add_child(_llm_service)
	_llm_service.request_completed.connect(_on_llm_request_completed)
	_llm_service.request_failed.connect(_on_llm_request_failed)
	_llm_ready = _llm_service.configure(
		"MinigameContentLLMService",
		PRIMARY_ROLE,
		FALLBACK_ROLES,
		{},
		{
			"temperature": 0.5,
		}
	)


func supports(minigame_type: String) -> bool:
	return minigame_type == "script_fill" or minigame_type == "emotion_tag"


func request_content(task_data: Dictionary) -> String:
	var minigame_type: String = str(task_data.get("minigame_type", "")).strip_edges()
	var task_id: String = str(task_data.get("task_id", "")).strip_edges()
	var request_id: String = "mg_fallback_%d" % int(Time.get_ticks_msec())
	var fallback_content: Dictionary = _build_fallback_content(minigame_type, task_data)

	if not supports(minigame_type):
		call_deferred(
			"_emit_content_ready",
			request_id,
			task_id,
			minigame_type,
			fallback_content,
			true,
			"unsupported_minigame_type"
		)
		return request_id

	var config_mgr := AIConfigManager.get_instance()
	if config_mgr != null and config_mgr.is_background_llm_disabled():
		call_deferred(
			"_emit_content_ready",
			request_id,
			task_id,
			minigame_type,
			fallback_content,
			true,
			"background_llm_disabled"
		)
		return request_id

	var kb_context: String = _build_kb_context(task_data)
	if not _llm_ready or _llm_service == null or not _llm_service.is_enabled():
		call_deferred(
			"_emit_content_ready",
			request_id,
			task_id,
			minigame_type,
			fallback_content,
			true,
			"llm_not_configured"
		)
		return request_id

	var work_order: Dictionary = _get_effective_work_order(task_data)
	var prompt_vars: Dictionary = {
		"task_title": str(work_order.get("title", "")).strip_edges(),
		"task_description": str(work_order.get("description", "")).strip_edges(),
		"task_scene_target": str(work_order.get("scene_target", "")).strip_edges(),
		"task_performance_context": str(work_order.get("performance_context", "")).strip_edges(),
		"minigame_type": minigame_type,
		"kb_context": kb_context,
	}
	var type_meta: Dictionary = _get_type_prompt_meta(minigame_type)
	prompt_vars["type_specific_instructions"] = str(type_meta.get("instructions", "")).strip_edges()
	prompt_vars["output_schema"] = str(type_meta.get("output_schema", "")).strip_edges()

	var system_prompt: String = _resolve_prompt(
		"minigame_content_generator_system",
		{},
		"你是一个小游戏内容生成器。请只输出符合要求的 DSL 文本。"
	)
	var user_prompt: String = _resolve_prompt(
		"minigame_content_generator",
		prompt_vars,
		_build_fallback_prompt(prompt_vars)
	)

	request_id = _llm_service.request_text(
		user_prompt,
		system_prompt,
		{
			"task_id": task_id,
			"minigame_type": minigame_type,
			"fallback_content": fallback_content,
		},
		{}
	)
	if request_id.is_empty():
		request_id = "mg_fallback_%d" % int(Time.get_ticks_msec())
		call_deferred(
			"_emit_content_ready",
			request_id,
			task_id,
			minigame_type,
			fallback_content,
			true,
			"request_start_failed"
		)
	return request_id


func _on_llm_request_completed(request_id: String, context: Dictionary, raw_text: String, _response: Dictionary) -> void:
	var task_id: String = str(context.get("task_id", "")).strip_edges()
	var minigame_type: String = str(context.get("minigame_type", "")).strip_edges()
	var fallback_content: Dictionary = context.get("fallback_content", {})
	print("[MinigameContentService] LLM raw response (%s/%s):\n%s\n[MinigameContentService] End raw response" % [
		minigame_type,
		task_id,
		raw_text,
	])
	var normalized: Dictionary = _normalize_generated_content(minigame_type, raw_text, fallback_content)
	var content: Dictionary = normalized.get("content", fallback_content)
	var payload_count: int = 0
	if content.get("blocks", []) is Array:
		payload_count = (content.get("blocks", []) as Array).size()
	elif content.get("slots", []) is Array:
		payload_count = (content.get("slots", []) as Array).size()
	elif content.get("items", []) is Array:
		payload_count = (content.get("items", []) as Array).size()
	print("[MinigameContentService] Normalized result (%s/%s): used_fallback=%s error=%s payload=%d brief=%s" % [
		minigame_type,
		task_id,
		str(bool(normalized.get("used_fallback", true))),
		str(normalized.get("error_message", "")).strip_edges(),
		payload_count,
		str(content.get("scene_brief", "")).strip_edges(),
	])
	_emit_content_ready(
		request_id,
		task_id,
		minigame_type,
		content,
		bool(normalized.get("used_fallback", true)),
		str(normalized.get("error_message", "")).strip_edges()
	)


func _on_llm_request_failed(request_id: String, context: Dictionary, error_message: String, _error_code: int) -> void:
	var task_id: String = str(context.get("task_id", "")).strip_edges()
	var minigame_type: String = str(context.get("minigame_type", "")).strip_edges()
	var fallback_content: Dictionary = context.get("fallback_content", {})
	_emit_content_ready(
		request_id,
		task_id,
		minigame_type,
		fallback_content,
		true,
		error_message
	)


func _emit_content_ready(
	request_id: String,
	task_id: String,
	minigame_type: String,
	content: Dictionary,
	used_fallback: bool,
	error_message: String
) -> void:
	content_ready.emit(request_id, task_id, minigame_type, content, used_fallback, error_message)


func _build_kb_context(task_data: Dictionary) -> String:
	var kb: Node = get_node_or_null("/root/KnowledgeBaseManager")
	if kb == null or not kb.has_method("get_documents"):
		return "暂无可用知识库摘要。"

	var kb_sources: Array[String] = _extract_kb_sources(task_data)
	if kb_sources.is_empty():
		return "暂无可用知识库摘要。"

	var lines: PackedStringArray = []
	var total_chars: int = 0
	for source in kb_sources:
		var docs: Array = kb.get_documents(source)
		if docs.is_empty():
			continue
		var sorted_docs: Array = docs.duplicate(true)
		sorted_docs.sort_custom(_sort_docs_for_prompt)
		var used_count: int = 0
		for raw_doc in sorted_docs:
			if used_count >= DEFAULT_DOCS_PER_CATEGORY:
				break
			if not raw_doc is Dictionary:
				continue
			var doc: Dictionary = raw_doc
			var title: String = str(doc.get("title", "")).strip_edges()
			var content: String = _trim_text(str(doc.get("content", "")).strip_edges(), MAX_DOC_CHARS)
			if content.is_empty():
				continue
			var block: String = "### [%s] %s\n%s" % [source, title if not title.is_empty() else str(doc.get("doc_id", "")), content]
			if total_chars + block.length() > MAX_TOTAL_CONTEXT_CHARS:
				break
			lines.append(block)
			total_chars += block.length()
			used_count += 1
		if total_chars >= MAX_TOTAL_CONTEXT_CHARS:
			break

	if lines.is_empty():
		return "暂无可用知识库摘要。"
	return "\n\n".join(lines)


func _extract_kb_sources(task_data: Dictionary) -> Array[String]:
	var sources: Array[String] = []
	if task_data.get("kb_sources", []) is Array:
		for raw_source in task_data.get("kb_sources", []):
			var source_name := str(raw_source).strip_edges().to_lower()
			if source_name in ["world", "characters", "story", "notes"] and source_name not in sources:
				sources.append(source_name)
	var template: Dictionary = task_data.get("post_task_work_order", {})
	if template.is_empty():
		template = task_data.get("work_order_template", {})
	if not template.is_empty() and template.get("kb_sources", []) is Array:
		for raw_source in template.get("kb_sources", []):
			var source_name := str(raw_source).strip_edges().to_lower()
			if source_name in ["world", "characters", "story", "notes"] and source_name not in sources:
				sources.append(source_name)
	return sources


func _get_effective_work_order(task_data: Dictionary) -> Dictionary:
	var work_order: Dictionary = task_data.get("post_task_work_order", {})
	if work_order.is_empty():
		work_order = task_data.get("work_order_template", {})
	return {
		"title": str(work_order.get("title", task_data.get("title", ""))).strip_edges(),
		"description": str(work_order.get("description", task_data.get("description", ""))).strip_edges(),
		"scene_target": str(work_order.get("scene_target", "")).strip_edges(),
		"performance_context": str(work_order.get("performance_context", "")).strip_edges(),
	}


func _sort_docs_for_prompt(a: Dictionary, b: Dictionary) -> bool:
	return _doc_prompt_score(a) > _doc_prompt_score(b)


func _doc_prompt_score(doc: Dictionary) -> int:
	var score: int = 0
	var state: String = str(doc.get("state", "")).strip_edges().to_lower()
	var kind: String = str(doc.get("doc_kind", "")).strip_edges().to_lower()
	var doc_id: String = str(doc.get("doc_id", "")).strip_edges().to_lower()
	if state == "confirmed":
		score += 3
	elif state == "draft":
		score += 1
	if kind in ["canonical", "backbone", "decision_log"]:
		score += 2
	elif kind in ["brief", "reference"]:
		score += 1
	if doc_id in ["creative_core", "open_design_questions", "seed_development_backbone"]:
		score += 2
	return score


func _trim_text(text: String, max_chars: int) -> String:
	if text.length() <= max_chars:
		return text
	return text.substr(0, max_chars).strip_edges() + "..."


func _get_type_prompt_meta(minigame_type: String) -> Dictionary:
	if minigame_type == "script_fill":
		var instructions: String = _resolve_prompt(
			"minigame_script_fill_instructions", {}, ""
		)
		var output_schema: String = _resolve_prompt(
			"minigame_script_fill_schema", {}, ""
		)
		return {
			"instructions": instructions,
			"output_schema": output_schema,
		}
	if minigame_type == "emotion_tag":
		var emotion_instructions: String = _resolve_prompt(
			"minigame_emotion_tag_instructions", {}, ""
		)
		var emotion_output_schema: String = _resolve_prompt(
			"minigame_emotion_tag_schema", {}, ""
		)
		return {
			"instructions": emotion_instructions,
			"output_schema": emotion_output_schema,
		}
	return {"instructions": "", "output_schema": ""}


func _build_fallback_prompt(prompt_vars: Dictionary) -> String:
	return """## 当前任务
标题：%s
描述：%s

## 当前小游戏类型
%s

## 项目背景（知识库摘要）
%s

## 生成要求
%s

## 输出格式
%s""" % [
		str(prompt_vars.get("task_title", "")),
		str(prompt_vars.get("task_description", "")),
		str(prompt_vars.get("minigame_type", "")),
		str(prompt_vars.get("kb_context", "")),
		str(prompt_vars.get("type_specific_instructions", "")),
		str(prompt_vars.get("output_schema", "")),
	]


func _resolve_prompt(prompt_key: String, vars: Dictionary, fallback_text: String) -> String:
	var pm: Node = get_node_or_null("/root/PromptManager")
	if pm == null or not pm.has_method("has_prompt") or not pm.has_method("resolve_with_vars"):
		return fallback_text
	if not pm.has_prompt(prompt_key):
		return fallback_text
	return str(pm.resolve_with_vars(prompt_key, vars)).strip_edges()


func _build_fallback_content(minigame_type: String, task_data: Dictionary) -> Dictionary:
	if minigame_type == "script_fill":
		var work_order: Dictionary = _get_effective_work_order(task_data)
		var title: String = str(work_order.get("title", "")).strip_edges()
		var description: String = str(work_order.get("description", "")).strip_edges()
		var brief: String = description if not description.is_empty() else title
		if brief.is_empty():
			brief = "一场气氛微妙的对话正在等待收束。"
		return {
			"scene_brief": brief,
			"blocks": _build_fallback_script_fill_blocks(),
		}
	if minigame_type == "emotion_tag":
		var emotion_work_order: Dictionary = _get_effective_work_order(task_data)
		var emotion_title: String = str(emotion_work_order.get("title", "")).strip_edges()
		var emotion_description: String = str(emotion_work_order.get("description", "")).strip_edges()
		var emotion_brief: String = emotion_description if not emotion_description.is_empty() else emotion_title
		if emotion_brief.is_empty():
			emotion_brief = "判断这批句子的情绪落点，让角色演出更稳一些。"
		return {
			"scene_brief": emotion_brief,
			"items": _build_fallback_emotion_tag_items(),
		}
	return {}


func _build_fallback_script_fill_blocks() -> Array[Dictionary]:
	return [
		{
			"type": "narration",
			"text": "走廊尽头灯光昏暗，少女站在拐角处。",
		},
		{
			"type": "dialogue",
			"speaker": "少女",
			"text": "「你到底要去哪？这都几点了。」",
		},
		{
			"type": "narration",
			"text": "少年停下脚步，但没有转身。",
		},
		{
			"type": "dialogue",
			"speaker": "少女",
			"text": "「上次你也是这样，一声不吭就跑了。」",
		},
		{
			"type": "narration",
			"text": "她的声音有点发抖。",
		},
		{
			"type": "dialogue",
			"speaker": "少女",
			"text": "「你就不能让我少操一回心？」",
		},
		{
			"type": "blank",
			"hint": "试探 / 怼回去 / 找借口",
			"speaker": "少年",
			"suggestions": [
				"我随便走走而已，你管那么多。",
				"……我只是想透透气。",
				"你不是也一个人在这吗？",
			],
		},
		{
			"type": "narration",
			"text": "少女没有马上接话。",
		},
		{
			"type": "stage_blank",
			"target": "少女",
			"hint": "心软 / 追问 / 赌气",
			"suggestions": [
				"攥紧了手，又很快松开。",
				"咬住嘴唇，不想让情绪露出来。",
				"往前走了一步，还是没舍得退开。",
			],
		},
		{
			"type": "dialogue",
			"speaker": "少女",
			"text": "「那你至少说一声啊。」",
		},
		{
			"type": "dialogue",
			"speaker": "少年",
			"text": "「我说了你就不拦了？」",
		},
		{
			"type": "narration",
			"text": "短暂的沉默。",
		},
		{
			"type": "blank",
			"speaker": "少女",
			"hint": "留白 / 嘴硬 / 认真",
			"suggestions": [
				"你每次都这样说。",
				"……你就不能让我少操点心？",
				"行，那我不管了。",
			],
		},
		{
			"type": "narration",
			"text": "少女转身走了两步又停下来。",
		},
		{
			"type": "dialogue",
			"speaker": "少女",
			"text": "「……算了，你自己注意点。」",
		},
		{
			"type": "narration",
			"text": "她没有回头，声音很轻。",
		},
		{
			"type": "dialogue",
			"speaker": "少女",
			"text": "「反正你也听不进去。」",
		},
		{
			"type": "narration",
			"text": "少年看着她的背影，走廊里只剩下空调的嗡嗡声。",
		},
		{
			"type": "blank",
			"speaker": "少年",
			"hint": "留白 / 嘴硬 / 认真",
			"suggestions": [
				"这次算我记住了。",
				"你别又一个人扛着。",
				"剩下的话，下次再说。",
			],
		},
		{
			"type": "narration",
			"text": "少女听到他的声音停下了脚步，但没有回头。",
		},
	]


func _build_fallback_emotion_tag_items() -> Array[Dictionary]:
	return [
		{
			"speaker": "赛琳",
			"line": "你为什么每次都这样？",
			"correct_emotion": "委屈",
			"options": ["愤怒", "委屈", "担忧", "冷淡", "期待"],
		},
		{
			"speaker": "阿尔诺",
			"line": "我不是想躲着你，我只是没想好怎么说。",
			"correct_emotion": "犹豫",
			"options": ["犹豫", "欣喜", "骄傲", "释然", "冷淡"],
		},
		{
			"speaker": "旁白",
			"line": "风从露台边灌了进来，谁都没有先把视线挪开。",
			"correct_emotion": "焦虑",
			"options": ["安心", "焦虑", "欣喜", "期待", "冷淡"],
		},
		{
			"speaker": "赛琳",
			"line": "……算了，你至少先回来就好。",
			"correct_emotion": "安心",
			"options": ["愤怒", "安心", "绝望", "骄傲", "欣喜"],
		},
		{
			"speaker": "阿尔诺",
			"line": "你别总把所有事都揽到自己身上。",
			"correct_emotion": "担忧",
			"options": ["担忧", "冷淡", "期待", "欣喜", "释然"],
		},
		{
			"speaker": "旁白",
			"line": "她明明想再追问一句，却还是先把手松开了。",
			"correct_emotion": "口是心非",
			"options": ["口是心非", "感激", "释然", "骄傲", "欣喜"],
		},
	]


func _sanitize_generated_payload_text(raw_text: String) -> String:
	var text: String = raw_text.strip_edges()
	if text.begins_with("<thinking>") or text.begins_with("<think>"):
		var paired_regex := RegEx.new()
		paired_regex.compile("^\\s*<(thinking|think)>([\\s\\S]*?)</(thinking|think)>\\s*")
		var paired_match := paired_regex.search(text)
		if paired_match != null:
			text = text.substr(paired_match.get_end()).strip_edges()
	if text.begins_with("```"):
		var first_newline: int = text.find("\n")
		if first_newline >= 0:
			text = text.substr(first_newline + 1)
		if text.ends_with("```"):
			text = text.substr(0, text.length() - 3)
	return text.strip_edges()


func _parse_json_object(raw_text: String) -> Variant:
	var text: String = _sanitize_generated_payload_text(raw_text)
	if text.is_empty():
		return {}
	var start: int = text.find("{")
	var finish: int = text.rfind("}")
	if start >= 0 and finish > start:
		text = text.substr(start, finish - start + 1)
	return JSON.parse_string(text)


func _normalize_generated_content(minigame_type: String, raw_text: String, fallback_content: Dictionary) -> Dictionary:
	if minigame_type == "script_fill":
		var parsed: Variant = _parse_script_fill_payload(raw_text)
		return _normalize_script_fill_content(parsed, fallback_content)
	if minigame_type == "emotion_tag":
		var emotion_parsed: Variant = _parse_emotion_tag_payload(raw_text)
		return _normalize_emotion_tag_content(emotion_parsed, fallback_content)
	return {
		"content": fallback_content,
		"used_fallback": true,
		"error_message": "unsupported_minigame_type",
	}


func _parse_script_fill_payload(raw_text: String) -> Variant:
	var text: String = _sanitize_generated_payload_text(raw_text)
	if text.find("@slot") >= 0:
		var parsed_legacy: Dictionary = _parse_legacy_script_fill_dsl(text)
		if not parsed_legacy.is_empty():
			return parsed_legacy
	var parsed_dsl: Dictionary = _parse_script_fill_dsl(text)
	if not parsed_dsl.is_empty():
		return parsed_dsl
	return _parse_json_object(raw_text)


func _parse_script_fill_dsl(raw_text: String) -> Dictionary:
	var text: String = _sanitize_generated_payload_text(raw_text)
	if text.is_empty():
		return {}

	var scene_brief: String = ""
	var blocks: Array[Dictionary] = []
	var pending_blank_index: int = -1
	var raw_lines: PackedStringArray = text.split("\n")
	var i: int = 0
	while i < raw_lines.size():
		var line: String = str(raw_lines[i]).strip_edges()
		if scene_brief.is_empty() and _is_scene_brief_line(line):
			scene_brief = _parse_scene_brief_line(line)
			i += 1
			continue
		if line.is_empty():
			i += 1
			continue
		if line.begins_with("@suggestions") or line.begins_with("@suggestion"):
			if pending_blank_index < 0 or pending_blank_index >= blocks.size():
				i += 1
				continue
			var suggestion_lines: Array[String] = []
			i += 1
			while i < raw_lines.size():
				var suggestion_line: String = str(raw_lines[i]).strip_edges()
				if suggestion_line.begins_with("@end"):
					break
				var suggestion: String = _normalize_dsl_suggestion_line(suggestion_line)
				if not suggestion.is_empty():
					suggestion_lines.append(suggestion)
				i += 1
			var pending_block: Dictionary = blocks[pending_blank_index].duplicate(true)
			pending_block["suggestions"] = suggestion_lines.duplicate()
			blocks[pending_blank_index] = pending_block
			pending_blank_index = -1
			if i < raw_lines.size() and str(raw_lines[i]).strip_edges().begins_with("@end"):
				i += 1
			continue
		if line.begins_with("@end"):
			pending_blank_index = -1
			i += 1
			continue

		var block: Dictionary = _parse_script_fill_flow_block_line(line)
		if not block.is_empty():
			blocks.append(block)
			var block_type: String = str(block.get("type", "")).strip_edges()
			pending_blank_index = blocks.size() - 1 if block_type in ["blank", "stage_blank"] else -1
		else:
			pending_blank_index = -1
		i += 1

	if not _script_fill_blocks_are_valid(blocks):
		return {}
	return {
		"scene_brief": scene_brief,
		"blocks": blocks,
	}


func _parse_legacy_script_fill_dsl(raw_text: String) -> Dictionary:
	var text: String = _sanitize_generated_payload_text(raw_text)
	if text.is_empty():
		return {}

	var scene_brief: String = ""
	var slots: Array[Dictionary] = []
	var current_speaker: String = ""
	var current_hint: String = ""
	var block_lines: Array[String] = []
	var suggestion_lines: Array[String] = []
	var in_slot: bool = false
	var in_suggestions: bool = false

	for raw_line in text.split("\n"):
		var line: String = str(raw_line).strip_edges()
		if not in_slot:
			if scene_brief.is_empty() and _is_scene_brief_line(line):
				scene_brief = _parse_scene_brief_line(line)
				continue
			if line.begins_with("@slot"):
				var header: Dictionary = _parse_script_fill_slot_header(line)
				current_speaker = str(header.get("speaker", "")).strip_edges()
				current_hint = str(header.get("hint", "")).strip_edges()
				block_lines.clear()
				suggestion_lines.clear()
				in_slot = true
				in_suggestions = false
			continue

		if line.begins_with("@end"):
			var slot: Dictionary = _build_script_fill_slot_from_dsl(
				current_speaker,
				current_hint,
				block_lines,
				suggestion_lines
			)
			if not slot.is_empty():
				slots.append(slot)
			if slots.size() >= MAX_SLOT_COUNT:
				break
			current_speaker = ""
			current_hint = ""
			block_lines.clear()
			suggestion_lines.clear()
			in_slot = false
			in_suggestions = false
			continue

		if line.begins_with("@hint"):
			current_hint = line.trim_prefix("@hint").strip_edges()
			continue

		if line.begins_with("@suggestions") or line.begins_with("@suggestion"):
			in_suggestions = true
			continue

		if in_suggestions:
			var suggestion: String = _normalize_dsl_suggestion_line(line)
			if not suggestion.is_empty():
				suggestion_lines.append(suggestion)
		else:
			block_lines.append(line)

	if in_slot and slots.size() < MAX_SLOT_COUNT:
		var trailing_slot: Dictionary = _build_script_fill_slot_from_dsl(
			current_speaker,
			current_hint,
			block_lines,
			suggestion_lines
		)
		if not trailing_slot.is_empty():
			slots.append(trailing_slot)

	if slots.is_empty():
		return {}
	return {
		"scene_brief": scene_brief,
		"slots": slots,
	}


func _is_scene_brief_line(line: String) -> bool:
	var normalized: String = line.to_lower()
	return normalized.begins_with("scene_brief:") \
		or normalized.begins_with("scene_brief：") \
		or line.begins_with("场景摘要:") \
		or line.begins_with("场景摘要：")


func _parse_scene_brief_line(line: String) -> String:
	var colon_pos: int = line.find("：")
	if colon_pos < 0:
		colon_pos = line.find(":")
	if colon_pos < 0:
		return ""
	return line.substr(colon_pos + 1).strip_edges()


func _parse_script_fill_slot_header(line: String) -> Dictionary:
	var payload: String = line.trim_prefix("@slot").strip_edges()
	var speaker: String = ""
	var hint: String = ""
	if payload.contains("|"):
		var parts: PackedStringArray = payload.split("|", false, 1)
		speaker = parts[0].strip_edges()
		hint = parts[1].strip_edges()
	else:
		speaker = payload
	return {
		"speaker": speaker,
		"hint": hint,
	}


func _build_script_fill_slot_from_dsl(
	header_speaker: String,
	header_hint: String,
	body_lines: Array[String],
	raw_suggestions: Array[String]
) -> Dictionary:
	if body_lines.is_empty():
		return {}
	var blocks: Array[Dictionary] = []
	var resolved_speaker: String = header_speaker
	for raw_line in body_lines:
		var block: Dictionary = _parse_script_fill_block_line(str(raw_line), resolved_speaker)
		if block.is_empty():
			continue
		if str(block.get("type", "")) == "blank":
			resolved_speaker = str(block.get("speaker", resolved_speaker)).strip_edges()
		blocks.append(block)

	if not _script_fill_slot_blocks_are_valid(blocks):
		return {}
	if resolved_speaker.is_empty():
		resolved_speaker = _find_script_fill_blank_speaker(blocks)
	if resolved_speaker.is_empty():
		resolved_speaker = "???"

	return {
		"blocks": blocks,
		"speaker": resolved_speaker,
		"hint": header_hint if not header_hint.is_empty() else "试探 / 留白 / 认真",
		"suggestions": raw_suggestions.duplicate(),
	}


func _contains_script_fill_blank_marker(line: String) -> bool:
	if line.find("<<<FILL") >= 0 or line.find("<<FILL") >= 0:
		return true
	for marker in SCRIPT_FILL_BLANK_MARKERS:
		if line.find(str(marker)) >= 0:
			return true
	return false


func _extract_script_fill_speaker(line: String) -> String:
	var sep_pos: int = line.find("：")
	if sep_pos < 0:
		sep_pos = line.find(":")
	if sep_pos <= 0:
		return ""
	return line.substr(0, sep_pos).strip_edges()


func _extract_script_fill_blank_hint(marker_text: String) -> String:
	var text: String = marker_text.strip_edges()
	if not text.begins_with("<<<FILL"):
		return ""
	var payload: String = text.trim_prefix("<<<FILL").trim_suffix(">>>").strip_edges()
	if not payload.begins_with("|"):
		return ""
	return payload.substr(1).strip_edges()


func _parse_script_fill_flow_block_line(raw_line: String) -> Dictionary:
	var line: String = raw_line.strip_edges()
	if line.is_empty():
		return {}

	var stage_fill_regex := RegEx.new()
	stage_fill_regex.compile("^\\[(.*?)\\s*[·•]\\s*STAGE_FILL(?:\\s*\\|\\s*(.*?))?\\]$")
	var stage_fill_match := stage_fill_regex.search(line)
	if stage_fill_match != null:
		return {
			"type": "stage_blank",
			"target": stage_fill_match.get_string(1).strip_edges(),
			"hint": stage_fill_match.get_string(2).strip_edges(),
			"suggestions": [],
		}

	if line.begins_with("▸"):
		var stage_text: String = line.trim_prefix("▸").strip_edges()
		if stage_text.is_empty():
			return {}
		return {
			"type": "stage_direction",
			"text": stage_text,
		}

	if _contains_script_fill_blank_marker(line):
		var blank_speaker: String = _extract_script_fill_speaker(line)
		var blank_sep_pos: int = line.find("：")
		if blank_sep_pos < 0:
			blank_sep_pos = line.find(":")
		var marker_text: String = line.substr(blank_sep_pos + 1).strip_edges() if blank_sep_pos >= 0 else line
		return {
			"type": "blank",
			"speaker": blank_speaker if not blank_speaker.is_empty() else "???",
			"hint": _extract_script_fill_blank_hint(marker_text),
			"suggestions": [],
		}

	var sep_pos: int = line.find("：")
	if sep_pos < 0:
		sep_pos = line.find(":")
	if sep_pos > 0 and sep_pos < 16:
		var speaker: String = line.substr(0, sep_pos).strip_edges()
		var text: String = line.substr(sep_pos + 1).strip_edges()
		if not speaker.is_empty() and not text.is_empty():
			return {
				"type": "dialogue",
				"speaker": speaker,
				"text": text,
			}
	return {
		"type": "narration",
		"text": line,
	}


func _parse_script_fill_block_line(raw_line: String, fallback_speaker: String) -> Dictionary:
	var line: String = raw_line.strip_edges()
	if line.is_empty():
		return {}
	if _contains_script_fill_blank_marker(line):
		var blank_speaker: String = _extract_script_fill_speaker(line)
		if blank_speaker.is_empty():
			blank_speaker = fallback_speaker
		return {
			"type": "blank",
			"speaker": blank_speaker if not blank_speaker.is_empty() else "???",
		}
	var sep_pos: int = line.find("：")
	if sep_pos < 0:
		sep_pos = line.find(":")
	if sep_pos > 0 and sep_pos < 16:
		var speaker: String = line.substr(0, sep_pos).strip_edges()
		var text: String = line.substr(sep_pos + 1).strip_edges()
		if not speaker.is_empty() and not text.is_empty() and text.begins_with("「"):
			return {
				"type": "dialogue",
				"speaker": speaker,
				"text": text,
			}
	return {
		"type": "narration",
		"text": line,
	}


func _normalize_dsl_suggestion_line(line: String) -> String:
	var suggestion: String = line.strip_edges()
	if suggestion.begins_with("- ") or suggestion.begins_with("* "):
		suggestion = suggestion.substr(2).strip_edges()
	else:
		var numbered := RegEx.new()
		numbered.compile("^\\d+[\\.)、]\\s*")
		var match_result := numbered.search(suggestion)
		if match_result != null:
			suggestion = suggestion.substr(match_result.get_end()).strip_edges()
	return suggestion


func _script_fill_slot_blocks_are_valid(blocks: Array[Dictionary]) -> bool:
	var blank_count: int = 0
	var dialogue_before_blank: int = 0
	for block in blocks:
		var block_type: String = str(block.get("type", "")).strip_edges()
		if block_type == "blank":
			blank_count += 1
			continue
		if block_type == "dialogue" and blank_count == 0:
			dialogue_before_blank += 1
	return blank_count == 1 and dialogue_before_blank > 0


func _script_fill_blocks_are_valid(blocks: Array[Dictionary]) -> bool:
	var blank_count: int = 0
	var dialogue_count: int = 0
	for block in blocks:
		var block_type: String = str(block.get("type", "")).strip_edges()
		if block_type in ["blank", "stage_blank"]:
			blank_count += 1
		elif block_type == "dialogue":
			dialogue_count += 1
	return blank_count >= MIN_SCRIPT_FILL_BLANKS and dialogue_count >= 2


func _find_script_fill_blank_speaker(blocks: Array[Dictionary]) -> String:
	for block in blocks:
		if str(block.get("type", "")).strip_edges() != "blank":
			continue
		return str(block.get("speaker", "")).strip_edges()
	return ""


func _normalize_script_fill_blocks(raw_blocks: Variant, fallback_speaker: String) -> Array[Dictionary]:
	var blocks: Array[Dictionary] = []
	if not raw_blocks is Array:
		return blocks
	for raw_block in raw_blocks:
		if not raw_block is Dictionary:
			continue
		var block: Dictionary = raw_block
		var block_type: String = str(block.get("type", "")).strip_edges()
		match block_type:
			"narration":
				var narration_text: String = str(block.get("text", "")).strip_edges()
				if not narration_text.is_empty():
					blocks.append({"type": "narration", "text": narration_text})
			"dialogue":
				var speaker: String = str(block.get("speaker", "")).strip_edges()
				var text: String = str(block.get("text", "")).strip_edges()
				if not speaker.is_empty() and not text.is_empty():
					blocks.append({"type": "dialogue", "speaker": speaker, "text": text})
			"stage_direction":
				var stage_text: String = str(block.get("text", "")).strip_edges()
				var stage_target: String = str(block.get("target", "")).strip_edges()
				if not stage_text.is_empty():
					blocks.append({"type": "stage_direction", "text": stage_text, "target": stage_target})
			"blank":
				var blank_speaker: String = str(block.get("speaker", fallback_speaker)).strip_edges()
				blocks.append({
					"type": "blank",
					"speaker": blank_speaker if not blank_speaker.is_empty() else "???",
					"hint": str(block.get("hint", "")).strip_edges(),
					"suggestions": block.get("suggestions", []),
				})
			"stage_blank":
				var target: String = str(block.get("target", fallback_speaker)).strip_edges()
				blocks.append({
					"type": "stage_blank",
					"target": target,
					"hint": str(block.get("hint", "")).strip_edges(),
					"suggestions": block.get("suggestions", []),
				})
	return blocks


func _normalize_script_fill_slot(slot: Dictionary) -> Dictionary:
	var speaker: String = str(slot.get("speaker", "")).strip_edges()
	var blocks: Array[Dictionary] = _normalize_script_fill_blocks(slot.get("blocks", []), speaker)

	if not _script_fill_slot_blocks_are_valid(blocks):
		return {}
	var blank_speaker: String = _find_script_fill_blank_speaker(blocks)
	if blank_speaker.is_empty():
		blank_speaker = speaker if not speaker.is_empty() else "???"
	return {
		"blocks": blocks,
		"speaker": blank_speaker,
		"hint": str(slot.get("hint", "")).strip_edges(),
		"suggestions": slot.get("suggestions", []),
	}


func _compose_script_fill_blocks_text(blocks: Array[Dictionary], include_blank_placeholder: bool = true) -> String:
	var lines: Array[String] = []
	for block in blocks:
		var block_type: String = str(block.get("type", "")).strip_edges()
		match block_type:
			"narration":
				var narration: String = str(block.get("text", "")).strip_edges()
				if not narration.is_empty():
					lines.append(narration)
			"dialogue":
				var speaker: String = str(block.get("speaker", "")).strip_edges()
				var text: String = str(block.get("text", "")).strip_edges()
				if not speaker.is_empty() and not text.is_empty():
					lines.append("%s：%s" % [speaker, text])
			"stage_direction":
				var stage_target: String = str(block.get("target", "")).strip_edges()
				var stage_text: String = str(block.get("text", "")).strip_edges()
				if not stage_text.is_empty():
					var core: String = stage_text
					if not stage_target.is_empty() and not stage_text.begins_with(stage_target):
						core = "%s%s" % [stage_target, stage_text]
					lines.append("[%s]" % core)
			"blank":
				if include_blank_placeholder:
					lines.append("%s：<<<FILL>>>" % str(block.get("speaker", "???")).strip_edges())
			"stage_blank":
				if include_blank_placeholder:
					var target: String = str(block.get("target", "")).strip_edges()
					if target.is_empty():
						lines.append("[STAGE_FILL]")
					else:
						lines.append("[%s · STAGE_FILL]" % target)
	return "\n".join(lines)


func _normalize_script_fill_content(parsed: Variant, fallback_content: Dictionary) -> Dictionary:
	if not parsed is Dictionary:
		return {
			"content": fallback_content,
			"used_fallback": true,
			"error_message": "invalid_json_payload",
		}

	var scene_brief: String = str(parsed.get("scene_brief", fallback_content.get("scene_brief", ""))).strip_edges()
	var normalized_blocks: Array[Dictionary] = []
	var raw_blocks: Variant = parsed.get("blocks", [])
	if raw_blocks is Array:
		normalized_blocks = _normalize_script_fill_blocks(raw_blocks, "")
	else:
		var raw_slots: Variant = parsed.get("slots", [])
		if raw_slots is Array:
			normalized_blocks = _flatten_legacy_script_fill_slots(raw_slots)

	var scene_context: String = _compose_script_fill_blocks_text(normalized_blocks)
	var finalized_blocks: Array[Dictionary] = []
	var blank_count: int = 0
	for block in normalized_blocks:
		var block_type: String = str(block.get("type", "")).strip_edges()
		match block_type:
			"blank":
				blank_count += 1
				var hint: String = str(block.get("hint", "")).strip_edges()
				if hint.is_empty():
					hint = "试探 / 留白 / 认真"
				finalized_blocks.append({
					"type": "blank",
					"speaker": str(block.get("speaker", "???")).strip_edges(),
					"hint": _trim_text(hint, 32),
					"suggestions": _normalize_slot_suggestions(block.get("suggestions", []), scene_context, hint, "blank"),
				})
			"stage_blank":
				blank_count += 1
				var stage_hint: String = str(block.get("hint", "")).strip_edges()
				if stage_hint.is_empty():
					stage_hint = "动作 / 表情 / 停顿"
				finalized_blocks.append({
					"type": "stage_blank",
					"target": str(block.get("target", "")).strip_edges(),
					"hint": _trim_text(stage_hint, 32),
					"suggestions": _normalize_slot_suggestions(block.get("suggestions", []), scene_context, stage_hint, "stage_blank"),
				})
			_:
				finalized_blocks.append(block)

	if blank_count < MIN_SCRIPT_FILL_BLANKS:
		return {
			"content": fallback_content,
			"used_fallback": true,
			"error_message": "not_enough_blanks",
		}

	return {
		"content": {
			"scene_brief": scene_brief,
			"blocks": finalized_blocks,
		},
		"used_fallback": false,
		"error_message": "",
	}


func _flatten_legacy_script_fill_slots(raw_slots: Variant) -> Array[Dictionary]:
	var blocks: Array[Dictionary] = []
	if not raw_slots is Array:
		return blocks

	for raw_slot in raw_slots:
		if not raw_slot is Dictionary:
			continue
		var slot: Dictionary = _normalize_script_fill_slot(raw_slot)
		if slot.is_empty():
			continue
		var slot_blocks: Array[Dictionary] = slot.get("blocks", [])
		var applied_hint: bool = false
		for raw_block in slot_blocks:
			if not raw_block is Dictionary:
				continue
			var block: Dictionary = (raw_block as Dictionary).duplicate(true)
			if not applied_hint and str(block.get("type", "")).strip_edges() == "blank":
				block["hint"] = str(slot.get("hint", "")).strip_edges()
				block["suggestions"] = slot.get("suggestions", []).duplicate(true)
				applied_hint = true
			blocks.append(block)
	return blocks


func _parse_emotion_tag_payload(raw_text: String) -> Variant:
	var parsed_dsl: Dictionary = _parse_emotion_tag_dsl(raw_text)
	if not parsed_dsl.is_empty():
		return parsed_dsl
	return _parse_json_object(raw_text)


func _parse_emotion_tag_dsl(raw_text: String) -> Dictionary:
	var text: String = _sanitize_generated_payload_text(raw_text)
	if text.is_empty():
		return {}

	var scene_brief: String = ""
	var items: Array[Dictionary] = []
	var current_speaker: String = ""
	var current_emotion: String = ""
	var body_lines: Array[String] = []
	var option_lines: Array[String] = []
	var in_item: bool = false
	var in_options: bool = false

	for raw_line in text.split("\n"):
		var line: String = str(raw_line).strip_edges()
		if not in_item:
			if scene_brief.is_empty() and _is_scene_brief_line(line):
				scene_brief = _parse_scene_brief_line(line)
				continue
			if line.begins_with("@item"):
				var header: Dictionary = _parse_emotion_tag_item_header(line)
				current_speaker = str(header.get("speaker", "")).strip_edges()
				current_emotion = str(header.get("correct_emotion", "")).strip_edges()
				body_lines.clear()
				option_lines.clear()
				in_item = true
				in_options = false
			continue

		if line.begins_with("@end"):
			var item: Dictionary = _build_emotion_tag_item_from_dsl(current_speaker, current_emotion, body_lines, option_lines)
			if not item.is_empty():
				items.append(item)
			if items.size() >= MAX_EMOTION_TAG_ITEMS:
				break
			current_speaker = ""
			current_emotion = ""
			body_lines.clear()
			option_lines.clear()
			in_item = false
			in_options = false
			continue

		if line.begins_with("@options") or line.begins_with("@option"):
			in_options = true
			continue

		if in_options:
			var option: String = _normalize_dsl_suggestion_line(line)
			if not option.is_empty():
				option_lines.append(option)
		else:
			if not line.is_empty():
				body_lines.append(line)

	if in_item and items.size() < MAX_EMOTION_TAG_ITEMS:
		var trailing_item: Dictionary = _build_emotion_tag_item_from_dsl(current_speaker, current_emotion, body_lines, option_lines)
		if not trailing_item.is_empty():
			items.append(trailing_item)

	if items.is_empty():
		return {}
	return {
		"scene_brief": scene_brief,
		"items": items,
	}


func _parse_emotion_tag_item_header(line: String) -> Dictionary:
	var payload: String = line.trim_prefix("@item").strip_edges()
	var speaker: String = ""
	var correct_emotion: String = ""
	if payload.contains("|"):
		var parts: PackedStringArray = payload.split("|", false, 1)
		speaker = parts[0].strip_edges()
		correct_emotion = parts[1].strip_edges()
	else:
		correct_emotion = payload
	return {
		"speaker": speaker,
		"correct_emotion": correct_emotion,
	}


func _build_emotion_tag_item_from_dsl(
	header_speaker: String,
	header_emotion: String,
	body_lines: Array[String],
	raw_options: Array[String]
) -> Dictionary:
	var line_text: String = "\n".join(body_lines).strip_edges()
	var normalized_options: Array[String] = _normalize_emotion_tag_options(raw_options, header_emotion)
	if line_text.is_empty() or header_emotion.is_empty() or normalized_options.size() < MIN_EMOTION_TAG_OPTIONS:
		return {}
	return {
		"speaker": header_speaker,
		"line": line_text,
		"correct_emotion": header_emotion,
		"options": normalized_options,
	}


func _normalize_emotion_tag_item(raw_item: Dictionary) -> Dictionary:
	var line: String = _trim_text(str(raw_item.get("line", "")).strip_edges(), EMOTION_TAG_LINE_MAX_CHARS)
	var correct_emotion: String = _trim_text(str(raw_item.get("correct_emotion", "")).strip_edges(), EMOTION_TAG_LABEL_MAX_CHARS)
	var speaker: String = str(raw_item.get("speaker", "")).strip_edges()
	var options: Array[String] = _normalize_emotion_tag_options(raw_item.get("options", []), correct_emotion)
	if line.is_empty() or correct_emotion.is_empty() or options.size() < MIN_EMOTION_TAG_OPTIONS:
		return {}
	return {
		"speaker": speaker,
		"line": line,
		"correct_emotion": correct_emotion,
		"options": options,
	}


func _normalize_emotion_tag_options(raw_options: Variant, correct_emotion: String) -> Array[String]:
	var normalized: Array[String] = []
	if raw_options is Array:
		for raw_option in raw_options:
			var option: String = _trim_text(str(raw_option).strip_edges(), EMOTION_TAG_LABEL_MAX_CHARS)
			if option.is_empty() or option in normalized:
				continue
			normalized.append(option)

	var options: Array[String] = []
	if not correct_emotion.is_empty():
		options.append(correct_emotion)
	for option in normalized:
		if option == correct_emotion or option in options:
			continue
		options.append(option)
	for fallback in EMOTION_TAG_FALLBACK_POOL:
		if options.size() >= EMOTION_TAG_OPTIONS_PER_ITEM:
			break
		if fallback == correct_emotion or fallback in options:
			continue
		options.append(fallback)
	if options.size() > EMOTION_TAG_OPTIONS_PER_ITEM:
		options.resize(EMOTION_TAG_OPTIONS_PER_ITEM)
	if not correct_emotion.is_empty() and correct_emotion not in options:
		if options.is_empty():
			options.append(correct_emotion)
		else:
			options[options.size() - 1] = correct_emotion
	return options


func _normalize_emotion_tag_content(parsed: Variant, fallback_content: Dictionary) -> Dictionary:
	if not parsed is Dictionary:
		return {
			"content": fallback_content,
			"used_fallback": true,
			"error_message": "invalid_emotion_tag_payload",
		}

	var scene_brief: String = str(parsed.get("scene_brief", fallback_content.get("scene_brief", ""))).strip_edges()
	var items: Array[Dictionary] = []
	var raw_items: Variant = parsed.get("items", [])
	if raw_items is Array:
		for raw_item in raw_items:
			if not raw_item is Dictionary:
				continue
			var item: Dictionary = _normalize_emotion_tag_item(raw_item)
			if item.is_empty():
				continue
			items.append(item)
			if items.size() >= MAX_EMOTION_TAG_ITEMS:
				break

	if items.size() < MIN_EMOTION_TAG_ITEMS:
		return {
			"content": fallback_content,
			"used_fallback": true,
			"error_message": "not_enough_emotion_tag_items",
		}

	return {
		"content": {
			"scene_brief": scene_brief,
			"items": items,
		},
		"used_fallback": false,
		"error_message": "",
	}


func _normalize_slot_suggestions(raw_suggestions: Variant, context: String, hint: String, blank_type: String = "blank") -> Array[String]:
	var suggestions: Array[String] = []
	if raw_suggestions is Array:
		for raw_suggestion in raw_suggestions:
			var suggestion: String = str(raw_suggestion).strip_edges()
			if suggestion.length() > MAX_LINE_CHARS:
				suggestion = suggestion.substr(0, MAX_LINE_CHARS).strip_edges()
			if suggestion.is_empty() or suggestion in suggestions:
				continue
			suggestions.append(suggestion)
			if suggestions.size() >= SUGGESTIONS_PER_SLOT:
				break

	if suggestions.size() >= SUGGESTIONS_PER_SLOT:
		return suggestions

	var fallback_suggestions: Array[String] = _build_fallback_suggestions(context, hint, blank_type)
	for suggestion in fallback_suggestions:
		if suggestion in suggestions:
			continue
		suggestions.append(suggestion)
		if suggestions.size() >= SUGGESTIONS_PER_SLOT:
			break
	return suggestions


func _build_fallback_suggestions(context: String, _hint: String, blank_type: String = "blank") -> Array[String]:
	var generic_pool: Array[String] = []
	if blank_type == "stage_blank":
		generic_pool = [
			"抿住嘴，没有立刻接话",
			"往前走了一步，又停住",
			"偏开视线，不想让人看见表情",
			"肩膀绷了一下，最后还是没躲开",
			"垂下眼睛，像是把话咽了回去",
		]
	else:
		generic_pool = [
			"你先听我说完。",
			"我不是那个意思。",
			"你明明知道我在意。",
			"这次算我没藏住。",
			"别把话停在这里。",
		]
	var suggestions: Array[String] = []
	for generic in generic_pool:
		if generic in suggestions:
			continue
		suggestions.append(generic)
		if suggestions.size() >= SUGGESTIONS_PER_SLOT:
			break

	if suggestions.is_empty():
		var trimmed_context := context
		if trimmed_context.length() > MAX_LINE_CHARS:
			trimmed_context = trimmed_context.substr(0, MAX_LINE_CHARS).strip_edges()
		suggestions.append(trimmed_context)
	return suggestions
