@tool
extends Resource
class_name LinkChatTheme
## LinkChat 专属样式工厂

# --- 背景色 ---
const COLOR_BG_NAV = Color("#EDEEF0") # 最左导航条，偏深灰
const COLOR_BG_SIDEBAR = Color("#FAFBFC") # 频道列表，偏白
const COLOR_BG_MAIN = Color("#FFFFFF") # 纯白聊天主区
const COLOR_BG_HEADER = Color("#F7F7F7") # 顶部微灰
const COLOR_BG_INPUT_AREA = Color("#FFFFFF")
const COLOR_BG_INPUT_FIELD = Color("#F5F5F5") # 输入框胶囊底色

# --- 气泡色 ---
const COLOR_BUBBLE_NPC = Color("#F2F4F5") # 浅灰底，与白背景区分
const COLOR_BUBBLE_PLAYER = Color("#95EC69") # 微信/Line 绿
const COLOR_BUBBLE_SYSTEM = Color("#F0F0F0") # 系统消息浅灰底

# --- 侧边栏 ---
const COLOR_CONTACT_HOVER = Color("#E8EAEE")    # hover 更偏蓝灰，与新 sidebar 白底对比更清晰
const COLOR_CONTACT_SELECTED = Color("#B8C1C9") # 选中更深，与 hover 明显区分
const COLOR_CONTACT_SEPARATOR = Color.TRANSPARENT # 去掉分割线

# --- 文字色 ---
const COLOR_TEXT_PRIMARY = Color("#1F1F1F")
const COLOR_TEXT_SECONDARY = Color("#858585")
const COLOR_TEXT_MUTED = Color("#B0B0B0")
const COLOR_TEXT_TIME = Color("#C0C0C0")
const COLOR_TEXT_SENDER_NPC = Color("#555555")
const COLOR_TEXT_SENDER_PLAYER = Color("#1F1F1F") # 浅绿背景用深色字

# --- 状态色 ---
const COLOR_ONLINE = Color("#4CD964")
const COLOR_UNREAD_BADGE = Color("#FF3B30")
const COLOR_ACCENT = Color("#95EC69") # 主题色
const COLOR_ACCENT_HOVER = Color("#89D961")

# --- 边框 ---
const COLOR_BORDER = Color("#E0E0E0")
const COLOR_BORDER_INPUT = Color.TRANSPARENT
const COLOR_BORDER_FOCUS = Color("#95EC69")

# --- 圆角 ---
const RADIUS_SM: int = 6
const RADIUS_MD: int = 10
const RADIUS_LG: int = 18
const RADIUS_BUBBLE: int = 16
const RADIUS_AVATAR: int = 26 # 更适配放大后的头像尺寸


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
	# 白底 + 微阴影；统一四角圆角，取消弱尖角
	var s := rounded_flat(COLOR_BUBBLE_NPC, RADIUS_BUBBLE, Color.TRANSPARENT, 0, Color(0, 0, 0, 0.05), 1)
	s.content_margin_left = 20
	s.content_margin_top = 14
	s.content_margin_right = 20
	s.content_margin_bottom = 14
	return s


## 玩家消息气泡
static func get_player_bubble_style() -> StyleBoxFlat:
	var s := rounded_flat(COLOR_BUBBLE_PLAYER, RADIUS_BUBBLE)
	s.content_margin_left = 20
	s.content_margin_top = 14
	s.content_margin_right = 20
	s.content_margin_bottom = 14
	return s


## 侧边栏背景
static func get_sidebar_bg_style() -> StyleBoxFlat:
	return rounded_flat(COLOR_BG_SIDEBAR, 0)


## 联系人条目 hover
static func get_contact_hover_style() -> StyleBoxFlat:
	return rounded_flat(COLOR_CONTACT_HOVER, RADIUS_SM)


## 联系人条目 selected
static func get_contact_selected_style() -> StyleBoxFlat:
	return rounded_flat(COLOR_CONTACT_SELECTED, RADIUS_SM)


## 输入框
static func get_input_field_style() -> StyleBoxFlat:
	var s := rounded_flat(COLOR_BG_INPUT_FIELD, RADIUS_LG)
	s.content_margin_left = 20
	s.content_margin_top = 12
	s.content_margin_right = 20
	s.content_margin_bottom = 12
	return s


## 输入框 focus
static func get_input_field_focus_style() -> StyleBoxFlat:
	var s := rounded_flat(Color("#FFFFFF"), RADIUS_LG, COLOR_BORDER_FOCUS, 1)
	s.content_margin_left = 20
	s.content_margin_top = 12
	s.content_margin_right = 20
	s.content_margin_bottom = 12
	return s


## 输入框 disabled / read_only
static func get_input_field_disabled_style() -> StyleBoxFlat:
	var s := rounded_flat(Color("#E5E5E5"), RADIUS_LG) # 灰色不可用状态
	s.content_margin_left = 20
	s.content_margin_top = 12
	s.content_margin_right = 20
	s.content_margin_bottom = 12
	return s


## 发送按钮
static func get_send_button_style() -> StyleBoxFlat:
	var s := rounded_flat(COLOR_BG_INPUT_FIELD, RADIUS_LG) # 默认灰底
	s.content_margin_left = 18
	s.content_margin_top = 10
	s.content_margin_right = 18
	s.content_margin_bottom = 10
	return s


## 发送按钮 hover
static func get_send_button_hover_style() -> StyleBoxFlat:
	var s := rounded_flat(COLOR_ACCENT, RADIUS_LG) # 悬停变绿
	s.content_margin_left = 18
	s.content_margin_top = 10
	s.content_margin_right = 18
	s.content_margin_bottom = 10
	return s


## 头像占位（圆形）
static func get_avatar_style(color: Color = Color("#555560")) -> StyleBoxFlat:
	return rounded_flat(color, RADIUS_AVATAR)


## 未读红点
static func get_unread_badge_style() -> StyleBoxFlat:
	return rounded_flat(COLOR_UNREAD_BADGE, 12)


## 推荐回复选项 (Chip)
static func get_chip_style() -> StyleBoxFlat:
	# 改浅灰底 + 更深边框，在聊天主区白底上立起来
	var s := rounded_flat(Color("#F4F6F8"), RADIUS_LG, Color("#D1D5DB"), 1)
	s.content_margin_left = 16
	s.content_margin_top = 8
	s.content_margin_right = 16
	s.content_margin_bottom = 8
	return s


static func get_chip_hover_style() -> StyleBoxFlat:
	var s := rounded_flat(Color("#E8F6DD"), RADIUS_LG, COLOR_ACCENT, 1)
	s.content_margin_left = 16
	s.content_margin_top = 8
	s.content_margin_right = 16
	s.content_margin_bottom = 8
	return s


## 推荐回复 chip — disabled（与 chip normal 同边距，底色与边框略灰化）
static func get_chip_disabled_style() -> StyleBoxFlat:
	var s := rounded_flat(Color("#EBEDF0"), RADIUS_LG, Color("#D8DCE3"), 1)
	s.content_margin_left = 16
	s.content_margin_top = 8
	s.content_margin_right = 16
	s.content_margin_bottom = 8
	return s
