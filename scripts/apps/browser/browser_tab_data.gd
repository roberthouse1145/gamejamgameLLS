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
var display_url: String = ""
var is_search_result: bool = false
var keyword: String = ""
var state: TabState = TabState.IDLE
var request_id: String = ""
var search_results: Array = []
var page_content: Dictionary = {}
var error_message: String = ""
var design_prompt: String = ""
