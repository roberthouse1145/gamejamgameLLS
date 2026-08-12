extends Node
## 真实 LLM lab：直接生成三种不同的小事件，检查文本长度、视觉节拍与角色反应。

const AVGSceneGeneratorClass = preload("res://scripts/avg/generation/avg_scene_generator.gd")
const AVGDSLSerializerClass = preload("res://scripts/avg/dsl/avg_dsl_serializer.gd")

const SESSION_PREFIX: String = "lab_avg_visual_variety"
const COMPANION_ID: String = "lu_yuanyuan"
const VISUAL_COMMAND_TYPES: PackedStringArray = [
	"STAGE_SET",
	"STAGE_ENTER",
	"STAGE_EXIT",
	"SHOW_CHARACTER",
	"HIDE_CHARACTER",
	"MOVE_CHARACTER",
	"MOVE_CHARACTER_BY",
	"FLIP_CHARACTER",
	"CHANGE_EXPRESSION",
	"CHARACTER_EFFECT",
	"SCREEN_FADE",
	"SET_TIME_OF_DAY",
	"SCREEN_FLASH",
	"SCREEN_SHAKE",
	"CAMERA_ZOOM",
	"CAMERA_PAN",
	"CAMERA_RESET",
	"CHANGE_BACKGROUND",
	"SHOW_IMAGE",
	"HIDE_IMAGE",
	"WAIT_TIME",
]

var _generator: Node = null
var _event_index: int = 0
var _events: Array[Dictionary] = [
	{
		"id": "park_cat",
		"title": "长椅下的橘猫",
		"scene_prompt": "周六午后，阮云柚与陆鸢鸢已经来到汐见河滨公园的长椅附近。一只橘猫突然从长椅下钻出，从阮云柚脚边轻快掠过，随后自行跳上矮墙晒太阳。通过阮云柚受惊、陆鸢鸢调侃、二人试着靠近却被猫高冷无视的即时反应与对话完成这个小事件，最后继续散步。背景使用 riverside_park_day。",
	},
	{
		"id": "concert_opening",
		"title": "突然亮起的舞台",
		"scene_prompt": "傍晚，阮云柚与陆鸢鸢抵达 ECHO LIVE HALL，先在场馆外短暂交谈，再进入内场。全场灯光熄灭后，乐队用强烈灯光突然开场，阮云柚先被吓了一跳，随后被现场气氛吸引。通过抵达、入场、开场反应和两人的短交流完成事件。外景使用 echo_live_hall_exterior_evening，内景使用 echo_live_hall_interior。",
	},
	{
		"id": "cafe_labels",
		"title": "贴反的饮料标签",
		"scene_prompt": "白天，阮云柚与陆鸢鸢坐在河畔咖啡座休息。桌上的两杯饮料标签贴反了：阮云柚先发现味道不对，两人观察杯子、交换饮料并互相吐槽，轻松解决这个日常小麻烦。事件始终发生在座位附近，以细微的惊讶、确认、点头和轻快反应为演出重点。背景使用 riverside_cafe_day。",
	},
]


func _ready() -> void:
	_select_requested_event()
	_generator = AVGSceneGeneratorClass.new()
	_generator.name = "LabAVGVisualVarietyGenerator"
	add_child(_generator)
	_generator.scene_generated.connect(_on_scene_generated)
	_generator.scene_failed.connect(_on_scene_failed)
	call_deferred("_generate_next_event")


func _select_requested_event() -> void:
	var requested_id: String = OS.get_environment("AVG_VISUAL_LAB_CASE").strip_edges()
	if requested_id.is_empty():
		return
	var selected_events: Array[Dictionary] = []
	for event_data: Dictionary in _events:
		if str(event_data.get("id", "")) == requested_id:
			selected_events.append(event_data)
	_events = selected_events
	print("[LabAVGVisualVariety] FILTER case=%s matched=%d" % [requested_id, _events.size()])


func _generate_next_event() -> void:
	if _event_index >= _events.size():
		print("[LabAVGVisualVariety] COMPLETE cases=%d" % _events.size())
		return
	if _generator == null or not bool(_generator.call("is_available")):
		push_error("[LabAVGVisualVariety] AVG LLM 当前不可用")
		return

	var companion: CharacterProfile = LinkChatManager.get_character(COMPANION_ID)
	if companion == null:
		push_error("[LabAVGVisualVariety] 缺少同行角色资源")
		return

	var event_data: Dictionary = _events[_event_index]
	var event_id: String = str(event_data.get("id", "event_%d" % _event_index))
	var session_id: String = "%s_%s" % [SESSION_PREFIX, event_id]
	var relationship: Dictionary = GameState.get_relationship(COMPANION_ID)
	var setting_context: String = OutingManager._resolve_outing_prompt("outing/avg_date_context", {
		"player_profile": OutingManager._player_prompt(),
		"companion_name": companion.display_name,
		"companion_profile": companion.persona_prompt,
	})
	var runtime_context: String = OutingManager._resolve_outing_prompt("outing/avg_date_runtime_context", {
		"relationship": JSON.stringify(relationship),
		"invitation_transcript": "player: 这周一起出去走走？\nlu_yuanyuan: 好啊，地点你定。",
		"recent_outings": OutingManager._build_recent_outing_context(),
	})
	var generation_session: Dictionary = {
		"title": str(event_data.get("title", event_id)),
		"scene_prompt": str(event_data.get("scene_prompt", "")),
		"setting_context": setting_context,
		"runtime_context": runtime_context,
		"constraints": OutingManager._resolve_outing_prompt("outing/avg_constraints"),
		"story_guidance_prompt": OutingManager._resolve_outing_prompt("outing/avg_guidance"),
		"scene_id_prefix": "lab_visual_%s" % event_id,
		"scene_window_title": str(event_data.get("title", event_id)),
	}

	print("[LabAVGVisualVariety] START case=%s title=%s" % [event_id, generation_session["title"]])
	if not bool(_generator.call("generate_for_session", session_id, generation_session)):
		push_error("[LabAVGVisualVariety] 生成请求未能启动：%s" % event_id)


func _on_scene_generated(session_id: String, package: Dictionary) -> void:
	var expected_id: String = _current_session_id()
	if session_id != expected_id:
		return
	var event_id: String = str(_events[_event_index].get("id", "event_%d" % _event_index))
	var commands: Array = _extract_commands(package)
	var serializer: RefCounted = AVGDSLSerializerClass.new()
	var dsl_text: String = str(serializer.call("serialize", commands)).strip_edges()
	print("LAB_AVG_VISUAL_CASE_%s_DSL\n%s\nLAB_AVG_VISUAL_CASE_%s_DSL_END" % [
		event_id.to_upper(),
		dsl_text,
		event_id.to_upper(),
	])
	_print_metrics(event_id, commands)
	_event_index += 1
	call_deferred("_generate_next_event")


func _on_scene_failed(session_id: String, error: String) -> void:
	var expected_id: String = _current_session_id()
	if session_id != expected_id:
		return
	var event_id: String = str(_events[_event_index].get("id", "event_%d" % _event_index))
	push_error("[LabAVGVisualVariety] FAILED case=%s error=%s" % [event_id, error])
	_event_index += 1
	call_deferred("_generate_next_event")


func _current_session_id() -> String:
	if _event_index < 0 or _event_index >= _events.size():
		return ""
	return "%s_%s" % [SESSION_PREFIX, str(_events[_event_index].get("id", "event_%d" % _event_index))]


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


func _print_metrics(event_id: String, commands: Array) -> void:
	var dialogue_blocks: int = 0
	var narration_blocks: int = 0
	var thought_blocks: int = 0
	var expression_blocks: int = 0
	var visual_commands: int = 0
	var character_effects: int = 0
	var stage_commands: int = 0
	var transition_commands: int = 0
	var camera_commands: int = 0
	var wait_commands: int = 0
	var current_text_run: int = 0
	var max_text_run: int = 0

	for command: Variant in commands:
		if not command is Resource or not "command_type" in command:
			continue
		var command_type: String = str(command.command_type)
		var params: Dictionary = command.params if "params" in command else {}
		if command_type == "DIALOGUE":
			dialogue_blocks += 1
			current_text_run += 1
			max_text_run = maxi(max_text_run, current_text_run)
			var speaker: String = str(params.get("speaker", "")).strip_edges()
			if not str(params.get("emotion", "")).strip_edges().is_empty():
				expression_blocks += 1
			if speaker.is_empty():
				narration_blocks += 1
			elif _is_thought_text(str(params.get("text", ""))):
				thought_blocks += 1
			continue

		if VISUAL_COMMAND_TYPES.has(command_type):
			visual_commands += 1
			current_text_run = 0
		if command_type == "CHARACTER_EFFECT":
			character_effects += 1
		elif command_type.begins_with("STAGE_") or command_type in ["SHOW_CHARACTER", "HIDE_CHARACTER", "MOVE_CHARACTER", "MOVE_CHARACTER_BY", "FLIP_CHARACTER"]:
			stage_commands += 1
		elif command_type in ["SCREEN_FADE", "SET_TIME_OF_DAY", "SCREEN_FLASH", "SCREEN_SHAKE", "CHANGE_BACKGROUND"]:
			transition_commands += 1
		elif command_type.begins_with("CAMERA_"):
			camera_commands += 1
		elif command_type == "WAIT_TIME":
			wait_commands += 1

	print("[LabAVGVisualVariety] METRICS case=%s commands=%d text=%d narration=%d thoughts=%d expression_blocks=%d visual=%d effects=%d stage=%d transitions=%d camera=%d waits=%d max_text_run=%d" % [
		event_id,
		commands.size(),
		dialogue_blocks,
		narration_blocks,
		thought_blocks,
		expression_blocks,
		visual_commands,
		character_effects,
		stage_commands,
		transition_commands,
		camera_commands,
		wait_commands,
		max_text_run,
	])


func _is_thought_text(text_value: String) -> bool:
	var text: String = text_value.strip_edges()
	return text.begins_with("（") and text.ends_with("）")
