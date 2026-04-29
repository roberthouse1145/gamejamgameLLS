class_name KnowledgeBaseApp extends Control

## 统一文档模型的知识库 UI。
## 四个页签分别对应 world / characters / story / notes 分类。

## UI References
@onready var close_button: Button = %CloseButton
@onready var bookmark_list: VBoxContainer = %BookmarkList
@onready var content_container: MarginContainer = %ContentContainer

# Category Panels（复用原场景节点名，但映射到新分类）
@onready var world_panel: Control = %WorldPanel
@onready var character_panel: Control = %CharacterPanel
@onready var beat_panel: Control = %BeatPanel       # 现在是 story 分类
@onready var asset_panel: Control = %AssetPanel     # 现在是 notes 分类

# Canvases
@onready var world_canvas: Control = %WorldCanvas
@onready var character_canvas: Control = %CharacterCanvas
@onready var beat_canvas: Control = %BeatCanvas      # story canvas
@onready var note_canvas: Control = %NoteCanvas

# Add buttons
@onready var add_world_btn: Button = %AddWorldBtn
@onready var add_character_btn: Button = %AddCharacterBtn
@onready var add_beat_btn: Button = %AddBeatBtn
@onready var add_note_btn: Button = %AddNoteBtn

var _category_panels: Array[Control] = []

## 页签名 → category 映射
const TAB_CONFIG: Array[Dictionary] = [
	{"label": "🌍 世界观设定 (World)", "category": "world"},
	{"label": "👤 角色设定 (Characters)", "category": "characters"},
	{"label": "📖 故事剧本 (Story)", "category": "story"},
	{"label": "📝 灵感备忘 (Notes)", "category": "notes"},
]

const DraggableCardScene = preload("res://scenes/apps/knowledge_base/draggable_card.tscn")

signal close_requested

func _ready() -> void:
	_category_panels = [world_panel, character_panel, beat_panel, asset_panel]
	_connect_signals()

	if KnowledgeBaseManager.documents.size() > 0:
		_setup_ui()
	else:
		KnowledgeBaseManager.data_loaded.connect(func(): _setup_ui(), CONNECT_ONE_SHOT)

func _setup_ui() -> void:
	# Build sidebar bookmarks
	for child in bookmark_list.get_children():
		child.queue_free()

	for i in range(TAB_CONFIG.size()):
		var btn := Button.new()
		btn.text = TAB_CONFIG[i]["label"]
		btn.add_theme_font_size_override("font_size", 14)
		btn.custom_minimum_size = Vector2(0, 48)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT

		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.2, 0.2, 0.25, 1)
		style.corner_radius_top_left = 8
		style.corner_radius_bottom_left = 8
		style.content_margin_left = 12
		btn.add_theme_stylebox_override("normal", style)

		var hover_style: StyleBoxFlat = style.duplicate()
		hover_style.bg_color = Color(0.3, 0.3, 0.35, 1)
		btn.add_theme_stylebox_override("hover", hover_style)

		btn.pressed.connect(_on_category_selected.bind(i))
		bookmark_list.add_child(btn)

	# Hide all panels initially
	for panel in _category_panels:
		if panel:
			panel.visible = false

	_on_category_selected(0)
	_refresh_all()

func _refresh_all() -> void:
	_refresh_canvas(world_canvas, "world")
	_refresh_canvas(character_canvas, "characters")
	_refresh_canvas(beat_canvas, "story")
	_refresh_canvas(note_canvas, "notes")

# =============================================================================
# Generic canvas builder — 根据 category 动态生成卡片
# =============================================================================

func _refresh_canvas(canvas: Control, category: String) -> void:
	for child in canvas.get_children():
		child.queue_free()

	var docs: Array[Dictionary] = KnowledgeBaseManager.get_documents(category)
	for doc in docs:
		_build_doc_card(canvas, doc, category)

func _build_doc_card(canvas: Control, doc: Dictionary, category: String) -> void:
	var card = DraggableCardScene.instantiate()
	canvas.add_child(card)

	var pos_x: float = doc.get("position_x", randf_range(50.0, 400.0))
	var pos_y: float = doc.get("position_y", randf_range(50.0, 400.0))
	card.setup(doc.get("doc_id", ""), doc.get("author", "player"), pos_x, pos_y)

	card.card_moved.connect(func(_moved_card, new_pos: Vector2):
		doc["position_x"] = new_pos.x
		doc["position_y"] = new_pos.y
		KnowledgeBaseManager.save_data()
	)

	var vbox: VBoxContainer = card.content_vbox

	# --- Header: title + delete ---
	var header := HBoxContainer.new()
	vbox.add_child(header)

	var title_edit := LineEdit.new()
	title_edit.text = doc.get("title", "")
	title_edit.placeholder_text = _get_title_placeholder(category)
	title_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_edit.add_theme_font_size_override("font_size", 16)
	title_edit.text_changed.connect(func(t: String): doc["title"] = t)
	header.add_child(title_edit)

	var del_btn := Button.new()
	del_btn.text = "×"
	del_btn.modulate = Color.RED
	del_btn.pressed.connect(func():
		KnowledgeBaseManager.delete_document(doc.get("doc_id", ""))
		_refresh_canvas(canvas, category)
	)
	header.add_child(del_btn)

	# --- ID display ---
	var id_box := HBoxContainer.new()
	vbox.add_child(id_box)
	var id_lbl := Label.new()
	id_lbl.text = "ID: "
	id_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	id_box.add_child(id_lbl)
	var id_val := Label.new()
	id_val.text = doc.get("doc_id", "")
	id_val.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	id_val.add_theme_font_size_override("font_size", 12)
	id_box.add_child(id_val)

	vbox.add_child(HSeparator.new())

	# --- Content: free-form text area ---
	var placeholder: String = _get_content_placeholder(category)
	var edit := TextEdit.new()
	edit.text = doc.get("content", "")
	edit.placeholder_text = placeholder
	edit.custom_minimum_size = Vector2(0, 200)
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	edit.text_changed.connect(func(): doc["content"] = edit.text)
	vbox.add_child(edit)

	# --- Tags display/edit ---
	var tags: Array = doc.get("tags", [])
	var tag_lbl := Label.new()
	tag_lbl.text = "标签: " + ", ".join(tags) if tags.size() > 0 else ""
	tag_lbl.add_theme_font_size_override("font_size", 11)
	tag_lbl.add_theme_color_override("font_color", Color(0.5, 0.6, 0.7))
	vbox.add_child(tag_lbl)

# =============================================================================
# Add new document
# =============================================================================

func _add_new_document(category: String, canvas: Control, spawn_pos: Vector2 = Vector2(50, 50)) -> void:
	var doc_id: String = KnowledgeBaseManager.generate_doc_id(category)
	var title: String = _get_default_title(category)
	KnowledgeBaseManager.upsert_document(doc_id, title, "", category, [], "player")

	# Set spawn position
	var doc: Dictionary = KnowledgeBaseManager.get_document(doc_id)
	if not doc.is_empty():
		doc["position_x"] = spawn_pos.x
		doc["position_y"] = spawn_pos.y

	_refresh_canvas(canvas, category)

# =============================================================================
# Placeholders & defaults per category
# =============================================================================

func _get_title_placeholder(category: String) -> String:
	match category:
		"world": return "主题/概念名称"
		"characters": return "角色名"
		"story": return "章节/剧情标题"
		"notes": return "备忘标题"
	return "标题"

func _get_content_placeholder(category: String) -> String:
	match category:
		"world":
			return "在这里写下游戏的世界观、核心概要、基调等。\n比如：故事发生在什么时代？核心矛盾是什么？情感基调是温暖还是沉重？"
		"characters":
			return "在这里写角色的设定。\n比如性格、说话习惯、经历、和其他角色的关系、动机、外貌特征等。\n随便写，碎片化也行。"
		"story":
			return "在这里写故事大纲或具体场景剧本。\n可以用自然语言描述剧情走向，也可以用内联舞台指示：\n[背景: 教室 | BGM: 轻松日常]\n[林夏出现, 表情: 开心]\n林夏：\"早上好呀！\""
		"notes":
			return "随手记录灵感、讨论备忘、待办想法等。"
	return ""

func _get_default_title(category: String) -> String:
	match category:
		"world": return "新文档"
		"characters": return "新角色"
		"story": return "新章节"
		"notes": return "新备忘"
	return "新文档"

# =============================================================================
# Signals
# =============================================================================

func _connect_signals() -> void:
	close_button.pressed.connect(func(): close_requested.emit())
	%SaveButton.pressed.connect(_save_current_project)

	add_world_btn.pressed.connect(func(): _add_new_document("world", world_canvas))
	add_character_btn.pressed.connect(func(): _add_new_document("characters", character_canvas))
	add_beat_btn.pressed.connect(func(): _add_new_document("story", beat_canvas))
	add_note_btn.pressed.connect(func(): _add_new_document("notes", note_canvas))

	# Double-click on canvas to add new card
	world_canvas.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
			_add_new_document("world", world_canvas, world_canvas.get_local_mouse_position())
			world_canvas.accept_event()
	)
	character_canvas.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
			_add_new_document("characters", character_canvas, character_canvas.get_local_mouse_position())
			character_canvas.accept_event()
	)
	beat_canvas.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
			_add_new_document("story", beat_canvas, beat_canvas.get_local_mouse_position())
			beat_canvas.accept_event()
	)
	note_canvas.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
			_add_new_document("notes", note_canvas, note_canvas.get_local_mouse_position())
			note_canvas.accept_event()
	)


func _save_current_project() -> void:
	if StorageManager.current_project == null:
		push_warning("KnowledgeBaseApp: 当前没有可保存的项目")
		return

	var save_err: Error = StorageManager.save_project(StorageManager.current_project)
	if save_err != OK:
		push_error("KnowledgeBaseApp: 保存项目失败，error=%d" % save_err)

func _on_category_selected(index: int) -> void:
	for i in range(_category_panels.size()):
		if _category_panels[i]:
			_category_panels[i].visible = (i == index)

	# Highlight selected bookmark
	for i in range(bookmark_list.get_child_count()):
		var btn: Button = bookmark_list.get_child(i)
		var style: StyleBoxFlat = btn.get_theme_stylebox("normal").duplicate()
		if i == index:
			style.bg_color = Color(0.4, 0.4, 0.5, 1)
			style.border_width_right = 4
			style.border_color = Color(0.8, 0.8, 0.9, 1)
		else:
			style.bg_color = Color(0.2, 0.2, 0.25, 1)
			style.border_width_right = 0
		btn.add_theme_stylebox_override("normal", style)
