class_name AVGSceneRunner extends Control
## AVG Scene Runner - 场景运行时引擎
## 遍历节点树，收集命令，按模式执行：
##   自动(0): DFS顺序拼接成主线，顺序执行（瞬时命令连续，阻塞命令暂停）
##   并行(1): 场景加载时立即全部触发
##   点击(2): 注册为节点点击事件处理器

# Preload dependencies
const VariableManagerClass = preload("res://scripts/avg/runtime/variable_manager.gd")
const CommandContextClass = preload("res://scripts/avg/runtime/command_context.gd")
const CommandRegistryClass = preload("res://scripts/avg/commands/command_registry.gd")
const CommandInitializerClass = preload("res://scripts/avg/commands/command_initializer.gd")
const ParallelExecutorClass = preload("res://scripts/avg/runtime/parallel_executor.gd")
const AVGVariableClass = preload("res://scripts/avg/resources/avg_variable.gd")
const AVGCanvasLayerNodeClass = preload("res://scripts/avg/resources/nodes/avg_canvas_layer_node.gd")
const HistoryManagerClass = preload("res://scripts/avg/runtime/history_manager.gd")
const AVGSaveManagerClass = preload("res://scripts/avg/runtime/save_manager.gd")
const GameScreenManagerClass = preload("res://scripts/avg/runtime/game_screen_manager.gd")
const AVGScreenConfigClass = preload("res://scripts/avg/resources/avg_screen_config.gd")
const AVGResourceLoaderClass = preload("res://scripts/avg/assets/avg_resource_loader.gd")

## 阻塞命令类型集合 — 这些命令会暂停主线等待
const BLOCKING_COMMANDS: Array[String] = [
	"DIALOGUE", "WAIT_CLICK", "WAIT_TIME", "CHOICE", "SCREEN_FADE", "CHANGE_BACKGROUND", "SET_TIME_OF_DAY"
]

## 由运行时直接处理的命令（不走 handler）
const RUNTIME_HANDLED_COMMANDS: Array[String] = [
	"IF", "CALL_EVENT", "CHECK_HOVER", "CHECK_CLICK", "CHECK_VAR"
]

## 转场类型名称 -> shader transition_type 映射
const TRANSITION_TYPES: Dictionary = {
	"fade": 0,
	"dissolve": 1,
	"wipe_left": 2,
	"wipe_right": 3,
	"wipe_up": 4,
	"wipe_down": 5,
}

const TIME_OF_DAY_PRESETS: Dictionary = {
	"day": {
		"effect_strength": 0.0,
		"tint_color": Color(1.0, 1.0, 1.0, 1.0),
		"tint_strength": 0.0,
		"saturation": 1.0,
		"exposure": 1.0,
		"gradient_top_color": Color(1.0, 1.0, 1.0, 1.0),
		"gradient_bottom_color": Color(1.0, 1.0, 1.0, 1.0),
		"gradient_strength": 0.0,
	},
	"dusk": {
		"effect_strength": 1.0,
		"tint_color": Color(1.08, 0.92, 0.78, 1.0),
		"tint_strength": 0.22,
		"saturation": 0.94,
		"exposure": 0.95,
		"gradient_top_color": Color(0.96, 0.78, 0.62, 1.0),
		"gradient_bottom_color": Color(1.0, 0.9, 0.78, 1.0),
		"gradient_strength": 0.16,
	},
	"night": {
		"effect_strength": 1.0,
		"tint_color": Color(0.76, 0.86, 1.08, 1.0),
		"tint_strength": 0.34,
		"saturation": 0.82,
		"exposure": 0.78,
		"gradient_top_color": Color(0.22, 0.3, 0.52, 1.0),
		"gradient_bottom_color": Color(0.48, 0.56, 0.7, 1.0),
		"gradient_strength": 0.22,
	},
}

# =============================================================================
# Signals
# =============================================================================

signal scene_started(scene_id: String)
signal scene_ended(scene_id: String)
signal command_executed(command_type: String, command_index: int)
## 标题界面请求开始游戏（由标题界面按钮触发）
signal title_start_requested(first_scene_index: int)
## 游戏内 UI 按钮被点击（action: save/load/auto/skip/log/hide_ui/settings/menu）
signal game_ui_action_requested(action: String)

# =============================================================================
# Node References
# =============================================================================

## 设计分辨率容器 — 世界内容放在这里，受 Camera2D 影响
@onready var design_container: Control = %DesignContainer
@onready var background_display: TextureRect = %BackgroundDisplay
@onready var character_display: Control = %CharacterDisplay
## UI 层容器 — 不受 Camera2D 影响
@onready var ui_container: Control = %UIContainer
@onready var dialog_overlay_container: Control = %DialogOverlayContainer
@onready var dialog_box: Control = %DialogBox
@onready var choice_display: Control = %ChoiceDisplay
## 效果层容器 — 不受 Camera2D 影响
@onready var effects_container: Control = %EffectsContainer
@onready var audio_manager: Node = %AVGAudioAdapter
## 摄像机
@onready var _camera: Camera2D = %Camera2D

## 动态节点容器 — 渲染 AVG 节点树中的可视节点（在 DesignContainer 内）
var _nodes_layer: Control = null
## AVG node_id -> Godot Control 映射
var _rendered_nodes: Dictionary = {}
## 屏幕效果层（淡入淡出、闪烁，在效果层容器内）
var _screen_effects_layer: ColorRect = null
var _time_of_day_layer: ColorRect = null
## 图片层（CG/图片显示，在角色层之上）
var _image_layer: Control = null
## 已显示的图片: image_id -> TextureRect
var _displayed_images: Dictionary = {}
## 图片层过渡 tween: image_id -> Tween
var _image_transition_tweens: Dictionary = {}
## 图片层旧图 overlay: image_id -> TextureRect
var _image_transition_overlays: Dictionary = {}
## 图片层黑场 overlay: image_id -> ColorRect
var _image_black_overlays: Dictionary = {}
## 摄像机动画 tween
var _camera_tween: Tween = null
## 转场动画 tween
var _transition_tween: Tween = null
var _time_of_day_tween: Tween = null
## 待播放的转场入场效果（跨场景跳转时使用）
## {type: int, duration: float, color: Color}
var _pending_transition: Dictionary = {}
## 待执行的跳转转场参数（由 jump_scene_with_transition 设置，_on_scene_jump_requested 消费）
var _pending_jump_transition: Dictionary = {}
## 背景转场覆盖层（在 BackgroundDisplay 之上）
var _bg_transition_layer: TextureRect = null
## 背景转场 tween
var _bg_transition_tween: Tween = null
## 标题界面容器（运行时生成，覆盖在 UI 层）
var _title_screen: Control = null
## 是否正在显示标题界面
var _showing_title: bool = false
var _current_time_of_day: String = "day"
## 游戏内 UI 按钮容器
var _game_ui_container: Control = null
## 游戏内 UI 按钮映射: action -> Button
var _game_ui_buttons: Dictionary = {}

# =============================================================================
# State
# =============================================================================

## 当前场景和游戏数据
var current_scene: Resource = null
var game_data: Resource = null

## 主线命令队列（从所有自动tab DFS收集）
var _main_queue: Array = []  # Array[AVGCommand]
## 主线当前执行位置
var _main_index: int = 0
## 标签索引: label_name -> index in _main_queue
var _label_index: Dictionary = {}
## 点击事件处理器: node_id -> Array[AVGCommand]
var _click_handlers: Dictionary = {}
## CALL_EVENT 调用栈: Array of {queue: Array, index: int, label_index: Dictionary}
var _call_stack: Array = []

## 运行状态
var is_running: bool = false
var _should_continue: bool = false
var _is_blocked: bool = false
## 读档后等待玩家点击（恢复状态后不立即执行）
var _restore_waiting_click: bool = false
## 执行代数 — 每次 start() 递增，用于检测过期协程
var _execution_generation: int = 0

## ---- 事件循环系统 ----
## 所有带 command_tabs 的节点（DFS 扁平化，用于重新评估）
var _all_event_nodes: Array = []  # Array[Resource(AVGNode)]
## node_id -> 当前激活的 tab index（-1 = 无匹配 tab）
var _node_active_tab: Dictionary = {}
## 变量变化后需要重新评估的标记
var _needs_reevaluation: bool = false

## 场景开始时间（用于 play_time 游戏元素）
var _scene_start_time: float = 0.0

## 内部组件
var _variable_manager: RefCounted = null
var _command_context: RefCounted = null
var _command_registry: RefCounted = null
var _history_manager: RefCounted = null  # HistoryManager
var _save_manager: RefCounted = null  # AVGSaveManager
var _screen_manager: RefCounted = null  # GameScreenManager

## 项目分辨率（设计分辨率）
var _project_resolution: Vector2 = Vector2(3840, 2160)


# =============================================================================
# Lifecycle
# =============================================================================

func _ready() -> void:
	_command_registry = CommandRegistryClass.get_instance()
	CommandInitializerClass.register_all_commands(_command_registry)
	_variable_manager = VariableManagerClass.new()
	_command_context = CommandContextClass.new()
	_history_manager = HistoryManagerClass.new()
	_save_manager = AVGSaveManagerClass.new()
	_screen_manager = GameScreenManagerClass.new()
	_create_nodes_layer()
	_create_bg_transition_layer()
	_create_image_layer()
	_create_time_of_day_layer()
	_create_screen_effects_layer()
	_setup_command_context()
	_connect_signals()
	call_deferred("_update_container_scale")
	call_deferred("_setup_camera")
	# 监听 viewport size 变化，更新容器缩放
	var vp = get_viewport()
	if vp and vp is SubViewport:
		vp.size_changed.connect(_on_viewport_size_changed)


## viewport 大小变化时更新容器缩放
func _on_viewport_size_changed() -> void:
	_update_container_scale()
	_apply_camera_defaults()


## 创建动态节点渲染层（在 BackgroundDisplay 之后，CharacterDisplay 之前）
func _create_nodes_layer() -> void:
	_nodes_layer = Control.new()
	_nodes_layer.name = "NodesLayer"
	_nodes_layer.size = _project_resolution
	_nodes_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 插入到 DesignContainer 内，BackgroundDisplay 之后
	if design_container and background_display:
		var bg_index: int = background_display.get_index()
		design_container.add_child(_nodes_layer)
		design_container.move_child(_nodes_layer, bg_index + 1)
	elif design_container:
		design_container.add_child(_nodes_layer)
		design_container.move_child(_nodes_layer, 0)


## 创建背景转场覆盖层（在 BackgroundDisplay 之上、NodesLayer 之前）
func _create_bg_transition_layer() -> void:
	_bg_transition_layer = TextureRect.new()
	_bg_transition_layer.name = "BgTransitionLayer"
	_bg_transition_layer.position = Vector2.ZERO
	_bg_transition_layer.size = _project_resolution
	_bg_transition_layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg_transition_layer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg_transition_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg_transition_layer.visible = false
	# 加载背景转场 shader
	var shader: Shader = load("res://shaders/background_transition.gdshader")
	if shader:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("progress", 0.0)
		mat.set_shader_parameter("transition_type", 0)
		mat.set_shader_parameter("smoothness", 0.05)
		_bg_transition_layer.material = mat
	# 插入到 BackgroundDisplay 之后、NodesLayer 之前
	if design_container and background_display:
		var bg_index: int = background_display.get_index()
		design_container.add_child(_bg_transition_layer)
		design_container.move_child(_bg_transition_layer, bg_index + 1)
	elif design_container:
		design_container.add_child(_bg_transition_layer)


## 创建图片层（CG/图片，在 CharacterDisplay 之后、DialogBox 之前）
func _create_image_layer() -> void:
	_image_layer = Control.new()
	_image_layer.name = "ImageLayer"
	_image_layer.size = _project_resolution
	_image_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if design_container and dialog_box:
		var dialog_index: int = dialog_box.get_index()
		design_container.add_child(_image_layer)
		design_container.move_child(_image_layer, dialog_index)
	elif design_container:
		design_container.add_child(_image_layer)


## 创建屏幕效果层（淡入淡出、闪烁，在最顶层覆盖一切）
func _create_time_of_day_layer() -> void:
	_time_of_day_layer = ColorRect.new()
	_time_of_day_layer.name = "TimeOfDayLayer"
	_time_of_day_layer.position = Vector2.ZERO
	_time_of_day_layer.size = _project_resolution
	_time_of_day_layer.color = Color.WHITE
	_time_of_day_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_time_of_day_layer.visible = false

	var shader: Shader = load("res://shaders/time_of_day_grade.gdshader")
	if shader:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		_time_of_day_layer.material = mat
		_apply_time_of_day_params(TIME_OF_DAY_PRESETS["day"])

	if design_container:
		design_container.add_child(_time_of_day_layer)
		design_container.move_child(_time_of_day_layer, design_container.get_child_count() - 1)


func _create_screen_effects_layer() -> void:
	_screen_effects_layer = ColorRect.new()
	_screen_effects_layer.name = "ScreenEffectsLayer"
	_screen_effects_layer.position = Vector2.ZERO
	_screen_effects_layer.size = _project_resolution
	_screen_effects_layer.color = Color.WHITE  # shader 控制实际颜色
	_screen_effects_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen_effects_layer.visible = false
	# 加载转场 shader
	var shader: Shader = load("res://shaders/screen_transition.gdshader")
	if shader:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("progress", 0.0)
		mat.set_shader_parameter("fade_color", Color.BLACK)
		mat.set_shader_parameter("transition_type", 0)
		mat.set_shader_parameter("smoothness", 0.05)
		_screen_effects_layer.material = mat
	if effects_container:
		effects_container.add_child(_screen_effects_layer)


## 设置摄像机初始状态和限制
func _setup_camera() -> void:
	if _camera == null:
		return
	_camera.enabled = true
	_camera.zoom = Vector2.ONE
	_camera.offset = Vector2.ZERO
	_apply_camera_defaults()


## 根据当前 viewport 缩放比例设置 camera 默认位置和 limit
func _apply_camera_defaults() -> void:
	if _camera == null:
		return
	var base_scale: Vector2 = _get_base_scale()
	# 缩放后的场景尺寸
	var scaled_size: Vector2 = _project_resolution * base_scale
	# 初始位置在缩放后场景的中心
	_camera.position = scaled_size / 2.0
	# limit 为缩放后的场景边界
	_camera.limit_left = 0
	_camera.limit_top = 0
	_camera.limit_right = int(scaled_size.x)
	_camera.limit_bottom = int(scaled_size.y)
	_camera.limit_smoothed = true


## 获取 viewport 适配缩放比例
func _get_base_scale() -> Vector2:
	if _project_resolution.x <= 0 or _project_resolution.y <= 0:
		return Vector2.ONE
	var vp = get_viewport()
	if vp == null:
		return Vector2.ONE
	var vp_size: Vector2
	if vp is SubViewport:
		vp_size = Vector2(vp.size)
	else:
		vp_size = get_viewport_rect().size
	if vp_size.x <= 0 or vp_size.y <= 0:
		return Vector2.ONE
	return vp_size / _project_resolution


## 更新容器缩放（viewport_size / design_resolution）
## Camera2D 处理 zoom/pan，这里只做 viewport 适配
func _update_container_scale() -> void:
	if design_container == null:
		return
	if _project_resolution.x <= 0 or _project_resolution.y <= 0:
		return
	var vp = get_viewport()
	if vp == null:
		return
	var vp_size: Vector2
	if vp is SubViewport:
		vp_size = Vector2(vp.size)
	else:
		vp_size = get_viewport_rect().size
	if vp_size.x <= 0 or vp_size.y <= 0:
		return
	# viewport 适配缩放
	var base_scale: Vector2 = vp_size / _project_resolution
	design_container.scale = base_scale
	design_container.position = Vector2.ZERO
	# UI 层和效果层也需要同样的缩放
	if ui_container:
		ui_container.scale = base_scale
	if dialog_overlay_container:
		dialog_overlay_container.scale = base_scale
	if effects_container:
		effects_container.scale = base_scale


func _setup_command_context() -> void:
	_command_context.initialize({
		"scene_runner": self,
		"variable_manager": _variable_manager,
		"dialog_box": dialog_box,
		"character_display": character_display,
		"choice_display": choice_display,
		"audio_manager": audio_manager,
		"background_display": background_display,
	})


func _connect_signals() -> void:
	# 对话框点击 → 推进主线
	if dialog_box != null and dialog_box.has_signal("clicked"):
		dialog_box.clicked.connect(_on_dialog_clicked)
	# 标签/场景/事件跳转请求
	if _command_context != null:
		_command_context.label_jump_requested.connect(_on_label_jump_requested)
		_command_context.scene_jump_requested.connect(_on_scene_jump_requested)
		_command_context.event_call_requested.connect(_on_event_call_requested)
	# 变量变化 → 标记需要重新评估节点 tab
	if _variable_manager != null:
		_variable_manager.variable_changed.connect(_on_variable_changed)
	# 游戏内 UI 按钮 → 打开子界面
	game_ui_action_requested.connect(_on_game_ui_action)
	# 子界面管理器信号
	if _screen_manager != null:
		_screen_manager.screen_closed.connect(_on_screen_closed)
		_screen_manager.save_requested.connect(_on_save_requested)
		_screen_manager.load_requested.connect(_on_load_requested)
		_screen_manager.return_to_title_requested.connect(_on_return_to_title)
		_screen_manager.quit_requested.connect(_on_quit_requested)


# =============================================================================
# Scene Loading
# =============================================================================

## 加载游戏本体的 AVG 数据
func load_game_data(data: Resource) -> void:
	if data == null:
		push_error("AVGSceneRunner: Cannot load null game data")
		return
	game_data = data

	# 更新设计分辨率，设置容器大小和缩放
	if "resolution" in data:
		_project_resolution = Vector2(data.resolution)
	if design_container:
		design_container.size = _project_resolution
	if _nodes_layer:
		_nodes_layer.size = _project_resolution
	if _image_layer:
		_image_layer.size = _project_resolution
	if _time_of_day_layer:
		_time_of_day_layer.size = _project_resolution
	if _screen_effects_layer:
		_screen_effects_layer.size = _project_resolution
	if dialog_overlay_container:
		dialog_overlay_container.size = _project_resolution
	_update_container_scale()
	_setup_camera()

	# 传递设计分辨率给 character_display（立绘直接用设计坐标，不需要缩放）
	if character_display != null and character_display.has_method("set_design_resolution"):
		character_display.set_design_resolution(_project_resolution)

	if data.variables != null and data.variables.size() > 0:
		_variable_manager.initialize(data.variables)
	_setup_character_data()

	# Pass dialog settings to dialog_box and choice_display
	if "dialog_settings" in data and data.dialog_settings != null:
		if dialog_box != null and dialog_box.has_method("set_dialog_settings"):
			dialog_box.set_dialog_settings(data.dialog_settings)
		if choice_display != null and choice_display.has_method("set_dialog_settings"):
			choice_display.set_dialog_settings(data.dialog_settings)
		if character_display != null and character_display.has_method("set_dialog_settings"):
			character_display.set_dialog_settings(data.dialog_settings)

	# Pass variable manager to dialog_box for {var_name} substitution
	if dialog_box != null and dialog_box.has_method("set_variable_manager"):
		dialog_box.set_variable_manager(_variable_manager)

	# 初始化 game_ui_config
	if not "game_ui_config" in data or data.game_ui_config == null:
		var AVGGameUIConfigClass = load("res://scripts/avg/resources/avg_game_ui_config.gd")
		if AVGGameUIConfigClass:
			data.game_ui_config = AVGGameUIConfigClass.new()
			if data.game_ui_config.has_method("init_defaults"):
				data.game_ui_config.init_defaults()
	if _save_manager != null:
		_save_manager.set_save_namespace(data.game_name)
	if _screen_manager != null and ui_container != null:
		_screen_manager.setup(ui_container, _project_resolution, data, _save_manager, _history_manager)


func load_game_texture(asset_ref: String) -> Texture2D:
	return AVGResourceLoaderClass.load_texture(asset_ref)


## 加载场景 — 遍历节点树，收集命令
func load_scene(scene: Resource) -> void:
	if scene == null:
		push_error("AVGSceneRunner: Cannot load null scene")
		return
	if is_running:
		stop()

	current_scene = scene
	_main_queue.clear()
	_main_index = 0
	_label_index.clear()
	_click_handlers.clear()
	_all_event_nodes.clear()
	_node_active_tab.clear()
	_needs_reevaluation = false

	# 初始化场景独立变量
	if _variable_manager != null:
		_variable_manager.clear_local()
		if "local_variables" in scene and scene.local_variables != null and scene.local_variables.size() > 0:
			_variable_manager.initialize_local(scene.local_variables)

	# DFS 遍历节点树，收集所有带 command_tabs 的节点
	for node in scene.nodes:
		if node != null:
			_collect_event_nodes_dfs(node)

	# 首次评估所有节点，收集命令
	_evaluate_and_collect_all()

	# 构建标签索引
	_build_label_index()

	# 设置场景初始状态（背景、BGM来自 Root 节点）
	_setup_scene_initial_state()


## DFS 遍历节点，收集所有带 command_tabs 的节点到 _all_event_nodes
func _collect_event_nodes_dfs(node: Resource) -> void:
	if node == null:
		return

	# SharedNodeRef — 解析为实际节点后递归
	if node is AVGSharedNodeRef:
		var resolved: Resource = node.get_resolved_node(game_data)
		if resolved != null:
			_collect_event_nodes_dfs(resolved)
		return

	# 如果节点有 command_tabs，加入事件节点列表
	if "command_tabs" in node and node.command_tabs != null and node.command_tabs.size() > 0:
		_all_event_nodes.append(node)

	# 递归处理子节点
	if "children" in node:
		for child in node.children:
			_collect_event_nodes_dfs(child)


## 评估所有事件节点，收集命令到对应队列（首次加载 + 事件循环重新评估共用）
func _evaluate_and_collect_all() -> void:
	_main_queue.clear()
	_main_index = 0
	_click_handlers.clear()
	_parallel_commands.clear()
	_stop_parallel_executors()

	for node in _all_event_nodes:
		var node_id: String = node.node_id if "node_id" in node else ""
		var tab_result: Dictionary = _evaluate_command_tabs_with_index(node)
		var tab_index: int = tab_result.get("index", -1)
		var tab: Dictionary = tab_result.get("tab", {})

		# 记录当前激活的 tab
		if not node_id.is_empty():
			_node_active_tab[node_id] = tab_index

		if tab.is_empty():
			continue

		var mode: int = tab.get("mode", 0)
		var commands: Array = tab.get("commands", [])

		match mode:
			0:  # 自动 → 追加到主线队列
				_main_queue.append_array(commands)
			1:  # 并行 → 暂存
				if not _parallel_commands.has(node):
					_parallel_commands[node] = commands
			2:  # 点击 → 注册处理器
				if not node_id.is_empty():
					_click_handlers[node_id] = commands


## 评估节点的 command_tabs，返回匹配的 tab 和其 index
## 返回 {"index": int, "tab": Dictionary}
func _evaluate_command_tabs_with_index(node: Resource) -> Dictionary:
	if not "command_tabs" in node or node.command_tabs == null:
		return {"index": -1, "tab": {}}

	var tabs: Array = node.command_tabs
	if tabs.is_empty():
		return {"index": -1, "tab": {}}

	# 从最后一个 tab 向前检查
	for i in range(tabs.size() - 1, -1, -1):
		var tab: Dictionary = tabs[i]
		if _check_tab_condition(tab):
			return {"index": i, "tab": tab}

	return {"index": -1, "tab": {}}


## 并行执行器列表 — 每个并行模式节点一个独立执行器
var _parallel_executors: Array = []  # Array[ParallelExecutor]
## 并行命令暂存（load_scene 时收集，start 时创建执行器）
var _parallel_commands: Dictionary = {}  # node -> Array[AVGCommand]
## 鼠标悬停节点追踪: node_id -> bool
var _hovered_nodes: Dictionary = {}
## 鼠标按下节点追踪: node_id -> bool
var _pressed_nodes: Dictionary = {}


## 评估节点的 command_tabs，从最后一个向前检查条件
## 返回第一个满足条件的 tab（Dictionary），或空 Dictionary
func _evaluate_command_tabs(node: Resource) -> Dictionary:
	return _evaluate_command_tabs_with_index(node).get("tab", {})


## 检查单个 tab 的条件是否满足
func _check_tab_condition(tab: Dictionary) -> bool:
	var condition_commands: Array = tab.get("condition_commands", [])

	# 空条件列表 = 无条件 = 始终满足
	if condition_commands.is_empty():
		# 向后兼容：检查旧格式
		var condition_type: int = tab.get("condition_type", 0)
		if condition_type == 0:
			return true
		if condition_type == 1:
			var var_name: String = tab.get("condition_var", "")
			var op: String = tab.get("condition_op", ">=")
			var expected = tab.get("condition_value", 0)
			if var_name.is_empty():
				return true
			var actual = _variable_manager.get_value(var_name)
			if actual == null:
				return false
			return _compare_values(actual, op, expected)
		return false

	return _evaluate_condition_commands(condition_commands)


## 统一条件命令列表评估（tab 条件和 IF 命令共用）
## 从上到下执行条件命令，全部通过 = true，任何一个中断 = false
func _evaluate_condition_commands(commands: Array) -> bool:
	for cmd in commands:
		if cmd == null:
			continue

		var cmd_type: String = ""
		var params: Dictionary = {}

		# 支持 AVGCommand 资源和纯 Dictionary 两种格式
		if cmd is Resource and "command_type" in cmd:
			cmd_type = cmd.command_type
			params = cmd.params if cmd.params != null else {}
		elif cmd is Dictionary:
			cmd_type = cmd.get("command_type", "")
			params = cmd.get("params", {})
		else:
			continue

		match cmd_type:
			"CHECK_VAR":
				if not _eval_check_var(params):
					return false
			"CHECK_HOVER":
				var nid: String = params.get("node_id", "")
				if not nid.is_empty() and not is_node_hovered(nid):
					return false
				elif nid.is_empty():
					return false  # 在 tab 条件中没有 owner_node 上下文
			"CHECK_CLICK":
				var nid2: String = params.get("node_id", "")
				if not nid2.is_empty() and not is_node_pressed(nid2):
					return false
				elif nid2.is_empty():
					return false
			"IF":
				if not _eval_condition_if(params):
					return false
			_:
				push_warning("AVGSceneRunner: Unknown condition command '%s'" % cmd_type)
				return false

	# 抵达终点 = 条件满足
	return true


## 评估 CHECK_VAR 条件命令
func _eval_check_var(params: Dictionary) -> bool:
	# 优先使用 variable_id，向后兼容 variable_name
	var var_id: String = params.get("variable_id", "")
	var var_name: String = params.get("variable_name", "")
	var op: String = params.get("operator", ">=")

	# 获取左值 — scope 由 ID 前缀自动决定 (var_NNN=global, lvar_NNN=local)
	var actual: Variant = null
	if not var_id.is_empty():
		actual = _variable_manager.get_value_by_id(var_id)
	elif not var_name.is_empty():
		actual = _variable_manager.get_value(var_name)
	else:
		return true

	if actual == null:
		return false

	# 获取右值（比较对象）
	var value_source: String = params.get("value_source", "constant")
	var expected: Variant = _resolve_check_value(params, value_source)
	return _compare_values(actual, op, expected)


## 解析 CHECK_VAR 的比较值
func _resolve_check_value(params: Dictionary, source: String) -> Variant:
	match source:
		"variable":
			var src_id: String = params.get("source_variable_id", "")
			var src_key: String = params.get("source_variable_key", params.get("source_variable_name", ""))
			if _variable_manager != null:
				if not src_id.is_empty():
					return _variable_manager.get_value_by_id(src_id)
				if not src_key.is_empty():
					return _variable_manager.get_value(src_key)
			return 0
		"game_data":
			var key: String = params.get("game_data_key", "")
			return _resolve_game_data(key)
		_:  # "constant"
			return _parse_condition_value(params.get("value", "0"))


## 获取游戏数据值
func _resolve_game_data(key: String) -> Variant:
	match key:
		"play_time":
			return int(Time.get_ticks_msec() / 1000.0)
		"click_count":
			if _command_context != null and "click_count" in _command_context:
				return _command_context.click_count
			return 0
		"scene_count":
			if game_data != null and "scenes" in game_data:
				return game_data.scenes.size()
			return 0
		"current_scene_index":
			if game_data != null and current_scene != null and "scenes" in game_data:
				for i in range(game_data.scenes.size()):
					if game_data.scenes[i] == current_scene:
						return i
			return 0
		_:
			return 0


## 评估条件中的 IF 命令（嵌套条件分支）
func _eval_condition_if(params: Dictionary) -> bool:
	var condition_commands: Array = params.get("condition_commands", [])

	# 向后兼容：旧格式 condition 字符串
	if condition_commands.is_empty():
		var condition_str: String = params.get("condition", "")
		if not condition_str.is_empty():
			return _evaluate_legacy_condition(condition_str)
		return true

	var condition_met: bool = _evaluate_condition_commands(condition_commands)

	if condition_met:
		# if 分支的条件命令也必须全部通过
		var if_commands: Array = params.get("if_condition_commands", [])
		if if_commands.is_empty():
			return true
		return _evaluate_condition_commands(if_commands)
	else:
		# else 分支
		var has_else: bool = params.get("has_else", false)
		if has_else:
			var else_commands: Array = params.get("else_condition_commands", [])
			if else_commands.is_empty():
				return true
			return _evaluate_condition_commands(else_commands)
		return false


## 解析条件值字符串为对应类型
func _parse_condition_value(value) -> Variant:
	return AVGVariableClass.normalize_script_literal(value)


## 比较两个值
func _compare_values(actual: Variant, op: String, expected: Variant) -> bool:
	var lhs_value: Variant = AVGVariableClass.normalize_runtime_value(actual)
	var rhs_value: Variant = AVGVariableClass.normalize_runtime_value(expected)
	var lhs_numeric: bool = lhs_value is int
	var rhs_numeric: bool = rhs_value is int
	var same_string_type: bool = lhs_value is String and rhs_value is String
	if same_string_type:
		match op:
			"==":
				return lhs_value == rhs_value
			"!=":
				return lhs_value != rhs_value
			">":
				return str(lhs_value) > str(rhs_value)
			">=":
				return str(lhs_value) >= str(rhs_value)
			"<":
				return str(lhs_value) < str(rhs_value)
			"<=":
				return str(lhs_value) <= str(rhs_value)
			_:
				return false

	if lhs_numeric and rhs_numeric:
		return _compare_numeric_values(int(lhs_value), op, int(rhs_value))

	push_warning("AVGSceneRunner: mixed CHECK_VAR comparison %s %s %s; string values will be coerced as empty=0 / non-empty=1" % [_type_label(lhs_value), op, _type_label(rhs_value)])
	var lhs_mixed: int = AVGVariableClass.coerce_mixed_comparison_number(lhs_value)
	var rhs_mixed: int = AVGVariableClass.coerce_mixed_comparison_number(rhs_value)
	return _compare_numeric_values(lhs_mixed, op, rhs_mixed)


func _compare_numeric_values(lhs_num: int, op: String, rhs_num: int) -> bool:
	match op:
		"==":
			return lhs_num == rhs_num
		"!=":
			return lhs_num != rhs_num
		">":
			return lhs_num > rhs_num
		">=":
			return lhs_num >= rhs_num
		"<":
			return lhs_num < rhs_num
		"<=":
			return lhs_num <= rhs_num
		_:
			return false


func _type_label(value: Variant) -> String:
	if value is int:
		return "int"
	if value is String:
		return "String"
	if value is bool:
		return "bool"
	if value == null:
		return "null"
	return type_string(typeof(value))


## 构建标签索引
func _build_label_index() -> void:
	_label_index.clear()
	for i in range(_main_queue.size()):
		var cmd = _main_queue[i]
		if cmd == null:
			continue
		if cmd.command_type == "LABEL":
			var label_name: String = cmd.params.get("name", "") if cmd.params else ""
			if not label_name.is_empty():
				if _label_index.has(label_name):
					push_warning("AVGSceneRunner: Duplicate label '%s'" % label_name)
				_label_index[label_name] = i


## 设置场景初始状态（从 Root 节点读取背景和 BGM）
func _setup_scene_initial_state() -> void:
	if current_scene == null:
		return
	for node in current_scene.nodes:
		if node is AVGRootNode:
			if node.background != null and background_display != null:
				background_display.texture = node.background
			if node.bgm != null and audio_manager != null:
				var bgm_path: String = node.bgm.resource_path
				if not bgm_path.is_empty():
					audio_manager.play_bgm(bgm_path, 1.0, 1.0)
			break

	# 渲染节点树
	_render_node_tree()


# =============================================================================
# Node Rendering — 将 AVG 节点树渲染为 Godot Control
# =============================================================================

## 清除所有已渲染的节点
func _clear_rendered_nodes() -> void:
	_rendered_nodes.clear()
	if _nodes_layer:
		for child in _nodes_layer.get_children():
			child.queue_free()


## 渲染整个节点树
func _render_node_tree() -> void:
	_clear_rendered_nodes()
	if current_scene == null or _nodes_layer == null:
		return
	for node in current_scene.nodes:
		if node != null:
			_render_node_recursive(node, _nodes_layer)


## 递归渲染节点及其子节点
func _render_node_recursive(avg_node: Resource, parent_control: Control) -> void:
	if avg_node == null:
		return

	# Root 节点不需要额外渲染（背景和 BGM 已在 _setup_scene_initial_state 处理）
	# 但仍需渲染其子节点
	if avg_node is AVGRootNode:
		for child in avg_node.children:
			_render_node_recursive(child, parent_control)
		return

	# SharedNodeRef — 用 ref 自身的位置/尺寸作为容器，渲染解析后的节点树
	if avg_node is AVGSharedNodeRef:
		var resolved: Resource = avg_node.get_resolved_node(game_data)
		if resolved != null:
			# 创建一个容器 Control，使用 ref 的位置/尺寸
			var ref_container := Control.new()
			ref_container.name = avg_node.node_name
			var ref_pixel_pos: Vector2 = avg_node.calc_pixel_position(_project_resolution)
			var ref_pixel_size: Vector2 = avg_node.calc_pixel_size(_project_resolution)
			ref_container.position = ref_pixel_pos
			ref_container.size = ref_pixel_size
			ref_container.visible = avg_node.visible
			ref_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
			parent_control.add_child(ref_container)
			# 在容器内渲染解析后的节点（resolved 的位置是相对于容器的）
			_render_node_recursive(resolved, ref_container)
		else:
			push_warning("AVGSceneRunner: Could not resolve SharedNodeRef '%s'" % avg_node.node_name)
		return

	# AVGCanvasLayerNode — 创建 CanvasLayer，子节点不受 Camera2D 影响
	if avg_node is AVGCanvasLayerNodeClass:
		var canvas_layer := CanvasLayer.new()
		canvas_layer.name = avg_node.node_name
		canvas_layer.layer = avg_node.layer
		# CanvasLayer 需要加到场景根节点（不能加到 Control 下）
		add_child(canvas_layer)
		# 在 CanvasLayer 内创建容器 Control 做适配缩放
		var layer_container := Control.new()
		layer_container.name = "LayerContainer"
		layer_container.size = _project_resolution
		layer_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# 应用 viewport 适配缩放
		var vp = get_viewport()
		if vp != null:
			var vp_size: Vector2 = Vector2(vp.size) if vp is SubViewport else get_viewport_rect().size
			if vp_size.x > 0 and vp_size.y > 0:
				layer_container.scale = vp_size / _project_resolution
		canvas_layer.add_child(layer_container)
		# 注册到 _rendered_nodes（用于后续操作）
		var layer_node_id: String = avg_node.node_id if "node_id" in avg_node else ""
		if not layer_node_id.is_empty():
			_rendered_nodes[layer_node_id] = layer_container
		# 递归渲染子节点到 layer_container
		for child in avg_node.children:
			_render_node_recursive(child, layer_container)
		return

	# 创建对应的 Godot Control
	var control: Control = _create_control_for_node(avg_node)
	if control == null:
		return

	# 使用归一化坐标计算像素位置/尺寸，再应用缩放
	var pixel_pos: Vector2 = avg_node.calc_pixel_position(_project_resolution)
	var pixel_size: Vector2 = avg_node.calc_pixel_size(_project_resolution)

	control.position = pixel_pos
	control.size = pixel_size
	control.visible = avg_node.visible
	control.name = avg_node.node_name

	parent_control.add_child(control)

	var node_id: String = avg_node.node_id if "node_id" in avg_node else ""
	if not node_id.is_empty():
		_rendered_nodes[node_id] = control
		# 为所有有 node_id 的节点连接悬停/点击信号（并行模式 CHECK_HOVER/CHECK_CLICK 需要）
		_connect_hover_click_signals(node_id, control)

	# 递归渲染子节点（相对于父节点定位）
	for child in avg_node.children:
		_render_node_recursive(child, control)


## 根据 AVG 节点类型创建对应的 Godot Control
func _create_control_for_node(avg_node: Resource) -> Control:
	if avg_node is AVGCharacterNode:
		# 角色节点只需要一个空容器，精灵由 CharacterDisplay 管理
		var container := Control.new()
		container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return container
	else:
		return _create_unified_control(avg_node)


## 统一渲染：style_box → texture → text，有 click 模式 command_tab 则连接点击
func _create_unified_control(avg_node: Resource) -> Control:
	var container := Control.new()
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if "clip_contents" in avg_node and avg_node.clip_contents:
		container.clip_contents = true

	# 1. style_box 背景
	if "style_box" in avg_node and avg_node.style_box != null and avg_node.style_box.has_method("to_stylebox"):
		var panel := Panel.new()
		panel.set_anchors_preset(Control.PRESET_FULL_RECT)
		panel.add_theme_stylebox_override("panel", avg_node.style_box.to_stylebox())
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		container.add_child(panel)

	# 2. texture 图片
	if "texture" in avg_node and avg_node.texture != null:
		var tex_rect := TextureRect.new()
		tex_rect.texture = avg_node.texture
		tex_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		if "modulate" in avg_node:
			tex_rect.modulate = avg_node.modulate
		tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		container.add_child(tex_rect)

	# 3. text 文本
	if "text" in avg_node and not avg_node.text.is_empty():
		var label := Label.new()
		label.text = avg_node.text
		label.set_anchors_preset(Control.PRESET_FULL_RECT)
		if "font_size" in avg_node and avg_node.font_size > 0:
			label.add_theme_font_size_override("font_size", avg_node.font_size)
		if "font_color" in avg_node:
			label.add_theme_color_override("font_color", avg_node.font_color)
		if "h_alignment" in avg_node:
			label.horizontal_alignment = avg_node.h_alignment as HorizontalAlignment
		if "v_alignment" in avg_node:
			label.vertical_alignment = avg_node.v_alignment as VerticalAlignment
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.clip_text = true
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		container.add_child(label)

	# 4. 检查是否有 click 模式的 command_tab → 连接点击事件
	var node_id: String = avg_node.node_id if "node_id" in avg_node else ""
	if not node_id.is_empty() and _click_handlers.has(node_id):
		container.mouse_filter = Control.MOUSE_FILTER_STOP
		container.gui_input.connect(_on_clickable_node_input.bind(node_id))

	return container


## 处理可点击节点的输入
func _on_clickable_node_input(event: InputEvent, node_id: String) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		handle_node_click(node_id)


## 从游戏数据加载角色。
## 保留原始 sprite 引用（alias / 路径 / Texture2D），由 CharacterDisplay 按需解析并缓存，
## 避免载入游戏数据时同步预载整套角色贴图。
func _setup_character_data() -> void:
	if game_data == null or character_display == null:
		return
	var char_data: Dictionary = {}
	for character in game_data.characters:
		if character == null:
			continue
		var char_id: String = character.character_id if "character_id" in character else ""
		if char_id.is_empty():
			continue
		char_data[char_id] = {
			"character_key": character.character_key if "character_key" in character else "",
			"character_name": character.character_name if "character_name" in character else "",
			"display_name": character.display_name if "display_name" in character else "",
			"sprites": character.sprites if "sprites" in character else {},
			"default_outfit": character.default_outfit if "default_outfit" in character else "",
			"available_outfits": character.available_outfits if "available_outfits" in character else [],
			"emotion_slots": character.emotion_slots if "emotion_slots" in character else {},
			"sprite_prefix": character.sprite_prefix if "sprite_prefix" in character else "",
			"sprite_base_dir": character.sprite_base_dir if "sprite_base_dir" in character else "",
			"sprite_extension": character.sprite_extension if "sprite_extension" in character else "png",
			"sprite_path_pattern": character.sprite_path_pattern if "sprite_path_pattern" in character else "",
			"display_offset": character.display_offset if "display_offset" in character else Vector2.ZERO,
			"display_scale": character.display_scale if "display_scale" in character else 1.0,
		}
	if character_display.has_method("set_character_data"):
		character_display.set_character_data(char_data)
	if character_display.has_method("set_texture_loader"):
		character_display.set_texture_loader(Callable(self, "load_game_texture"))
	if dialog_box != null and dialog_box.has_method("set_character_data"):
		dialog_box.set_character_data(char_data)


# =============================================================================
# Execution Control
# =============================================================================

## 开始执行
func start() -> void:
	if current_scene == null:
		push_error("AVGSceneRunner: Cannot start without a loaded scene")
		return
	if is_running:
		push_warning("AVGSceneRunner: Already running")
		return

	is_running = true
	_should_continue = true
	_execution_generation += 1
	var my_generation: int = _execution_generation
	_scene_start_time = Time.get_ticks_msec() / 1000.0

	# 首次运行时创建游戏内 UI 按钮（跨场景保持）
	if _game_ui_container == null or not is_instance_valid(_game_ui_container):
		_setup_game_ui_buttons()

	var scene_id: String = current_scene.scene_id if "scene_id" in current_scene else ""
	scene_started.emit(scene_id)

	# 创建并行执行器
	_setup_parallel_executors()

	# 如果有待播放的转场入场效果，先播放
	if not _pending_transition.is_empty():
		var t_type: int = _pending_transition.get("type", 0)
		var t_duration: float = _pending_transition.get("duration", 1.0)
		var t_color: Color = _pending_transition.get("color", Color.BLACK)
		_pending_transition = {}
		await play_transition_in(t_type, t_duration, t_color)

	# 启动主线执行循环
	await _main_execution_loop(my_generation)


## 停止执行
func stop() -> void:
	# 只有在运行时才发射 scene_ended 信号
	var was_running: bool = is_running
	_should_continue = false
	is_running = false
	_is_blocked = false
	_auto_mode = false
	_skip_mode = false
	_auto_timer = 0.0
	_restore_waiting_click = false
	_ui_hidden = false
	_call_stack.clear()
	_stop_parallel_executors()
	_hovered_nodes.clear()
	_pressed_nodes.clear()
	if dialog_box != null and dialog_box.has_method("hide_box"):
		dialog_box.hide_box()
	_stop_runtime_audio()
	# 关闭子界面
	if _screen_manager != null and _screen_manager.is_showing():
		_screen_manager.close_screen()
	if was_running:
		var scene_id: String = current_scene.scene_id if current_scene != null and "scene_id" in current_scene else ""
		scene_ended.emit(scene_id)


func is_playback_complete() -> bool:
	if not is_running or current_scene == null:
		return false
	if _is_blocked:
		return false
	if _main_index < _main_queue.size():
		return false
	if not _call_stack.is_empty():
		return false
	if choice_display != null and choice_display.is_waiting_for_selection():
		return false
	if dialog_box != null and dialog_box.visible:
		return false
	return true


## 重置
func reset() -> void:
	stop()
	_main_queue.clear()
	_main_index = 0
	_label_index.clear()
	_click_handlers.clear()
	_parallel_commands.clear()
	_stop_parallel_executors()
	_hovered_nodes.clear()
	_pressed_nodes.clear()
	_call_stack.clear()
	_all_event_nodes.clear()
	_node_active_tab.clear()
	_needs_reevaluation = false
	current_scene = null
	if _variable_manager != null:
		_variable_manager.clear_local()
		_variable_manager.reset_to_defaults()
	_clear_scene_presentation_state()


func _clear_scene_presentation_state() -> void:
	_clear_rendered_nodes()
	_stop_runtime_audio()
	if dialog_box != null and dialog_box.has_method("clear"):
		dialog_box.clear()
	if character_display != null and character_display.has_method("hide_all"):
		character_display.hide_all(0.0)
	if choice_display != null:
		choice_display.visible = false
	if background_display != null:
		background_display.texture = null
	_clear_image_layer()
	_reset_screen_effects()


## 从暂存的并行命令创建执行器（替代旧的 fire-and-forget）
func _stop_runtime_audio() -> void:
	if audio_manager == null:
		return
	if audio_manager.has_method("stop_all_audio"):
		audio_manager.stop_all_audio()
	elif audio_manager.has_method("stop_bgm"):
		audio_manager.stop_bgm(0.0)


func _setup_parallel_executors() -> void:
	for node in _parallel_commands:
		var commands: Array = _parallel_commands[node]
		if commands.is_empty():
			continue
		var executor: RefCounted = ParallelExecutorClass.new()
		executor.setup(commands.duplicate(), node)
		_parallel_executors.append(executor)
	_parallel_commands.clear()


## 停止并清除所有并行执行器
func _stop_parallel_executors() -> void:
	for executor in _parallel_executors:
		if executor != null:
			executor.stop()
	_parallel_executors.clear()


## _process — 每帧 tick 所有并行执行器 + 自动/快进模式
func _process(delta: float) -> void:
	if not is_running:
		return
	for executor in _parallel_executors:
		if executor != null:
			executor.tick(delta, self)

	# 自动模式：对话显示完毕后自动推进
	if _auto_mode and _is_blocked and _command_context != null:
		if dialog_box != null and not dialog_box._is_typing:
			_auto_timer += delta
			if _auto_timer >= AUTO_WAIT_TIME:
				_auto_timer = 0.0
				_command_context.notify_click()
		else:
			_auto_timer = 0.0

	# 快进模式：立即推进
	if _skip_mode and _is_blocked and _command_context != null:
		if dialog_box != null and dialog_box._is_typing:
			# 跳过打字动画
			if dialog_box.has_method("_skip_typewriter"):
				dialog_box._skip_typewriter()
		else:
			_command_context.notify_click()


# =============================================================================
# Main Thread Execution Loop
# =============================================================================

## 主线执行循环（事件循环模式）
## 执行完当前主线后不停止，等一帧后重新评估所有节点的 tab 条件。
## 如果有 tab 切换，收集新命令继续执行。无新命令则继续等待。
func _main_execution_loop(generation: int) -> void:
	while _should_continue and is_running and generation == _execution_generation:
		# 执行当前主线队列
		while _should_continue and is_running and generation == _execution_generation and _main_index < _main_queue.size():
			var cmd = _main_queue[_main_index]
			if cmd == null:
				_main_index += 1
				continue

			var cmd_type: String = cmd.command_type if "command_type" in cmd else ""
			var index_before: int = _main_index

			# IF 命令由运行时直接处理
			if cmd_type == "IF":
				_handle_if_command(cmd)
				if _main_index == index_before:
					_main_index += 1
				continue

			# CALL_EVENT 由运行时直接处理
			if cmd_type == "CALL_EVENT":
				var event_id: String = cmd.params.get("event_id", "") if cmd.params else ""
				if not event_id.is_empty():
					_push_event_call(event_id)
					continue
				else:
					_main_index += 1
					continue

			# 执行命令
			_execute_single_command(cmd)
			command_executed.emit(cmd_type, _main_index)

			# 如果是阻塞命令，等待
			if cmd_type in BLOCKING_COMMANDS:
				await _handle_blocking_command(cmd)
				if generation != _execution_generation:
					return

			# 如果没有发生跳转，推进到下一条
			if _main_index == index_before:
				_main_index += 1

			# 检查当前队列是否执行完毕，如果有调用栈则弹出
			while _main_index >= _main_queue.size() and not _call_stack.is_empty():
				_pop_event_call()

		# 主线队列执行完毕 — 进入事件循环等待阶段
		# 隐藏对话框
		if dialog_box != null and dialog_box.has_method("hide_box"):
			dialog_box.hide_box()

		# 等一帧，然后重新评估
		if not _should_continue or not is_running:
			break
		await get_tree().process_frame
		if not _should_continue or not is_running or generation != _execution_generation:
			break

		# 重新评估所有节点的 tab 条件
		var has_new_commands: bool = _reevaluate_all_nodes()

		if has_new_commands:
			# 有新命令，创建并行执行器，主线继续循环
			_setup_parallel_executors()
			_build_label_index()
			# 继续外层 while 循环执行新的主线队列
		else:
			# 没有新命令，继续等待（下一帧再检查）
			continue

	# 循环结束（stop() 被调用或 _should_continue = false）


## 变量变化回调 — 标记需要重新评估
func _on_variable_changed(_var_name: String, _old_value: Variant, _new_value: Variant) -> void:
	_needs_reevaluation = true


## 重新评估所有事件节点的 tab 条件
## 如果某节点的激活 tab 发生变化，收集新 tab 的命令
## 返回 true 如果有新命令产生
func _reevaluate_all_nodes() -> bool:
	var has_new_auto: bool = false
	var has_new_parallel: bool = false
	_needs_reevaluation = false

	for node in _all_event_nodes:
		var node_id: String = node.node_id if "node_id" in node else ""
		if node_id.is_empty():
			continue

		var old_tab_index: int = _node_active_tab.get(node_id, -1)
		var tab_result: Dictionary = _evaluate_command_tabs_with_index(node)
		var new_tab_index: int = tab_result.get("index", -1)
		var new_tab: Dictionary = tab_result.get("tab", {})

		# Tab 没变，跳过
		if new_tab_index == old_tab_index:
			continue

		# Tab 切换了！更新记录
		_node_active_tab[node_id] = new_tab_index

		if new_tab.is_empty():
			# 新状态无匹配 tab — 清除该节点的点击处理器和并行执行器
			_click_handlers.erase(node_id)
			_remove_parallel_executor_for_node(node)
			continue

		var mode: int = new_tab.get("mode", 0)
		var commands: Array = new_tab.get("commands", [])

		# Tab 切换时，先移除该节点的旧并行执行器
		_remove_parallel_executor_for_node(node)

		match mode:
			0:  # 自动 → 追加到主线队列尾部
				_main_queue.append_array(commands)
				# 重置 index 到新命令的起始位置（如果主线已经执行完了）
				if _main_index >= _main_queue.size() - commands.size():
					_main_index = _main_queue.size() - commands.size()
				has_new_auto = true
			1:  # 并行 → 暂存，稍后立即触发
				_parallel_commands[node] = commands
				has_new_parallel = true
			2:  # 点击 → 更新处理器
				_click_handlers[node_id] = commands

	return has_new_auto or has_new_parallel


## 执行单条命令（同步，不等待）
func _execute_single_command(cmd: Resource) -> void:
	if cmd == null or _command_registry == null:
		return
	var cmd_type: String = cmd.command_type if "command_type" in cmd else ""
	var handler = _command_registry.get_handler(cmd_type)
	if handler == null:
		push_warning("AVGSceneRunner: No handler for '%s'" % cmd_type)
		return
	handler.execute(cmd, _command_context)

	# 记录对话到历史
	if cmd_type == "DIALOGUE" and _history_manager != null and cmd.params != null:
		var speaker: String = cmd.params.get("speaker", "")
		var text: String = cmd.params.get("text", "")
		var scene_id: String = current_scene.scene_id if current_scene != null and "scene_id" in current_scene else ""
		# 解析 character_id / character_name 为显示名
		if not speaker.is_empty() and dialog_box != null and dialog_box.has_method("_find_character_data"):
			var cd: Dictionary = dialog_box._find_character_data(speaker)
			if not cd.is_empty():
				if cd.has("display_name") and not cd["display_name"].is_empty():
					speaker = cd["display_name"]
				elif cd.has("character_name") and not cd["character_name"].is_empty():
					speaker = cd["character_name"]
		_history_manager.add_entry(speaker, text, scene_id)


## 移除指定节点的并行执行器
func _remove_parallel_executor_for_node(node: Resource) -> void:
	for i in range(_parallel_executors.size() - 1, -1, -1):
		var executor: RefCounted = _parallel_executors[i]
		if executor != null and executor.owner_node == node:
			executor.stop()
			_parallel_executors.remove_at(i)


# =============================================================================
# Hover / Click Tracking — 鼠标悬停和按下状态追踪
# =============================================================================

## 查询节点是否被鼠标悬停（供 ParallelExecutor 调用）
func is_node_hovered(node_id: String) -> bool:
	return _hovered_nodes.get(node_id, false)


## 查询节点是否被鼠标按下（供 ParallelExecutor 调用）
func is_node_pressed(node_id: String) -> bool:
	return _pressed_nodes.get(node_id, false)


## 为已渲染的节点连接鼠标悬停和按下信号
func _connect_hover_click_signals(node_id: String, control: Control) -> void:
	if node_id.is_empty() or control == null:
		return
	# 确保 control 能接收鼠标事件
	if control.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		control.mouse_filter = Control.MOUSE_FILTER_PASS
	control.mouse_entered.connect(_on_node_mouse_entered.bind(node_id))
	control.mouse_exited.connect(_on_node_mouse_exited.bind(node_id))
	control.gui_input.connect(_on_node_gui_input_hover.bind(node_id))


func _on_node_mouse_entered(node_id: String) -> void:
	_hovered_nodes[node_id] = true


func _on_node_mouse_exited(node_id: String) -> void:
	_hovered_nodes[node_id] = false
	_pressed_nodes[node_id] = false


func _on_node_gui_input_hover(event: InputEvent, node_id: String) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_pressed_nodes[node_id] = event.pressed


# =============================================================================
# Node Operations — 运行时节点操作方法（由各 handler 调用）
# =============================================================================

## 获取已渲染的节点 Control（公共方法，供 handler 使用）
func get_rendered_control(node_id: String) -> Control:
	if not _rendered_nodes.has(node_id):
		return null
	var control: Control = _rendered_nodes[node_id]
	if not is_instance_valid(control):
		_rendered_nodes.erase(node_id)
		return null
	return control


## 变量插值 — 将 {{var_001}} / {{local:var_L01}} / {{global:var_001}} 替换为变量值
func interpolate_variables(text: String) -> String:
	if _variable_manager == null:
		return text
	var result: String = text
	# 匹配 {{id}} — scope 由 ID 前缀自动决定 (var_NNN / lvar_NNN)
	var regex := RegEx.new()
	regex.compile("\\{\\{([^}]+)\\}\\}")
	var matches: Array = regex.search_all(result)
	# 从后往前替换，避免偏移问题
	for i in range(matches.size() - 1, -1, -1):
		var m: RegExMatch = matches[i]
		var var_id: String = m.get_string(1)
		var val: Variant = _variable_manager.get_value_by_id(var_id)
		if val == null:
			val = "?"
		result = result.substr(0, m.get_start()) + str(val) + result.substr(m.get_end())
	return result


## SET_TEXT — 设置节点文本（支持变量插值）
func node_set_text(node_id: String, text: String) -> void:
	var control: Control = get_rendered_control(node_id)
	if control == null:
		push_warning("AVGSceneRunner: node_set_text — node '%s' not found" % node_id)
		return
	var resolved: String = interpolate_variables(text)
	for child in control.get_children():
		if child is Label:
			child.text = resolved
			return
	# 没有 Label，创建一个
	var label := Label.new()
	label.text = resolved
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	control.add_child(label)


## SET_STYLE — 设置节点样式（内联 flat 属性）
func node_set_style(node_id: String, bg_color: Color, corner_radius: int, border_width: int, border_color: Color) -> void:
	var control: Control = get_rendered_control(node_id)
	if control == null:
		push_warning("AVGSceneRunner: node_set_style — node '%s' not found" % node_id)
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg_color
	sb.set_corner_radius_all(corner_radius)
	sb.border_width_left = border_width
	sb.border_width_top = border_width
	sb.border_width_right = border_width
	sb.border_width_bottom = border_width
	sb.border_color = border_color
	for child in control.get_children():
		if child is Panel:
			child.add_theme_stylebox_override("panel", sb)
			return
	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	control.add_child(panel)
	control.move_child(panel, 0)


## MOVE_NODE — 移动节点（归一化坐标，带动画）
func node_move(node_id: String, norm_x: float, norm_y: float, duration: float) -> void:
	var control: Control = get_rendered_control(node_id)
	if control == null:
		push_warning("AVGSceneRunner: node_move — node '%s' not found" % node_id)
		return
	var target_pos: Vector2 = Vector2(norm_x, norm_y) * _project_resolution
	if duration <= 0:
		control.position = target_pos
		return
	var tween: Tween = create_tween()
	tween.tween_property(control, "position", target_pos, duration)


## RESIZE_NODE — 调整节点大小（归一化尺寸，带动画）
func node_resize(node_id: String, norm_w: float, norm_h: float, duration: float) -> void:
	var control: Control = get_rendered_control(node_id)
	if control == null:
		push_warning("AVGSceneRunner: node_resize — node '%s' not found" % node_id)
		return
	var target_size: Vector2 = Vector2(norm_w, norm_h) * _project_resolution
	if duration <= 0:
		control.size = target_size
		return
	var tween: Tween = create_tween()
	tween.tween_property(control, "size", target_size, duration)


## SHOW_NODE — 显示节点（淡入）
func node_show(node_id: String, fade_duration: float) -> void:
	var control: Control = get_rendered_control(node_id)
	if control == null:
		push_warning("AVGSceneRunner: node_show — node '%s' not found" % node_id)
		return
	control.visible = true
	if fade_duration <= 0:
		control.modulate.a = 1.0
		return
	control.modulate.a = 0.0
	var tween: Tween = create_tween()
	tween.tween_property(control, "modulate:a", 1.0, fade_duration)


## HIDE_NODE — 隐藏节点（淡出）
func node_hide(node_id: String, fade_duration: float) -> void:
	var control: Control = get_rendered_control(node_id)
	if control == null:
		push_warning("AVGSceneRunner: node_hide — node '%s' not found" % node_id)
		return
	if fade_duration <= 0:
		control.visible = false
		return
	var tween: Tween = create_tween()
	tween.tween_property(control, "modulate:a", 0.0, fade_duration)
	var captured_control: Control = control
	tween.finished.connect(func():
		if is_instance_valid(captured_control):
			captured_control.visible = false
	)


## REMOVE_NODE — 移除节点（淡出后删除）
func node_remove(node_id: String, fade_duration: float) -> void:
	var control: Control = get_rendered_control(node_id)
	if control == null:
		push_warning("AVGSceneRunner: node_remove — node '%s' not found" % node_id)
		return
	_rendered_nodes.erase(node_id)
	if fade_duration <= 0:
		control.queue_free()
		return
	var tween: Tween = create_tween()
	tween.tween_property(control, "modulate:a", 0.0, fade_duration)
	var captured_control: Control = control
	tween.finished.connect(func():
		if is_instance_valid(captured_control):
			captured_control.queue_free()
	)


## SPAWN_NODE — 生成公共节点实例
func node_spawn(shared_node_id: String, instance_id: String, norm_x: float, norm_y: float, parent_node_id: String) -> void:
	if game_data == null:
		push_warning("AVGSceneRunner: node_spawn — no game data loaded")
		return
	# 查找公共节点模板
	var template: Resource = null
	if "shared_nodes" in game_data:
		for sn in game_data.shared_nodes:
			if sn != null and "node_id" in sn and sn.node_id == shared_node_id:
				template = sn
				break
	if template == null:
		push_warning("AVGSceneRunner: node_spawn — shared node '%s' not found" % shared_node_id)
		return
	# 确定实例 ID
	var final_id: String = instance_id
	if final_id.is_empty():
		final_id = "spawn_%s_%d" % [shared_node_id, Time.get_ticks_msec()]
	# 确定父节点
	var parent_control: Control = _nodes_layer
	if not parent_node_id.is_empty():
		var pc: Control = get_rendered_control(parent_node_id)
		if pc != null:
			parent_control = pc
	# 创建 Control
	var control: Control = _create_unified_control(template)
	if control == null:
		return
	control.position = Vector2(norm_x, norm_y) * _project_resolution
	var pixel_size: Vector2 = template.calc_pixel_size(_project_resolution) if template.has_method("calc_pixel_size") else Vector2(200, 60)
	control.size = pixel_size
	control.name = final_id
	parent_control.add_child(control)
	_rendered_nodes[final_id] = control
	# 连接悬停/点击信号
	_connect_hover_click_signals(final_id, control)


## 处理阻塞命令 — 根据类型等待不同条件
func _handle_blocking_command(cmd: Resource) -> void:
	var cmd_type: String = cmd.command_type if "command_type" in cmd else ""
	_is_blocked = true

	# 非 DIALOGUE/CHOICE 阻塞命令执行前隐藏对话框
	if cmd_type != "DIALOGUE" and cmd_type != "CHOICE" and dialog_box != null:
		if dialog_box.has_method("hide_box"):
			dialog_box.hide_box()

	match cmd_type:
		"DIALOGUE", "WAIT_CLICK":
			await _command_context.wait_for_click()
		"WAIT_TIME":
			var duration: float = cmd.params.get("duration", 1.0) if cmd.params else 1.0
			await _command_context.wait_for_time(duration)
		"CHOICE":
			await _handle_choice_command(cmd)
		"SCREEN_FADE":
			var direction: String = cmd.params.get("direction", "out") if cmd.params else "out"
			var color: Color = cmd.params.get("color", Color.BLACK) if cmd.params else Color.BLACK
			var duration: float = cmd.params.get("duration", 1.0) if cmd.params else 1.0
			var transition: String = cmd.params.get("transition", "fade") if cmd.params else "fade"
			await screen_fade(direction, color, duration, transition)
		"CHANGE_BACKGROUND":
			var duration: float = cmd.params.get("fade_duration", 0.5) if cmd.params else 0.5
			if duration > 0:
				await _command_context.wait_for_time(duration)
		"SET_TIME_OF_DAY":
			var duration: float = cmd.params.get("duration", 0.6) if cmd.params else 0.6
			if duration > 0:
				await _command_context.wait_for_time(duration)

	_is_blocked = false


## 处理选项命令 — 等待玩家选择，然后执行选项的子命令
func _handle_choice_command(cmd: Resource) -> void:
	if choice_display == null:
		return

	# 等待玩家选择
	if choice_display.is_waiting_for_selection():
		var selected_idx: int = await choice_display.choice_selected

		var choices: Array = cmd.params.get("choices", []) if cmd.params else []
		if selected_idx >= 0 and selected_idx < choices.size():
			var selected: Dictionary = choices[selected_idx]

			# New format: execute commands array (insert into main queue like IF does)
			var branch_commands: Array = selected.get("commands", [])
			if not branch_commands.is_empty():
				var insert_pos: int = _main_index + 1
				for i in range(branch_commands.size()):
					_main_queue.insert(insert_pos + i, branch_commands[i])
				_build_label_index()

			# Backward compatibility: jump_to still works if present and no commands
			elif selected.has("jump_to"):
				var target: String = selected["jump_to"]
				if not target.is_empty():
					jump_to_label(target)


# =============================================================================
# IF/ELSE Command Handling
# =============================================================================

## 处理 IF 命令 — 评估条件，将匹配分支的命令插入主队列
func _handle_if_command(cmd: Resource) -> void:
	if cmd == null or cmd.params == null:
		return

	var condition_commands: Array = cmd.params.get("condition_commands", [])
	var condition_met: bool = false

	if not condition_commands.is_empty():
		condition_met = _evaluate_condition_commands(condition_commands)
	else:
		# 向后兼容：旧格式 condition 字符串
		var condition: String = cmd.params.get("condition", "")
		condition_met = _evaluate_legacy_condition(condition)

	var branch_commands: Array = []
	if condition_met:
		branch_commands = cmd.params.get("if_commands", [])
	else:
		var has_else: bool = cmd.params.get("has_else", false)
		if has_else:
			branch_commands = cmd.params.get("else_commands", [])

	if branch_commands.is_empty():
		return

	# 将分支命令插入到当前位置之后
	var insert_pos: int = _main_index + 1
	for i in range(branch_commands.size()):
		_main_queue.insert(insert_pos + i, branch_commands[i])

	# 重建标签索引（插入可能改变了位置）
	_build_label_index()


## 向后兼容：评估旧格式条件字符串 "variable_name op value"
func _evaluate_legacy_condition(condition: String) -> bool:
	if condition.is_empty():
		return false

	var parts: PackedStringArray = condition.strip_edges().split(" ", false)
	if parts.size() < 3:
		push_warning("AVGSceneRunner: Invalid IF condition format: '%s'" % condition)
		return false

	var var_name: String = parts[0]
	var op: String = parts[1]
	var value_str: String = parts[2]

	var actual = _variable_manager.get_value(var_name)
	if actual == null:
		return false

	var expected: Variant = _parse_condition_value(value_str)
	return _compare_values(actual, op, expected)


# =============================================================================
# CALL_EVENT — 事件调用栈
# =============================================================================

## 将当前执行状态压栈，切换到事件命令队列
func _push_event_call(event_id: String) -> void:
	if game_data == null:
		push_warning("AVGSceneRunner: No game data loaded for CALL_EVENT")
		return

	# 查找事件
	var event: Resource = null
	for e in game_data.events:
		if e == null:
			continue
		var eid: String = e.event_id if "event_id" in e else ""
		if eid == event_id:
			event = e
			break

	if event == null:
		push_warning("AVGSceneRunner: Event '%s' not found" % event_id)
		return

	var event_commands: Array = event.commands if "commands" in event else []
	if event_commands.is_empty():
		push_warning("AVGSceneRunner: Event '%s' has no commands" % event_id)
		return

	# 保存当前状态到调用栈
	_call_stack.append({
		"queue": _main_queue,
		"index": _main_index + 1,  # 返回时从下一条继续
		"label_index": _label_index.duplicate(),
	})

	# 切换到事件命令队列
	_main_queue = event_commands.duplicate()
	_main_index = 0
	_build_label_index()


## 事件执行完毕，弹出调用栈恢复之前的状态
func _pop_event_call() -> void:
	if _call_stack.is_empty():
		return

	var frame: Dictionary = _call_stack.pop_back()
	_main_queue = frame["queue"]
	_main_index = frame["index"]
	_label_index = frame["label_index"]


## 处理 event_call_requested 信号（从 handler 触发时）
func _on_event_call_requested(event_id: String) -> void:
	_push_event_call(event_id)


# =============================================================================
# Jump / Flow Control
# =============================================================================

## 跳转到标签
func jump_to_label(label_name: String) -> bool:
	if label_name.is_empty():
		push_warning("AVGSceneRunner: Empty label name")
		return false
	if not _label_index.has(label_name):
		push_warning("AVGSceneRunner: Label '%s' not found" % label_name)
		return false
	_main_index = _label_index[label_name]
	# 如果当前被阻塞（等待点击等），解除阻塞
	if _is_blocked:
		_is_blocked = false
		_command_context.notify_click()  # 解除 wait_for_click
	return true


## 跳转到场景
func _on_scene_jump_requested(scene_id: String) -> void:
	if game_data == null:
		push_warning("AVGSceneRunner: No game data loaded for scene jump")
		return
	for scene in game_data.scenes:
		if scene == null:
			continue
		var sid: String = scene.scene_id if "scene_id" in scene else ""
		if sid == scene_id:
			# 检查是否有转场参数（由 set_jump_transition 设置）
			var transition_info: Dictionary = _pending_jump_transition
			_pending_jump_transition = {}
			if not transition_info.is_empty():
				# 有转场 → 立即停止主线循环，播放 transition_out，再切换场景
				_should_continue = false
				is_running = false
				var t_type: int = transition_info.get("type", 0)
				var t_duration: float = transition_info.get("duration", 1.0)
				var t_color: Color = transition_info.get("color", Color.BLACK)
				await play_transition_out(t_type, t_duration, t_color)
				# 清理旧场景状态（不触发 scene_ended 信号，因为还在转场中）
				_is_blocked = false
				_call_stack.clear()
				_stop_parallel_executors()
				_hovered_nodes.clear()
				_pressed_nodes.clear()
				if dialog_box != null and dialog_box.has_method("hide_box"):
					dialog_box.hide_box()
				_clear_scene_presentation_state()
				# 设置 _pending_transition 让 start() 播放 transition_in
				_pending_transition = transition_info
				load_scene(scene)
				start()
			else:
				# 无转场 → 硬跳转
				stop()
				_clear_scene_presentation_state()
				load_scene(scene)
				start()
			return
	push_warning("AVGSceneRunner: Scene '%s' not found" % scene_id)


func _on_label_jump_requested(label_name: String) -> void:
	jump_to_label(label_name)


# =============================================================================
# Click Event Handling
# =============================================================================

## 节点被点击时调用（由外部 UI 层触发）
func handle_node_click(node_id: String) -> void:
	if not _click_handlers.has(node_id):
		return
	var commands: Array = _click_handlers[node_id]
	# 执行点击事件的所有命令（自动填充空 node_id 为被点击的节点）
	for cmd in commands:
		if cmd == null:
			continue
		_resolve_click_node_id(cmd, node_id)
		_execute_single_command(cmd)
		# 跳转命令会通过 _command_context 信号修改主线位置


## 点击模式下自动填充空 node_id 为被点击的节点 ID
func _resolve_click_node_id(cmd: Resource, click_node_id: String) -> void:
	if cmd == null or cmd.params == null:
		return
	if not cmd.params.has("node_id"):
		return
	if not cmd.params["node_id"].is_empty():
		return
	cmd.params["node_id"] = click_node_id


## 对话框点击 → 推进主线
func _on_dialog_clicked() -> void:
	if _restore_waiting_click:
		# 读档恢复后的首次点击：启动执行循环（_main_index 已指向下一条命令）
		_restore_waiting_click = false
		_execution_generation += 1
		var my_generation: int = _execution_generation
		_setup_game_ui_buttons()
		_setup_parallel_executors()
		_main_execution_loop(my_generation)
		return
	if _command_context != null:
		_command_context.notify_click()


# =============================================================================
# Public API
# =============================================================================

func get_variable_manager() -> RefCounted:
	return _variable_manager

func get_command_context() -> RefCounted:
	return _command_context

func get_command_registry() -> RefCounted:
	return _command_registry

func get_state() -> Dictionary:
	return {
		"scene_id": current_scene.scene_id if current_scene != null and "scene_id" in current_scene else "",
		"command_index": _main_index,
		"variables": _variable_manager.get_all_values() if _variable_manager != null else {},
		"is_running": is_running,
		"time_of_day": _current_time_of_day,
	}

func restore_state(state: Dictionary) -> void:
	if state.has("command_index"):
		_main_index = state["command_index"]
	if state.has("variables") and _variable_manager != null:
		_variable_manager.load_values(state["variables"])
	if state.has("time_of_day"):
		set_time_of_day(str(state["time_of_day"]), 0.0)


# =============================================================================
# Screen Effects — 屏幕效果方法（由 handler 调用）
# =============================================================================

## 屏幕淡入淡出（使用 shader 转场）
## direction: "out" = 从透明到颜色（遮挡画面），"in" = 从颜色到透明（显示画面）
## transition: 转场类型名称（fade, dissolve, wipe_left 等），默认 "fade"
func screen_fade(direction: String, color: Color, duration: float, transition: String = "fade") -> void:
	if _screen_effects_layer == null:
		return

	var t_type: int = TRANSITION_TYPES.get(transition, 0)
	if direction == "out":
		await play_transition_out(t_type, duration, color)
	else:
		await play_transition_in(t_type, duration, color)


## 播放转场出场（progress 0→1，画面被遮挡）
func play_transition_out(t_type: int, duration: float, color: Color) -> void:
	if _screen_effects_layer == null:
		return
	if _transition_tween != null and _transition_tween.is_valid():
		_transition_tween.kill()

	var mat: ShaderMaterial = _screen_effects_layer.material as ShaderMaterial
	if mat == null:
		return

	_screen_effects_layer.visible = true
	mat.set_shader_parameter("fade_color", color)
	mat.set_shader_parameter("transition_type", t_type)
	mat.set_shader_parameter("progress", 0.0)
	_screen_effects_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if duration <= 0:
		mat.set_shader_parameter("progress", 1.0)
		return

	var tween_out := create_tween()
	_transition_tween = tween_out
	tween_out.tween_method(func(p: float): mat.set_shader_parameter("progress", p), 0.0, 1.0, duration)
	await tween_out.finished
	_screen_effects_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE


## 播放转场入场（progress 1→0，画面显示出来）
func play_transition_in(t_type: int, duration: float, color: Color) -> void:
	if _screen_effects_layer == null:
		return
	if _transition_tween != null and _transition_tween.is_valid():
		_transition_tween.kill()

	var mat: ShaderMaterial = _screen_effects_layer.material as ShaderMaterial
	if mat == null:
		return

	_screen_effects_layer.visible = true
	mat.set_shader_parameter("fade_color", color)
	mat.set_shader_parameter("transition_type", t_type)
	mat.set_shader_parameter("progress", 1.0)

	if duration <= 0:
		mat.set_shader_parameter("progress", 0.0)
		_screen_effects_layer.visible = false
		_screen_effects_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return

	var tween_in := create_tween()
	_transition_tween = tween_in
	tween_in.tween_method(func(p: float): mat.set_shader_parameter("progress", p), 1.0, 0.0, duration)
	await tween_in.finished
	_screen_effects_layer.visible = false
	_screen_effects_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE


## 设置跳转转场参数（由 JUMP_SCENE handler 调用，在 scene_jump_requested 之前）
func set_jump_transition(transition: String, duration: float, color: Color) -> void:
	var t_type: int = TRANSITION_TYPES.get(transition, 0)
	_pending_jump_transition = {
		"type": t_type,
		"duration": duration,
		"color": color,
	}


## 切换背景（带 shader 转场效果）
## 新背景纹理显示在覆盖层上，progress 0→1 逐渐显现，完成后替换实际背景并隐藏覆盖层
func change_background_transition(new_texture: Texture2D, duration: float, transition: String = "fade") -> void:
	if background_display == null:
		return

	# 无动画 → 直接切换
	if duration <= 0 or _bg_transition_layer == null:
		background_display.texture = new_texture
		return

	if _bg_transition_tween != null and _bg_transition_tween.is_valid():
		_bg_transition_tween.kill()

	var mat: ShaderMaterial = _bg_transition_layer.material as ShaderMaterial
	if mat == null:
		background_display.texture = new_texture
		return

	var t_type: int = TRANSITION_TYPES.get(transition, 0)

	# 设置覆盖层纹理和 shader 参数
	_bg_transition_layer.texture = new_texture
	mat.set_shader_parameter("progress", 0.0)
	mat.set_shader_parameter("transition_type", t_type)
	_bg_transition_layer.visible = true

	_bg_transition_tween = create_tween()
	_bg_transition_tween.tween_method(func(p: float): mat.set_shader_parameter("progress", p), 0.0, 1.0, duration)
	await _bg_transition_tween.finished

	# 转场完成 → 替换实际背景，隐藏覆盖层
	if is_instance_valid(background_display):
		background_display.texture = new_texture
	if is_instance_valid(_bg_transition_layer):
		_bg_transition_layer.visible = false
		_bg_transition_layer.texture = null


func set_time_of_day(preset: String, duration: float = 0.6) -> void:
	var preset_name: String = preset.strip_edges().to_lower()
	if not TIME_OF_DAY_PRESETS.has(preset_name):
		push_warning("AVGSceneRunner: Unknown time_of_day preset '%s'" % preset)
		return

	if _time_of_day_layer == null:
		_current_time_of_day = preset_name
		return

	var mat: ShaderMaterial = _time_of_day_layer.material as ShaderMaterial
	if mat == null:
		_current_time_of_day = preset_name
		return

	if _time_of_day_tween != null and _time_of_day_tween.is_valid():
		_time_of_day_tween.kill()
		_time_of_day_tween = null

	_current_time_of_day = preset_name
	var target: Dictionary = TIME_OF_DAY_PRESETS[preset_name]
	_time_of_day_layer.visible = true

	if duration <= 0.0:
		_apply_time_of_day_params(target)
		_time_of_day_layer.visible = preset_name != "day"
		return

	var initial_params: Dictionary = _capture_time_of_day_params()
	_time_of_day_tween = create_tween()
	_time_of_day_tween.set_trans(Tween.TRANS_SINE)
	_time_of_day_tween.set_ease(Tween.EASE_IN_OUT)
	_time_of_day_tween.tween_method(
		func(weight: float) -> void:
			_lerp_time_of_day_params(initial_params, target, weight),
		0.0,
		1.0,
		duration
	)
	_time_of_day_tween.finished.connect(func() -> void:
		if is_instance_valid(_time_of_day_layer):
			_time_of_day_layer.visible = preset_name != "day"
		_time_of_day_tween = null
	)


func _capture_time_of_day_params() -> Dictionary:
	var defaults: Dictionary = TIME_OF_DAY_PRESETS["day"].duplicate(true)
	var mat: ShaderMaterial = null
	if _time_of_day_layer != null:
		mat = _time_of_day_layer.material as ShaderMaterial
	if mat == null:
		return defaults
	return {
		"effect_strength": float(mat.get_shader_parameter("effect_strength")),
		"tint_color": mat.get_shader_parameter("tint_color"),
		"tint_strength": float(mat.get_shader_parameter("tint_strength")),
		"saturation": float(mat.get_shader_parameter("saturation")),
		"exposure": float(mat.get_shader_parameter("exposure")),
		"gradient_top_color": mat.get_shader_parameter("gradient_top_color"),
		"gradient_bottom_color": mat.get_shader_parameter("gradient_bottom_color"),
		"gradient_strength": float(mat.get_shader_parameter("gradient_strength")),
	}


func _apply_time_of_day_params(params: Dictionary) -> void:
	if _time_of_day_layer == null:
		return
	var mat: ShaderMaterial = _time_of_day_layer.material as ShaderMaterial
	if mat == null:
		return
	for key in params.keys():
		mat.set_shader_parameter(StringName(key), params[key])


func _lerp_time_of_day_params(from_params: Dictionary, to_params: Dictionary, weight: float) -> void:
	var blended: Dictionary = {}
	for key in to_params.keys():
		var from_value: Variant = from_params.get(key, to_params[key])
		var to_value: Variant = to_params[key]
		if from_value is Color and to_value is Color:
			blended[key] = (from_value as Color).lerp(to_value as Color, weight)
		elif from_value is float or from_value is int:
			blended[key] = lerpf(float(from_value), float(to_value), weight)
		else:
			blended[key] = to_value
	_apply_time_of_day_params(blended)


## 屏幕闪烁（临时使用 fade 类型快速闪一下）
func screen_flash(color: Color, duration: float, intensity: float) -> void:
	if _screen_effects_layer == null:
		return

	var mat: ShaderMaterial = _screen_effects_layer.material as ShaderMaterial
	if mat == null:
		return

	_screen_effects_layer.visible = true
	mat.set_shader_parameter("fade_color", color)
	mat.set_shader_parameter("transition_type", 0)  # fade
	mat.set_shader_parameter("progress", intensity)

	if duration <= 0:
		mat.set_shader_parameter("progress", 0.0)
		_screen_effects_layer.visible = false
		return

	var tween: Tween = create_tween()
	tween.tween_method(func(p: float): mat.set_shader_parameter("progress", p), intensity, 0.0, duration)
	tween.finished.connect(func():
		if is_instance_valid(_screen_effects_layer):
			_screen_effects_layer.visible = false
	)


## 屏幕震动（通过 Camera2D offset 实现）
func screen_shake(intensity: float, duration: float, frequency: float) -> void:
	if _camera == null:
		return

	var original_offset: Vector2 = _camera.offset
	var shake_count: int = maxi(int(duration * frequency), 1)
	var interval: float = duration / float(shake_count)

	var tween: Tween = create_tween()
	for i in range(shake_count):
		var shake_offset: Vector2 = Vector2(
			randf_range(-intensity, intensity),
			randf_range(-intensity, intensity)
		)
		tween.tween_property(_camera, "offset", original_offset + shake_offset, interval / 2.0)
		tween.tween_property(_camera, "offset", original_offset, interval / 2.0)

	var captured_offset: Vector2 = original_offset
	tween.finished.connect(func():
		if is_instance_valid(_camera):
			_camera.offset = captured_offset
	)


## ---- 摄像机方法 (Camera2D) ----

## CAMERA_ZOOM — 缩放摄像机，聚焦到归一化坐标 (focus_x, focus_y)
## zoom=1.0 为默认，zoom=2.0 为放大两倍
func camera_zoom(zoom_level: float, focus_x: float, focus_y: float, duration: float) -> void:
	if _camera == null:
		return
	if _camera_tween != null and _camera_tween.is_valid():
		_camera_tween.kill()

	var base_scale: Vector2 = _get_base_scale()
	var target_zoom: Vector2 = Vector2(zoom_level, zoom_level)
	# 聚焦点：归一化坐标 -> 设计像素 -> 缩放后像素
	var target_pos: Vector2 = Vector2(focus_x, focus_y) * _project_resolution * base_scale

	if duration <= 0:
		_camera.zoom = target_zoom
		_camera.position = target_pos
		return

	_camera_tween = create_tween()
	_camera_tween.set_ease(Tween.EASE_IN_OUT)
	_camera_tween.set_trans(Tween.TRANS_CUBIC)
	_camera_tween.set_parallel(true)
	_camera_tween.tween_property(_camera, "zoom", target_zoom, duration)
	_camera_tween.tween_property(_camera, "position", target_pos, duration)


## CAMERA_PAN — 平移摄像机（相对偏移）
func camera_pan(norm_x: float, norm_y: float, duration: float) -> void:
	if _camera == null:
		return
	if _camera_tween != null and _camera_tween.is_valid():
		_camera_tween.kill()

	var base_scale: Vector2 = _get_base_scale()
	var offset_pixel: Vector2 = Vector2(norm_x, norm_y) * _project_resolution * base_scale
	var target_pos: Vector2 = _camera.position + offset_pixel

	if duration <= 0:
		_camera.position = target_pos
		return

	_camera_tween = create_tween()
	_camera_tween.set_ease(Tween.EASE_IN_OUT)
	_camera_tween.set_trans(Tween.TRANS_CUBIC)
	_camera_tween.tween_property(_camera, "position", target_pos, duration)


## CAMERA_RESET — 重置摄像机到默认状态（场景中心，zoom=1）
func camera_reset(duration: float) -> void:
	if _camera == null:
		return
	if _camera_tween != null and _camera_tween.is_valid():
		_camera_tween.kill()

	var base_scale: Vector2 = _get_base_scale()
	var default_pos: Vector2 = _project_resolution * base_scale / 2.0

	if duration <= 0:
		_camera.zoom = Vector2.ONE
		_camera.position = default_pos
		return

	_camera_tween = create_tween()
	_camera_tween.set_ease(Tween.EASE_IN_OUT)
	_camera_tween.set_trans(Tween.TRANS_CUBIC)
	_camera_tween.set_parallel(true)
	_camera_tween.tween_property(_camera, "zoom", Vector2.ONE, duration)
	_camera_tween.tween_property(_camera, "position", default_pos, duration)


## 重置屏幕效果层
func _reset_screen_effects() -> void:
	if _screen_effects_layer != null:
		var mat: ShaderMaterial = _screen_effects_layer.material as ShaderMaterial
		if mat != null:
			mat.set_shader_parameter("progress", 0.0)
			mat.set_shader_parameter("fade_color", Color.BLACK)
			mat.set_shader_parameter("transition_type", 0)
		_screen_effects_layer.visible = false
		_screen_effects_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _transition_tween != null and _transition_tween.is_valid():
		_transition_tween.kill()
	if _time_of_day_tween != null and _time_of_day_tween.is_valid():
		_time_of_day_tween.kill()
		_time_of_day_tween = null
	_current_time_of_day = "day"
	if _time_of_day_layer != null:
		_apply_time_of_day_params(TIME_OF_DAY_PRESETS["day"])
		_time_of_day_layer.visible = false
	# 重置摄像机
	if _camera != null:
		_camera.zoom = Vector2.ONE
		_camera.offset = Vector2.ZERO
		_apply_camera_defaults()
	if _camera_tween != null and _camera_tween.is_valid():
		_camera_tween.kill()
		_camera_tween = null
	# 重置对话框打字速度覆盖
	if dialog_box != null and dialog_box.has_method("set_override_text_speed"):
		dialog_box.set_override_text_speed(0.0)


# =============================================================================
# Image Layer — 图片层方法（由 handler 调用）
# =============================================================================

## 显示图片到图片层
func show_image(image_id: String, image_path: String, norm_pos: Vector2, norm_size: Vector2, fade_duration: float, z_order: int, transition: String = "") -> void:
	if _image_layer == null:
		return

	if image_id.is_empty():
		push_warning("AVGSceneRunner: Image id is required")
		return

	var texture: Texture2D = load_game_texture(image_path)
	if texture == null:
		push_warning("AVGSceneRunner: Could not load image '%s'" % image_path)
		return

	var mode: String = _resolve_image_transition_mode(image_id, transition)
	var duration: float = maxf(fade_duration, 0.0)
	var target_rect: TextureRect = _build_image_rect(image_id, texture, image_path, norm_pos, norm_size, z_order)
	var existing_rect: TextureRect = _displayed_images.get(image_id, null)

	_cancel_image_transition(image_id)

	if existing_rect != null and is_instance_valid(existing_rect):
		match mode:
			"instant":
				existing_rect.queue_free()
				_image_layer.add_child(target_rect)
				_displayed_images[image_id] = target_rect
			"crossfade":
				if duration <= 0.0:
					_image_layer.add_child(target_rect)
					_displayed_images[image_id] = target_rect
					existing_rect.queue_free()
					return
				_image_layer.add_child(target_rect)
				existing_rect.z_index = target_rect.z_index + 1
				_displayed_images[image_id] = target_rect
				_image_transition_overlays[image_id] = existing_rect
				var crossfade_tween: Tween = create_tween()
				_image_transition_tweens[image_id] = crossfade_tween
				crossfade_tween.set_trans(Tween.TRANS_QUAD)
				crossfade_tween.set_ease(Tween.EASE_OUT)
				crossfade_tween.tween_property(existing_rect, "modulate:a", 0.0, duration)
				crossfade_tween.finished.connect(func():
					if not is_instance_valid(self):
						return
					if is_instance_valid(existing_rect):
						existing_rect.queue_free()
					_image_transition_tweens.erase(image_id)
					if _image_transition_overlays.get(image_id, null) == existing_rect:
						_image_transition_overlays.erase(image_id)
				)
			"fade_through_black":
				_image_layer.add_child(target_rect)
				_displayed_images[image_id] = target_rect
				if duration <= 0.0:
					existing_rect.queue_free()
					return
				target_rect.modulate.a = 0.0
				var black_overlay: ColorRect = _create_image_black_overlay(image_id, target_rect)
				_image_black_overlays[image_id] = black_overlay
				var half: float = duration / 2.0
				var fade_tween: Tween = create_tween()
				_image_transition_tweens[image_id] = fade_tween
				fade_tween.set_parallel(true)
				fade_tween.tween_property(existing_rect, "modulate:a", 0.0, half)
				fade_tween.tween_property(black_overlay, "modulate:a", 1.0, half)
				fade_tween.set_parallel(false)
				fade_tween.tween_callback(func():
					if is_instance_valid(existing_rect):
						existing_rect.queue_free()
				)
				fade_tween.set_parallel(true)
				fade_tween.tween_property(target_rect, "modulate:a", 1.0, half)
				fade_tween.tween_property(black_overlay, "modulate:a", 0.0, half)
				fade_tween.finished.connect(func():
					if not is_instance_valid(self):
						return
					_image_transition_tweens.erase(image_id)
					if _image_black_overlays.get(image_id, null) == black_overlay:
						_image_black_overlays.erase(image_id)
					if is_instance_valid(black_overlay):
						black_overlay.queue_free()
				)
			_:
				existing_rect.queue_free()
				_image_layer.add_child(target_rect)
				_displayed_images[image_id] = target_rect
				if duration > 0.0:
					target_rect.modulate.a = 0.0
					var fade_tween: Tween = create_tween()
					_image_transition_tweens[image_id] = fade_tween
					fade_tween.tween_property(target_rect, "modulate:a", 1.0, duration)
					fade_tween.finished.connect(func():
						if not is_instance_valid(self):
							return
						_image_transition_tweens.erase(image_id)
					)
		return

	_image_layer.add_child(target_rect)
	_displayed_images[image_id] = target_rect
	if mode != "instant" and duration > 0.0:
		target_rect.modulate.a = 0.0
		var intro_tween: Tween = create_tween()
		_image_transition_tweens[image_id] = intro_tween
		intro_tween.tween_property(target_rect, "modulate:a", 1.0, duration)
		intro_tween.finished.connect(func():
			if not is_instance_valid(self):
				return
			_image_transition_tweens.erase(image_id)
		)


## 隐藏/移除图片
func hide_image(image_id: String, fade_duration: float, transition: String = "") -> void:
	if not _displayed_images.has(image_id):
		push_warning("AVGSceneRunner: Image '%s' not found" % image_id)
		return

	var tex_rect: Control = _displayed_images[image_id]
	if not is_instance_valid(tex_rect):
		_displayed_images.erase(image_id)
		return

	_cancel_image_transition(image_id)
	var normalized_transition: String = str(transition).strip_edges().to_lower()
	if normalized_transition == "instant" or fade_duration <= 0:
		tex_rect.queue_free()
		_displayed_images.erase(image_id)
		return

	var tween: Tween = create_tween()
	_image_transition_tweens[image_id] = tween
	tween.tween_property(tex_rect, "modulate:a", 0.0, fade_duration)
	var captured_id: String = image_id
	tween.finished.connect(func():
		if not is_instance_valid(self):
			return
		if is_instance_valid(tex_rect):
			tex_rect.queue_free()
		_displayed_images.erase(captured_id)
		_image_transition_tweens.erase(captured_id)
	)


## 清除图片层所有图片
func _clear_image_layer() -> void:
	for image_id in _displayed_images.keys():
		_cancel_image_transition(str(image_id))
	_displayed_images.clear()
	if _image_layer != null:
		for child in _image_layer.get_children():
			child.queue_free()


func _build_image_rect(image_id: String, texture: Texture2D, image_path: String, norm_pos: Vector2, norm_size: Vector2, z_order: int) -> TextureRect:
	var tex_rect := TextureRect.new()
	tex_rect.name = image_id
	tex_rect.texture = texture
	tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex_rect.position = norm_pos * _project_resolution
	tex_rect.size = norm_size * _project_resolution
	tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tex_rect.z_index = z_order
	tex_rect.set_meta("image_path", image_path)
	tex_rect.set_meta("norm_pos", norm_pos)
	tex_rect.set_meta("norm_size", norm_size)
	tex_rect.set_meta("z_order", z_order)
	return tex_rect


func _create_image_overlay(image_id: String, source_rect: TextureRect) -> TextureRect:
	var overlay := TextureRect.new()
	overlay.name = "%s_overlay" % image_id
	overlay.texture = source_rect.texture
	overlay.expand_mode = source_rect.expand_mode
	overlay.stretch_mode = source_rect.stretch_mode
	overlay.position = source_rect.position
	overlay.size = source_rect.size
	overlay.scale = source_rect.scale
	overlay.rotation = source_rect.rotation
	overlay.pivot_offset = source_rect.pivot_offset
	overlay.modulate = source_rect.modulate
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.z_index = source_rect.z_index + 1
	overlay.set_meta("image_path", source_rect.get_meta("image_path", ""))
	overlay.set_meta("norm_pos", source_rect.get_meta("norm_pos", Vector2.ZERO))
	overlay.set_meta("norm_size", source_rect.get_meta("norm_size", Vector2.ONE))
	overlay.set_meta("z_order", source_rect.get_meta("z_order", source_rect.z_index))
	return overlay


func _create_image_black_overlay(image_id: String, source_rect: TextureRect) -> ColorRect:
	var overlay := ColorRect.new()
	overlay.name = "%s_black" % image_id
	overlay.color = Color.BLACK
	overlay.position = source_rect.position
	overlay.size = source_rect.size
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.z_index = source_rect.z_index + 1
	overlay.modulate.a = 0.0
	_image_layer.add_child(overlay)
	return overlay


func _cancel_image_transition(image_id: String) -> void:
	if _image_transition_tweens.has(image_id):
		var tween: Tween = _image_transition_tweens[image_id]
		if tween != null and tween.is_valid():
			tween.kill()
		_image_transition_tweens.erase(image_id)
	if _image_transition_overlays.has(image_id):
		var overlay: TextureRect = _image_transition_overlays[image_id]
		if is_instance_valid(overlay):
			overlay.queue_free()
		_image_transition_overlays.erase(image_id)
	if _image_black_overlays.has(image_id):
		var black_overlay: ColorRect = _image_black_overlays[image_id]
		if is_instance_valid(black_overlay):
			black_overlay.queue_free()
		_image_black_overlays.erase(image_id)


func _resolve_image_transition_mode(image_id: String, transition: String) -> String:
	var normalized: String = transition.strip_edges().to_lower()
	if normalized.is_empty():
		return "crossfade" if image_id == "cg" else "fade"
	if normalized in ["fade", "crossfade", "fade_through_black", "instant"]:
		return normalized
	push_warning("AVGSceneRunner: unsupported image transition '%s', falling back to fade" % transition)
	return "fade"


# =============================================================================
# Notification — 通知方法（由 handler 调用）
# =============================================================================

## 显示通知消息（自动消失）
func show_notification(text: String, duration: float, pos: String, font_size: int, color: Color) -> void:
	if design_container == null:
		return

	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var actual_font_size: int = font_size if font_size > 0 else 28
	label.add_theme_font_size_override("font_size", actual_font_size)
	label.add_theme_color_override("font_color", color)

	# 添加阴影增强可读性
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)

	label.size = Vector2(_project_resolution.x * 0.6, 60)
	label.position.x = (_project_resolution.x - label.size.x) / 2.0

	match pos:
		"top":
			label.position.y = 40
		"center":
			label.position.y = (_project_resolution.y - label.size.y) / 2.0
		"bottom":
			label.position.y = _project_resolution.y - label.size.y - 40
		_:
			label.position.y = 40

	label.modulate.a = 0.0
	design_container.add_child(label)

	# 淡入 → 停留 → 淡出 → 删除
	var tween: Tween = create_tween()
	tween.tween_property(label, "modulate:a", 1.0, 0.3)
	tween.tween_interval(duration)
	tween.tween_property(label, "modulate:a", 0.0, 0.3)
	tween.finished.connect(func():
		if is_instance_valid(label):
			label.queue_free()
	)


# =============================================================================
# Title Screen — 标题界面（运行时自动生成）
# =============================================================================

## 显示标题界面
func show_title_screen() -> void:
	if game_data == null:
		return
	_showing_title = true
	_hide_game_layers()
	_build_title_screen()


## 隐藏标题界面
func hide_title_screen() -> void:
	_showing_title = false
	if _title_screen != null and is_instance_valid(_title_screen):
		_title_screen.queue_free()
		_title_screen = null
	_show_game_layers()


## 获取标题配置（从 title_config 或回退默认值）
func _get_title_config() -> Resource:
	if game_data != null and game_data.title_config != null:
		return game_data.title_config
	return null


## 构建标题界面 UI（从 AVGTitleConfig 读取所有配置）
func _build_title_screen() -> void:
	# 清除旧的标题界面
	if _title_screen != null and is_instance_valid(_title_screen):
		_title_screen.queue_free()

	var config: Resource = _get_title_config()

	_title_screen = Control.new()
	_title_screen.name = "TitleScreen"
	_title_screen.size = _project_resolution
	_title_screen.mouse_filter = Control.MOUSE_FILTER_STOP

	# ---- 背景颜色 ----
	var bg := ColorRect.new()
	bg.size = _project_resolution
	bg.color = config.background_color if config != null else Color(0.05, 0.05, 0.1, 1.0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_screen.add_child(bg)

	# ---- 背景图 ----
	var bg_path: String = config.background_image if config != null else ""
	if not bg_path.is_empty():
		var tex: Texture2D = load_game_texture(bg_path)
		if tex != null:
			var bg_img := TextureRect.new()
			bg_img.texture = tex
			bg_img.size = _project_resolution
			bg_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			bg_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			bg_img.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_title_screen.add_child(bg_img)

	# ---- 标题文字 ----
	var title_text: String = ""
	if config != null and not config.title_text.is_empty():
		title_text = config.title_text
	elif game_data != null:
		title_text = game_data.game_name
	var title_font_size: int = config.title_font_size if config != null else 72
	var title_color: Color = config.title_color if config != null else Color.WHITE
	var title_norm_pos: Vector2 = config.title_norm_position if config != null else Vector2(0.5, 0.25)

	var title_label := Label.new()
	title_label.text = title_text
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", title_font_size)
	title_label.add_theme_color_override("font_color", title_color)
	title_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	title_label.add_theme_constant_override("shadow_offset_x", 3)
	title_label.add_theme_constant_override("shadow_offset_y", 3)
	var title_size := Vector2(_project_resolution.x, 120)
	title_label.size = title_size
	# 归一化位置（锚点=中心）
	title_label.position = Vector2(
		title_norm_pos.x * _project_resolution.x - title_size.x / 2.0,
		title_norm_pos.y * _project_resolution.y - title_size.y / 2.0
	)
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_screen.add_child(title_label)

	# ---- 按钮通用参数 ----
	var btn_font_size: int = config.button_font_size if config != null else 28
	var btn_size: Vector2 = config.button_size if config != null else Vector2(300, 60)
	var _btn_spacing: float = config.button_spacing if config != null else 20.0

	# ---- 开始游戏按钮 ----
	var start_text: String = config.start_button_text if config != null else "开始游戏"
	var start_norm_pos: Vector2 = config.start_button_norm_position if config != null else Vector2(0.5, 0.55)
	var start_btn := Button.new()
	start_btn.text = start_text
	start_btn.custom_minimum_size = btn_size
	start_btn.size = btn_size
	start_btn.add_theme_font_size_override("font_size", btn_font_size)
	start_btn.position = Vector2(
		start_norm_pos.x * _project_resolution.x - btn_size.x / 2.0,
		start_norm_pos.y * _project_resolution.y - btn_size.y / 2.0
	)
	_apply_title_button_style(start_btn, config)
	start_btn.pressed.connect(_on_title_start_pressed)
	_title_screen.add_child(start_btn)

	# ---- 读档按钮 ----
	var load_enabled: bool = config.load_button_enabled if config != null else false
	var load_text: String = config.load_button_text if config != null else "读档"
	var load_norm_pos: Vector2 = config.load_button_norm_position if config != null else Vector2(0.5, 0.62)
	var load_btn := Button.new()
	load_btn.text = load_text
	load_btn.custom_minimum_size = btn_size
	load_btn.size = btn_size
	load_btn.add_theme_font_size_override("font_size", btn_font_size)
	load_btn.position = Vector2(
		load_norm_pos.x * _project_resolution.x - btn_size.x / 2.0,
		load_norm_pos.y * _project_resolution.y - btn_size.y / 2.0
	)
	load_btn.disabled = not load_enabled
	_apply_title_button_style(load_btn, config)
	load_btn.pressed.connect(_on_title_load_pressed)
	_title_screen.add_child(load_btn)

	# ---- 设置按钮 ----
	var settings_enabled: bool = config.settings_button_enabled if config != null else false
	var settings_text: String = config.settings_button_text if config != null else "设置"
	var settings_norm_pos: Vector2 = config.settings_button_norm_position if config != null else Vector2(0.5, 0.69)
	var settings_btn := Button.new()
	settings_btn.text = settings_text
	settings_btn.custom_minimum_size = btn_size
	settings_btn.size = btn_size
	settings_btn.add_theme_font_size_override("font_size", btn_font_size)
	settings_btn.position = Vector2(
		settings_norm_pos.x * _project_resolution.x - btn_size.x / 2.0,
		settings_norm_pos.y * _project_resolution.y - btn_size.y / 2.0
	)
	settings_btn.disabled = not settings_enabled
	_apply_title_button_style(settings_btn, config)
	settings_btn.pressed.connect(_on_title_settings_pressed)
	_title_screen.add_child(settings_btn)

	# 添加到 DesignContainer 最顶层
	if design_container:
		design_container.add_child(_title_screen)


## 标题界面 "开始游戏" 按钮回调
func _on_title_start_pressed() -> void:
	var first_index: int = 0
	var config: Resource = _get_title_config()
	if config != null and config.has_method("resolve_first_scene_index"):
		first_index = config.resolve_first_scene_index(game_data)
	hide_title_screen()
	title_start_requested.emit(first_index)


## 将 title_config.button_style（AVGStyleBox）的四状态应用到按钮
func _apply_title_button_style(btn: BaseButton, config: Resource) -> void:
	if config == null:
		return
	if "button_style" in config and config.button_style != null and config.button_style.has_method("apply_to_button"):
		config.button_style.apply_to_button(btn)


## 标题界面 "读档" 按钮回调
func _on_title_load_pressed() -> void:
	if _screen_manager != null:
		_screen_manager.show_screen(AVGScreenConfigClass.ScreenType.LOAD)


## 标题界面 "设置" 按钮回调
func _on_title_settings_pressed() -> void:
	if _screen_manager != null:
		_screen_manager.show_screen(AVGScreenConfigClass.ScreenType.SETTINGS)


## 隐藏游戏层（标题界面显示时）
func _hide_game_layers() -> void:
	if background_display:
		background_display.visible = false
	if character_display:
		character_display.visible = false
	if dialog_box:
		dialog_box.visible = false
	if choice_display:
		choice_display.visible = false
	if _nodes_layer:
		_nodes_layer.visible = false
	if _image_layer:
		_image_layer.visible = false
	if _game_ui_container and is_instance_valid(_game_ui_container):
		_game_ui_container.visible = false


## 显示游戏层（标题界面隐藏后）
func _show_game_layers() -> void:
	if background_display:
		background_display.visible = true
	if character_display:
		character_display.visible = true
	# dialog_box 和 choice_display 由命令控制显隐，不在这里强制显示
	if _nodes_layer:
		_nodes_layer.visible = true
	if _image_layer:
		_image_layer.visible = true
	if _game_ui_container and is_instance_valid(_game_ui_container):
		_game_ui_container.visible = true

# =============================================================================
# 游戏内 UI 按钮
# =============================================================================

## 创建游戏内 UI 按钮（从 game_ui_config 读取配置）
func _setup_game_ui_buttons() -> void:
	# 清除旧的
	if _game_ui_container != null and is_instance_valid(_game_ui_container):
		_game_ui_container.queue_free()
	_game_ui_container = null
	_game_ui_buttons.clear()

	if game_data == null:
		return
	if not "game_ui_config" in game_data or game_data.game_ui_config == null:
		return
	var config: Resource = game_data.game_ui_config
	var buttons: Array = config.buttons if "buttons" in config else []
	if buttons.is_empty():
		return
	if ui_container == null:
		return

	_game_ui_container = Control.new()
	_game_ui_container.name = "GameUIButtons"
	_game_ui_container.size = _project_resolution
	_game_ui_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_container.add_child(_game_ui_container)

	for btn_data in buttons:
		if not btn_data.visible_default:
			continue
		var btn := Button.new()
		btn.text = btn_data.display_text
		btn.custom_minimum_size = btn_data.size
		btn.size = btn_data.size
		btn.add_theme_font_size_override("font_size", btn_data.font_size)
		btn.position = Vector2(
			btn_data.norm_position.x * _project_resolution.x - btn_data.size.x / 2.0,
			btn_data.norm_position.y * _project_resolution.y - btn_data.size.y / 2.0
		)
		if "button_style" in config and config.button_style != null and config.button_style.has_method("apply_to_button"):
			config.button_style.apply_to_button(btn)
		var action: String = btn_data.action
		btn.pressed.connect(_on_game_ui_button_pressed.bind(action))
		_game_ui_container.add_child(btn)
		_game_ui_buttons[action] = btn

	# 标题界面时隐藏
	if _showing_title:
		_game_ui_container.visible = false


## 游戏内 UI 按钮点击回调
func _on_game_ui_button_pressed(action: String) -> void:
	game_ui_action_requested.emit(action)


## 显示/隐藏游戏内 UI 按钮
func set_game_ui_visible(p_visible: bool) -> void:
	if _game_ui_container != null and is_instance_valid(_game_ui_container):
		_game_ui_container.visible = p_visible


# =============================================================================
# 游戏内子界面 — 菜单/存档/读档/历史/设置
# =============================================================================

## 处理游戏内 UI 按钮动作
func _on_game_ui_action(action: String) -> void:
	if _screen_manager == null:
		return
	# 如果已经在显示子界面，先关闭
	if _screen_manager.is_showing():
		_screen_manager.close_screen()
		return

	# --- 存档/读档/菜单 只在安全时机允许 ---
	# 安全时机：
	#   1. 对话阻塞中 + 对话已完整显示（非打字中）
	#   2. 选项等待选择中
	#   3. 命令队列执行完毕（空闲状态）
	#   4. 读档恢复等待点击中
	var needs_safe_timing: bool = action in ["menu", "save", "load", "log", "settings"]
	if needs_safe_timing:
		var is_choice_waiting: bool = choice_display != null and choice_display.is_waiting_for_selection()
		var is_dialogue_ready: bool = _is_blocked and (dialog_box == null or not dialog_box._is_typing)
		var is_idle: bool = is_running and _main_index >= _main_queue.size()
		var is_restore_waiting: bool = _restore_waiting_click
		if not is_choice_waiting and not is_dialogue_ready and not is_idle and not is_restore_waiting:
			return

	match action:
		"menu":
			_screen_manager.show_screen(AVGScreenConfigClass.ScreenType.MENU)
		"save":
			_screen_manager.show_screen(AVGScreenConfigClass.ScreenType.SAVE)
		"load":
			_screen_manager.show_screen(AVGScreenConfigClass.ScreenType.LOAD)
		"log":
			_screen_manager.show_screen(AVGScreenConfigClass.ScreenType.HISTORY)
		"settings":
			_screen_manager.show_screen(AVGScreenConfigClass.ScreenType.SETTINGS)
		"hide_ui":
			_toggle_ui_visibility()
		"auto":
			_toggle_auto_mode()
		"skip":
			_toggle_skip_mode()


## 子界面关闭回调
func _on_screen_closed() -> void:
	pass  # 恢复游戏状态（如果需要暂停的话）


## 存档请求回调
func _on_save_requested(slot_index: int) -> void:
	if _save_manager == null:
		return
	var state: Dictionary = _build_save_data()
	var err: Error = _save_manager.save_game(slot_index, state)
	if err == OK:
		print("[AVGSceneRunner] Game saved to slot %d" % slot_index)
	else:
		push_error("[AVGSceneRunner] Failed to save game to slot %d" % slot_index)


## 读档请求回调
func _on_load_requested(slot_index: int) -> void:
	if _save_manager == null:
		return
	var data: Dictionary = _save_manager.load_game(slot_index)
	if data.is_empty():
		push_warning("[AVGSceneRunner] No save data in slot %d" % slot_index)
		return
	_restore_save_data(data)


## 返回标题回调
func _on_return_to_title() -> void:
	stop()
	reset()
	if game_data != null:
		load_game_data(game_data)
	show_title_screen()


## 退出回调
func _on_quit_requested() -> void:
	stop()
	reset()
	# 发出信号让外部处理（GamePreviewer 等）
	var scene_id: String = ""
	scene_ended.emit(scene_id)


## 构建存档数据
func _build_save_data() -> Dictionary:
	var data: Dictionary = {}
	# 场景信息
	if current_scene != null:
		data["scene_id"] = current_scene.scene_id if "scene_id" in current_scene else ""
		data["scene_name"] = current_scene.scene_name if "scene_name" in current_scene else ""
	
	# 命令索引：保存当前命令位置
	data["command_index"] = _main_index
	
	# 变量（包含全局和本地）
	if _variable_manager != null and _variable_manager.has_method("get_all_values"):
		data["variables"] = _variable_manager.get_all_values()
	# 历史记录
	if _history_manager != null:
		data["history"] = _history_manager.to_data()
	
	# --- 对话框完整状态 ---
	if dialog_box != null:
		data["dialog_box"] = dialog_box.get_state()
	
	# --- 选项状态 ---
	if choice_display != null and choice_display.visible:
		data["choice_visible"] = true
	
	# 背景
	if background_display != null and background_display.texture != null:
		data["background_path"] = background_display.texture.resource_path
	data["time_of_day"] = _current_time_of_day

	# --- 角色状态 ---
	if character_display != null:
		var char_states: Dictionary = character_display.get_all_character_states()
		# Vector2 不能直接 JSON 序列化，转为 [x, y] 数组
		var serialized_chars: Dictionary = {}
		for cid in char_states:
			var s: Dictionary = char_states[cid].duplicate()
			if s.has("position_ratio") and s["position_ratio"] is Vector2:
				var v: Vector2 = s["position_ratio"]
				s["position_ratio"] = [v.x, v.y]
			serialized_chars[cid] = s
		data["characters"] = serialized_chars

	# --- 图片层状态 ---
	var images_data: Array = []
	for image_id in _displayed_images:
		var tex_rect: Control = _displayed_images[image_id]
		if not is_instance_valid(tex_rect):
			continue
		var img_entry: Dictionary = {
			"image_id": image_id,
			"image_path": tex_rect.get_meta("image_path", ""),
			"norm_pos": [tex_rect.get_meta("norm_pos", Vector2.ZERO).x, tex_rect.get_meta("norm_pos", Vector2.ZERO).y],
			"norm_size": [tex_rect.get_meta("norm_size", Vector2.ZERO).x, tex_rect.get_meta("norm_size", Vector2.ZERO).y],
			"z_order": tex_rect.get_meta("z_order", 0),
		}
		images_data.append(img_entry)
	data["images"] = images_data

	# --- 摄像机状态 ---
	if _camera != null:
		data["camera"] = {
			"zoom": [_camera.zoom.x, _camera.zoom.y],
			"position": [_camera.position.x, _camera.position.y],
			"offset": [_camera.offset.x, _camera.offset.y],
		}

	# --- BGM ---
	if audio_manager != null and audio_manager.has_method("get_current_bgm"):
		var bgm_path: String = audio_manager.get_current_bgm()
		if not bgm_path.is_empty():
			data["bgm_path"] = bgm_path

	return data


## 从存档数据恢复游戏状态
func _restore_save_data(data: Dictionary) -> void:
	var scene_id: String = data.get("scene_id", "")
	if scene_id.is_empty() or game_data == null:
		push_warning("[AVGSceneRunner] Cannot restore: missing scene_id or game data")
		return

	# 查找场景
	var target_scene: Resource = null
	for scene in game_data.scenes:
		if scene == null:
			continue
		var sid: String = scene.scene_id if "scene_id" in scene else ""
		if sid == scene_id:
			target_scene = scene
			break

	if target_scene == null:
		push_warning("[AVGSceneRunner] Cannot restore: scene '%s' not found" % scene_id)
		return

	# 停止当前运行
	stop()
	hide_title_screen()

	# 加载场景（这会初始化本地变量为默认值）
	load_scene(target_scene)

	# 恢复变量（必须在 load_scene 之后，覆盖默认值）
	if data.has("variables") and _variable_manager != null and _variable_manager.has_method("load_values"):
		_variable_manager.load_values(data["variables"])

	# 恢复历史记录
	if data.has("history") and _history_manager != null:
		_history_manager.from_data(data["history"])

	# 跳转到指定命令位置
	var cmd_index: int = data.get("command_index", 0)
	_main_index = mini(cmd_index, _main_queue.size())

	# 恢复背景
	if data.has("background_path") and background_display != null:
		var bg_path: String = data["background_path"]
		if not bg_path.is_empty():
			var tex: Texture2D = load(bg_path) as Texture2D
			if tex != null:
				background_display.texture = tex

	# --- 恢复角色状态 ---
	if data.has("characters") and character_display != null:
		character_display.restore_all_characters(data["characters"])
	if data.has("time_of_day"):
		set_time_of_day(str(data["time_of_day"]), 0.0)

	# --- 恢复图片层 ---
	if data.has("images"):
		_clear_image_layer()
		for img_entry in data["images"]:
			var img_id: String = img_entry.get("image_id", "")
			var img_path: String = img_entry.get("image_path", "")
			if img_id.is_empty() or img_path.is_empty():
				continue
			var np: Array = img_entry.get("norm_pos", [0.0, 0.0])
			var ns: Array = img_entry.get("norm_size", [0.0, 0.0])
			var norm_pos: Vector2 = Vector2(np[0], np[1])
			var norm_size: Vector2 = Vector2(ns[0], ns[1])
			var z_order: int = img_entry.get("z_order", 0)
			show_image(img_id, img_path, norm_pos, norm_size, 0.0, z_order)

	# --- 恢复摄像机 ---
	if data.has("camera") and _camera != null:
		var cam: Dictionary = data["camera"]
		if cam.has("zoom"):
			var z: Array = cam["zoom"]
			_camera.zoom = Vector2(z[0], z[1])
		if cam.has("position"):
			var p: Array = cam["position"]
			_camera.position = Vector2(p[0], p[1])
		if cam.has("offset"):
			var o: Array = cam["offset"]
			_camera.offset = Vector2(o[0], o[1])

	# --- 恢复 BGM ---
	if data.has("bgm_path") and audio_manager != null:
		var bgm_path: String = data["bgm_path"]
		if not bgm_path.is_empty():
			audio_manager.play_bgm(bgm_path, 0.0, 1.0)

	# --- 恢复对话框状态 ---
	if data.has("dialog_box") and dialog_box != null:
		dialog_box.restore_state(data["dialog_box"])

	# 恢复阻塞等待状态（对话框或选项正在等待点击）
	var dialog_state: Dictionary = data.get("dialog_box", {})
	var dialog_visible: bool = dialog_state.get("visible", false)
	var choice_visible: bool = data.get("choice_visible", false)

	if dialog_visible or choice_visible:
		if choice_visible:
			# CHOICE 存档：需要重新执行 CHOICE 命令让玩家选择
			# _main_index 不变，直接 start() 重新执行当前 CHOICE
			start()
		else:
			# DIALOGUE 存档：对话框已恢复显示，跳过当前命令
			# 等玩家点击后从下一条开始
			_main_index += 1
			is_running = true
			_should_continue = true
			_is_blocked = false
			_show_game_layers()
			_restore_waiting_click = true
	else:
		start()

	print("[AVGSceneRunner] Game restored from save, scene: %s, index: %d" % [scene_id, cmd_index])


## 切换 UI 可见性（隐藏/显示对话框和按钮）
var _ui_hidden: bool = false
var _ui_restore_overlay: ColorRect = null

func _toggle_ui_visibility() -> void:
	_ui_hidden = not _ui_hidden
	if _ui_hidden:
		if dialog_box != null:
			dialog_box.visible = false
		if choice_display != null:
			choice_display.visible = false
		set_game_ui_visible(false)
		_create_restore_overlay()
	else:
		_remove_restore_overlay()
		# 恢复 UI — 对话框只在有内容时显示
		if dialog_box != null and not dialog_box._full_text.is_empty():
			dialog_box.visible = true
		if choice_display != null and choice_display.is_waiting_for_selection():
			choice_display.visible = true
		set_game_ui_visible(true)


## 创建全屏透明遮罩，点击后恢复 UI
func _create_restore_overlay() -> void:
	_remove_restore_overlay()
	_ui_restore_overlay = ColorRect.new()
	_ui_restore_overlay.name = "UIRestoreOverlay"
	_ui_restore_overlay.color = Color(0, 0, 0, 0)
	_ui_restore_overlay.size = _project_resolution
	_ui_restore_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_ui_restore_overlay.gui_input.connect(_on_restore_overlay_input)
	if ui_container:
		ui_container.add_child(_ui_restore_overlay)


## 遮罩点击回调
func _on_restore_overlay_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_toggle_ui_visibility()


## 移除恢复遮罩
func _remove_restore_overlay() -> void:
	if _ui_restore_overlay != null and is_instance_valid(_ui_restore_overlay):
		_ui_restore_overlay.queue_free()
	_ui_restore_overlay = null


## 自动模式
var _auto_mode: bool = false
var _auto_timer: float = 0.0
const AUTO_WAIT_TIME: float = 2.0

func _toggle_auto_mode() -> void:
	_auto_mode = not _auto_mode
	_skip_mode = false
	if _auto_mode:
		print("[AVGSceneRunner] Auto mode ON")
	else:
		print("[AVGSceneRunner] Auto mode OFF")


## 快进模式
var _skip_mode: bool = false

func _toggle_skip_mode() -> void:
	_skip_mode = not _skip_mode
	_auto_mode = false
	if _skip_mode:
		print("[AVGSceneRunner] Skip mode ON")
		# 立即推进
		if _is_blocked and _command_context != null:
			_command_context.notify_click()
	else:
		print("[AVGSceneRunner] Skip mode OFF")


## 获取历史记录管理器（供外部访问）
func get_history_manager() -> RefCounted:
	return _history_manager


## 获取存档管理器（供外部访问）
func get_save_manager() -> RefCounted:
	return _save_manager


## 获取子界面管理器（供外部访问）
func get_screen_manager() -> RefCounted:
	return _screen_manager
