extends Control
## 小游戏正式链路测试场景
## 这里不再直接实例化小游戏，而是：
##   1. 注入一条 Dev Work 任务
##   2. 打开 Dev Work APP
##   3. 由玩家在 Dev Work 中点击任务，进入正式链路

const WindowManagerClass = preload("res://scripts/pseudo_os/window_manager.gd")

const MINIGAME_TESTS: Array[Dictionary] = [
	{
		"type": "typing_code",
		"label": "代码打字",
		"title": "整理战斗输入响应",
		"description": "把当前战斗输入响应里最卡手的部分先敲顺，方便后续继续补反馈细节。",
		"stat_changes": {"quality": 4, "completion": 5},
		"weight": 8,
	},
	{
		"type": "find_bugs",
		"label": "Bug修复 · 翻牌配对",
		"title": "清掉 UI 交互回归问题",
		"description": "先把这一轮界面回归里最明显的几个错位和错态找出来，别让试玩继续被它们绊住。",
		"stat_changes": {"stability": 5, "completion": 3},
		"weight": 8,
	},
	{
		"type": "code_puzzle",
		"label": "代码排序 · 执行拼图",
		"title": "收束事件触发顺序",
		"description": "把事件触发链先理顺，让后续剧情切换不会因为顺序错乱而断掉。",
		"stat_changes": {"quality": 3, "completion": 5},
		"weight": 8,
	},
	{
		"type": "creative_decision",
		"label": "创意决策 · 主线方向",
		"title": "和林夏敲定钟塔线关键取舍",
		"description": "先把钟塔戏的关键取舍（谁先破冰、是否直接和好、回忆杀留不留）逐轮决定，后面才好写台词。",
		"kb_sources": ["characters", "story", "notes"],
		"topic_config": {
			"goal_description": "和林夏一起敲定钟塔露台争执戏里 3~4 个关键方向选择",
		},
		"stat_changes": {"quality": 3, "completion": 2},
		"weight": 8,
	},
	{
		"type": "structured_form",
		"label": "方案填写 · Day1 企划卡",
		"title": "AGJ 2027 · 第一版企划卡",
		"description": "把 Day1 讨论收束成一张结构化企划卡，确认作品名、类型、标签和短大纲。",
		"form_config": {
			"form_id": "test_day1_creative_brief",
			"title": "AGJ 2027 · 第一版企划卡",
			"description": "测试用表单，字段与 Day1 正式企划卡保持一致。",
			"fields": [
				{"id": "game_title", "type": "text", "label": "作品名称", "required": true, "max_length": 20},
				{"id": "game_genre", "type": "single_select", "label": "类型", "required": true, "allow_custom": true, "options": ["恋爱 Gal", "悬疑推理", "轻喜剧", "奇幻冒险"]},
				{"id": "game_tags", "type": "multi_select", "label": "核心标签", "required": true, "min_selected": 1, "max_selected": 3, "options": ["异世界", "魔法学院", "暧昧", "成长", "轻推理"]},
				{"id": "game_outline", "type": "textarea", "label": "短大纲", "required": true, "max_length": 200},
			],
			"llm_assist": {
				"actions": [
					{
						"id": "generate_outline",
						"label": "生成短大纲",
						"target_field": "game_outline",
						"prompt": "根据当前表单内容，生成一段 150 字以内的 AVG 企划短大纲。只输出 value: DSL。"
					}
				]
			},
			"review": {"mode": "dsl"},
		},
		"post_task_handler": {"type": "creative_brief_completed"},
		"stat_changes": {"quality": 4, "completion": 4},
		"stress_cost": 0,
		"weight": 10,
	},
	{
		"type": "emotion_tag",
		"label": "情绪标注 · 演出校准",
		"title": "校准钟塔露台争执戏的情绪",
		"description": "先判断几句候选台词更接近什么情绪，让后续表情和演出别跑偏。",
		"kb_sources": ["characters", "story", "notes"],
		"stat_changes": {"quality": 4, "completion": 3},
		"weight": 9,
	},
	{
		"type": "script_fill",
		"label": "台词填空 · 关键句补完",
		"title": "补完钟塔露台争执戏的关键台词",
		"description": "先把学院线冲突场面的关键句补上，让人物关系和后续演出都能继续往前推。",
		"kb_sources": ["characters", "story", "notes"],
		"post_task_work_order": {
			"title": "补完《星穹学院的逆时书》钟塔露台争执戏",
			"description": "男主角阿尔诺私自前往旧钟塔调查禁书回响，差点被失控魔力吞没。女主角赛琳在露台拦下他后爆发争执。补出这场戏里最关键的几句台词，让冲突从互相顶嘴推进到第一次暴露彼此在意，但不能直接和好。",
			"kb_sources": ["characters", "story", "notes"],
			"scene_target": "clocktower_rooftop_argument",
			"performance_context": "none",
		},
		"stat_changes": {"quality": 4, "completion": 4},
		"weight": 10,
	},
]

const SCRIPT_FILL_FAKE_KB_DOCS: Array[Dictionary] = [
	{
		"doc_id": "creative_core",
		"title": "项目核心创意",
		"content": "项目是一部异世界学院恋爱冒险 AVG《星穹学院的逆时书》。舞台是漂浮在天穹海上的赫利俄斯学院，学生通过刻印术与誓约器施法。主线围绕旧钟塔里不断复苏的禁书回响展开，角色关系要从互相试探逐步走到真正并肩。",
		"category": "notes",
		"doc_kind": "brief",
		"state": "confirmed",
	},
	{
		"doc_id": "char_arnor",
		"title": "男主角阿尔诺设定",
		"content": "阿尔诺是从边境矿镇转入赫利俄斯学院的奖学生，拥有听见遗物残留情绪回声的能力。表面冷静寡言，遇到危险时却习惯自己扛，越在意别人越容易先把人推开。",
		"category": "characters",
		"doc_kind": "canonical",
		"state": "confirmed",
	},
	{
		"doc_id": "char_selene",
		"title": "女主角赛琳设定",
		"content": "赛琳是赫利俄斯学院高阶术式科首席生兼纪律委员长，出身古老誓约师家系。她习惯把责任全揽到自己身上，嘴硬、控制欲强，真正担心人的时候反而会说得更重。",
		"category": "characters",
		"doc_kind": "canonical",
		"state": "confirmed",
	},
	{
		"doc_id": "story_clocktower_argument",
		"title": "钟塔露台争执戏节拍",
		"content": "阿尔诺私自前往旧钟塔调查禁书回响，差点被失控魔力吞没。赛琳在露台拦下他后先质问，再被他嘴硬顶回去。冲突核心不是单纯生气，而是两人都在害怕对方出事，却还不愿承认自己已经把对方看得很重。",
		"category": "story",
		"doc_kind": "backbone",
		"state": "confirmed",
	},
	{
		"doc_id": "open_design_questions",
		"title": "当前待确认问题",
		"content": "这场争执戏的目标是让阿尔诺和赛琳的关系出现第一次真正松动，但不能直接和好。需要保留学院优等生与问题转学生之间的身份张力，同时让观众第一次看见他们嘴硬下面那层在意。",
		"category": "notes",
		"doc_kind": "decision_log",
		"state": "draft",
	},
]

var _menu_container: VBoxContainer = null
var _status_label: Label = null
var _result_label: RichTextLabel = null
var _window_host: Control = null
var _window_container: Control = null
var _wm: Node = null
var _current_test_task_id: String = ""

var _original_kb_documents: Array = []
var _original_dcm_state: Dictionary = {}
var _original_glm_state: Dictionary = {}
var _original_gm_state: Dictionary = {}
var _original_window_manager: Node = null


func _ready() -> void:
	_snapshot_runtime_state()
	_build_ui()
	_ensure_window_manager()
	_connect_runtime_signals()
	_ensure_original_kb_snapshot()
	_set_status("选择一种测试任务。场景会先模拟打开 Dev Work，真正启动小游戏需要你在 Dev Work 里再点一次。")
	_append_result_line("[color=#89b4fa]提示[/color] script_fill / emotion_tag 会走正式内容生成链路；如果后台 LLM 关闭，就会自动退回 fallback。")
	print("[TestMinigame] Ready. Formal flow test via DevWorkApp.")


func _exit_tree() -> void:
	_stop_running_task()
	_restore_baseline_state()
	var am: Node = get_node_or_null("/root/AppManager")
	if am != null and am.has_method("set_window_manager") and am.get("window_manager") == _wm:
		am.set_window_manager(_original_window_manager)


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color("#0f1724")
	add_child(bg)

	var root := HBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	var sidebar := PanelContainer.new()
	sidebar.custom_minimum_size = Vector2(440, 0)
	root.add_child(sidebar)

	var sidebar_margin := MarginContainer.new()
	sidebar_margin.add_theme_constant_override("margin_left", 20)
	sidebar_margin.add_theme_constant_override("margin_top", 20)
	sidebar_margin.add_theme_constant_override("margin_right", 20)
	sidebar_margin.add_theme_constant_override("margin_bottom", 20)
	sidebar.add_child(sidebar_margin)

	_menu_container = VBoxContainer.new()
	_menu_container.add_theme_constant_override("separation", 14)
	sidebar_margin.add_child(_menu_container)

	var title := Label.new()
	title.text = "小游戏正式链路测试"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color("#e2e8f0"))
	_menu_container.add_child(title)

	var intro := Label.new()
	intro.text = "这里不会直接跳小游戏。点击下面任一入口后，会先打开 Dev Work，再由你在 Dev Work 中点击任务。"
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_font_size_override("font_size", 18)
	intro.add_theme_color_override("font_color", Color("#94a3b8"))
	_menu_container.add_child(intro)

	for entry in MINIGAME_TESTS:
		var btn := Button.new()
		btn.text = "打开 Dev Work · %s" % str(entry.get("label", ""))
		btn.custom_minimum_size = Vector2(0, 54)
		btn.add_theme_font_size_override("font_size", 20)
		btn.pressed.connect(_on_prepare_test_pressed.bind(entry.duplicate(true)))
		_menu_container.add_child(btn)

	var sep := HSeparator.new()
	_menu_container.add_child(sep)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_font_size_override("font_size", 18)
	_status_label.add_theme_color_override("font_color", Color("#cbd5e1"))
	_status_label.text = ""
	_menu_container.add_child(_status_label)

	_result_label = RichTextLabel.new()
	_result_label.bbcode_enabled = true
	_result_label.fit_content = true
	_result_label.scroll_active = false
	_result_label.custom_minimum_size = Vector2(0, 220)
	_result_label.add_theme_font_size_override("normal_font_size", 17)
	_result_label.text = ""
	_menu_container.add_child(_result_label)

	_window_host = Control.new()
	_window_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_window_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_window_host)

	var stage_bg := ColorRect.new()
	stage_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage_bg.color = Color("#111827")
	_window_host.add_child(stage_bg)

	var stage_hint := Label.new()
	stage_hint.text = "Dev Work / 小游戏窗口会出现在这里"
	stage_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stage_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	stage_hint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage_hint.add_theme_font_size_override("font_size", 24)
	stage_hint.add_theme_color_override("font_color", Color("#334155"))
	_window_host.add_child(stage_hint)

	_window_container = Control.new()
	_window_container.name = "WindowContainer"
	_window_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_window_host.add_child(_window_container)


func _ensure_window_manager() -> void:
	_wm = WindowManagerClass.new()
	_wm.name = "WindowManager"
	add_child(_wm)
	_wm.set_window_container(_window_container)

	var am: Node = get_node_or_null("/root/AppManager")
	if am == null:
		push_error("[TestMinigame] AppManager autoload not found")
		return
	_original_window_manager = am.get("window_manager")
	if am.has_method("set_window_manager"):
		am.set_window_manager(_wm)
	else:
		am.window_manager = _wm


func _connect_runtime_signals() -> void:
	var mgr: Node = get_node_or_null("/root/MinigameManager")
	if mgr != null:
		if mgr.has_signal("minigame_started") and not mgr.minigame_started.is_connected(_on_minigame_started):
			mgr.minigame_started.connect(_on_minigame_started)
		if mgr.has_signal("minigame_cancelled") and not mgr.minigame_cancelled.is_connected(_on_minigame_cancelled):
			mgr.minigame_cancelled.connect(_on_minigame_cancelled)
		if mgr.has_signal("review_completed") and not mgr.review_completed.is_connected(_on_review_completed):
			mgr.review_completed.connect(_on_review_completed)


func _snapshot_runtime_state() -> void:
	var kb: Node = get_node_or_null("/root/KnowledgeBaseManager")
	if kb != null:
		_original_kb_documents = kb.documents.duplicate(true)

	var dcm: Node = get_node_or_null("/root/DevCycleManager")
	if dcm != null:
		_original_dcm_state = {
			"task_pool": dcm.get("_task_pool").duplicate(true),
			"order_queue": dcm.get("_order_queue").duplicate(true),
			"active_task_id": str(dcm.get("_active_task_id")),
			"active_order_id": str(dcm.get("_active_order_id")),
			"completed_task_ids": dcm.get("_completed_task_ids").duplicate(true),
		}

	var glm: Node = get_node_or_null("/root/GameLoopManager")
	if glm != null and glm.has_method("get_run_state"):
		_original_glm_state = glm.get_run_state()

	var gm: Node = get_node_or_null("/root/GameManager")
	if gm != null and gm.has_method("get_run_state"):
		_original_gm_state = gm.get_run_state()


func _ensure_original_kb_snapshot() -> void:
	if not _original_kb_documents.is_empty():
		return
	var kb: Node = get_node_or_null("/root/KnowledgeBaseManager")
	if kb != null and not kb.documents.is_empty():
		_original_kb_documents = kb.documents.duplicate(true)


func _restore_baseline_state() -> void:
	var kb: Node = get_node_or_null("/root/KnowledgeBaseManager")
	if kb != null:
		kb.documents = _original_kb_documents.duplicate(true)

	var dcm: Node = get_node_or_null("/root/DevCycleManager")
	if dcm != null and not _original_dcm_state.is_empty():
		dcm.set("_task_pool", _original_dcm_state.get("task_pool", {}).duplicate(true))
		dcm.set("_order_queue", _original_dcm_state.get("order_queue", []).duplicate(true))
		dcm.set("_active_task_id", str(_original_dcm_state.get("active_task_id", "")))
		dcm.set("_active_order_id", str(_original_dcm_state.get("active_order_id", "")))
		dcm.set("_completed_task_ids", _original_dcm_state.get("completed_task_ids", []).duplicate(true))
		dcm.tasks_updated.emit()

	var glm: Node = get_node_or_null("/root/GameLoopManager")
	if glm != null and glm.has_method("load_run_state") and not _original_glm_state.is_empty():
		glm.load_run_state(_original_glm_state.duplicate(true))

	var gm: Node = get_node_or_null("/root/GameManager")
	if gm != null and gm.has_method("load_run_state") and not _original_gm_state.is_empty():
		gm.load_run_state(_original_gm_state.duplicate(true))

	_current_test_task_id = ""


func _on_prepare_test_pressed(entry: Dictionary) -> void:
	_ensure_original_kb_snapshot()
	_stop_running_task()
	_restore_baseline_state()
	_prepare_fake_kb(entry)
	_prepare_test_progress_state()

	var task_def := _build_test_task(entry)
	var dcm: Node = get_node_or_null("/root/DevCycleManager")
	if dcm == null or not dcm.has_method("add_dynamic_task"):
		_set_status("DevCycleManager 不可用，无法注入测试任务。")
		return

	var added_id: String = dcm.add_dynamic_task(task_def)
	if added_id.is_empty():
		_set_status("测试任务注入失败。")
		return

	_current_test_task_id = added_id
	var window := _open_dev_work_app()
	if window == null:
		_set_status("Dev Work 打开失败，无法继续正式链路测试。")
		return

	_set_status("已准备任务「%s」。请在右侧 Dev Work 窗口里点击这条任务，再进入小游戏。" % str(task_def.get("title", "")))
	_append_result_line("[color=#a6e3a1]已注入[/color] %s" % str(task_def.get("title", "")))


func _prepare_fake_kb(entry: Dictionary) -> void:
	var kb: Node = get_node_or_null("/root/KnowledgeBaseManager")
	if kb == null:
		return
	if str(entry.get("type", "")) in ["script_fill", "emotion_tag"]:
		kb.documents = SCRIPT_FILL_FAKE_KB_DOCS.duplicate(true)


func _prepare_test_progress_state() -> void:
	var glm: Node = get_node_or_null("/root/GameLoopManager")
	if glm != null and glm.has_method("load_run_state"):
		var test_state: Dictionary = _original_glm_state.duplicate(true)
		test_state["max_ap_per_day"] = 3
		test_state["current_ap"] = 3
		glm.load_run_state(test_state)

	var gm: Node = get_node_or_null("/root/GameManager")
	if gm != null and gm.has_method("load_run_state"):
		gm.load_run_state(_original_gm_state.duplicate(true))

	var dcm: Node = get_node_or_null("/root/DevCycleManager")
	if dcm != null:
		dcm.set("_task_pool", {})
		dcm.set("_order_queue", [])
		dcm.set("_active_task_id", "")
		dcm.set("_active_order_id", "")
		dcm.set("_completed_task_ids", [])
		dcm.tasks_updated.emit()


func _build_test_task(entry: Dictionary) -> Dictionary:
	var task_id: String = "test_%s" % str(entry.get("type", "unknown"))
	var task: Dictionary = {
		"task_id": task_id,
		"title": str(entry.get("title", "测试任务")),
		"description": str(entry.get("description", "")),
		"task_type": "minigame",
		"minigame_type": str(entry.get("type", "")),
		"stat_changes": entry.get("stat_changes", {}).duplicate(true),
		"stress_cost": 1,
		"weight": int(entry.get("weight", 8)),
		"one_time": false,
	}
	if entry.get("kb_sources", []) is Array:
		task["kb_sources"] = entry.get("kb_sources", []).duplicate(true)
	if entry.get("post_task_work_order", {}) is Dictionary:
		task["post_task_work_order"] = entry.get("post_task_work_order", {}).duplicate(true)
	if entry.get("topic_config", {}) is Dictionary:
		task["topic_config"] = entry.get("topic_config", {}).duplicate(true)
	return task


func _open_dev_work_app() -> Control:
	var am: Node = get_node_or_null("/root/AppManager")
	if am == null or not am.has_method("launch_app"):
		return null
	return am.launch_app("dev_work", true)


func _stop_running_task() -> void:
	var mgr: Node = get_node_or_null("/root/MinigameManager")
	if mgr != null and mgr.has_method("is_running") and mgr.is_running():
		mgr.force_stop()


func _on_minigame_started(task_id: String, minigame_type: String) -> void:
	if task_id != _current_test_task_id:
		return
	_set_status("Dev Work 已启动任务，当前进入正式小游戏链路：%s" % minigame_type)
	_append_result_line("[color=#f9e2af]已启动[/color] %s" % minigame_type)


func _on_minigame_cancelled(task_id: String) -> void:
	if task_id != _current_test_task_id:
		return
	_set_status("小游戏已取消。任务会回到 Dev Work 中，可再次点击。")
	_append_result_line("[color=#f38ba8]已取消[/color] %s" % task_id)


func _on_review_completed(task_id: String, result: Dictionary) -> void:
	if task_id != _current_test_task_id:
		return

	if bool(result.get("cancelled", false)):
		_set_status("本次测试被中断，任务已恢复可用。")
		return

	var score: float = float(result.get("score", -1.0))
	if score >= 0.0:
		_set_status("本次正式链路已走完，评分 %.0f%%。如需重测，可回到 Dev Work 再点一次。 " % (score * 100.0))
	else:
		_set_status("本次正式链路已走完。")

	var parts: PackedStringArray = ["[color=#a6e3a1]链路完成[/color] %s" % task_id]
	if score >= 0.0:
		parts.append("得分：%.0f%%" % (score * 100.0))
	if result.has("correct_count"):
		parts.append("correct=%s" % str(result.get("correct_count", 0)))
	if result.has("total_items"):
		parts.append("total=%s" % str(result.get("total_items", 0)))
	if result.has("filled_slots"):
		parts.append("filled_slots=%s" % str(result.get("filled_slots", 0)))
	if result.has("slot_count"):
		parts.append("slot_count=%s" % str(result.get("slot_count", 0)))
	if result.has("filled_blanks"):
		parts.append("filled_blanks=%s" % str(result.get("filled_blanks", 0)))
	if result.has("blank_count"):
		parts.append("blank_count=%s" % str(result.get("blank_count", 0)))
	_append_result_line(" | ".join(parts))


func _set_status(text: String) -> void:
	if _status_label != null:
		_status_label.text = text


func _append_result_line(text: String) -> void:
	if _result_label == null:
		return
	var current: String = _result_label.text.strip_edges()
	if current.is_empty():
		_result_label.text = text
	else:
		_result_label.text = current + "\n" + text
