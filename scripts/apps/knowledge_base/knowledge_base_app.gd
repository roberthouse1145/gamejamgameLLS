class_name KnowledgeBaseApp extends Control

## UI References
@onready var close_button: Button = %CloseButton
@onready var bookmark_list: VBoxContainer = %BookmarkList
@onready var content_container: MarginContainer = %ContentContainer

# Category Panels
@onready var world_panel: Control = %WorldPanel
@onready var character_panel: Control = %CharacterPanel
@onready var character_list: ItemList = %CharacterList
@onready var character_form: Control = %CharacterForm
@onready var add_character_btn: Button = %AddCharacterBtn
@onready var beat_panel: Control = %BeatPanel
@onready var beat_list: ItemList = %BeatList
@onready var beat_form: Control = %BeatForm
@onready var add_beat_btn: Button = %AddBeatBtn
@onready var asset_panel: Control = %AssetPanel

var _category_panels: Array[Control] = []

const CATEGORIES: Array[String] = [
	"🌍 我们的世界 (World)",
	"👤 角色灵感设定 (Characters)",
	"📖 剧情剧本卡 (Story Beats)",
	"🎨 美术看板 (Assets)"
]


signal close_requested

func _ready() -> void:
	_category_panels = [world_panel, character_panel, beat_panel, asset_panel]
	
	if KnowledgeBaseManager.current_data:
		_setup_ui()
	else:
		KnowledgeBaseManager.data_loaded.connect(func(_d): _setup_ui())
	
	_connect_signals()

func _setup_ui() -> void:
	# Add categories to bookmark list
	for child in bookmark_list.get_children():
		child.queue_free()
		
	for i in range(CATEGORIES.size()):
		var btn = Button.new()
		btn.text = CATEGORIES[i]
		btn.add_theme_font_size_override("font_size", 14)
		btn.custom_minimum_size = Vector2(0, 48)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		
		# Bookmark style
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.2, 0.2, 0.25, 1)
		style.corner_radius_top_left = 8
		style.corner_radius_bottom_left = 8
		style.content_margin_left = 12
		btn.add_theme_stylebox_override("normal", style)
		
		var hover_style = style.duplicate()
		hover_style.bg_color = Color(0.3, 0.3, 0.35, 1)
		btn.add_theme_stylebox_override("hover", hover_style)
		
		btn.pressed.connect(func(): _on_category_selected(i))
		bookmark_list.add_child(btn)
	
	# Hide all panels initially
	for panel in _category_panels:
		if panel:
			panel.visible = false
	
	# Select first category automatically
	_on_category_selected(0)
		
	_build_world_panel()
	_refresh_character_list()
	_refresh_beat_list()

func _build_world_panel() -> void:
	# Clear existing children except the title label
	for i in range(1, world_panel.get_child_count()):
		world_panel.get_child(i).queue_free()
		
	var data: KnowledgeBaseData = KnowledgeBaseManager.current_data
	if not data: return
	
	_add_field_ui(world_panel, "游戏名称 (Game Title)", data.game_title, false, func(t): data.game_title = t)
	
	var placeholder = "【助理留言】：在这里写下你想做的游戏吧！\n不用写得太完整，随便写写：\n1. 这是一个什么样的故事？世界背景是什么样的？\n2. 游戏大概的基调是轻松的还是沉重的？\n\n我们会一起把这些点子变成现实的！"
	_add_notes_field_with_tags(world_panel, "核心策划案 (Core Concept)", data.synopsis, placeholder,
		["[+ 核心玩法]", "[+ 题材风格]", "[+ 情感基调]", "[+ 视觉风格]", "[+ 特殊机制]"],
		func(t):
			data.synopsis = t
			# Merging genre, tone, art_style, world_rules into one concept text
	)

func _add_field_ui(parent: Control, label_text: String, initial_val: String, is_multiline: bool, callback: Callable) -> void:
	var vbox = VBoxContainer.new()
	var label = Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(label)
	
	if is_multiline:
		var edit = TextEdit.new()
		edit.text = initial_val
		edit.custom_minimum_size = Vector2(0, 120)
		edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		edit.text_changed.connect(func(): callback.call(edit.text))
		vbox.add_child(edit)
	else:
		var edit = LineEdit.new()
		edit.text = initial_val
		edit.text_changed.connect(func(new_text): callback.call(new_text))
		vbox.add_child(edit)
	
	# Add spacer
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	vbox.add_child(spacer)
	
	parent.add_child(vbox)

const DraggableCardScene = preload("res://scenes/apps/knowledge_base/draggable_card.tscn")

# --- Characters ---
@onready var character_canvas: Control = %CharacterCanvas

func _refresh_character_list() -> void:
	for child in character_canvas.get_children():
		child.queue_free()
		
	var data: KnowledgeBaseData = KnowledgeBaseManager.current_data
	if not data: return
	
	for i in range(data.characters.size()):
		_build_character_card(data.characters[i], i)

func _build_character_card(c: Dictionary, index: int) -> void:
	var data: KnowledgeBaseData = KnowledgeBaseManager.current_data
	
	var card = DraggableCardScene.instantiate()
	character_canvas.add_child(card)
	
	var pos_x = c.get("position_x", randi_range(50, 400))
	var pos_y = c.get("position_y", randi_range(50, 400))
	card.setup(c.get("character_id", ""), c.get("author", "player"), pos_x, pos_y)
	
	card.card_moved.connect(func(_moved_card, new_pos):
		c["position_x"] = new_pos.x
		c["position_y"] = new_pos.y
		KnowledgeBaseManager.save_data()
	)
	
	var vbox = card.content_vbox
	
	# Header
	var header = HBoxContainer.new()
	vbox.add_child(header)
	
	var name_edit = LineEdit.new()
	name_edit.text = c.get("full_name", "Unnamed")
	name_edit.placeholder_text = "角色全名"
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.add_theme_font_size_override("font_size", 16)
	name_edit.text_changed.connect(func(t): c["full_name"] = t)
	header.add_child(name_edit)
	
	var del_btn = Button.new()
	del_btn.text = "×"
	del_btn.modulate = Color.RED
	del_btn.pressed.connect(func():
		data.characters.remove_at(index)
		_refresh_character_list()
	)
	header.add_child(del_btn)
	
	var id_box = HBoxContainer.new()
	vbox.add_child(id_box)
	var id_lbl = Label.new()
	id_lbl.text = "ID: "
	id_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	id_box.add_child(id_lbl)
	var id_edit = LineEdit.new()
	id_edit.text = c.get("character_id", "")
	id_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	id_edit.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	id_edit.text_changed.connect(func(t): c["character_id"] = t)
	id_box.add_child(id_edit)
	
	var sep = HSeparator.new()
	vbox.add_child(sep)
	
	var placeholder = "【助理留言】：TA是一个什么样的人呢？\n比如性格、一些经历、跟你或其他人的关系、说话的小习惯、害怕什么、喜欢什么。\n不用写作完整的长篇大论，碎片化的句子也行，只要是你觉得有趣的设定都可以写在这里哦！"
	_add_notes_field_with_tags(vbox, "人物便签", c.get("personality", ""), placeholder,
		["[+ 说话习惯]", "[+ 隐藏的秘密]", "[+ 最大的弱点]", "[+ 喜欢/讨厌]", "[+ 核心动机]"],
		func(t): c["personality"] = t
	)

func _add_new_character(spawn_pos: Vector2 = Vector2(50, 50)) -> void:
	var data: KnowledgeBaseData = KnowledgeBaseManager.current_data
	if not data: return
	data.characters.append({
		"character_id": "char_" + str(Time.get_ticks_msec()).substr(3, 10),
		"full_name": "New Character",
		"personality": "",
		"author": "player",
		"position_x": spawn_pos.x,
		"position_y": spawn_pos.y
	})
	_refresh_character_list()

# --- Beats ---
@onready var beat_canvas: Control = %BeatCanvas

func _refresh_beat_list() -> void:
	for child in beat_canvas.get_children():
		child.queue_free()
		
	var data: KnowledgeBaseData = KnowledgeBaseManager.current_data
	if not data: return
	
	for i in range(data.beats.size()):
		_build_beat_card(data.beats[i], i)

func _build_beat_card(b: Dictionary, index: int) -> void:
	var data: KnowledgeBaseData = KnowledgeBaseManager.current_data
	
	var card = DraggableCardScene.instantiate()
	beat_canvas.add_child(card)
	
	var pos_x = b.get("position_x", randi_range(50, 400))
	var pos_y = b.get("position_y", randi_range(50, 400))
	card.setup(b.get("beat_id", ""), b.get("author", "player"), pos_x, pos_y)
	
	card.card_moved.connect(func(_moved_card, new_pos):
		b["position_x"] = new_pos.x
		b["position_y"] = new_pos.y
		KnowledgeBaseManager.save_data()
	)
	
	var vbox = card.content_vbox
	
	# Header
	var header = HBoxContainer.new()
	vbox.add_child(header)
	
	var title_edit = LineEdit.new()
	title_edit.text = b.get("title", "Untitled Beat")
	title_edit.placeholder_text = "剧情片段标题"
	title_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_edit.add_theme_font_size_override("font_size", 16)
	title_edit.text_changed.connect(func(t): b["title"] = t)
	header.add_child(title_edit)
	
	var del_btn = Button.new()
	del_btn.text = "×"
	del_btn.modulate = Color.RED
	del_btn.pressed.connect(func():
		data.beats.remove_at(index)
		_refresh_beat_list()
	)
	header.add_child(del_btn)
	
	var id_box = HBoxContainer.new()
	vbox.add_child(id_box)
	var id_lbl = Label.new()
	id_lbl.text = "ID: "
	id_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	id_box.add_child(id_lbl)
	var id_edit = LineEdit.new()
	id_edit.text = b.get("beat_id", "")
	id_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	id_edit.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	id_edit.text_changed.connect(func(t): b["beat_id"] = t)
	id_box.add_child(id_edit)
	
	var sep = HSeparator.new()
	vbox.add_child(sep)
	
	var placeholder = "【助理留言】：想好这段剧情要怎么发展了吗？\n你可以写大纲，也可以直接写对白，或者用 [标签: 值] 的形式标注场景和舞台指示。\n\n[示例]\n[背景: 教室 | BGM: 轻松日常]\n[林夏出现, 表情: 开心]\n林夏：\"早上好呀！\""
	_add_notes_field_with_tags(vbox, "剧本便签", b.get("content", ""), placeholder,
		["[+ 环境氛围]", "[+ 核心冲突]", "[+ 情绪转折]", "[+ 隐藏细节]"],
		func(t): b["content"] = t
	)

func _add_new_beat(spawn_pos: Vector2 = Vector2(50, 50)) -> void:
	var data: KnowledgeBaseData = KnowledgeBaseManager.current_data
	if not data: return
	data.beats.append({
		"beat_id": "beat_" + str(Time.get_ticks_msec()).substr(3, 10),
		"title": "New Beat",
		"content": "",
		"author": "player",
		"position_x": spawn_pos.x,
		"position_y": spawn_pos.y
	})
	_refresh_beat_list()

func _add_notes_field_with_tags(parent: Control, label_text: String, initial_val: String, placeholder: String, tags: Array[String], callback: Callable) -> TextEdit:
	var vbox = VBoxContainer.new()
	
	var label = Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(label)
	
	var edit = TextEdit.new()
	edit.text = initial_val
	edit.placeholder_text = placeholder
	edit.custom_minimum_size = Vector2(0, 200)
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	edit.text_changed.connect(func(): callback.call(edit.text))
	vbox.add_child(edit)
	
	var flow = HFlowContainer.new()
	for tag in tags:
		var btn = Button.new()
		btn.text = tag
		btn.add_theme_font_size_override("font_size", 12)
		btn.pressed.connect(func():
			edit.text += "\n" + tag + ": "
			edit.set_caret_line(edit.get_line_count())
			edit.set_caret_column(edit.get_line(edit.get_line_count() - 1).length())
			edit.grab_focus()
			callback.call(edit.text)
		)
		flow.add_child(btn)
	vbox.add_child(flow)
	
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	vbox.add_child(spacer)
	
	parent.add_child(vbox)
	return edit

func _connect_signals() -> void:
	close_button.pressed.connect(func(): close_requested.emit())
	%SaveButton.pressed.connect(func(): KnowledgeBaseManager.save_data())
	
	add_character_btn.pressed.connect(_add_new_character)
	add_beat_btn.pressed.connect(_add_new_beat)
	
	character_canvas.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
			_add_new_character(character_canvas.get_local_mouse_position())
			character_canvas.accept_event()
	)
	
	beat_canvas.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
			_add_new_beat(beat_canvas.get_local_mouse_position())
			beat_canvas.accept_event()
	)

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
