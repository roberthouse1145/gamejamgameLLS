class_name AVGPlayer extends Control
## AVG 剧情播放器 APP
## 在桌面窗口中播放 AVG 场景资源或动态生成的场景包。

signal playback_finished(session_id: String, outcome: Dictionary)
## 剧情开始播放时发出（用于通知 music_player 之类的 App 进入互斥状态）
signal playback_started(session_id: String)

enum Page { HOME, PLAYBACK }

const CHOICE_VAR_ID: String = "var_001"
const DESIGN_RESOLUTION: Vector2 = Vector2(2560, 1440)

# -- 普通 AVG 播放区节点 --
@onready var scene_runner: Control = %AVGSceneRunner
@onready var title_label: Label = %TitleLabel
@onready var content_container: Control = %ContentContainer
@onready var preview_container: SubViewportContainer = %PreviewContainer

# -- 页面节点 --
@onready var idle_page: Control = %IdlePage
@onready var playback_page: Control = %PlaybackPage

# -- 状态 --
var _session_id: String = ""
var _event_request: Dictionary = {}
var _scene_package: Dictionary = {}
var _finished: bool = false
var _current_page: Page = Page.HOME
var _did_pause_global_bgm: bool = false
var _is_playing_scene: bool = false


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
	call_deferred("navigate_to", Page.HOME)
	set_process(false)


func navigate_to(page: Page) -> void:
	_current_page = page
	if playback_page != null:
		playback_page.visible = page == Page.PLAYBACK
	if idle_page != null:
		idle_page.visible = page == Page.HOME


func play_event(session_id: String, event_request: Dictionary, _record_history: bool = true) -> void:
	_session_id = session_id
	_event_request = event_request.duplicate(true)
	_scene_package.clear()
	_finished = false
	if title_label != null:
		title_label.text = str(_event_request.get("title", "AVG Scene"))

	navigate_to(Page.PLAYBACK)

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
	_pause_global_bgm()
	_is_playing_scene = true
	playback_started.emit(_session_id)


func play_scene_package(session_id: String, scene_package: Dictionary, _record_history: bool = true) -> void:
	_session_id = session_id
	_event_request.clear()
	_scene_package = scene_package.duplicate(true)
	_finished = false
	print("[AVGPlayer] Playing scene_package (session=%s):\n%s" % [session_id, str(scene_package.get("scene_outline", "(no outline)"))])
	if title_label != null:
		title_label.text = str(_scene_package.get("title", "AVG Scene"))

	navigate_to(Page.PLAYBACK)

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
	_pause_global_bgm()
	_is_playing_scene = true
	playback_started.emit(_session_id)


func _on_scene_ended(_scene_id: String) -> void:
	if _finished:
		return

	var variable_manager: RefCounted = null
	if scene_runner != null and scene_runner.has_method("get_variable_manager"):
		variable_manager = scene_runner.get_variable_manager()

	var choice_id: int = 0
	if variable_manager != null and variable_manager.has_method("get_value_by_id"):
		var choice_value: Variant = variable_manager.get_value_by_id(CHOICE_VAR_ID)
		if choice_value != null:
			choice_id = int(choice_value)

	if not _event_request.is_empty():
		var outcomes: Dictionary = _event_request.get("outcomes", {})
		var selected_outcome: Dictionary = outcomes.get(choice_id, {})
		var outcome := selected_outcome.duplicate(true)
		outcome["success"] = true
		outcome["choice_id"] = choice_id
		outcome["choice_text"] = str(selected_outcome.get("text", ""))
		_emit_outcome(outcome)
		return

	var choice_labels: Dictionary = _scene_package.get("choice_labels", {})
	var selected_choice_text: String = str(choice_labels.get(choice_id, "")).strip_edges()
	_emit_outcome({
		"success": true,
		"choice_id": choice_id,
		"choice_text": selected_choice_text,
		"summary": selected_choice_text,
	})


func _emit_outcome(outcome: Dictionary) -> void:
	if _finished:
		return
	_finished = true
	_is_playing_scene = false
	set_process(false)
	_resume_global_bgm()

	if title_label != null:
		var ended_title := title_label.text.strip_edges()
		if not ended_title.ends_with(" · 已结束"):
			title_label.text = "%s · 已结束" % ended_title

	playback_finished.emit(_session_id, outcome)

	var return_timer := get_tree().create_timer(1.5)
	return_timer.timeout.connect(func() -> void:
		if is_instance_valid(self):
			navigate_to(Page.HOME)
	)


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


func is_playing_scene() -> bool:
	return _is_playing_scene


func _pause_global_bgm() -> void:
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("pause_bgm"):
		_did_pause_global_bgm = true
		audio.pause_bgm()


func _resume_global_bgm() -> void:
	if not _did_pause_global_bgm:
		return
	_did_pause_global_bgm = false
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("resume_bgm"):
		audio.resume_bgm()
