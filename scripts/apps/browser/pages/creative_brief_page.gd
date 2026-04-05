extends MarginContainer
## AGJ 项目立案页面 — 玩家填写创意企划书
## 包含: 作品名称、类型（含自定义）、基调标签、故事大纲
## 审核 LLM 校验后写入 KB，触发林夏反馈

const AIServiceClass = preload("res://scripts/llm/AIService.gd")

# ── 视觉常量 ──────────────────────────────────────────────────────────────
const C_PAGE_BG := Color("#080B12")
const C_HERO_BG := Color("#0A0D18")
const C_CARD_BG := Color("#0D1020")
const C_CARD_BORDER := Color("#1A1F35")
const C_RULE := Color("#141828")
const C_ACCENT := Color("#3D6FFF")
const C_ORANGE := Color("#E8622A")
const C_GREEN := Color("#28C76F")
const C_WHITE := Color("#ECEEF8")
const C_DIM := Color("#7A82A0")
const C_MUTED := Color("#3D4460")
const C_ACCENT_TEXT := Color("#5B8AFF")
const C_FIELD_BG := Color("#0A0D1A")
const C_FIELD_BORDER := Color("#1A1F35")
const C_FIELD_FOCUS := Color("#3D6FFF")
const C_FIELD_TEXT := Color("#D8DCF0")
const C_FIELD_PH := Color("#3D4460")
const C_ERROR := Color("#E84040")
const C_ERROR_BG := Color("#180A0A")
const C_SUCCESS := Color("#28C76F")
const C_SUCCESS_BG := Color("#0A1810")
const C_INFO_BG := Color("#0A0D1A")
const C_TAG_BG := Color("#141828")
const C_TAG_SELECTED := Color("#1A2548")
const C_TAG_BORDER := Color("#2A3158")
const C_TAG_SELECTED_BORDER := Color("#3D6FFF")

# ── 数据常量 ──────────────────────────────────────────────────────────────
const FIXED_THEME: String = "日式魔法异世界学院"
const MAX_TITLE_LEN: int = 20
const MAX_OUTLINE_LEN: int = 200

const GENRE_OPTIONS: PackedStringArray = [
	"恋爱 Gal",
	"乙女",
	"悬疑推理",
	"冒险奇幻",
	"日常治愈",
]

const TONE_TAGS: PackedStringArray = [
	"甜蜜", "热血", "日常", "虐心",
	"搞笑", "黑暗", "治愈", "史诗",
]

const MIN_TAGS: int = 1
const MAX_TAGS: int = 3

# ── 审核 Prompt ──────────────────────────────────────────────────────────
const REVIEW_SYSTEM_PROMPT: String = """你负责审核 GameJam 项目立案页面中的企划信息。这是一个纯合规检查，不涉及创意评价。

【审核原则】
- 默认通过，只有明确违规才拒绝
- 拿不准时一律通过

【拒绝条件】（仅限以下明确情形）
- 包含色情、暴力、血腥、恐怖等 NSFW 内容
- 包含歧视、仇恨、反社会言论
- 作品名称或大纲为纯乱码、纯符号、纯数字
- 大纲内容与"日式魔法异世界学院"主题完全无关（比如"火星殖民"）

【不应拒绝的情况】
- 常见创意方向（恋爱、悬疑、冒险等）
- 简短或模糊的大纲（可以通过，由后续流程补强）
- 自定义类型名称（只要不违规就通过）
- 大纲留空的情况（这种情况不会提交给你审核）

仅返回 JSON：
{
  "approved": true/false,
  "reason": "拒绝原因（通过时留空字符串）"
}"""

# ── 大纲生成 Prompt ────────────────────────────────────────────────────
const OUTLINE_SYSTEM_PROMPT_TEMPLATE: String = """你是林夏，正在帮搭档为 GameJam 参赛作品构思故事大纲。

【你是谁】
{{heroine/lin_xia_core}}

【比赛主题】日式魔法异世界学院
【比赛约束——必须遵守】
- 这是一个 AVG（视觉小说），不能设计需要复杂系统的玩法
- 总开发周期约 45 天，两人团队（你负责美术/设计，搭档负责策划/文案/代码）
- 规模控制在 3-5 章、每章 10-20 分钟游玩时长
- 可用素材：官方素材包（魔法学院风格立绘、背景、UI）
- 不要设计需要大量原创美术资源的内容

【要求】
- 150字以内
- 包含：主角设定（1句）、核心冲突（1句）、大致走向（1-2句）
- 风格贴合所选类型和基调
- 不要写得太具体，留出展开空间
- 只输出大纲文本，不要加标题或格式标记"""

# ── 状态 ─────────────────────────────────────────────────────────────────
var _browser_app: Node = null
var _page_payload: Dictionary = {}
var _submission_locked: bool = false
var _is_reviewing: bool = false
var _is_generating_outline: bool = false

# LLM 服务
var _review_service: Node = null
var _review_enabled: bool = false
var _pending_review_id: String = ""

var _outline_service: Node = null
var _outline_enabled: bool = false
var _pending_outline_id: String = ""

# ── UI 引用 ──────────────────────────────────────────────────────────────
var _root_vbox: VBoxContainer
var _scroll: ScrollContainer
var _form_container: VBoxContainer

var _title_input: LineEdit
var _genre_select: OptionButton
var _genre_custom_input: LineEdit
var _genre_custom_row: Control
var _tag_checks: Array[CheckBox] = []
var _outline_edit: TextEdit
var _outline_char_label: Label
var _submit_button: Button
var _status_container: PanelContainer
var _status_label: Label
var _status_dot: Label


func _ready() -> void:
	_root_vbox = $Root
	_build_page()
	_ensure_review_service()
	_ensure_outline_service()
	_set_status("info", "请填写项目立案信息。")


func configure_browser_page(browser_app: Node, page_payload: Dictionary) -> void:
	_browser_app = browser_app
	_page_payload = page_payload.duplicate(true)
	_load_existing_values()
	if not _submission_locked:
		call_deferred("_focus_first_input")


# ═════════════════════════════════════════════════════════════════════════
#region 页面构建
# ═════════════════════════════════════════════════════════════════════════

func _build_page() -> void:
	var bg := ColorRect.new()
	bg.color = C_PAGE_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	move_child(bg, 0)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_root_vbox.add_child(_scroll)

	var page_vbox := VBoxContainer.new()
	page_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_vbox.add_theme_constant_override("separation", 0)
	_scroll.add_child(page_vbox)

	page_vbox.add_child(_build_navbar())
	page_vbox.add_child(_build_hero())
	page_vbox.add_child(_build_divider_rule())

	var content_wrap := MarginContainer.new()
	content_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_wrap.add_theme_constant_override("margin_left", 60)
	content_wrap.add_theme_constant_override("margin_right", 60)
	content_wrap.add_theme_constant_override("margin_top", 40)
	page_vbox.add_child(content_wrap)

	var content_vbox := VBoxContainer.new()
	content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_vbox.add_theme_constant_override("separation", 36)
	content_wrap.add_child(content_vbox)

	content_vbox.add_child(_build_theme_notice())
	content_vbox.add_child(_build_form_section())
	content_vbox.add_child(_build_status_bar())
	content_vbox.add_child(_build_footer())
	content_vbox.add_child(_spacer(24))

#endregion


# ═════════════════════════════════════════════════════════════════════════
#region UI 组件
# ═════════════════════════════════════════════════════════════════════════

func _build_navbar() -> Control:
	var navbar := PanelContainer.new()
	navbar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = C_PAGE_BG
	style.content_margin_left = 60
	style.content_margin_right = 60
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	navbar.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	navbar.add_child(hbox)

	var logo := Label.new()
	logo.text = "AGJ"
	logo.add_theme_font_size_override("font_size", 30)
	logo.add_theme_color_override("font_color", C_WHITE)
	hbox.add_child(logo)

	var year := Label.new()
	year.text = "2027"
	year.add_theme_font_size_override("font_size", 16)
	year.add_theme_color_override("font_color", C_ORANGE)
	year.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(year)

	hbox.add_child(_nav_separator())
	hbox.add_child(_nav_link_highlight("PROJECT BRIEF"))
	hbox.add_child(_nav_link("SCHEDULE", "gamejam://schedule"))
	hbox.add_child(_nav_link("NEWS", "gamejam://news"))
	hbox.add_child(_nav_link("FAQ", "gamejam://faq"))

	return navbar


func _build_hero() -> Control:
	var hero := PanelContainer.new()
	hero.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = C_HERO_BG
	style.content_margin_left = 60
	style.content_margin_right = 60
	style.content_margin_top = 48
	style.content_margin_bottom = 48
	hero.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	hero.add_child(vbox)

	var tag_row := HBoxContainer.new()
	tag_row.add_theme_constant_override("separation", 8)
	vbox.add_child(tag_row)
	tag_row.add_child(_make_badge("新星赛道", C_ACCENT))
	tag_row.add_child(_make_badge("叙事组", C_GREEN))

	vbox.add_child(_spacer(20))

	var title := Label.new()
	title.text = "PROJECT BRIEF"
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", C_WHITE)
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "项目立案"
	subtitle.add_theme_font_size_override("font_size", 22)
	subtitle.add_theme_color_override("font_color", C_ACCENT_TEXT)
	vbox.add_child(subtitle)

	vbox.add_child(_spacer(24))

	var desc := Label.new()
	desc.text = "在开始开发前，请提交你的作品企划。企划将作为开发方向的基础，提交后不可修改。"
	desc.add_theme_font_size_override("font_size", 18)
	desc.add_theme_color_override("font_color", C_DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(desc)

	return hero


func _build_theme_notice() -> Control:
	var card := _make_card()
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	card.add_child(vbox)

	vbox.add_child(_section_header("比赛主题", "THEME"))
	vbox.add_child(_h_rule())

	var notice := Label.new()
	notice.text = "本届叙事组主题已公布。所有参赛作品必须围绕以下主题展开："
	notice.add_theme_font_size_override("font_size", 18)
	notice.add_theme_color_override("font_color", C_DIM)
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(notice)

	var theme_label := Label.new()
	theme_label.text = "「 %s 」" % FIXED_THEME
	theme_label.add_theme_font_size_override("font_size", 28)
	theme_label.add_theme_color_override("font_color", C_ACCENT_TEXT)
	theme_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	theme_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(theme_label)

	var sub := Label.new()
	sub.text = "你可以自由选择作品类型和基调，但故事背景必须设定在魔法学院世界中。"
	sub.add_theme_font_size_override("font_size", 16)
	sub.add_theme_color_override("font_color", C_MUTED)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(sub)

	return card


func _build_form_section() -> Control:
	var card := _make_card()
	_form_container = VBoxContainer.new()
	_form_container.add_theme_constant_override("separation", 28)
	card.add_child(_form_container)

	_form_container.add_child(_section_header("项目信息", "DETAILS"))
	_form_container.add_child(_h_rule())

	# ❶ 作品名称
	_title_input = _make_line_edit("为你的作品起个名字", MAX_TITLE_LEN)
	_form_container.add_child(_field_group("作品名称", "TITLE",
		"%d 字以内。" % MAX_TITLE_LEN, _title_input))

	# ❷ 作品类型
	_form_container.add_child(_build_genre_field())

	# ❸ 基调标签
	_form_container.add_child(_build_tone_tags_field())

	# ❹ 故事大纲
	_form_container.add_child(_build_outline_field())

	# 提交按钮
	_submit_button = Button.new()
	_submit_button.text = "提交立案"
	_submit_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_submit_button.custom_minimum_size.y = 50
	_submit_button.add_theme_font_size_override("font_size", 20)
	_style_primary_button(_submit_button)
	_submit_button.pressed.connect(_on_submit_clicked)
	_form_container.add_child(_submit_button)

	return card


func _build_genre_field() -> Control:
	var group := VBoxContainer.new()
	group.add_theme_constant_override("separation", 8)

	var label_row := HBoxContainer.new()
	label_row.add_theme_constant_override("separation", 8)
	group.add_child(label_row)
	var primary := Label.new()
	primary.text = "作品类型"
	primary.add_theme_font_size_override("font_size", 20)
	primary.add_theme_color_override("font_color", C_WHITE)
	label_row.add_child(primary)
	var secondary := Label.new()
	secondary.text = "GENRE"
	secondary.add_theme_font_size_override("font_size", 15)
	secondary.add_theme_color_override("font_color", C_MUTED)
	secondary.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label_row.add_child(secondary)

	var hint := Label.new()
	hint.text = "选择预设类型或自定义。"
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", C_MUTED)
	group.add_child(hint)

	_genre_select = OptionButton.new()
	_genre_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_genre_select.custom_minimum_size.y = 46
	_style_option_button(_genre_select)
	_genre_select.clear()
	_genre_select.add_item("- 请选择类型 -")
	_genre_select.set_item_disabled(0, true)
	for g in GENRE_OPTIONS:
		_genre_select.add_item(g)
	_genre_select.add_item("自定义...")
	_genre_select.item_selected.connect(_on_genre_selected)
	group.add_child(_genre_select)

	# 自定义类型输入行（默认隐藏）
	_genre_custom_row = HBoxContainer.new()
	_genre_custom_row.add_theme_constant_override("separation", 8)
	_genre_custom_row.visible = false
	group.add_child(_genre_custom_row)

	var custom_label := Label.new()
	custom_label.text = "自定义："
	custom_label.add_theme_font_size_override("font_size", 18)
	custom_label.add_theme_color_override("font_color", C_DIM)
	custom_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_genre_custom_row.add_child(custom_label)

	_genre_custom_input = _make_line_edit("输入你的类型名称", 10)
	_genre_custom_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_genre_custom_row.add_child(_genre_custom_input)

	return group


func _build_tone_tags_field() -> Control:
	var group := VBoxContainer.new()
	group.add_theme_constant_override("separation", 8)

	var label_row := HBoxContainer.new()
	label_row.add_theme_constant_override("separation", 8)
	group.add_child(label_row)
	var primary := Label.new()
	primary.text = "基调标签"
	primary.add_theme_font_size_override("font_size", 20)
	primary.add_theme_color_override("font_color", C_WHITE)
	label_row.add_child(primary)
	var secondary := Label.new()
	secondary.text = "TONE"
	secondary.add_theme_font_size_override("font_size", 15)
	secondary.add_theme_color_override("font_color", C_MUTED)
	secondary.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label_row.add_child(secondary)

	var hint := Label.new()
	hint.text = "选择 %d~%d 个标签，描述作品的整体氛围。" % [MIN_TAGS, MAX_TAGS]
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", C_MUTED)
	group.add_child(hint)

	# 使用 FlowContainer 实现标签式布局
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 10)
	group.add_child(flow)

	_tag_checks.clear()
	for tag_text in TONE_TAGS:
		var cb := _make_tag_checkbox(tag_text)
		flow.add_child(cb)
		_tag_checks.append(cb)

	return group


func _build_outline_field() -> Control:
	var group := VBoxContainer.new()
	group.add_theme_constant_override("separation", 6)

	var label_row := HBoxContainer.new()
	label_row.add_theme_constant_override("separation", 8)
	group.add_child(label_row)
	var primary := Label.new()
	primary.text = "故事大纲"
	primary.add_theme_font_size_override("font_size", 20)
	primary.add_theme_color_override("font_color", C_WHITE)
	label_row.add_child(primary)
	var secondary := Label.new()
	secondary.text = "OUTLINE"
	secondary.add_theme_font_size_override("font_size", 15)
	secondary.add_theme_color_override("font_color", C_MUTED)
	secondary.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label_row.add_child(secondary)

	var hint := Label.new()
	hint.text = "%d 字以内。可以留空——你的搭档会帮你构思。" % MAX_OUTLINE_LEN
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", C_MUTED)
	group.add_child(hint)

	_outline_edit = TextEdit.new()
	_outline_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_outline_edit.custom_minimum_size.y = 120
	_outline_edit.placeholder_text = "简要描述你的故事概念……"
	_outline_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_style_text_edit(_outline_edit)
	_outline_edit.text_changed.connect(_on_outline_text_changed)
	group.add_child(_outline_edit)

	_outline_char_label = Label.new()
	_outline_char_label.text = "0 / %d" % MAX_OUTLINE_LEN
	_outline_char_label.add_theme_font_size_override("font_size", 14)
	_outline_char_label.add_theme_color_override("font_color", C_MUTED)
	_outline_char_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_outline_char_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	group.add_child(_outline_char_label)

	return group


func _build_status_bar() -> Control:
	_status_container = PanelContainer.new()
	_status_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = C_INFO_BG
	style.border_color = Color(C_ACCENT, 0.25)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	_status_container.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	_status_container.add_child(hbox)

	_status_dot = Label.new()
	_status_dot.text = "-"
	_status_dot.add_theme_font_size_override("font_size", 20)
	_status_dot.add_theme_color_override("font_color", C_ACCENT_TEXT)
	hbox.add_child(_status_dot)

	_status_label = Label.new()
	_status_label.text = ""
	_status_label.add_theme_font_size_override("font_size", 17)
	_status_label.add_theme_color_override("font_color", C_DIM)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(_status_label)

	return _status_container


func _build_footer() -> Control:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.add_child(_h_rule())
	var row := HBoxContainer.new()
	vbox.add_child(row)
	var left := Label.new()
	left.text = "ARCADE GRAND JAM 2027"
	left.add_theme_font_size_override("font_size", 16)
	left.add_theme_color_override("font_color", C_MUTED)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	var right := Label.new()
	right.text = "support@arcadegrandjam.com"
	right.add_theme_font_size_override("font_size", 16)
	right.add_theme_color_override("font_color", C_MUTED)
	row.add_child(right)
	return vbox

#endregion


# ═════════════════════════════════════════════════════════════════════════
#region UI 工具函数
# ═════════════════════════════════════════════════════════════════════════

func _build_divider_rule() -> Control:
	var divider := ColorRect.new()
	divider.color = C_RULE
	divider.custom_minimum_size.y = 1
	divider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return divider

func _spacer(height: int) -> Control:
	var s := Control.new()
	s.custom_minimum_size.y = height
	return s

func _h_rule() -> Control:
	var d := ColorRect.new()
	d.color = C_RULE
	d.custom_minimum_size.y = 1
	d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return d

func _nav_separator() -> Control:
	var sep := Label.new()
	sep.text = "|"
	sep.add_theme_font_size_override("font_size", 20)
	sep.add_theme_color_override("font_color", C_MUTED)
	sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return sep

func _nav_link_highlight(text_value: String) -> Control:
	var lbl := Label.new()
	lbl.text = text_value
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", C_ACCENT_TEXT)
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return lbl

func _nav_link(text_value: String, url: String) -> Button:
	var btn := Button.new()
	btn.text = text_value
	btn.flat = true
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color", C_DIM)
	btn.add_theme_color_override("font_hover_color", C_WHITE)
	btn.add_theme_color_override("font_pressed_color", C_ACCENT_TEXT)
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.pressed.connect(_on_nav_link_pressed.bind(url))
	return btn

func _on_nav_link_pressed(url: String) -> void:
	if _browser_app != null and _browser_app.has_method("_on_page_action"):
		_browser_app.call("_on_page_action", {"action": "open_url", "url": url})

func _section_header(en_label: String, short_label: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var bar := ColorRect.new()
	bar.color = C_ACCENT
	bar.custom_minimum_size = Vector2(3, 20)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)
	var en := Label.new()
	en.text = en_label
	en.add_theme_font_size_override("font_size", 16)
	en.add_theme_color_override("font_color", C_ACCENT_TEXT)
	en.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(en)
	var short_text := Label.new()
	short_text.text = "  " + short_label
	short_text.add_theme_font_size_override("font_size", 22)
	short_text.add_theme_color_override("font_color", C_WHITE)
	short_text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(short_text)
	return row

func _make_badge(text_value: String, color: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color, 0.12)
	style.border_color = Color(color, 0.35)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	panel.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", color)
	panel.add_child(label)
	return panel

func _make_card() -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = C_CARD_BG
	style.border_color = C_CARD_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 36
	style.content_margin_right = 36
	style.content_margin_top = 30
	style.content_margin_bottom = 30
	card.add_theme_stylebox_override("panel", style)
	return card

func _make_line_edit(placeholder: String, max_len: int) -> LineEdit:
	var field := LineEdit.new()
	field.placeholder_text = placeholder
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.custom_minimum_size.y = 46
	if max_len > 0:
		field.max_length = max_len
	_style_line_edit(field)
	return field

func _make_tag_checkbox(tag_text: String) -> CheckBox:
	var cb := CheckBox.new()
	cb.text = tag_text
	cb.add_theme_font_size_override("font_size", 18)
	cb.add_theme_color_override("font_color", C_DIM)
	cb.add_theme_color_override("font_hover_color", C_WHITE)
	cb.add_theme_color_override("font_pressed_color", C_ACCENT_TEXT)
	cb.toggled.connect(_on_tag_toggled.bind(cb))
	return cb

func _field_group(primary_label: String, secondary_label: String,
		hint: String, control: Control) -> VBoxContainer:
	var group := VBoxContainer.new()
	group.add_theme_constant_override("separation", 6)
	var label_row := HBoxContainer.new()
	label_row.add_theme_constant_override("separation", 8)
	group.add_child(label_row)
	var p := Label.new()
	p.text = primary_label
	p.add_theme_font_size_override("font_size", 20)
	p.add_theme_color_override("font_color", C_WHITE)
	label_row.add_child(p)
	var s := Label.new()
	s.text = secondary_label
	s.add_theme_font_size_override("font_size", 15)
	s.add_theme_color_override("font_color", C_MUTED)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label_row.add_child(s)
	if not hint.is_empty():
		var h := Label.new()
		h.text = hint
		h.add_theme_font_size_override("font_size", 16)
		h.add_theme_color_override("font_color", C_MUTED)
		group.add_child(h)
	group.add_child(control)
	return group

#endregion


# ═════════════════════════════════════════════════════════════════════════
#region 样式
# ═════════════════════════════════════════════════════════════════════════

func _style_line_edit(field: LineEdit) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = C_FIELD_BG
	normal.border_color = C_FIELD_BORDER
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(4)
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	normal.content_margin_top = 6
	normal.content_margin_bottom = 6
	field.add_theme_stylebox_override("normal", normal)
	var focus := normal.duplicate() as StyleBoxFlat
	focus.border_color = C_FIELD_FOCUS
	field.add_theme_stylebox_override("focus", focus)
	field.add_theme_color_override("font_color", C_FIELD_TEXT)
	field.add_theme_color_override("font_placeholder_color", C_FIELD_PH)
	field.add_theme_font_size_override("font_size", 20)

func _style_text_edit(edit: TextEdit) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = C_FIELD_BG
	normal.border_color = C_FIELD_BORDER
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(4)
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	edit.add_theme_stylebox_override("normal", normal)
	var focus := normal.duplicate() as StyleBoxFlat
	focus.border_color = C_FIELD_FOCUS
	edit.add_theme_stylebox_override("focus", focus)
	edit.add_theme_color_override("font_color", C_FIELD_TEXT)
	edit.add_theme_color_override("font_placeholder_color", C_FIELD_PH)
	edit.add_theme_font_size_override("font_size", 18)

func _style_option_button(button: OptionButton) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = C_FIELD_BG
	normal.border_color = C_FIELD_BORDER
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(4)
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	normal.content_margin_top = 6
	normal.content_margin_bottom = 6
	button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.border_color = C_FIELD_FOCUS
	button.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.border_color = C_ACCENT
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_color_override("font_color", C_FIELD_TEXT)
	button.add_theme_font_size_override("font_size", 20)

func _style_primary_button(button: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = C_ACCENT
	normal.set_corner_radius_all(4)
	normal.content_margin_left = 20
	normal.content_margin_right = 20
	normal.content_margin_top = 10
	normal.content_margin_bottom = 10
	button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(C_ACCENT, 0.8)
	button.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(C_ACCENT, 0.6)
	button.add_theme_stylebox_override("pressed", pressed)
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(C_MUTED, 0.3)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_color", C_WHITE)
	button.add_theme_color_override("font_hover_color", C_WHITE)
	button.add_theme_color_override("font_pressed_color", C_WHITE)
	button.add_theme_color_override("font_disabled_color", C_MUTED)

#endregion


# ═════════════════════════════════════════════════════════════════════════
#region 表单交互
# ═════════════════════════════════════════════════════════════════════════

func _on_genre_selected(idx: int) -> void:
	# 最后一项是"自定义..."
	var is_custom: bool = (idx == _genre_select.item_count - 1)
	_genre_custom_row.visible = is_custom
	if is_custom and _genre_custom_input != null:
		_genre_custom_input.grab_focus()


func _on_tag_toggled(_pressed: bool, _cb: CheckBox) -> void:
	var selected_count := _get_selected_tags().size()
	# 超过上限时取消最后一个
	if selected_count > MAX_TAGS and _pressed:
		_cb.set_pressed_no_signal(false)


func _on_outline_text_changed() -> void:
	if _outline_edit == null or _outline_char_label == null:
		return
	var text := _outline_edit.text
	var char_count := text.length()
	# 硬限制字数
	if char_count > MAX_OUTLINE_LEN:
		_outline_edit.text = text.left(MAX_OUTLINE_LEN)
		_outline_edit.set_caret_column(MAX_OUTLINE_LEN)
		_outline_edit.set_caret_line(_outline_edit.get_line_count() - 1)
		char_count = MAX_OUTLINE_LEN
	_outline_char_label.text = "%d / %d" % [char_count, MAX_OUTLINE_LEN]
	if char_count > MAX_OUTLINE_LEN * 0.9:
		_outline_char_label.add_theme_color_override("font_color", C_ORANGE)
	else:
		_outline_char_label.add_theme_color_override("font_color", C_MUTED)


func _get_selected_genre() -> String:
	if _genre_select == null:
		return ""
	var idx: int = _genre_select.selected
	if idx <= 0:
		return ""
	# 自定义
	if idx == _genre_select.item_count - 1:
		if _genre_custom_input != null:
			return _genre_custom_input.text.strip_edges()
		return ""
	return _genre_select.get_item_text(idx)


func _get_selected_tags() -> PackedStringArray:
	var result: PackedStringArray = []
	for cb in _tag_checks:
		if cb.button_pressed:
			result.append(cb.text)
	return result


func _focus_first_input() -> void:
	if _title_input != null and not _submission_locked:
		_title_input.grab_focus()

#endregion


# ═════════════════════════════════════════════════════════════════════════
#region LLM 服务初始化
# ═════════════════════════════════════════════════════════════════════════

func _ensure_review_service() -> void:
	var config_mgr := AIConfigManager.get_instance()
	var review_role: String = "signup_review"
	if config_mgr.get_config_for_role(review_role).is_empty():
		review_role = "input_guard"
	var config: Dictionary = config_mgr.get_config_for_role(review_role)
	if config.is_empty():
		_review_enabled = false
		return
	_review_service = AIServiceClass.new()
	if not config_mgr.apply_to_service(_review_service, review_role):
		_review_enabled = false
		return
	_review_service.default_temperature = 0.3
	_review_service.default_max_tokens = 512
	_review_service.request_completed.connect(_on_review_completed)
	_review_service.request_failed.connect(_on_review_failed)
	add_child(_review_service)
	_review_enabled = true


func _ensure_outline_service() -> void:
	var config_mgr := AIConfigManager.get_instance()
	var outline_role: String = "creative_brief_outline"
	if config_mgr.get_config_for_role(outline_role).is_empty():
		outline_role = "chat_default"
	var config: Dictionary = config_mgr.get_config_for_role(outline_role)
	if config.is_empty():
		_outline_enabled = false
		return
	_outline_service = AIServiceClass.new()
	if not config_mgr.apply_to_service(_outline_service, outline_role):
		_outline_enabled = false
		return
	_outline_service.default_temperature = 0.7
	_outline_service.default_max_tokens = 512
	_outline_service.request_completed.connect(_on_outline_completed)
	_outline_service.request_failed.connect(_on_outline_failed)
	add_child(_outline_service)
	_outline_enabled = true

#endregion


# ═════════════════════════════════════════════════════════════════════════
#region 提交流程
# ═════════════════════════════════════════════════════════════════════════

func _on_submit_clicked() -> void:
	if _submission_locked or _is_reviewing or _is_generating_outline:
		return

	# ── 前端校验 ──
	var title_text := _title_input.text.strip_edges() if _title_input else ""
	if title_text.is_empty():
		_set_status("error", "请输入作品名称。")
		if _title_input:
			_title_input.grab_focus()
		return

	var genre := _get_selected_genre()
	if genre.is_empty():
		_set_status("error", "请选择作品类型。")
		return

	var tags := _get_selected_tags()
	if tags.size() < MIN_TAGS:
		_set_status("error", "请至少选择 %d 个基调标签。" % MIN_TAGS)
		return

	var outline := _outline_edit.text.strip_edges() if _outline_edit else ""

	# ── 大纲为空：先生成大纲 ──
	if outline.is_empty():
		_start_outline_generation(title_text, genre, tags)
		return

	# ── 有大纲：走审核 ──
	_start_review(title_text, genre, tags, outline)


func _start_review(title_text: String, genre: String, tags: PackedStringArray, outline: String) -> void:
	_is_reviewing = true
	if _submit_button:
		_submit_button.disabled = true
		_submit_button.text = "审核中..."
	_set_status("info", "正在审核企划信息...")

	if not _review_enabled or _review_service == null:
		# 无审核服务：直接通过
		_do_approve(title_text, genre, tags, outline)
		return

	var user_msg := "作品名称: %s\n作品类型: %s\n基调标签: %s\n比赛主题: %s\n故事大纲: %s" % [
		title_text, genre, ", ".join(tags), FIXED_THEME, outline
	]
	var messages: Array = [
		{"role": "system", "content": REVIEW_SYSTEM_PROMPT},
		{"role": "user", "content": user_msg},
	]
	_pending_review_id = _review_service.chat(messages, {"temperature": 0.3, "max_tokens": 512})


func _on_review_completed(request_id: String, response: Dictionary) -> void:
	if request_id != _pending_review_id:
		return
	_pending_review_id = ""
	_is_reviewing = false

	var content: String = ""
	var choices: Array = response.get("choices", [])
	if choices.size() > 0:
		content = str(choices[0].get("message", {}).get("content", ""))

	var clean := content.strip_edges()
	if clean.begins_with("```"):
		var first_nl := clean.find("\n")
		if first_nl >= 0:
			clean = clean.substr(first_nl + 1)
		if clean.ends_with("```"):
			clean = clean.substr(0, clean.length() - 3).strip_edges()

	var json := JSON.new()
	if json.parse(clean) != OK or not (json.data is Dictionary):
		# 解析失败：直接通过
		var title_text := _title_input.text.strip_edges() if _title_input else ""
		var genre := _get_selected_genre()
		var tags := _get_selected_tags()
		var outline := _outline_edit.text.strip_edges() if _outline_edit else ""
		_do_approve(title_text, genre, tags, outline)
		return

	var result: Dictionary = json.data

	if not bool(result.get("approved", true)):
		# ── 审核拒绝 ──
		var reason: String = str(result.get("reason", "内容不符合要求"))
		_set_status("error", "审核未通过：%s" % reason)
		# 林夏吐槽（通过 topic 让 LLM 自然表达）
		var title_for_reject := _title_input.text.strip_edges() if _title_input else ""
		await _fire_lin_xia_topic_and_wait("brief_rejection",
			"搭档提交的 GameJam 企划书没有通过官方审核。\n\n"
			+ "- 作品名称：%s\n- 拒绝原因：%s\n\n" % [title_for_reject, reason]
			+ "用 1-2 句话吐槽或调侃，不要重复审核原因原文。")
		if _submit_button:
			_submit_button.disabled = false
			_submit_button.text = "提交立案"
		return

	# ── 审核通过 ──
	var title_text := _title_input.text.strip_edges() if _title_input else ""
	var genre := _get_selected_genre()
	var tags := _get_selected_tags()
	var outline := _outline_edit.text.strip_edges() if _outline_edit else ""
	_do_approve(title_text, genre, tags, outline)


func _on_review_failed(request_id: String, error: String, _error_code: int) -> void:
	if request_id != _pending_review_id:
		return
	_pending_review_id = ""
	_is_reviewing = false
	push_warning("CreativeBriefPage: 审核服务失败: %s" % error)
	# 审核失败：直接通过
	var title_text := _title_input.text.strip_edges() if _title_input else ""
	var genre := _get_selected_genre()
	var tags := _get_selected_tags()
	var outline := _outline_edit.text.strip_edges() if _outline_edit else ""
	_do_approve(title_text, genre, tags, outline)

#endregion


# ═════════════════════════════════════════════════════════════════════════
#region 大纲生成
# ═════════════════════════════════════════════════════════════════════════

func _start_outline_generation(title_text: String, genre: String, tags: PackedStringArray) -> void:
	_is_generating_outline = true
	if _submit_button:
		_submit_button.disabled = true
		_submit_button.text = "构思中..."
	_set_status("info", "大纲留空——林夏正在帮你构思...")

	if not _outline_enabled or _outline_service == null:
		# 无大纲服务：生成一个兜底大纲
		_on_outline_result(_generate_fallback_outline(title_text, genre, tags))
		return

	var user_msg := "作品名称: %s\n作品类型: %s\n基调: %s" % [title_text, genre, ", ".join(tags)]
	var resolved_prompt := OUTLINE_SYSTEM_PROMPT_TEMPLATE
	var pm: Node = get_node_or_null("/root/PromptManager")
	if pm != null and pm.has_method("resolve_template"):
		resolved_prompt = pm.resolve_template(OUTLINE_SYSTEM_PROMPT_TEMPLATE)
	var messages: Array = [
		{"role": "system", "content": resolved_prompt},
		{"role": "user", "content": user_msg},
	]
	_pending_outline_id = _outline_service.chat(messages, {"temperature": 0.7, "max_tokens": 512})


func _on_outline_completed(request_id: String, response: Dictionary) -> void:
	if request_id != _pending_outline_id:
		return
	_pending_outline_id = ""

	var content: String = ""
	var choices: Array = response.get("choices", [])
	if choices.size() > 0:
		content = str(choices[0].get("message", {}).get("content", "")).strip_edges()

	if content.is_empty():
		var title_text := _title_input.text.strip_edges() if _title_input else ""
		var genre := _get_selected_genre()
		var tags := _get_selected_tags()
		content = _generate_fallback_outline(title_text, genre, tags)

	_on_outline_result(content)


func _on_outline_failed(request_id: String, error: String, _error_code: int) -> void:
	if request_id != _pending_outline_id:
		return
	_pending_outline_id = ""
	push_warning("CreativeBriefPage: 大纲生成失败: %s" % error)
	var title_text := _title_input.text.strip_edges() if _title_input else ""
	var genre := _get_selected_genre()
	var tags := _get_selected_tags()
	_on_outline_result(_generate_fallback_outline(title_text, genre, tags))


func _on_outline_result(outline_text: String) -> void:
	_is_generating_outline = false

	var title_for_topic := _title_input.text.strip_edges() if _title_input else ""
	var genre_for_topic := _get_selected_genre()
	var tags_for_topic := _get_selected_tags()

	# 林夏展示她“帮忙构思”的大纲——包含完整大纲内容
	await _fire_lin_xia_topic_and_wait("outline_result",
		"搭档正在填写 GameJam 企划书，但没写故事大纲，你帮他想了一个。\n\n"
		+ "【企划信息】\n"
		+ "- 作品名称：%s\n" % title_for_topic
		+ "- 作品类型：%s\n" % genre_for_topic
		+ "- 基调：%s\n\n" % ", ".join(tags_for_topic)
		+ "【你构思的大纲】\n%s\n\n" % outline_text
		+ "向搭档展示你构思的大纲，告诉他可以在页面上修改后提交。"
		+ "把大纲要点用自己的话说出来，不要原样复制。")

	# 等林夏在 LinkChat 里说完，再把大纲写回网页。
	if _outline_edit != null:
		_outline_edit.text = outline_text
		_on_outline_text_changed()

	_set_status("info", "大纲已生成，你可以修改后提交。")
	if _submit_button:
		_submit_button.disabled = false
		_submit_button.text = "提交立案"


func _generate_fallback_outline(title_text: String, genre: String, tags: PackedStringArray) -> String:
	var tone := ", ".join(tags) if tags.size() > 0 else "日常"
	return "在一所以魔法闻名的学院中，一位新入学的少年发现自己拥有独特的天赋。在%s的氛围下，围绕「%s」的主题，一段%s的故事就此展开。" % [tone, title_text, genre]

#endregion


# ═════════════════════════════════════════════════════════════════════════
#region 审核通过 → KB + 林夏反馈 + StoryDirector
# ═════════════════════════════════════════════════════════════════════════

func _do_approve(title_text: String, genre: String, tags: PackedStringArray,
		outline: String) -> void:
	# ── 写入 KB ──
	_write_to_knowledge_base(title_text, genre, tags, outline)

	# ── 设置 StoryDirector 变量 ──
	var story_director: Node = get_node_or_null("/root/StoryDirector")
	if story_director != null and story_director.has_method("set_variable"):
		story_director.set_variable("creative_brief_submitted", "true")
		story_director.set_variable("game_title", title_text)
		story_director.set_variable("game_genre", genre)
		story_director.set_variable("game_tags", ", ".join(tags))

	# ── 锁定页面 ──
	_lock_submission()
	_set_status("info", "审核通过，林夏正在看你的企划……")

	# ── 林夏反馈 topic（审核通过的正面反应）──
	await _activate_feedback_topic(title_text, genre, tags, outline)

	# ── 通知 DevCycleManager：企划完成 → 触发开发计划生成 ──
	var dcm: Node = get_node_or_null("/root/DevCycleManager")
	if dcm != null and dcm.has_method("on_creative_brief_completed"):
		dcm.on_creative_brief_completed({
			"game_title": title_text,
			"game_genre": genre,
			"game_tags": ", ".join(tags),
			"game_outline": outline,
		})

	# ── 触发 story event（通知 BrowserApp → StoryDirector）──
	if _browser_app != null and _browser_app.has_method("_on_page_action"):
		_browser_app.call("_on_page_action", {
			"action": "story_event",
			"story_condition": "variable_equals",
			"story_key": "creative_brief_submitted",
			"story_value": "true",
			"form_data": {
				"game_title": title_text,
				"game_genre": genre,
				"game_tags": ", ".join(tags),
				"game_outline": outline,
			},
			"page_url": "gamejam://brief",
			"success_status": "立案通过",
		})

	_set_status("success", "立案通过！开发即将开始。")


func _write_to_knowledge_base(title_text: String, genre: String,
		tags: PackedStringArray, outline: String) -> void:
	var kb: Node = get_node_or_null("/root/KnowledgeBaseManager")
	if kb == null or not kb.has_method("upsert_document"):
		push_warning("CreativeBriefPage: KnowledgeBaseManager 不可用")
		return

	var content := "## 基本信息\n- 作品名称：%s\n- 作品类型：%s\n- 基调标签：%s\n- 比赛主题：%s\n\n## 故事大纲\n%s" % [
		title_text, genre, ", ".join(tags), FIXED_THEME, outline
	]
	kb.upsert_document("creative_brief", "项目企划书", content, "creative_brief",
		["brief", "direction", genre], "player")


func _activate_feedback_topic(title_text: String, genre: String,
		tags: PackedStringArray, outline: String) -> void:
	await _fire_lin_xia_topic_and_wait("brief_feedback",
		"搭档提交的 GameJam 企划书已通过审核。\n\n"
		+ "【企划信息】\n"
		+ "- 作品名称：%s\n" % title_text
		+ "- 作品类型：%s\n" % genre
		+ "- 基调：%s\n" % ", ".join(tags)
		+ "- 故事大纲：%s\n\n" % outline
		+ "用 1-3 句话表达对这个企划的反应。可以期待、兴奋、好奇、或善意吐槽。"
		+ "不要重复企划内容。")

#endregion


# ═════════════════════════════════════════════════════════════════════════
#region 林夏消息 & 页面状态
# ═════════════════════════════════════════════════════════════════════════

## 创建一次性 topic 让林夏通过 LLM 自然说话
func _fire_lin_xia_topic(id_prefix: String, system_prompt: String) -> String:
	var chat: Node = get_node_or_null("/root/ChatManager")
	if chat == null:
		return ""

	var topic := ChatTopic.new()
	topic.topic_id = "%s_%d" % [id_prefix, int(Time.get_unix_time_from_system())]
	topic.topic_type = "casual_interaction"
	topic.display_title = id_prefix.replace("_", " ").capitalize()
	topic.npc_id = "npc_lin_xia"
	topic.channel_id = "dm_lin_xia"
	topic.system_prompt = system_prompt
	topic.max_turns = 1
	topic.context_data = {
		"complete_after_first_reply": true,
		"linkchat_open_mode": "force",
		"suppress_system_notice": true,
	}

	if chat.has_method("activate_topic"):
		if chat.activate_topic(topic):
			if chat.has_method("request_topic_npc_reply"):
				if chat.request_topic_npc_reply("dm_lin_xia", "", false, true):
					return topic.topic_id

	return ""


func _fire_lin_xia_topic_and_wait(id_prefix: String, system_prompt: String) -> bool:
	var topic_id := _fire_lin_xia_topic(id_prefix, system_prompt)
	if topic_id.is_empty():
		return false
	return await _wait_for_topic_finish("dm_lin_xia", topic_id)


func _wait_for_topic_finish(channel_id: String, topic_id: String, timeout_seconds: float = 45.0) -> bool:
	var chat: Node = get_node_or_null("/root/ChatManager")
	if chat == null:
		return false

	var deadline_msec := Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while Time.get_ticks_msec() < deadline_msec:
		var active_topic: ChatTopic = null
		if chat.has_method("get_active_topic"):
			active_topic = chat.get_active_topic(channel_id)
		if active_topic == null or str(active_topic.topic_id) != topic_id:
			return true
		await get_tree().process_frame

	return false


func _lock_submission() -> void:
	_submission_locked = true
	if _title_input:
		_title_input.editable = false
		_title_input.add_theme_color_override("font_color", C_MUTED)
	if _genre_select:
		_genre_select.disabled = true
	if _genre_custom_input:
		_genre_custom_input.editable = false
	for cb in _tag_checks:
		cb.disabled = true
	if _outline_edit:
		_outline_edit.editable = false
	if _submit_button:
		_submit_button.disabled = true
		_submit_button.text = "已提交"


func _load_existing_values() -> void:
	var story_director: Node = get_node_or_null("/root/StoryDirector")
	if story_director == null or not story_director.has_method("get_variable"):
		return
	var completed: Variant = story_director.get_variable("creative_brief_submitted")
	if str(completed) != "true":
		return
	# 恢复已提交的数据
	_submission_locked = true
	var saved_title: Variant = story_director.get_variable("game_title")
	var saved_genre: Variant = story_director.get_variable("game_genre")
	var saved_tags: Variant = story_director.get_variable("game_tags")
	if saved_title != null and _title_input != null:
		_title_input.text = str(saved_title)
	if saved_genre != null and _genre_select != null:
		var genre_str := str(saved_genre)
		var found := false
		for i in range(1, _genre_select.item_count - 1):
			if _genre_select.get_item_text(i) == genre_str:
				_genre_select.selected = i
				found = true
				break
		if not found:
			# 自定义类型
			_genre_select.selected = _genre_select.item_count - 1
			_genre_custom_row.visible = true
			if _genre_custom_input:
				_genre_custom_input.text = genre_str
	if saved_tags != null:
		var tag_list: PackedStringArray = str(saved_tags).split(", ")
		for cb in _tag_checks:
			cb.button_pressed = cb.text in tag_list
	# 恢复大纲（从 KB 读取）
	var kb: Node = get_node_or_null("/root/KnowledgeBaseManager")
	if kb != null and kb.has_method("get_document"):
		var doc: Dictionary = kb.get_document("creative_brief")
		if not doc.is_empty() and _outline_edit != null:
			var doc_content: String = str(doc.get("content", ""))
			var outline_marker := "## 故事大纲\n"
			var idx := doc_content.find(outline_marker)
			if idx >= 0:
				_outline_edit.text = doc_content.substr(idx + outline_marker.length()).strip_edges()
	_lock_submission()
	_set_status("success", "立案已通过。")


func _set_status(status_type: String, message: String) -> void:
	if _status_container == null or _status_label == null or _status_dot == null:
		return
	_status_label.text = message
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(4)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	match status_type:
		"error":
			_status_dot.text = "✕"
			_status_dot.add_theme_color_override("font_color", C_ERROR)
			_status_label.add_theme_color_override("font_color", C_ERROR)
			style.bg_color = C_ERROR_BG
			style.border_color = Color(C_ERROR, 0.3)
			style.set_border_width_all(1)
		"success":
			_status_dot.text = "✓"
			_status_dot.add_theme_color_override("font_color", C_SUCCESS)
			_status_label.add_theme_color_override("font_color", C_SUCCESS)
			style.bg_color = C_SUCCESS_BG
			style.border_color = Color(C_SUCCESS, 0.3)
			style.set_border_width_all(1)
		_:
			_status_dot.text = "-"
			_status_dot.add_theme_color_override("font_color", C_ACCENT_TEXT)
			_status_label.add_theme_color_override("font_color", C_DIM)
			style.bg_color = C_INFO_BG
			style.border_color = Color(C_ACCENT, 0.25)
			style.set_border_width_all(1)
	_status_container.add_theme_stylebox_override("panel", style)

#endregion
