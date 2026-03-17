class_name DateEventPlayer extends Control

signal playback_finished(session_id: String, outcome: Dictionary)

const CHOICE_VAR_ID: String = "var_001"
const DESIGN_RESOLUTION: Vector2 = Vector2(2560, 1440)

@onready var scene_runner: Control = %AVGSceneRunner
@onready var title_label: Label = %TitleLabel
@onready var content_container: Control = %ContentContainer
@onready var preview_container: SubViewportContainer = %PreviewContainer

var _session_id: String = ""
var _event_request: Dictionary = {}
var _scene_package: Dictionary = {}
var _finished: bool = false


func _ready() -> void:
	if scene_runner != null:
		scene_runner.scene_ended.connect(_on_scene_ended)
	if content_container != null:
		content_container.resized.connect(_on_content_resized)
	if preview_container != null:
		preview_container.set_anchors_preset(Control.PRESET_TOP_LEFT)
		preview_container.anchor_right = 0.0
		preview_container.anchor_bottom = 0.0
	call_deferred("_on_content_resized")
	set_process(false)


func play_event(session_id: String, event_request: Dictionary) -> void:
	_session_id = session_id
	_event_request = event_request.duplicate(true)
	_scene_package.clear()
	_finished = false
	title_label.text = str(_event_request.get("title", "Important Date"))

	var project: Resource = _event_request.get("project", null)
	var scene: Resource = _event_request.get("scene", null)
	if project == null or scene == null or scene_runner == null:
		_emit_outcome({"success": false, "error": "invalid_event_request"})
		return

	scene_runner.reset()
	scene_runner.load_project(project)
	scene_runner.load_scene(scene)
	scene_runner.start()
	set_process(true)


func play_scene_package(session_id: String, scene_package: Dictionary) -> void:
	_session_id = session_id
	_event_request.clear()
	_scene_package = scene_package.duplicate(true)
	_finished = false
	title_label.text = str(_scene_package.get("title", "Date Scene"))

	var project: Resource = _scene_package.get("project", null)
	var scene: Resource = _scene_package.get("scene", null)
	if project == null or scene == null or scene_runner == null:
		_emit_outcome({"success": false, "error": "invalid_scene_package"})
		return

	scene_runner.reset()
	scene_runner.load_project(project)
	scene_runner.load_scene(scene)
	scene_runner.start()
	set_process(true)


func _on_scene_ended(_scene_id: String) -> void:
	if _finished:
		return

	var variable_manager: RefCounted = null
	if scene_runner != null and scene_runner.has_method("get_variable_manager"):
		variable_manager = scene_runner.get_variable_manager()

	var choice_id: int = 0
	if variable_manager != null and variable_manager.has_method("get_value_by_id"):
		choice_id = int(variable_manager.get_value_by_id(CHOICE_VAR_ID))

	if not _event_request.is_empty():
		var outcomes: Dictionary = _event_request.get("outcomes", {})
		var selected_outcome: Dictionary = outcomes.get(choice_id, {})
		_emit_outcome({
			"success": true,
			"choice_id": choice_id,
			"choice_text": str(selected_outcome.get("text", "")),
			"summary": str(selected_outcome.get("summary", "")),
			"affection_delta": int(selected_outcome.get("affection_delta", 0)),
			"tag": str(selected_outcome.get("tag", "")),
		})
		return

	var choice_labels: Dictionary = _scene_package.get("choice_labels", {})
	var selected_choice_text: String = str(choice_labels.get(choice_id, "")).strip_edges()
	_emit_outcome({
		"success": true,
		"choice_id": choice_id,
		"choice_text": selected_choice_text,
		"summary": selected_choice_text,
		"affection_delta": 0,
		"tag": "",
	})


func _emit_outcome(outcome: Dictionary) -> void:
	if _finished:
		return
	_finished = true
	set_process(false)
	playback_finished.emit(_session_id, outcome)


func _process(_delta: float) -> void:
	if _finished or scene_runner == null:
		return
	if scene_runner.has_method("is_playback_complete") and scene_runner.is_playback_complete():
		if scene_runner.has_method("stop"):
			scene_runner.stop()
		else:
			_on_scene_ended("")


func _on_content_resized() -> void:
	if content_container == null or preview_container == null:
		return

	var available_size: Vector2 = content_container.size
	if available_size.x <= 0.0 or available_size.y <= 0.0:
		return

	var aspect_ratio: float = DESIGN_RESOLUTION.x / DESIGN_RESOLUTION.y
	var container_aspect: float = available_size.x / available_size.y

	var new_size: Vector2
	if container_aspect > aspect_ratio:
		new_size.y = available_size.y
		new_size.x = available_size.y * aspect_ratio
	else:
		new_size.x = available_size.x
		new_size.y = available_size.x / aspect_ratio

	preview_container.size = new_size
	preview_container.position = (available_size - new_size) / 2.0
