extends Control
## 可视化测试：通过 DSL 演示所有舞台站位。
## 使用 AVGSceneRunner 执行 DSL，与真实运行时一致。

const ParserClass = preload("res://scripts/avg/dsl/avg_dsl_parser_v2.gd")
const ValidatorClass = preload("res://scripts/avg/dsl/avg_dsl_validator.gd")
const AVGSceneClass = preload("res://scripts/avg/resources/avg_scene.gd")
const AVGRootNodeClass = preload("res://scripts/avg/resources/nodes/avg_root_node.gd")

const TEMPLATE_PROJECT_PATH: String = "res://templates/tutorial_project/project.tres"

## DSL 剧本：逐步展示 1~5 人排位、手动位置、enter/exit 补位
const POSITION_TEST_DSL: String = """
stage.set("Heroine01", emotions="happy")
# => TextBlock(speaker="Heroine01", expression="happy")
> 【1人】单人自动居中 (center = 0.5)

stage.set("Heroine01", "Hero01", emotions="happy,default")
# => TextBlock(speaker="Heroine01", expression="happy")
> 【2人】自动排成 left(0.35) / right(0.65)

stage.set("Heroine01", "Hero01", "Heroine02", emotions="happy,default,default")
# => TextBlock(speaker="Heroine01", expression="happy")
> 【3人】自动排成 far_left(0.3) / center(0.5) / far_right(0.7)

stage.set("Heroine01", "Hero01", "Heroine02", "Hero02", emotions="happy,default,default,default")
# => TextBlock(speaker="Heroine01", expression="happy")
> 【4人】均匀排布 (0.12 / 0.37 / 0.63 / 0.88)

stage.set("Heroine01", "Hero01", "Heroine02", "Hero02", "Heroine03", emotions="happy,default,default,default,default")
# => TextBlock(speaker="Heroine01", expression="happy")
> 【5人】均匀排布 (0.08 / 0.28 / 0.50 / 0.72 / 0.92)

stage.set("Heroine01", emotions="happy")
Heroine01.show(position="left", emotion="happy")
# => TextBlock(speaker="Heroine01", expression="happy")
> 【手动 left】单人站在 left(0.35) 位置

Heroine01.hide()
Hero01.show(position="right", emotion="default")
# => TextBlock(speaker="Hero01", expression="default")
> 【手动 right】单人站在 right(0.65) 位置

Hero01.hide()
Heroine02.show(position="far_left", emotion="default")
Hero02.show(position="far_right", emotion="default")
# => TextBlock(speaker="Heroine02", expression="default")
> 【手动 far_left + far_right】两侧边缘位置 (0.3 / 0.7)

stage.clear()
stage.set("Heroine01", emotions="happy")
# => TextBlock(speaker="Heroine01", expression="happy")
> 【stage.enter 准备】Heroine01 先单独登场 (center)

stage.enter("Hero01", emotions="default")
# => TextBlock(speaker="Hero01", expression="default")
> 【stage.enter】Hero01 加入，Heroine01 自动补位到 left

stage.exit("Hero01")
# => TextBlock(speaker="Heroine01", expression="happy")
> 【stage.exit】Hero01 退场，Heroine01 自动回到 center

stage.clear()
# => TextBlock(speaker="Heroine01")
> 【stage.clear】全部退场，演示结束
"""

@export var auto_play_on_ready: bool = true

@onready var scene_runner: Control = %AVGSceneRunner
@onready var status_label: Label = %StatusLabel

var _parser: RefCounted = ParserClass.new()
var _validator: RefCounted = ValidatorClass.new()


func _ready() -> void:
	if auto_play_on_ready:
		call_deferred("_play_position_test")


func _play_position_test() -> void:
	var raw_text: String = POSITION_TEST_DSL.strip_edges()
	var parse_result: Dictionary = _parser.parse(raw_text)
	if not bool(parse_result.get("success", false)):
		var errors: Array = parse_result.get("errors", [])
		print("DSL 解析失败：%s" % str(errors))
		_set_status("DSL 解析失败", Color(1.0, 0.56, 0.56, 1.0))
		return

	var project: Resource = _load_template_project()
	if project == null:
		print("ERROR: 无法加载 template project")
		_set_status("模板项目加载失败", Color(1.0, 0.56, 0.56, 1.0))
		return

	var commands: Array = parse_result.get("commands", [])
	var validate_result: Dictionary = _validator.validate_commands(commands, project, str(project.project_root_path), {
		"min_choice_count": 0,
		"max_choice_count": 0,
	})
	if not bool(validate_result.get("ok", false)):
		print("DSL 语义检查失败：%s" % str(validate_result.get("errors", [])))
		_set_status("DSL 语义检查失败", Color(1.0, 0.56, 0.56, 1.0))
		return

	var preview_scene: Resource = _build_preview_scene(commands)
	project.scenes = [preview_scene]

	if scene_runner.has_method("reset"):
		scene_runner.reset()
	if scene_runner.has_method("load_project"):
		scene_runner.load_project(project)
	if scene_runner.has_method("load_scene"):
		scene_runner.load_scene(preview_scene)
	if scene_runner.has_method("start"):
		scene_runner.start()

	print("=== 舞台站位可视化测试 ===")
	print("点击窗口推进对话，观察角色站位变化")
	_set_status("正在播放站位测试 DSL — 点击窗口推进", Color(0.66, 0.92, 0.72, 1.0))


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
	scene.scene_id = "stage_positions_test"
	scene.scene_name = "Stage Positions Visual Test"
	scene.nodes = [root]
	scene.local_variables = []
	return scene


func _set_status(text: String, color: Color) -> void:
	if status_label != null:
		status_label.text = text
		status_label.modulate = color
