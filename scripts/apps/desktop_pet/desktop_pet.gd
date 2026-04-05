class_name DesktopPetApp
extends Control
## 桌宠 —— 拓麻歌子风格 ASCII 养成游戏。破壳、成长、死亡、新蛋循环。

# ── 生命阶段 ─────────────────────────────────────────────
enum Stage { EGG, HATCHING, BABY, ADULT, DEAD, NEW_EGG }
enum Screen { HOME, FEED, PLAY, SLEEP, CLEAN }

const MENU := ["投喂", "玩耍", "睡觉", "清洁"]

# ── 配色 ─────────────────────────────────────────────────
const COL_SHELL  := Color("#1e272e")
const COL_LCD_BG := Color("#0d1b0e")
const COL_LCD_BD := Color("#1a3a1a")
const COL_LCD_TX := Color("#33ff66")
const COL_BTN_N  := Color("#485460")
const COL_BTN_H  := Color("#636e72")
const COL_BTN_T  := Color("#dfe6e9")

# ── 属性 ─────────────────────────────────────────────────
var hunger: float = 50.0
var happy: float = 50.0
var clean_v: float = 80.0
var health: float = 100.0
var age: int = 0

# ── 状态 ─────────────────────────────────────────────────
var _stage: Stage = Stage.EGG
var _scr: Screen = Screen.HOME
var _menu_idx: int = 0
var _frame: int = 0
var _blink: bool = false
var _action_ticks: int = 0
var _hatch_frame: int = 0
var _dialogue: String = ""
var _dlg_ticks: int = 0
var _decay_cd: int = 0

const TICK := 0.55
const DECAY_EVERY := 10
const BABY_AGE := 120
const MAX_AGE := 500
var _tick_acc: float = 0.0

# ── 对话文本 ─────────────────────────────────────────────
var _txt_hungry := ["咕噜噜~", "肚子好饿...", "想吃东西!", "有吃的吗?", "饿饿..."]
var _txt_sad    := ["不开心...", "哼...", "好无聊~", "陪陪我嘛", "寂寞..."]
var _txt_dirty  := ["身上痒痒的", "想洗澡~", "脏脏的...", "有味道了哦"]
var _txt_sick   := ["不舒服...", "头好晕...", "呜呜...", "救救我...", "身体好沉"]
var _txt_happy  := ["♪~♪~", "嘿嘿~", "今天超开心!", "好喜欢你!", "(*´▽`*)"]
var _txt_idle   := ["...", "~♪", "✧", "hehe", "♡", "(◕‿◕)", "∠(ᐛ」∠)＿"]
var _txt_baby   := ["喵~", "呜呜~", "咿呀!", "嗷~", "(*'▽'*)", "唔?"]

# ── UI ───────────────────────────────────────────────────
var _lcd: Label
var _font: Font

# ── 生命周期 ─────────────────────────────────────────────

func _ready() -> void:
	_font = _make_mono()
	_build_ui()
	_refresh()

func _process(d: float) -> void:
	_tick_acc += d
	if _tick_acc < TICK:
		return
	_tick_acc -= TICK
	_on_tick()

func _on_tick() -> void:
	_frame = (_frame + 1) % 4
	_blink = _frame == 3

	# 孵化动画推进
	if _stage == Stage.HATCHING:
		_hatch_frame += 1
		if _hatch_frame >= 8:
			_stage = Stage.BABY
			hunger = 60.0
			happy = 60.0
			clean_v = 80.0
			health = 100.0
			age = 0
			_say("喵~! 我出生了!", 10)
			_scr = Screen.HOME
		_refresh()
		return

	# 活着时更新
	if _stage == Stage.BABY or _stage == Stage.ADULT:
		age += 1
		_do_decay()
		_check_death()
		_check_growth()
		_auto_dialogue()

	# 动作计时
	if _scr != Screen.HOME:
		_action_ticks -= 1
		if _action_ticks <= 0:
			_scr = Screen.HOME

	# 对话计时
	if _dlg_ticks > 0:
		_dlg_ticks -= 1
		if _dlg_ticks <= 0:
			_dialogue = ""

	_refresh()

# ── 属性衰减 ─────────────────────────────────────────────

func _do_decay() -> void:
	_decay_cd += 1
	if _decay_cd < DECAY_EVERY:
		return
	_decay_cd = 0
	var rate := 1.6 if _stage == Stage.BABY else 1.0
	hunger  = maxf(0.0, hunger  - 3.0 * rate)
	happy   = maxf(0.0, happy   - 2.0 * rate)
	clean_v = maxf(0.0, clean_v - 2.5 * rate)
	if hunger < 20.0:
		health = maxf(0.0, health - 3.0)
	if happy < 15.0:
		health = maxf(0.0, health - 2.0)
	if clean_v < 15.0:
		health = maxf(0.0, health - 2.0)
	if hunger > 50.0 and happy > 50.0 and clean_v > 50.0:
		health = minf(100.0, health + 1.0)

func _check_death() -> void:
	if health <= 0.0:
		_stage = Stage.DEAD
		_scr = Screen.HOME
		_dialogue = ""

func _check_growth() -> void:
	if _stage == Stage.BABY and age >= BABY_AGE:
		_stage = Stage.ADULT
		_say("我长大了!", 10)
	elif _stage == Stage.ADULT and age >= MAX_AGE:
		_stage = Stage.NEW_EGG
		_scr = Screen.HOME
		_dialogue = ""

func _auto_dialogue() -> void:
	if _dialogue != "":
		return
	if _scr != Screen.HOME:
		return
	if _frame != 0 or randf() >= 0.28:
		return
	if health < 30.0:
		_say(_txt_sick.pick_random(), 6)
	elif hunger < 25.0:
		_say(_txt_hungry.pick_random(), 6)
	elif happy < 25.0:
		_say(_txt_sad.pick_random(), 6)
	elif clean_v < 25.0:
		_say(_txt_dirty.pick_random(), 6)
	elif happy > 70.0 and hunger > 50.0:
		_say(_txt_happy.pick_random(), 6)
	elif _stage == Stage.BABY:
		_say(_txt_baby.pick_random(), 5)
	else:
		_say(_txt_idle.pick_random(), 5)

func _say(msg: String, ticks: int) -> void:
	_dialogue = msg
	_dlg_ticks = ticks

# ── 字体 ─────────────────────────────────────────────────

func _make_mono() -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Consolas", "Courier New", "Liberation Mono", "monospace"])
	return f

# ── UI 构建 ──────────────────────────────────────────────

func _build_ui() -> void:
	var shell := Panel.new()
	shell.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var ss := StyleBoxFlat.new()
	ss.bg_color = COL_SHELL
	ss.set_corner_radius_all(14)
	shell.add_theme_stylebox_override("panel", ss)
	add_child(shell)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	var tp := Control.new()
	tp.custom_minimum_size.y = 16
	root.add_child(tp)

	# LCD 屏幕
	var sm := MarginContainer.new()
	sm.add_theme_constant_override("margin_left", 16)
	sm.add_theme_constant_override("margin_right", 16)
	sm.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(sm)

	var sp := Panel.new()
	var sps := StyleBoxFlat.new()
	sps.bg_color = COL_LCD_BG
	sps.set_corner_radius_all(4)
	sps.set_border_width_all(2)
	sps.border_color = COL_LCD_BD
	sps.content_margin_left = 8
	sps.content_margin_right = 8
	sps.content_margin_top = 8
	sps.content_margin_bottom = 8
	sp.add_theme_stylebox_override("panel", sps)
	sm.add_child(sp)

	_lcd = Label.new()
	_lcd.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_lcd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lcd.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_lcd.add_theme_font_override("font", _font)
	_lcd.add_theme_font_size_override("font_size", 14)
	_lcd.add_theme_color_override("font_color", COL_LCD_TX)
	sp.add_child(_lcd)

	var mp := Control.new()
	mp.custom_minimum_size.y = 8
	root.add_child(mp)

	# 三颗按钮 + 标签
	var bm := MarginContainer.new()
	bm.add_theme_constant_override("margin_left", 20)
	bm.add_theme_constant_override("margin_right", 20)
	bm.add_theme_constant_override("margin_bottom", 14)
	root.add_child(bm)

	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 2)
	bm.add_child(bv)

	var bh := HBoxContainer.new()
	bh.alignment = BoxContainer.ALIGNMENT_CENTER
	bh.add_theme_constant_override("separation", 20)
	bv.add_child(bh)

	_mk_btn(bh, "◁", _on_select)
	_mk_btn(bh, "●", _on_confirm)
	_mk_btn(bh, "✕", _on_cancel)

	var lh := HBoxContainer.new()
	lh.alignment = BoxContainer.ALIGNMENT_CENTER
	lh.add_theme_constant_override("separation", 20)
	bv.add_child(lh)
	for txt in ["选择", "确认", "取消"]:
		var lb := Label.new()
		lb.text = txt
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lb.custom_minimum_size.x = 48
		lb.add_theme_font_size_override("font_size", 10)
		lb.add_theme_color_override("font_color", Color(COL_BTN_T, 0.45))
		lh.add_child(lb)

func _mk_btn(par: Control, txt: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = txt
	b.custom_minimum_size = Vector2(48, 48)
	b.focus_mode = Control.FOCUS_NONE
	var s := StyleBoxFlat.new()
	s.bg_color = COL_BTN_N
	s.set_corner_radius_all(24)
	b.add_theme_stylebox_override("normal", s)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var h: StyleBoxFlat = s.duplicate()
	h.bg_color = COL_BTN_H
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)
	b.add_theme_color_override("font_color", COL_BTN_T)
	b.add_theme_font_size_override("font_size", 18)
	b.pressed.connect(cb)
	par.add_child(b)

# ── 渲染 ─────────────────────────────────────────────────

func _refresh() -> void:
	if not _lcd:
		return
	match _stage:
		Stage.EGG:
			_lcd.text = _r_egg()
		Stage.HATCHING:
			_lcd.text = _r_hatching()
		Stage.DEAD:
			_lcd.text = _r_dead()
		Stage.NEW_EGG:
			_lcd.text = _r_new_egg()
		_:
			match _scr:
				Screen.HOME:  _lcd.text = _r_home()
				Screen.FEED:  _lcd.text = _r_act("♥ 投喂", _art_eat(), "好吃!")
				Screen.PLAY:  _lcd.text = _r_act("♪ 玩耍", _art_play(), "好开心!")
				Screen.SLEEP: _lcd.text = _r_act("☾ 睡觉", _art_sleep(), "zzZ...")
				Screen.CLEAN: _lcd.text = _r_act("✧ 清洁", _art_clean(), "干净了!")


# ── 各屏幕内容 ───────────────────────────────────────────

func _r_egg() -> String:
	var L := PackedStringArray()
	L.append("♥ 新生命 ♥")
	L.append("───────────────")
	L.append("")
	if _frame % 2 == 0:
		L.append("    .---.")
		L.append("   / . . \\")
		L.append("  |   ?   |")
		L.append("   \\_____/")
	else:
		L.append("    .---.")
		L.append("   /  .  \\")
		L.append("  |  . .  |")
		L.append("   \\_____/")
	L.append("")
	L.append("按[确认]敲一下!")
	return "\n".join(L)

func _r_hatching() -> String:
	var L := PackedStringArray()
	L.append("───────────────")
	L.append("")
	if _hatch_frame < 3:
		L.append("    ._*_.")
		L.append("   / _/. \\")
		L.append("  | /    |")
		L.append("   \\/___/")
		L.append("")
		L.append("  咔嚓...")
	elif _hatch_frame < 6:
		L.append("   _. . ._")
		L.append("  /  --.  \\")
		L.append("  |  o o  |")
		L.append("   \\_____/")
		L.append("")
		L.append("  咔嚓咔嚓!")
	else:
		L.append("")
		L.append("  /\\_/\\")
		L.append(" ( o o )")
		L.append(" ( >w< )")
		L.append("")
		L.append(" 喵~! 出生了!")
	return "\n".join(L)

func _r_home() -> String:
	var L := PackedStringArray()
	# 菜单行（文字）
	var row := ""
	for i in MENU.size():
		if i == _menu_idx:
			row += "[%s]" % MENU[i]
		else:
			row += " %s " % MENU[i]
	L.append(row)
	L.append("───────────────")
	for ln in _art_idle():
		L.append(ln)
	L.append("")
	# 对话
	L.append(_dialogue if _dialogue != "" else _mood_hint())
	L.append("───────────────")
	# 状态条
	L.append("饱%s 乐%s" % [_bar(hunger), _bar(happy)])
	L.append("净%s 命%s" % [_bar(clean_v), _bar(health)])
	return "\n".join(L)

func _r_act(title: String, art: Array, msg: String) -> String:
	var L := PackedStringArray()
	L.append(title)
	L.append("───────────────")
	for ln in art:
		L.append(ln)
	L.append("")
	L.append(msg)
	return "\n".join(L)

func _r_dead() -> String:
	var L := PackedStringArray()
	L.append("───────────────")
	L.append("")
	L.append("      +")
	L.append("     /|\\")
	L.append("    /_|_\\")
	L.append("   R.I.P.")
	L.append("")
	L.append(" 它去了远方...")
	L.append("")
	L.append("[确认] 再来一次")
	return "\n".join(L)

func _r_new_egg() -> String:
	var L := PackedStringArray()
	L.append("───────────────")
	L.append("")
	L.append("  /\\_/\\   ♥")
	L.append(" ( ^ ^ )")
	L.append(" (  w  ) bye~")
	L.append("")
	L.append("  它留下了一颗蛋!")
	L.append("")
	L.append("[确认] 孵化新蛋")
	return "\n".join(L)

func _bar(v: float) -> String:
	var n := int(v / 20.0)
	return "█".repeat(n) + "░".repeat(5 - n)

func _mood_hint() -> String:
	if health < 30.0: return "不舒服..."
	if hunger < 20.0: return "饿..."
	if clean_v < 20.0: return "脏..."
	if happy < 20.0: return "闷..."
	if happy > 70.0: return "♪~"
	return "..."

# ── ASCII 美术 ───────────────────────────────────────────

func _art_idle() -> Array:
	var ey := _eyes()
	var mo: String = "w" if happy > 30.0 else "n"
	var tl: String = " ~" if _frame % 2 == 0 else ""
	if _stage == Stage.BABY:
		return [
			'  /\\_/\\',
			' ( %s )' % ey,
			' ( >%s< )%s' % [mo, tl],
		]
	return [
		'  /\\_/\\',
		' ( %s )' % ey,
		' (  %s  )%s' % [mo, tl],
		' (")_(")',
	]

func _eyes() -> String:
	if _blink: return "- -"
	if health < 20.0: return "x x"
	if hunger < 20.0 or happy < 20.0: return "; ;"
	if happy > 70.0: return "^ ^"
	return "o o"

func _body() -> Array:
	if _stage == Stage.BABY:
		return ['  /\\_/\\', ' ( o o )', ' (  w  )']
	return ['  /\\_/\\', ' ( o o )', ' (  w  )', ' (")_(")']

func _art_eat() -> Array:
	var a := _body()
	if _frame % 2 == 0:
		a[1] = ' ( o o ) ♪'
		a[2] = ' ( ~w~ )'
	else:
		a[1] = ' ( o o )'
		a[2] = ' (~w~ ) ♪'
	return a

func _art_play() -> Array:
	var a := _body()
	if _frame % 2 == 0:
		a[0] = '  /\\_/\\  ♪'
		a[1] = ' ( > < )'
		a[2] = ' (  w  )♪'
	else:
		a[0] = ' ♪/\\_/\\'
		a[1] = '  ( > < )'
		a[2] = ' ♪(  w  )'
	return a

func _art_sleep() -> Array:
	var zs: Array[String] = ["z", "zZ", "zZz"]
	var z: String = zs[_frame % 3]
	var a := _body()
	a[1] = ' ( - - ) %s' % z
	return a

func _art_clean() -> Array:
	var a := _body()
	if _frame % 2 == 0:
		a[0] = '  /\\_/\\ .o'
		a[1] = ' ( o o )o'
	else:
		a[0] = ' o./\\_/\\'
		a[1] = ' o( o o )'
	return a

# ── 输入处理 ─────────────────────────────────────────────

func _on_select() -> void:
	if _stage in [Stage.EGG, Stage.HATCHING, Stage.DEAD, Stage.NEW_EGG]:
		return
	if _scr == Screen.HOME:
		_menu_idx = (_menu_idx + 1) % MENU.size()
		_refresh()

func _on_confirm() -> void:
	match _stage:
		Stage.EGG:
			_stage = Stage.HATCHING
			_hatch_frame = 0
			_refresh()
		Stage.DEAD, Stage.NEW_EGG:
			_restart()
		_:
			if _scr == Screen.HOME:
				_do_menu()

func _on_cancel() -> void:
	if _stage in [Stage.EGG, Stage.HATCHING, Stage.DEAD, Stage.NEW_EGG]:
		return
	if _scr == Screen.HOME:
		_menu_idx = (_menu_idx - 1 + MENU.size()) % MENU.size()
	else:
		_scr = Screen.HOME
	_refresh()

func _do_menu() -> void:
	match _menu_idx:
		0: _do_feed()
		1: _do_play()
		2: _do_sleep()
		3: _do_clean()

# ── 操作 ─────────────────────────────────────────────────

func _do_feed() -> void:
	if hunger >= 95.0:
		_say("吃不下了!", 5)
		_refresh()
		return
	hunger = minf(100.0, hunger + 25.0)
	happy  = minf(100.0, happy  + 5.0)
	_scr = Screen.FEED
	_action_ticks = 5
	var msgs: Array[String] = ["好吃!", "谢谢~", "满足♥", "还想吃!"]
	_say(msgs.pick_random(), 5)
	_refresh()

func _do_play() -> void:
	if health < 15.0:
		_say("不舒服...", 5)
		_refresh()
		return
	happy  = minf(100.0, happy  + 20.0)
	hunger = maxf(0.0, hunger - 8.0)
	_scr = Screen.PLAY
	_action_ticks = 5
	var msgs: Array[String] = ["好开心!", "再玩!", "耶~♪"]
	_say(msgs.pick_random(), 5)
	_refresh()

func _do_sleep() -> void:
	health = minf(100.0, health + 10.0)
	happy  = minf(100.0, happy  + 3.0)
	_scr = Screen.SLEEP
	_action_ticks = 6
	_say("晚安...", 6)
	_refresh()

func _do_clean() -> void:
	clean_v = minf(100.0, clean_v + 25.0)
	happy   = minf(100.0, happy  + 5.0)
	_scr = Screen.CLEAN
	_action_ticks = 4
	var msgs: Array[String] = ["干净了!", "舒服~", "清爽♪"]
	_say(msgs.pick_random(), 4)
	_refresh()

func _restart() -> void:
	_stage = Stage.EGG
	_scr = Screen.HOME
	_menu_idx = 0
	hunger = 50.0
	happy = 50.0
	clean_v = 80.0
	health = 100.0
	age = 0
	_dialogue = ""
	_dlg_ticks = 0
	_decay_cd = 0
	_refresh()
