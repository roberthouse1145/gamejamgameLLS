@tool
extends Resource
class_name DeepCodeTheme

## Claude-inspired warm color palette

# Background colors
const COLOR_BG_MAIN = Color("#2b2b2b")        # Main chat area — warm dark
const COLOR_BG_SIDEBAR = Color("#252525")      # Sidebar / checklist
const COLOR_BG_INPUT = Color("#333333")        # Input field area
const COLOR_BG_INPUT_FIELD = Color("#3d3d3d")  # Input field itself
const COLOR_BG_HEADER = Color("#232323")       # Title bar / header

# Surface colors (cards, panels)
const COLOR_SURFACE = Color("#323232")         # Elevated surface (thinking panel, tool block)
const COLOR_SURFACE_HOVER = Color("#3a3a3a")   # Hover state

# Border colors
const COLOR_BORDER = Color("#404040")          # Subtle borders
const COLOR_BORDER_INPUT = Color("#505050")    # Input field border
const COLOR_BORDER_FOCUS = Color("#d4a574")    # Focus ring — warm accent
const COLOR_BORDER_THINKING = Color("#7c6f9b") # Thinking panel left border — muted purple

# Text colors
const COLOR_TEXT_PRIMARY = Color("#ececec")     # Main text
const COLOR_TEXT_SECONDARY = Color("#a0a0a0")  # Dimmed text
const COLOR_TEXT_MUTED = Color("#707070")       # Very dim (timestamps, etc.)
const COLOR_TEXT_ACCENT = Color("#d4a574")      # Warm accent (author labels, links)
const COLOR_TEXT_USER = Color("#ececec")        # User message text
const COLOR_TEXT_AI = Color("#d8d8d8")          # AI message text

# Accent colors
const COLOR_ACCENT = Color("#d4a574")          # Primary accent — warm gold/tan
const COLOR_ACCENT_HOVER = Color("#e0b88a")    # Accent hover
const COLOR_ERROR = Color("#e06c75")           # Error red
const COLOR_SUCCESS = Color("#98c379")         # Success green

# Radius
const RADIUS_SM: int = 6
const RADIUS_MD: int = 10
const RADIUS_LG: int = 16
const RADIUS_XL: int = 20


# ============ StyleBox Factories ============

static func rounded_flat(bg: Color, radius: int = RADIUS_MD, border_color: Color = Color.TRANSPARENT, border_width: int = 0) -> StyleBoxFlat:
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
	return s


static func left_border_flat(bg: Color, left_color: Color, left_width: int = 3, radius: int = RADIUS_SM) -> StyleBoxFlat:
	var s := rounded_flat(bg, radius)
	s.border_width_left = left_width
	s.border_color = left_color
	return s


# ============ Component Styles ============

## Main chat background
static func get_main_bg_style() -> StyleBoxFlat:
	return rounded_flat(COLOR_BG_MAIN, 0)


## Input field normal state
static func get_input_field_style() -> StyleBoxFlat:
	var s := rounded_flat(COLOR_BG_INPUT_FIELD, RADIUS_LG, COLOR_BORDER_INPUT, 1)
	s.content_margin_left = 16
	s.content_margin_top = 10
	s.content_margin_right = 16
	s.content_margin_bottom = 10
	return s


## Input field focused state
static func get_input_field_focus_style() -> StyleBoxFlat:
	var s := rounded_flat(COLOR_BG_INPUT_FIELD, RADIUS_LG, COLOR_BORDER_FOCUS, 1)
	s.content_margin_left = 16
	s.content_margin_top = 10
	s.content_margin_right = 16
	s.content_margin_bottom = 10
	return s


## Send button normal
static func get_send_button_style() -> StyleBoxFlat:
	var s := rounded_flat(COLOR_ACCENT, RADIUS_LG)
	s.content_margin_left = 16
	s.content_margin_top = 8
	s.content_margin_right = 16
	s.content_margin_bottom = 8
	return s


## Send button hover
static func get_send_button_hover_style() -> StyleBoxFlat:
	var s := rounded_flat(COLOR_ACCENT_HOVER, RADIUS_LG)
	s.content_margin_left = 16
	s.content_margin_top = 8
	s.content_margin_right = 16
	s.content_margin_bottom = 8
	return s


## Send button pressed
static func get_send_button_pressed_style() -> StyleBoxFlat:
	var s := rounded_flat(COLOR_ACCENT.darkened(0.1), RADIUS_LG)
	s.content_margin_left = 16
	s.content_margin_top = 8
	s.content_margin_right = 16
	s.content_margin_bottom = 8
	return s


## Thinking panel (collapsible)
static func get_thinking_panel_style() -> StyleBoxFlat:
	return left_border_flat(COLOR_SURFACE, COLOR_BORDER_THINKING, 3, RADIUS_SM)


## Tool status block
static func get_tool_block_style() -> StyleBoxFlat:
	return left_border_flat(COLOR_SURFACE, COLOR_ACCENT, 3, RADIUS_SM)


## Checklist toggle button
static func get_checklist_toggle_style() -> StyleBoxFlat:
	var s := rounded_flat(COLOR_SURFACE, RADIUS_SM, COLOR_BORDER, 1)
	s.content_margin_left = 12
	s.content_margin_top = 4
	s.content_margin_right = 12
	s.content_margin_bottom = 4
	return s


## Window title bar
static func get_window_titlebar_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = COLOR_BG_HEADER
	s.corner_radius_top_left = RADIUS_MD
	s.corner_radius_top_right = RADIUS_MD
	s.corner_radius_bottom_left = 0
	s.corner_radius_bottom_right = 0
	return s


## Window body background
static func get_window_body_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = COLOR_BG_MAIN
	s.corner_radius_top_left = 0
	s.corner_radius_top_right = 0
	s.corner_radius_bottom_left = RADIUS_MD
	s.corner_radius_bottom_right = RADIUS_MD
	s.border_width_left = 1
	s.border_width_right = 1
	s.border_width_bottom = 1
	s.border_color = COLOR_BORDER
	return s


## Window full background (with all rounded corners + border)
static func get_window_bg_style() -> StyleBoxFlat:
	var s := rounded_flat(COLOR_BG_MAIN, RADIUS_MD, COLOR_BORDER, 1)
	return s


## Empty / transparent style
static func get_empty_style() -> StyleBoxEmpty:
	return StyleBoxEmpty.new()
