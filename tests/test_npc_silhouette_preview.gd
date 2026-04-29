extends Control

const CharacterDisplayClass = preload("res://scripts/avg/runtime/character_display.gd")

const PROJECT_PATH := "res://narrative_projects/main_story/project.tres"
const DESIGN_RESOLUTION := Vector2(2560, 1440)

var _character_display: CharacterDisplay = null
var _title_label: Label = null
var _hint_label: Label = null
var _status_label: Label = null
var _project: Resource = null
var _character_map: Dictionary = {}


func _ready() -> void:
	_build_ui()
	_load_project()
	_build_character_map()
	_build_character_display()
	_show_preset(1)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				_show_preset(1)
			KEY_2:
				_show_preset(2)
			KEY_3:
				_show_preset(3)


func _build_ui() -> void:
	var background := ColorRect.new()
	background.anchor_right = 1.0
	background.anchor_bottom = 1.0
	background.color = Color("1c2029")
	add_child(background)

	var vignette := ColorRect.new()
	vignette.anchor_right = 1.0
	vignette.anchor_bottom = 1.0
	vignette.color = Color(0.0, 0.0, 0.0, 0.18)
	add_child(vignette)

	_title_label = Label.new()
	_title_label.position = Vector2(36, 24)
	_title_label.size = Vector2(980, 40)
	_title_label.add_theme_font_size_override("font_size", 26)
	_title_label.text = "NPC Silhouette Preview"
	add_child(_title_label)

	_hint_label = Label.new()
	_hint_label.position = Vector2(36, 64)
	_hint_label.size = Vector2(1600, 72)
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.add_theme_font_size_override("font_size", 18)
	_hint_label.text = "按 1 查看成人路人组合，按 2 查看店员组合，按 3 查看老人/小孩组合。关闭窗口前请目视确认：底边落地、头身比正常、男女身高关系自然、小孩显著更矮。"
	add_child(_hint_label)

	_status_label = Label.new()
	_status_label.position = Vector2(36, 126)
	_status_label.size = Vector2(1800, 120)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_font_size_override("font_size", 18)
	add_child(_status_label)


func _load_project() -> void:
	_project = load(PROJECT_PATH)
	if _project == null:
		push_error("Failed to load project: %s" % PROJECT_PATH)
		return


func _build_character_map() -> void:
	_character_map.clear()
	if _project == null or not ("characters" in _project):
		return
	for character in _project.characters:
		if character == null:
			continue
		var character_id: String = str(character.character_id if "character_id" in character else "").strip_edges()
		if character_id.is_empty():
			continue
		_character_map[character_id] = character


func _build_character_display() -> void:
	_character_display = CharacterDisplayClass.new()
	_character_display.name = "CharacterDisplay"
	_character_display.anchor_right = 1.0
	_character_display.anchor_bottom = 1.0
	add_child(_character_display)
	_character_display.set_design_resolution(DESIGN_RESOLUTION)
	_character_display.set_character_data(_character_map)


func _show_preset(index: int) -> void:
	if _character_display == null:
		return
	_character_display.hide_all(0.0)
	await get_tree().process_frame

	match index:
		1:
			_title_label.text = "NPC Silhouette Preview - Preset 1 / 成人路人"
			_status_label.text = _compose_status([
				"LinXia: happy / casual",
				"NpcFemale: 路人",
				"NpcMale: 路人",
			])
			_character_display.stage_set(["LinXia", "NpcFemale", "NpcMale"], "happy,路人,路人", "casual,_,_", 0.0)
		2:
			_title_label.text = "NPC Silhouette Preview - Preset 2 / 店员"
			_status_label.text = _compose_status([
				"LinXia: serious / casual",
				"NpcFemale: 店员",
				"NpcMale: 店员",
			])
			_character_display.stage_set(["LinXia", "NpcFemale", "NpcMale"], "serious,店员,店员", "casual,_,_", 0.0)
		3:
			_title_label.text = "NPC Silhouette Preview - Preset 3 / 老人 + 小孩"
			_status_label.text = _compose_status([
				"LinXia: soft_smile / casual",
				"NpcFemale: 老人",
				"NpcMale: 小孩",
			])
			_character_display.stage_set(["LinXia", "NpcFemale", "NpcMale"], "soft_smile,老人,小孩", "casual,_,_", 0.0)
		_:
			return

	await get_tree().process_frame
	_log_visible_metrics(index)


func _compose_status(lines: Array[String]) -> String:
	var result: Array[String] = []
	result.append("当前预设：")
	for line in lines:
		result.append("- %s" % line)
	return "\n".join(result)


func _log_visible_metrics(index: int) -> void:
	print("=== NPC Silhouette Preview Preset %d ===" % index)
	for reference in ["LinXia", "NpcFemale", "NpcMale"]:
		var sprite: TextureRect = _character_display.get_character_sprite(reference)
		if sprite == null or sprite.texture == null:
			print("%s -> missing sprite" % reference)
			continue
		print("%s -> texture=%s size=%s pos=%s" % [
			reference,
			str(sprite.texture.resource_path),
			str(sprite.size),
			str(sprite.position),
		])
