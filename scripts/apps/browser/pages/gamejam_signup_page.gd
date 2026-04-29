extends MarginContainer

const AIServiceClass = preload("res://scripts/llm/AIService.gd")

const C_PAGE_BG := Color("#080B12")
const C_HERO_BG := Color("#0A0D18")
const C_CARD_BG := Color("#0D1020")
const C_CARD_BORDER := Color("#1A1F35")
const C_RULE := Color("#141828")
const C_ACCENT := Color("#3D6FFF")
const C_ORANGE := Color("#E8622A")
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

const UNIVERSITY_NAME: String = "蓝鲸大学"
const BLOCKED_NAMES: PackedStringArray = [
	"林夏",
]
const REVIEW_PROMPT_KEY: String = "browser/signup_review"
const REVIEW_SYSTEM_FALLBACK: String = "审核大学 GameJam 报名信息。默认通过，明确违规才拒绝。只输出 JSON：approved, reason, normalized_player_name, normalized_team_name。"
const COLLEGE_OPTIONS: PackedStringArray = [
	"交互媒体学院",
	"计算机科学学院",
	"艺术与设计学院",
	"文学与新闻学院",
	"外国语学院",
	"心理学院",
	"商学院",
	"法学院",
	"历史学院",
	"哲学系",
	"社会学院",
	"数学学院",
	"物理学院",
	"化学与材料学院",
	"生命科学学院",
	"电子信息学院",
	"建筑与城规学院",
	"环境科学学院",
	"教育学院",
	"医学院",
]

var _browser_app: Node = null
var _page_payload: Dictionary = {}
var _review_service: Node = null
var _pending_review_request_id: String = ""
var _review_enabled: bool = false
var _submission_locked: bool = false

var _root_vbox: VBoxContainer
var _scroll: ScrollContainer
var _player_name_input: LineEdit
var _college_select: OptionButton
var _team_name_input: LineEdit
var _submit_button: Button
var _status_container: PanelContainer
var _status_label: Label
var _status_dot: Label
var _form_container: VBoxContainer


func _ready() -> void:
	_root_vbox = $Root
	_build_page()
	_populate_college_options()
	_ensure_review_service()
	_set_status("info", "请填写报名表。提交后不可修改。")


func configure_browser_page(browser_app: Node, page_payload: Dictionary) -> void:
	_browser_app = browser_app
	_page_payload = page_payload.duplicate(true)
	_load_existing_values()
	if not _submission_locked:
		call_deferred("_focus_first_input")


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

	content_vbox.add_child(_build_about_section())
	content_vbox.add_child(_build_requirements_section())
	content_vbox.add_child(_build_form_section())
	content_vbox.add_child(_build_status_bar())
	content_vbox.add_child(_build_footer())
	content_vbox.add_child(_spacer(24))


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

	var sep := Label.new()
	sep.text = "|"
	sep.add_theme_font_size_override("font_size", 20)
	sep.add_theme_color_override("font_color", C_MUTED)
	sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(sep)

	# 当前页高亮，其他页可点击
	var reg_label := Label.new()
	reg_label.text = "REGISTRATION"
	reg_label.add_theme_font_size_override("font_size", 16)
	reg_label.add_theme_color_override("font_color", C_ACCENT_TEXT)
	reg_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(reg_label)

	hbox.add_child(_nav_link("SCHEDULE", "gamejam://schedule"))
	hbox.add_child(_nav_link("NEWS", "gamejam://news"))
	hbox.add_child(_nav_link("FAQ", "gamejam://faq"))

	return navbar


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


func _build_hero() -> Control:
	var hero := PanelContainer.new()
	hero.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var style := StyleBoxFlat.new()
	style.bg_color = C_HERO_BG
	style.content_margin_left = 60
	style.content_margin_right = 60
	style.content_margin_top = 56
	style.content_margin_bottom = 56
	hero.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	hero.add_child(vbox)

	var tag_row := HBoxContainer.new()
	tag_row.add_theme_constant_override("separation", 8)
	vbox.add_child(tag_row)
	tag_row.add_child(_make_badge("新星赛道", C_ACCENT))
	tag_row.add_child(_make_badge("2027 赛季", C_ORANGE))

	vbox.add_child(_spacer(24))

	var title := Label.new()
	title.text = "ARCADE GRAND JAM"
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", C_WHITE)
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "参赛报名"
	subtitle.add_theme_font_size_override("font_size", 24)
	subtitle.add_theme_color_override("font_color", C_ACCENT_TEXT)
	vbox.add_child(subtitle)

	vbox.add_child(_spacer(28))

	var stats_row := HBoxContainer.new()
	stats_row.add_theme_constant_override("separation", 0)
	vbox.add_child(stats_row)
	stats_row.add_child(_stat_block("奖金池", "¥50,000+"))
	stats_row.add_child(_stat_divider())
	stats_row.add_child(_stat_block("报名截止", "本周五 23:59"))
	stats_row.add_child(_stat_divider())
	stats_row.add_child(_stat_block("队伍规模", "2~5 人"))
	stats_row.add_child(_stat_divider())
	stats_row.add_child(_stat_block("状态", "报名中"))

	vbox.add_child(_spacer(32))

	var cta_row := HBoxContainer.new()
	cta_row.add_theme_constant_override("separation", 12)
	vbox.add_child(cta_row)

	var cta := Button.new()
	cta.text = "立即报名"
	cta.add_theme_font_size_override("font_size", 20)
	cta.custom_minimum_size = Vector2(180, 46)
	_style_primary_button(cta)
	cta.pressed.connect(_scroll_to_form)
	cta_row.add_child(cta)

	var hint := Label.new()
	hint.text = "提交前请仔细核对信息。"
	hint.add_theme_font_size_override("font_size", 17)
	hint.add_theme_color_override("font_color", C_MUTED)
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cta_row.add_child(hint)

	return hero


func _build_divider_rule() -> Control:
	var divider := ColorRect.new()
	divider.color = C_RULE
	divider.custom_minimum_size.y = 1
	divider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return divider


func _build_about_section() -> Control:
	var card := _make_card()
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	card.add_child(vbox)

	vbox.add_child(_section_header("关于 AGJ", "ABOUT"))
	vbox.add_child(_h_rule())

	var intro := Label.new()
	intro.text = "Arcade Grand Jam（AGJ）是一项面向全球高校学生的年度游戏创作大赛。自 2019 年创办以来已成功举办六届，累计吸引超过 12,000 名参赛者。"
	intro.add_theme_font_size_override("font_size", 20)
	intro.add_theme_color_override("font_color", C_DIM)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(intro)

	var concept := Label.new()
	concept.text = "本届新星·叙事赛道的核心理念：回归创意本身。比赛将采用统一规则和限制条件，让所有参赛者站在同一起跑线上——不比拼资源堆砌和工业能力，只比拼创意组织能力和叙事表达。"
	concept.add_theme_font_size_override("font_size", 20)
	concept.add_theme_color_override("font_color", C_DIM)
	concept.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	concept.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(concept)

	var format := Label.new()
	format.text = "每支队伍由 2-5 人组成，在限定时间内共同完成一部原创作品。具体赛制（包括开发工具、素材要求、主题等）将在报名截止后统一公布。"
	format.add_theme_font_size_override("font_size", 20)
	format.add_theme_color_override("font_color", C_DIM)
	format.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	format.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(format)

	var awards := Label.new()
	awards.text = "总奖金池超过 ¥50,000，涵盖最佳作品、最佳叙事、最佳视觉表现、社区人气等多个奖项。所有获奖作品将在 AGJ 官方平台进行展示。"
	awards.add_theme_font_size_override("font_size", 20)
	awards.add_theme_color_override("font_color", C_DIM)
	awards.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	awards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(awards)

	return card


func _build_requirements_section() -> Control:
	var card := _make_card()
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	card.add_child(vbox)

	vbox.add_child(_section_header("参赛资格与规则", "规则"))
	vbox.add_child(_h_rule())

	var rules: Array[String] = [
		"仅限在校大学生参加。",
		"每支队伍由 2-5 名成员组成。",
		"主题及赛制详情将于报名截止后公布。",
		"报名信息提交后不可修改。",
	]

	for i in range(rules.size()):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		vbox.add_child(row)

		var num := Label.new()
		num.text = "%02d" % (i + 1)
		num.add_theme_font_size_override("font_size", 16)
		num.add_theme_color_override("font_color", C_ACCENT_TEXT)
		num.custom_minimum_size.x = 28
		row.add_child(num)

		var rule := Label.new()
		rule.text = rules[i]
		rule.add_theme_font_size_override("font_size", 20)
		rule.add_theme_color_override("font_color", C_DIM)
		rule.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(rule)

	return card


func _build_form_section() -> Control:
	var card := _make_card()
	_form_container = VBoxContainer.new()
	_form_container.add_theme_constant_override("separation", 28)
	card.add_child(_form_container)

	_form_container.add_child(_section_header("报名表", "填写信息"))
	_form_container.add_child(_h_rule())

	_player_name_input = _make_line_edit("请输入你的真实姓名", 16)
	_form_container.add_child(_field_group("真实姓名", "REAL NAME", "用于比赛报名的正式身份。请填写真实姓名。", _player_name_input))

	var uni_field := _make_line_edit(UNIVERSITY_NAME, 0)
	uni_field.editable = false
	uni_field.add_theme_color_override("font_color", C_MUTED)
	_form_container.add_child(_field_group("所属大学", "UNIVERSITY", "由系统自动填写。", uni_field))

	_college_select = OptionButton.new()
	_college_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_college_select.custom_minimum_size.y = 46
	_style_option_button(_college_select)
	_form_container.add_child(_field_group("所属学院", "COLLEGE", "选择你当前就读的学院。", _college_select))

	_team_name_input = _make_line_edit("请输入队伍名称", 20)
	_form_container.add_child(_field_group("队伍名称", "TEAM NAME", "将显示在排行榜和项目页面。", _team_name_input))

	_submit_button = Button.new()
	_submit_button.text = "提交报名"
	_submit_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_submit_button.custom_minimum_size.y = 50
	_submit_button.add_theme_font_size_override("font_size", 20)
	_style_primary_button(_submit_button)
	_submit_button.pressed.connect(_on_submit_clicked)
	_form_container.add_child(_submit_button)

	return card


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


func _stat_block(label_text: String, value_text: String) -> Control:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.custom_minimum_size.x = 130

	var value_label := Label.new()
	value_label.text = value_text
	value_label.add_theme_font_size_override("font_size", 26)
	value_label.add_theme_color_override("font_color", C_WHITE)
	vbox.add_child(value_label)

	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", C_MUTED)
	vbox.add_child(label)

	return vbox


func _stat_divider() -> Control:
	var divider := ColorRect.new()
	divider.color = C_RULE
	divider.custom_minimum_size = Vector2(1, 36)
	divider.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var container := MarginContainer.new()
	container.add_theme_constant_override("margin_left", 16)
	container.add_theme_constant_override("margin_right", 16)
	container.add_child(divider)
	return container


func _spacer(height: int) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = height
	return spacer


func _h_rule() -> Control:
	var divider := ColorRect.new()
	divider.color = C_RULE
	divider.custom_minimum_size.y = 1
	divider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return divider


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


func _field_group(primary_label: String, secondary_label: String, hint: String, control: Control) -> VBoxContainer:
	var group := VBoxContainer.new()
	group.add_theme_constant_override("separation", 6)

	var label_row := HBoxContainer.new()
	label_row.add_theme_constant_override("separation", 8)
	group.add_child(label_row)

	var primary := Label.new()
	primary.text = primary_label
	primary.add_theme_font_size_override("font_size", 20)
	primary.add_theme_color_override("font_color", C_WHITE)
	label_row.add_child(primary)

	var secondary := Label.new()
	secondary.text = secondary_label
	secondary.add_theme_font_size_override("font_size", 15)
	secondary.add_theme_color_override("font_color", C_MUTED)
	secondary.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label_row.add_child(secondary)

	if not hint.is_empty():
		var hint_label := Label.new()
		hint_label.text = hint
		hint_label.add_theme_font_size_override("font_size", 16)
		hint_label.add_theme_color_override("font_color", C_MUTED)
		group.add_child(hint_label)

	group.add_child(control)
	return group


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


func _populate_college_options() -> void:
	if _college_select == null:
		return
	_college_select.clear()
	_college_select.add_item("- 请选择学院 -")
	_college_select.set_item_disabled(0, true)
	for college in COLLEGE_OPTIONS:
		_college_select.add_item(college)


func _ensure_review_service() -> void:
	var config_mgr := AIConfigManager.get_instance()
	# 优先用 signup_review 角色，回退到 input_guard
	var review_role: String = "signup_review" if not config_mgr.get_config_for_role("signup_review").is_empty() else "input_guard"
	var config: Dictionary = config_mgr.get_config_for_role(review_role)
	if config.is_empty():
		_review_enabled = false
		return

	_review_service = AIServiceClass.new()
	if not config_mgr.apply_to_service(_review_service, review_role):
		_review_enabled = false
		return

	_review_service.default_temperature = 0.3
	_review_service.request_completed.connect(_on_review_completed)
	_review_service.request_failed.connect(_on_review_failed)
	add_child(_review_service)
	_review_enabled = true


func _load_existing_values() -> void:
	var story_director: Node = get_node_or_null("/root/StoryDirector")
	if story_director != null and story_director.has_method("get_variable"):
		var completed: Variant = story_director.get_variable("signup_completed")
		if str(completed) == "true":
			_submission_locked = true
			var player_name: Variant = story_director.get_variable("player_real_name")
			var college_name: Variant = story_director.get_variable("player_college")
			var team_name: Variant = story_director.get_variable("team_name")
			if player_name != null and _player_name_input != null:
				_player_name_input.text = str(player_name)
			if team_name != null and _team_name_input != null:
				_team_name_input.text = str(team_name)
			if college_name != null and _college_select != null:
				for i in range(_college_select.item_count):
					if _college_select.get_item_text(i) == str(college_name):
						_college_select.selected = i
						break
			_lock_submission()
			_set_status("success", "报名已提交。")
			return

	var defaults: Dictionary = _page_payload.get("defaults", {})
	if defaults.has("player_real_name") and _player_name_input != null:
		_player_name_input.text = str(defaults["player_real_name"])
	if defaults.has("team_name") and _team_name_input != null:
		_team_name_input.text = str(defaults["team_name"])


func _focus_first_input() -> void:
	if _player_name_input != null and not _submission_locked:
		_player_name_input.grab_focus()


func _scroll_to_form() -> void:
	if _scroll == null or _form_container == null:
		return
	var target_y: float = _form_container.global_position.y - _scroll.global_position.y + _scroll.scroll_vertical
	var tween := create_tween()
	tween.tween_property(_scroll, "scroll_vertical", int(target_y) - 20, 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


func _on_submit_clicked() -> void:
	if _submission_locked:
		return

	var player_name: String = _player_name_input.text.strip_edges() if _player_name_input else ""
	var team_name: String = _team_name_input.text.strip_edges() if _team_name_input else ""
	var college_idx: int = _college_select.selected if _college_select else 0

	if player_name.is_empty():
		_set_status("error", "请输入真实姓名。")
		if _player_name_input:
			_player_name_input.grab_focus()
		return
	if player_name in BLOCKED_NAMES:
		_set_status("error", "这个名字不可用。请填写你自己的真实姓名。")
		if _player_name_input:
			_player_name_input.grab_focus()
		return
	if college_idx <= 0:
		_set_status("error", "请选择学院。")
		return
	if team_name.is_empty():
		_set_status("error", "请输入队伍名称。")
		if _team_name_input:
			_team_name_input.grab_focus()
		return

	if _submit_button:
		_submit_button.disabled = true
		_submit_button.text = "提交中..."

	if _review_enabled and _review_service != null:
		_submit_with_review(player_name, team_name, college_idx)
	else:
		_submit_directly(player_name, team_name, college_idx)


func _submit_with_review(player_name: String, team_name: String, college_idx: int) -> void:
	_set_status("info", "正在审核报名信息...")
	var college_name: String = _college_select.get_item_text(college_idx)
	var user_msg := "player_name=%s\nuniversity=%s\ncollege=%s\nteam_name=%s" % [player_name, UNIVERSITY_NAME, college_name, team_name]
	var messages: Array = [
		{"role": "system", "content": _resolve_prompt(REVIEW_PROMPT_KEY, REVIEW_SYSTEM_FALLBACK)},
		{"role": "user", "content": user_msg},
	]
	_pending_review_request_id = _review_service.chat(messages, {"temperature": 0.3})


func _on_review_completed(request_id: String, response: Dictionary) -> void:
	if request_id != _pending_review_request_id:
		return
	_pending_review_request_id = ""

	var content: String = ""
	var choices: Array = response.get("choices", [])
	if choices.size() > 0:
		content = str(choices[0].get("message", {}).get("content", ""))

	var clean := content.strip_edges()
	if clean.begins_with("```"):
		var first_newline := clean.find("\n")
		if first_newline >= 0:
			clean = clean.substr(first_newline + 1)
		if clean.ends_with("```"):
			clean = clean.substr(0, clean.length() - 3).strip_edges()

	var json := JSON.new()
	if json.parse(clean) != OK or not (json.data is Dictionary):
		_submit_directly(_player_name_input.text.strip_edges(), _team_name_input.text.strip_edges(), _college_select.selected)
		return

	var result: Dictionary = json.data
	if not bool(result.get("approved", true)):
		_set_status("error", "审核未通过：%s" % str(result.get("reason", "")))
		if _submit_button:
			_submit_button.disabled = false
			_submit_button.text = "提交报名"
		return

	var final_player: String = str(result.get("normalized_player_name", _player_name_input.text.strip_edges()))
	var final_team: String = str(result.get("normalized_team_name", _team_name_input.text.strip_edges()))
	if _player_name_input:
		_player_name_input.text = final_player
	if _team_name_input:
		_team_name_input.text = final_team
	_do_submit(final_player, final_team, _college_select.selected)


func _on_review_failed(request_id: String, error: String, _error_code: int) -> void:
	if request_id != _pending_review_request_id:
		return
	_pending_review_request_id = ""
	push_warning("SignupPage: AI 审核失败: %s" % error)
	_submit_directly(_player_name_input.text.strip_edges(), _team_name_input.text.strip_edges(), _college_select.selected)


func _submit_directly(player_name: String, team_name: String, college_idx: int) -> void:
	_do_submit(player_name, team_name, college_idx)


func _do_submit(player_name: String, team_name: String, college_idx: int) -> void:
	var college_name: String = _college_select.get_item_text(college_idx) if _college_select else ""
	var form_data := {
		"player_real_name": player_name,
		"player_university": UNIVERSITY_NAME,
		"player_college": college_name,
		"team_name": team_name,
	}

	if _browser_app != null and _browser_app.has_method("_on_page_action"):
		_browser_app.call("_on_page_action", {
			"action": "story_event",
			"story_condition": "variable_equals",
			"story_key": "signup_completed",
			"story_value": "true",
			"form_data": form_data,
			"page_url": "gamejam://signup",
			"success_status": "报名完成",
		})

	var story_director: Node = get_node_or_null("/root/StoryDirector")
	if story_director != null and story_director.has_method("set_variable"):
		story_director.set_variable("player_real_name", player_name)
		story_director.set_variable("player_university", UNIVERSITY_NAME)
		story_director.set_variable("player_college", college_name)
		story_director.set_variable("team_name", team_name)

	_lock_submission()
	_set_status("success", "报名完成。")


func _lock_submission() -> void:
	_submission_locked = true
	if _player_name_input:
		_player_name_input.editable = false
		_player_name_input.add_theme_color_override("font_color", C_MUTED)
	if _team_name_input:
		_team_name_input.editable = false
		_team_name_input.add_theme_color_override("font_color", C_MUTED)
	if _college_select:
		_college_select.disabled = true
	if _submit_button:
		_submit_button.disabled = true
		_submit_button.text = "已提交"


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
			_status_dot.text = "x"
			_status_dot.add_theme_color_override("font_color", C_ERROR)
			_status_label.add_theme_color_override("font_color", C_ERROR)
			style.bg_color = C_ERROR_BG
			style.border_color = Color(C_ERROR, 0.3)
			style.set_border_width_all(1)
		"success":
			_status_dot.text = "+"
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


func submit_signup_for_test(data: Dictionary, skip_review: bool) -> bool:
	if _submission_locked:
		return false

	var player_name: String = str(data.get("player_name", "")).strip_edges()
	var college_name: String = str(data.get("player_college", ""))
	var team_name: String = str(data.get("team_name", "")).strip_edges()

	if player_name.is_empty() or college_name.is_empty() or team_name.is_empty():
		_set_status("error", "测试提交：缺少数据")
		return false
	if not skip_review:
		_set_status("error", "审核未通过（测试路径）")
		return false

	var college_idx: int = 0
	if _college_select != null:
		for i in range(_college_select.item_count):
			if _college_select.get_item_text(i) == college_name:
				college_idx = i
				break

	if _player_name_input:
		_player_name_input.text = player_name
	if _team_name_input:
		_team_name_input.text = team_name
	if _college_select and college_idx > 0:
		_college_select.selected = college_idx

	_do_submit(player_name, team_name, college_idx)
	return true


func get_status_text_for_test() -> String:
	if _status_label == null:
		return ""
	return _status_label.text


func _resolve_prompt(prompt_key: String, fallback: String) -> String:
	var pm: Node = get_node_or_null("/root/PromptManager")
	if pm != null and pm.has_method("has_prompt") and pm.has_method("resolve"):
		if pm.has_prompt(prompt_key):
			var resolved := str(pm.resolve(prompt_key)).strip_edges()
			if not resolved.is_empty():
				return resolved
	return fallback


func is_submission_locked_for_test() -> bool:
	return _submission_locked
