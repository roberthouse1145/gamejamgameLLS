extends Node

const PageMarkParserClass = preload("res://scripts/apps/browser/page_mark_parser.gd")

var _failures: int = 0
var _opened_page: Dictionary = {}
var _search_results: Array = []


func _ready() -> void:
	_test_page_mark_parser()
	await _test_browser_manager()
	if _failures == 0:
		print("[PASS] browser infrastructure")
	else:
		push_error("[FAIL] browser infrastructure: %d checks failed" % _failures)


func _test_page_mark_parser() -> void:
	var parsed: Dictionary = PageMarkParserClass.parse("::: col fill\n# Test Page\n\n[Open](url:browser://notice)\n:::")
	_check(not _dictionary_value(parsed.get("tree", {})).is_empty(), "PageMark builds a render tree")
	_check(_array_value(parsed.get("warnings", [])).is_empty(), "valid PageMark has no structural warnings")

	var pdf_parsed: Dictionary = PageMarkParserClass.parse(
		"::: pdf filename=notice.pdf\n::: document width=1200\n::: table cols=2\n::: cell\n项目\n:::\n::: cell\n内容\n:::\n:::\n:::\n:::"
	)
	var pdf_tree: Dictionary = _dictionary_value(pdf_parsed.get("tree", {}))
	_check(pdf_tree.get("type") == "pdf_viewer", "PageMark supports a PDF viewer root")
	var pdf_children: Array = _array_value(pdf_tree.get("children", []))
	_check(not pdf_children.is_empty() and _dictionary_value(pdf_children[0]).get("type") == "pdf_document", "PageMark preserves PDF document pages")


func _test_browser_manager() -> void:
	var manager: Node = get_node_or_null("/root/BrowserManager")
	_check(manager != null, "BrowserManager autoload exists")
	if manager == null:
		return
	var original_state: Dictionary = manager.get_run_state()
	manager.persist_history = false
	manager.allow_ai_requests = false
	manager.page_generated.connect(_on_page_generated)
	manager.search_completed.connect(_on_search_completed)

	_check(manager.has_premade_page("browser://welcome"), "neutral welcome page is indexed")
	manager.open_page("browser://welcome")
	await get_tree().process_frame
	_check(not _opened_page.is_empty(), "premade page opens without an LLM request")
	_check(not str(_opened_page.get("icon_path", "")).is_empty(), "premade page exposes its site icon")

	_opened_page.clear()
	manager.open_page("browser://offer-letter")
	await get_tree().process_frame
	_check(_opened_page.get("type") == "pdf_viewer", "offer letter opens through the PDF viewer DSL")

	_opened_page.clear()
	manager.open_page("browser://signup")
	await get_tree().process_frame
	var signup_children: Array = _array_value(_opened_page.get("children", []))
	_check(not signup_children.is_empty() and _dictionary_value(signup_children[0]).get("type") == "web_section", "signup page uses full-width website sections")

	manager.search("公告")
	await get_tree().process_frame
	_check(_search_results.size() == 1 and _search_results[0].get("url") == "browser://notice", "premade page participates in local search")
	_check(not manager.get_history_entries().is_empty(), "opening a page records browser history")

	manager.load_run_state(original_state)
	manager.allow_ai_requests = true
	manager.persist_history = true


func _on_page_generated(_request_id: String, _url: String, content: Dictionary) -> void:
	_opened_page = content.duplicate(true)


func _on_search_completed(_request_id: String, _keyword: String, results: Array) -> void:
	_search_results = results.duplicate(true)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[OK] %s" % label)
		return
	_failures += 1
	push_error("[CHECK FAILED] %s" % label)


func _dictionary_value(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


func _array_value(value: Variant) -> Array:
	return value if value is Array else []
