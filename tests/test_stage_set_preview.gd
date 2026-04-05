extends Control

const ParserClass = preload("res://scripts/avg/dsl/avg_dsl_parser_v2.gd")
const ValidatorClass = preload("res://scripts/avg/dsl/avg_dsl_validator.gd")
const AVGSceneClass = preload("res://scripts/avg/resources/avg_scene.gd")
const AVGRootNodeClass = preload("res://scripts/avg/resources/nodes/avg_root_node.gd")

const TEMPLATE_PROJECT_PATH: String = "res://templates/tutorial_project/project.tres"
const SAMPLE_DSL: String = """stage.set("Heroine01", emotions="happy")
# => TextBlock(speaker="Heroine01", expression="happy")
> 先让一位角色单独站在中间。

stage.set("Heroine01", "Hero01", emotions="surprised,serious")
# => TextBlock(speaker="Hero01", expression="serious")
> 第二位角色登场时，原来的角色会自动让位。

# => TextBlock(speaker="Heroine01", expression="surprised")
> 登场时的表情，也可以和 stage.set 一起指定。

stage.set("Heroine01", "Hero01", "Hero02", emotions="thinking,serious,happy")
# => TextBlock(speaker="Hero02", expression="happy")
> 第三位角色加入时，系统会继续自动排位。

stage.set("Heroine01", "Hero02", emotions="happy,thinking")
# => TextBlock(speaker="Heroine01", expression="happy")
> 中途有人离场后，剩下的人会自动补位。

stage.set("Hero02", emotions="serious")
# => TextBlock(speaker="Hero02", expression="serious")
> 最后只剩一个人时，会自动回到中间。
"""

@export var auto_play_on_ready: bool = true

@onready var dsl_input: TextEdit = %DSLInput
@onready var play_button: Button = %PlayButton
@onready var reset_button: Button = %ResetButton
@onready var status_label: Label = %StatusLabel
@onready var validation_view: TextEdit = %ValidationView
@onready var scene_runner: Control = %AVGSceneRunner

var _parser: RefCounted = ParserClass.new()
var _validator: RefCounted = ValidatorClass.new()
var _preview_project: Resource = null
var _preview_scene: Resource = null


func _ready() -> void:
	dsl_input.text = SAMPLE_DSL
	play_button.pressed.connect(_on_play_pressed)
	reset_button.pressed.connect(_on_reset_pressed)
	if auto_play_on_ready:
		call_deferred("_play_current_dsl")


func _on_play_pressed() -> void:
	_play_current_dsl()


func _on_reset_pressed() -> void:
	dsl_input.text = SAMPLE_DSL
	_play_current_dsl()


func _play_current_dsl() -> void:
	var raw_text: String = dsl_input.text.strip_edges()
	if raw_text.is_empty():
		validation_view.text = "请先输入 DSL。"
		_set_status("DSL 输入为空，无法播放。", Color(1.0, 0.56, 0.56, 1.0))
		return

	var parse_result: Dictionary = _parser.parse(raw_text)
	if not bool(parse_result.get("success", false)):
		validation_view.text = _format_parse_errors(parse_result.get("errors", []))
		_set_status("DSL 解析没有通过。", Color(1.0, 0.56, 0.56, 1.0))
		return

	var project: Resource = _load_template_project()
	if project == null:
		validation_view.text = "没有成功加载 template project。"
		_set_status("模板项目加载失败。", Color(1.0, 0.56, 0.56, 1.0))
		return

	var commands: Array = parse_result.get("commands", [])
	var validate_result: Dictionary = _validator.validate_commands(commands, project, str(project.project_root_path), {
		"min_choice_count": 0,
		"max_choice_count": 0,
	})
	validation_view.text = _format_validation_result(validate_result, commands.size(), project)
	if not bool(validate_result.get("ok", false)):
		_set_status("DSL 语义检查没有通过。", Color(1.0, 0.56, 0.56, 1.0))
		return

	_preview_project = project
	_preview_scene = _build_preview_scene(commands)
	_preview_project.scenes = [_preview_scene]
	_play_preview_scene()
	_set_status("已经按 template project 播放 DSL。你现在看到的是模板项目里的真实角色资源。", Color(0.66, 0.92, 0.72, 1.0))


func _load_template_project() -> Resource:
	if not ResourceLoader.exists(TEMPLATE_PROJECT_PATH):
		return null
	var source: Resource = load(TEMPLATE_PROJECT_PATH)
	if source == null:
		return null
	var project: Resource = source.duplicate(true)
	project.project_root_path = "res://templates/tutorial_project/"
	return project


func _build_preview_scene(commands: Array) -> Resource:
	var root := AVGRootNodeClass.new()
	root.node_id = "root"
	root.node_name = "Root"
	root.norm_position = Vector2.ZERO
	root.norm_size = Vector2.ONE
	root.position = Vector2.ZERO
	root.size = Vector2(2560, 1440)
	root.command_tabs = [{
		"commands": commands.duplicate(true),
		"condition_commands": [],
		"mode": 0,
	}]

	var scene := AVGSceneClass.new()
	scene.scene_id = "stage_set_preview_scene"
	scene.scene_name = "Stage Set Preview Scene"
	scene.nodes = [root]
	scene.local_variables = []
	return scene


func _play_preview_scene() -> void:
	if scene_runner == null or _preview_project == null or _preview_scene == null:
		return
	if scene_runner.has_method("reset"):
		scene_runner.reset()
	if scene_runner.has_method("load_project"):
		scene_runner.load_project(_preview_project)
	if scene_runner.has_method("load_scene"):
		scene_runner.load_scene(_preview_scene)
	if scene_runner.has_method("start"):
		scene_runner.start()


func _format_parse_errors(errors: Array) -> String:
	var lines: PackedStringArray = ["解析失败："]
	for entry in errors:
		if entry is Dictionary:
			lines.append("- 第 %d 行：%s" % [int(entry.get("line", 0)), str(entry.get("message", "未知错误"))])
		else:
			lines.append("- %s" % str(entry))
	return "\n".join(lines)


func _format_validation_result(result: Dictionary, command_count: int, project: Resource) -> String:
	var lines: PackedStringArray = []
	lines.append("命令数量：%d" % command_count)
	lines.append("语义检查：%s" % ("通过" if bool(result.get("ok", false)) else "未通过"))
	lines.append("模板项目角色数：%d" % int(project.characters.size() if project != null else 0))
	var errors: Array = result.get("errors", [])
	if errors.is_empty():
		lines.append("没有发现语义错误。")
	else:
		lines.append("错误列表：")
		for entry in errors:
			lines.append("- %s" % str(entry))
	return "\n".join(lines)


func _set_status(text: String, color: Color) -> void:
	status_label.text = text
	status_label.modulate = color
