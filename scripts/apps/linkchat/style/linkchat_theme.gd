@tool
extends Resource
class_name LinkChatTheme
## LinkChat 专属样式工厂

# --- 背景色 ---
const COLOR_BG_NAV = Color("#EDEEF0") # 最左导航条，偏深灰
const COLOR_BG_SIDEBAR = Color("#FAFBFC") # 频道列表，偏白
const COLOR_BG_MAIN = Color("#F8FBFF")
const COLOR_BG_HEADER = Color("#FCFDFF")
const COLOR_BG_INPUT_AREA = Color("#FFFFFF")
const COLOR_BG_INPUT_FIELD = Color("#FFFFFF")

# --- 气泡色 ---
const COLOR_BUBBLE_NPC = Color("#FFFDFC")
const COLOR_BUBBLE_PLAYER = Color("#B8D5FF")
const COLOR_BUBBLE_SYSTEM = Color("#F0F0F0") # 系统消息浅灰底
const COLOR_BUBBLE_NPC_BORDER = Color("#C8D1DE")
const COLOR_BUBBLE_PLAYER_BORDER = Color("#7CA7E6")

# --- 侧边栏 ---
const COLOR_CONTACT_HOVER = Color("#F0F5FC")
const COLOR_CONTACT_SELECTED = Color("#E6F0FF")
const COLOR_CONTACT_SEPARATOR = Color.TRANSPARENT # 去掉分割线

# --- 文字色 ---
const COLOR_TEXT_PRIMARY = Color("#20283A")
const COLOR_TEXT_SECONDARY = Color("#68738A")
const COLOR_TEXT_MUTED = Color("#B0B0B0")
const COLOR_TEXT_TIME = Color("#C0C0C0")
const COLOR_TEXT_SENDER_NPC = Color("#3F4B62")
const COLOR_TEXT_SENDER_PLAYER = Color("#254C82")

# --- 状态色 ---
const COLOR_ONLINE = Color("#4CD964")
const COLOR_UNREAD_BADGE = Color("#FF3B30")
const COLOR_ACCENT = Color("#76A9F0")
const COLOR_ACCENT_HOVER = Color("#5E91D9")

# --- 边框 ---
const COLOR_BORDER = Color("#E0E0E0")
const COLOR_BORDER_INPUT = Color("#C8D5E5")
const COLOR_BORDER_FOCUS = Color("#76A9F0")

# --- 圆角 ---
const RADIUS_SM: int = 9
const RADIUS_MD: int = 15
const RADIUS_LG: int = 27
const RADIUS_BUBBLE: int = 24
const RADIUS_AVATAR: int = 39


# ============ StyleBox 工厂 ============

static func rounded_flat(bg: Color, radius: int = RADIUS_MD, border_color: Color = Color.TRANSPARENT, border_width: int = 0, shadow_color: Color = Color.TRANSPARENT, shadow_size: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.corner_radius_top_left = radius
	s.corner_radius_top_right = radius
	s.corner_radius_bottom_left = radius
	s.corner_radius_bottom_right = radius
	if border_color != Color.TRANSPARENT and border_width > 0:
		s.border_width_left = border_width
		s.border_width_top = border_width
		s.border_width_right = border_width
		s.border_width_bottom = border_width
		s.border_color = border_color

	if shadow_size > 0:
		s.shadow_color = shadow_color
		s.shadow_size = shadow_size
		s.shadow_offset = Vector2(0, 1) # 微小下偏移
	return s


# ============ 组件样式 ============

## NPC 消息气泡
static func get_npc_bubble_style() -> StyleBoxFlat:
	var s := rounded_flat(COLOR_BUBBLE_NPC, RADIUS_BUBBLE, COLOR_BUBBLE_NPC_BORDER, 2, Color(0.12, 0.18, 0.28, 0.16), 8)
	s.corner_radius_top_left = 9
	s.shadow_offset = Vector2(0, 4)
	s.content_margin_left = 33
	s.content_margin_top = 24
	s.content_margin_right = 33
	s.content_margin_bottom = 24
	return s


## 玩家消息气泡
static func get_player_bubble_style() -> StyleBoxFlat:
	var s := rounded_flat(COLOR_BUBBLE_PLAYER, RADIUS_BUBBLE, COLOR_BUBBLE_PLAYER_BORDER, 2, Color(0.12, 0.2, 0.34, 0.2), 8)
	s.corner_radius_top_right = 9
	s.shadow_offset = Vector2(0, 4)
	s.content_margin_left = 33
	s.content_margin_top = 24
	s.content_margin_right = 33
	s.content_margin_bottom = 24
	return s


static func get_name_tag_style(is_player: bool) -> StyleBoxFlat:
	var background_color := Color("#EEF5FF") if is_player else Color("#FFFFFF")
	var border_color := Color("#9CBCE8") if is_player else Color("#D1D8E2")
	var s := rounded_flat(background_color, 18, border_color, 2, Color(0.1, 0.15, 0.24, 0.14), 4)
	s.shadow_offset = Vector2(0, 2)
	s.content_margin_left = 24
	s.content_margin_top = 5
	s.content_margin_right = 24
	s.content_margin_bottom = 6
	return s


static func get_chat_header_style() -> StyleBoxFlat:
	var s := rounded_flat(COLOR_BG_HEADER, 0)
	s.border_width_bottom = 2
	s.border_color = Color("#D9E2EF")
	s.shadow_color = Color(0.12, 0.18, 0.28, 0.09)
	s.shadow_size = 5
	s.shadow_offset = Vector2(0, 2)
	return s


static func get_input_area_style() -> StyleBoxFlat:
	var s := rounded_flat(Color("#F8FAFD"), 0)
	s.border_width_top = 2
	s.border_color = Color("#CFDBEA")
	s.shadow_color = Color(0.1, 0.16, 0.26, 0.12)
	s.shadow_size = 9
	s.shadow_offset = Vector2(0, -4)
	return s


## 侧边栏背景
static func get_sidebar_bg_style() -> StyleBoxFlat:
	var s := rounded_flat(Color("#F7FAFE"), 0)
	s.border_width_right = 2
	s.border_color = Color("#D4DFED")
	s.shadow_color = Color(0.12, 0.18, 0.28, 0.08)
	s.shadow_size = 7
	s.shadow_offset = Vector2(3, 0)
	return s


static func get_nav_strip_style() -> StyleBoxFlat:
	var s := rounded_flat(Color("#EAF1FA"), 0)
	s.border_width_right = 2
	s.border_color = Color("#CCD9E9")
	return s


static func get_nav_button_style(active: bool) -> StyleBoxFlat:
	if not active:
		return rounded_flat(Color.TRANSPARENT, 18)
	var s := rounded_flat(Color("#FFFFFF"), 18, Color("#B9CCE5"), 2, Color(0.1, 0.17, 0.28, 0.14), 7)
	s.shadow_offset = Vector2(0, 3)
	return s


static func get_moment_card_style() -> StyleBoxFlat:
	var s := rounded_flat(Color("#FFFFFF"), 27, Color("#CFDAE8"), 2, Color(0.1, 0.16, 0.26, 0.14), 10)
	s.shadow_offset = Vector2(0, 5)
	return s


## 联系人条目 hover
static func get_contact_hover_style() -> StyleBoxFlat:
	return rounded_flat(COLOR_CONTACT_HOVER, RADIUS_SM)


## 联系人条目 selected
static func get_contact_selected_style() -> StyleBoxFlat:
	return rounded_flat(COLOR_CONTACT_SELECTED, RADIUS_SM)


## 输入框
static func get_input_field_style() -> StyleBoxFlat:
	var s := rounded_flat(COLOR_BG_INPUT_FIELD, RADIUS_LG, COLOR_BORDER_INPUT, 2, Color(0.1, 0.16, 0.25, 0.1), 5)
	s.shadow_offset = Vector2(0, 2)
	s.content_margin_left = 30
	s.content_margin_top = 20
	s.content_margin_right = 30
	s.content_margin_bottom = 20
	return s


## 输入框 focus
static func get_input_field_focus_style() -> StyleBoxFlat:
	var s := rounded_flat(Color("#FFFFFF"), RADIUS_LG, COLOR_BORDER_FOCUS, 2, Color(0.15, 0.35, 0.65, 0.14), 6)
	s.shadow_offset = Vector2(0, 2)
	s.content_margin_left = 30
	s.content_margin_top = 20
	s.content_margin_right = 30
	s.content_margin_bottom = 20
	return s


## 输入框 disabled / read_only
static func get_input_field_disabled_style() -> StyleBoxFlat:
	var s := rounded_flat(Color("#EFF3F8"), RADIUS_LG, Color("#D3DDE9"), 2)
	s.content_margin_left = 30
	s.content_margin_top = 20
	s.content_margin_right = 30
	s.content_margin_bottom = 20
	return s


## 发送按钮
static func get_send_button_style() -> StyleBoxFlat:
	var s := rounded_flat(Color("#E5EBF3"), RADIUS_LG, Color("#D0DAE6"), 2)
	s.content_margin_left = 27
	s.content_margin_top = 18
	s.content_margin_right = 27
	s.content_margin_bottom = 18
	return s


## 发送按钮 hover
static func get_send_button_hover_style() -> StyleBoxFlat:
	var s := rounded_flat(COLOR_ACCENT, RADIUS_LG, COLOR_ACCENT_HOVER, 2, Color(0.12, 0.28, 0.52, 0.18), 6)
	s.shadow_offset = Vector2(0, 3)
	s.content_margin_left = 27
	s.content_margin_top = 18
	s.content_margin_right = 27
	s.content_margin_bottom = 18
	return s


## 头像占位（圆形）
static func get_avatar_style(color: Color = Color("#555560")) -> StyleBoxFlat:
	return rounded_flat(color, RADIUS_AVATAR)


## 未读红点
static func get_unread_badge_style() -> StyleBoxFlat:
	return rounded_flat(COLOR_UNREAD_BADGE, 18)


## 推荐回复选项 (Chip)
static func get_chip_style() -> StyleBoxFlat:
	# 改浅灰底 + 更深边框，在聊天主区白底上立起来
	var s := rounded_flat(Color("#F4F6F8"), RADIUS_LG, Color("#D1D5DB"), 1)
	s.content_margin_left = 24
	s.content_margin_top = 12
	s.content_margin_right = 24
	s.content_margin_bottom = 12
	return s


static func get_chip_hover_style() -> StyleBoxFlat:
	var s := rounded_flat(Color("#EDF5FF"), RADIUS_LG, COLOR_ACCENT, 1)
	s.content_margin_left = 24
	s.content_margin_top = 12
	s.content_margin_right = 24
	s.content_margin_bottom = 12
	return s


## 推荐回复 chip — disabled（与 chip normal 同边距，底色与边框略灰化）
static func get_chip_disabled_style() -> StyleBoxFlat:
	var s := rounded_flat(Color("#EBEDF0"), RADIUS_LG, Color("#D8DCE3"), 1)
	s.content_margin_left = 24
	s.content_margin_top = 12
	s.content_margin_right = 24
	s.content_margin_bottom = 12
	return s


## 剧情选项使用整行卡片，避免和自由输入的短推荐词混淆。
static func get_option_panel_style() -> StyleBoxFlat:
	var s := rounded_flat(Color("#FFFFFF"), 18, Color("#C7D5E8"), 2, Color(0.1, 0.17, 0.28, 0.13), 7)
	s.shadow_offset = Vector2(0, 3)
	s.content_margin_left = 30
	s.content_margin_top = 18
	s.content_margin_right = 30
	s.content_margin_bottom = 18
	return s


static func get_option_panel_hover_style() -> StyleBoxFlat:
	var s := rounded_flat(Color("#EDF5FF"), 18, COLOR_ACCENT, 2, Color(0.1, 0.2, 0.36, 0.18), 9)
	s.shadow_offset = Vector2(0, 4)
	s.content_margin_left = 30
	s.content_margin_top = 18
	s.content_margin_right = 30
	s.content_margin_bottom = 18
	return s


static func get_option_panel_pressed_style() -> StyleBoxFlat:
	var s := rounded_flat(Color("#DDEBFF"), 18, COLOR_ACCENT_HOVER, 2, Color(0.1, 0.18, 0.32, 0.12), 4)
	s.shadow_offset = Vector2(0, 2)
	s.content_margin_left = 30
	s.content_margin_top = 18
	s.content_margin_right = 30
	s.content_margin_bottom = 18
	return s
