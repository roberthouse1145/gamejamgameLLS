extends Node
## 真实 LLM lab：用通用动作语法测试模型能否自行编排复杂角色互动与复位。

const AVGSceneGeneratorClass = preload("res://scripts/avg/generation/avg_scene_generator.gd")
const AVGDSLSerializerClass = preload("res://scripts/avg/dsl/avg_dsl_serializer.gd")

const SESSION_PREFIX: String = "lab_avg_complex_staging"

var _generator: Node = null
var _event_index: int = 0
var _events: Array[Dictionary] = [
	{
		"id": "collar_tag",
		"title": "翻出来的衣领标签",
		"scene_prompt": "白天，阮云柚与陆鸢鸢在河畔咖啡座聊天。陆鸢鸢发现阮云柚背后的衣领标签翻了出来，于是走近替她整理；阮云柚先僵住，弄清原因后嘴硬道谢。整理完成后两人恢复原来的座位距离。背景使用 riverside_cafe_day。",
	},
	{
		"id": "frisbee_dodge",
		"title": "突然掠过的飞盘",
		"scene_prompt": "周六午后，阮云柚与陆鸢鸢在河滨公园步道交谈，一个飞盘突然从两人中间掠过。两人分别向两侧躲开，确认安全后互相吐槽，再走回原来的并肩构图。背景使用 riverside_park_day。",
	},
	{
		"id": "countdown_photo",
		"title": "门口的倒计时合照",
		"scene_prompt": "傍晚演出结束后，阮云柚与陆鸢鸢在 ECHO LIVE HALL 门口用定时拍照。两人从标准站位靠向画面中央，调整高低和表情，在倒计时结束时做出不同反应；拍完查看效果，再回到原来的对话站位。背景使用 echo_live_hall_exterior_evening。",
	},
]


func _ready() -> void:
	_select_requested_event()
	_generator = AVGSceneGeneratorClass.new()
	_generator.name = "LabAVGComplexStagingGenerator"
	add_child(_generator)
	_generator.scene_generated.connect(_on_scene_generated)
	_generator.scene_failed.connect(_on_scene_failed)
	call_deferred("_generate_next_event")


func _select_requested_event() -> void:
	var requested_id: String = OS.get_environment("AVG_COMPLEX_LAB_CASE").strip_edges()
	if requested_id.is_empty():
		return
	var selected_events: Array[Dictionary] = []
	for event_data: Dictionary in _events:
		if str(event_data.get("id", "")) == requested_id:
			selected_events.append(event_data)
	_events = selected_events
	print("[LabAVGComplexStaging] FILTER case=%s matched=%d" % [requested_id, _events.size()])


func _generate_next_event() -> void:
	if _event_index >= _events.size():
		print("[LabAVGComplexStaging] COMPLETE cases=%d" % _events.size())
		return
	if _generator == null or not bool(_generator.call("is_available")):
		push_error("[LabAVGComplexStaging] AVG LLM 当前不可用")
		return

	var event_data: Dictionary = _events[_event_index]
	var event_id: String = str(event_data.get("id", "event_%d" % _event_index))
	var session_id: String = "%s_%s" % [SESSION_PREFIX, event_id]
	var generation_session: Dictionary = {
		"title": str(event_data.get("title", event_id)),
		"scene_prompt": str(event_data.get("scene_prompt", "")),
		"setting_context": "阮云柚（DSL 角色名：柚柚）是怕生、嘴硬、内心戏多的宅女；陆鸢鸢（DSL 角色名：鸢鸢）是她干练、爱调侃也会照顾人的青梅。两人熟悉彼此，互动保持轻松日常。",
		"constraints": "生成一个线性、对话驱动的完整小事件，阮云柚正常登台，使用第三人称限知与短心理话。",
		"story_guidance_prompt": "保持轻松日常，以角色来回对话推进眼前的小事件。",
		"scene_id_prefix": "lab_complex_%s" % event_id,
		"scene_window_title": str(event_data.get("title", event_id)),
	}

	print("[LabAVGComplexStaging] START case=%s title=%s" % [event_id, generation_session["title"]])
	if not bool(_generator.call("generate_for_session", session_id, generation_session)):
		push_error("[LabAVGComplexStaging] 生成请求未能启动：%s" % event_id)


func _on_scene_generated(session_id: String, package: Dictionary) -> void:
	if session_id != _current_session_id():
		return
	var event_id: String = str(_events[_event_index].get("id", "event_%d" % _event_index))
	var commands: Array = _extract_commands(package)
	var serializer: RefCounted = AVGDSLSerializerClass.new()
	var dsl_text: String = str(serializer.call("serialize", commands)).strip_edges()
	print("LAB_AVG_COMPLEX_%s_DSL\n%s\nLAB_AVG_COMPLEX_%s_DSL_END" % [
		event_id.to_upper(),
		dsl_text,
		event_id.to_upper(),
	])
	_print_metrics(event_id, commands)
	_event_index += 1
	call_deferred("_generate_next_event")


func _on_scene_failed(session_id: String, error: String) -> void:
	if session_id != _current_session_id():
		return
	var event_id: String = str(_events[_event_index].get("id", "event_%d" % _event_index))
	push_error("[LabAVGComplexStaging] FAILED case=%s error=%s" % [event_id, error])
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
	var move_count: int = 0
	var custom_move_count: int = 0
	var effect_count: int = 0
	var wait_count: int = 0
	var stage_set_count: int = 0
	var camera_zoom_count: int = 0
	var camera_reset_count: int = 0
	var first_custom_move_index: int = -1
	var restore_after_move: bool = false

	for index in range(commands.size()):
		var command: Variant = commands[index]
		if not command is Resource or not "command_type" in command:
			continue
		var command_type: String = str(command.command_type)
		var params: Dictionary = command.params if "params" in command else {}
		match command_type:
			"MOVE_CHARACTER":
				move_count += 1
				var target: String = str(params.get("target", ""))
				if "," in target:
					custom_move_count += 1
					if first_custom_move_index < 0:
						first_custom_move_index = index
			"CHARACTER_EFFECT":
				effect_count += 1
			"WAIT_TIME":
				wait_count += 1
			"STAGE_SET":
				stage_set_count += 1
				if first_custom_move_index >= 0 and index > first_custom_move_index:
					restore_after_move = true
			"CAMERA_ZOOM":
				camera_zoom_count += 1
			"CAMERA_RESET":
				camera_reset_count += 1

	print("[LabAVGComplexStaging] METRICS case=%s commands=%d moves=%d custom_moves=%d effects=%d waits=%d stage_sets=%d restore_after_move=%s camera_zoom=%d camera_reset=%d" % [
		event_id,
		commands.size(),
		move_count,
		custom_move_count,
		effect_count,
		wait_count,
		stage_set_count,
		str(restore_after_move),
		camera_zoom_count,
		camera_reset_count,
	])
