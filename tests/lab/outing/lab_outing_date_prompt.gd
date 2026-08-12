extends Node
## 真实 LLM lab：绕过玩家点击与外出事务，直接生成一次约会 AVG，并打印完整 DSL。

const AVGSceneGeneratorClass = preload("res://scripts/avg/generation/avg_scene_generator.gd")
const AVGDSLSerializerClass = preload("res://scripts/avg/dsl/avg_dsl_serializer.gd")

const SESSION_ID: String = "lab_outing_date_prompt"
const ACTIVITY_ID: String = "riverside_walk_01"
const COMPANION_ID: String = "lu_yuanyuan"

var _generator: Node = null
var _generation_started_msec: int = 0


func _ready() -> void:
	_generator = AVGSceneGeneratorClass.new()
	_generator.name = "LabOutingDateGenerator"
	add_child(_generator)
	_generator.scene_generated.connect(_on_scene_generated)
	_generator.scene_failed.connect(_on_scene_failed)
	call_deferred("_generate_date_scene")


func _generate_date_scene() -> void:
	if _generator == null or not bool(_generator.call("is_available")):
		push_error("[LabOutingDatePrompt] AVG LLM 当前不可用")
		return

	var activity: OutingActivity = OutingManager.get_activity(ACTIVITY_ID)
	var companion: CharacterProfile = LinkChatManager.get_character(COMPANION_ID)
	if activity == null or companion == null:
		push_error("[LabOutingDatePrompt] 缺少活动或同行角色资源")
		return

	var relationship: Dictionary = GameState.get_relationship(COMPANION_ID)
	var setting_context: String = OutingManager._resolve_outing_prompt("outing/avg_date_context", {
		"player_profile": OutingManager._player_prompt(),
		"companion_name": companion.display_name,
		"companion_profile": companion.persona_prompt,
	})
	var runtime_context: String = OutingManager._resolve_outing_prompt("outing/avg_date_runtime_context", {
		"relationship": JSON.stringify(relationship),
		"invitation_transcript": "player: 要不要一起去河边走走？\nlu_yuanyuan: 行啊，正好陪你出去透口气。",
		"recent_outings": OutingManager._build_recent_outing_context(),
	})
	var constraints: String = OutingManager._resolve_outing_prompt("outing/avg_constraints")
	var guidance: String = OutingManager._resolve_outing_prompt("outing/avg_guidance")
	var generation_session: Dictionary = {
		"title": activity.title,
		"scene_prompt": OutingManager._build_scene_prompt(activity, OutingManager.get_place(activity.place_id), OutingManager.MODE_DATE, companion),
		"setting_context": setting_context,
		"runtime_context": runtime_context,
		"constraints": constraints,
		"story_guidance_prompt": guidance,
		"scene_id_prefix": "lab_outing",
		"scene_window_title": activity.title,
	}

	print("[LabOutingDatePrompt] 开始生成：%s × %s｜%s" % [
		OutingManager._player_prompt().get_slice("。", 0),
		companion.display_name,
		activity.title,
	])
	_generation_started_msec = Time.get_ticks_msec()
	if not bool(_generator.call("generate_for_session", SESSION_ID, generation_session)):
		push_error("[LabOutingDatePrompt] 生成请求未能启动")


func _on_scene_generated(session_id: String, package: Dictionary) -> void:
	if session_id != SESSION_ID:
		return
	var commands: Array = _extract_commands(package)
	var serializer: RefCounted = AVGDSLSerializerClass.new()
	var dsl_text: String = str(serializer.call("serialize", commands)).strip_edges()
	print("LAB_OUTING_DATE_DSL\n%s\nLAB_OUTING_DATE_DSL_END" % dsl_text)
	_print_text_statistics(commands)
	_print_elapsed("生成完成")


func _on_scene_failed(session_id: String, error: String) -> void:
	if session_id != SESSION_ID:
		return
	_print_elapsed("生成失败")
	push_error("[LabOutingDatePrompt] 生成失败：%s" % error)


func _print_elapsed(label: String) -> void:
	if _generation_started_msec <= 0:
		return
	var elapsed_seconds: float = float(Time.get_ticks_msec() - _generation_started_msec) / 1000.0
	print("[LabOutingDatePrompt] %s，总耗时：%.2f 秒" % [label, elapsed_seconds])


func _extract_commands(package: Dictionary) -> Array:
	var result: Array = []
	var scene_value: Variant = package.get("scene")
	if not scene_value is Resource:
		return result
	var scene: Resource = scene_value as Resource
	if not "nodes" in scene or scene.nodes == null or scene.nodes.is_empty():
		return result
	var root: Resource = scene.nodes[0]
	if root == null or not "command_tabs" in root or root.command_tabs == null or root.command_tabs.is_empty():
		return result
	var first_tab: Dictionary = root.command_tabs[0]
	var raw_commands: Variant = first_tab.get("commands", [])
	if raw_commands is Array:
		result.assign(raw_commands)
	return result


func _print_text_statistics(commands: Array) -> void:
	var character_blocks: int = 0
	var narration_blocks: int = 0
	var thought_lines: int = 0
	var mixed_thought_blocks: int = 0
	for command: Variant in commands:
		if not command is Resource or not "command_type" in command:
			continue
		if str(command.command_type) != "DIALOGUE":
			continue
		var params: Dictionary = command.params if "params" in command else {}
		var speaker: String = str(params.get("speaker", "")).strip_edges()
		if speaker.is_empty():
			narration_blocks += 1
			continue
		character_blocks += 1
		var has_thought_line: bool = false
		var has_spoken_line: bool = false
		for raw_line: String in str(params.get("text", "")).split("\n"):
			var line: String = raw_line.strip_edges()
			if line.begins_with("（") and line.ends_with("）"):
				thought_lines += 1
				has_thought_line = true
			elif not line.is_empty():
				has_spoken_line = true
		if has_thought_line and has_spoken_line:
			mixed_thought_blocks += 1
	print("[LabOutingDatePrompt] 文本统计：角色块=%d，心理话行=%d，旁白块=%d，混合心理块=%d" % [
		character_blocks,
		thought_lines,
		narration_blocks,
		mixed_thought_blocks,
	])
