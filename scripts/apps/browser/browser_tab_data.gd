class_name BrowserTabData
extends RefCounted

enum TabState {
	IDLE,
	LOADING,
	READY,
	ERROR,
}

var tab_id: String = ""
var title: String = "新标签页"
var icon_path: String = "res://Assets/images/app_icons/sp_icon_browser.png"
var display_url: String = ""
var keyword: String = ""
var state: TabState = TabState.IDLE
var request_id: String = ""
var page_content: Dictionary = {}
var error_message: String = ""
var design_prompt: String = ""
