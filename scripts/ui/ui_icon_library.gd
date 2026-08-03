class_name UIIconLibrary
extends RefCounted

const ICON_WARNING: Texture2D = preload("res://Assets/images/ui_icons/ui_icon_warning.png")
const ICON_INFO: Texture2D = preload("res://Assets/images/ui_icons/ui_icon_info.png")
const ICON_SETTINGS: Texture2D = preload("res://Assets/images/ui_icons/ui_icon_settings.png")
const ICON_POWER: Texture2D = preload("res://Assets/images/ui_icons/ui_icon_power.png")

const _ICON_MAP := {
	"warning": ICON_WARNING,
	"info": ICON_INFO,
	"settings": ICON_SETTINGS,
	"power": ICON_POWER,
	"⚠": ICON_WARNING,
	"💡": ICON_INFO,
	"⚙": ICON_SETTINGS,
	"⏻": ICON_POWER,
}


static func get_icon(token: String) -> Texture2D:
	var normalized := token.strip_edges().to_lower()
	if normalized.is_empty():
		return null
	# 先查预加载贴图
	if _ICON_MAP.has(normalized):
		return _ICON_MAP[normalized]
	if _ICON_MAP.has(token.strip_edges()):
		return _ICON_MAP[token.strip_edges()]
	return null
