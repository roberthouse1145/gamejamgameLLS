extends Node

## 测试 DateManager 的 LLM 约会事件生成流程
## 验证：AIService 配置、prompt 加载、DSL 解析、实际 LLM 请求

const ActivityBlockParserClass = preload("res://scripts/activity/activity_block_parser.gd")
const ActivityCatalogProtocolClass = preload("res://scripts/activity/activity_catalog_protocol.gd")

func _ready() -> void:
	print("\n=== 约会事件 LLM 生成测试 ===\n")
	_test_ai_config_role()
	_test_prompt_loading()
	_test_parse_mock_output()
	_test_initial_events()
	_test_live_llm_request()
	print("\n=== 静态测试完成，等待 LLM 响应... ===\n")


func _test_ai_config_role() -> void:
	print("[Test] AIConfigManager role 配置")
	var config_mgr := AIConfigManager.new()
	var loaded: bool = config_mgr.load_config()
	_assert("配置文件已加载", loaded)

	var date_config: Dictionary = config_mgr.get_config_for_role("date_event")
	print("  date_event config: %s" % str(date_config))
	if date_config.is_empty():
		print("  [INFO] date_event 未配置，将 fallback 到 chat_default")

	var fallback_config: Dictionary = config_mgr.get_config_for_role("chat_default")
	_assert("chat_default 有配置", not fallback_config.is_empty())
	print("  chat_default model: %s" % str(fallback_config.get("model", "")))


func _test_prompt_loading() -> void:
	print("[Test] PromptManager 加载约会事件 prompt")
	var pm: Node = get_node_or_null("/root/PromptManager")
	_assert("PromptManager 可用", pm != null)
	if pm == null:
		return
	_assert("prompt key 存在", pm.has_method("has_prompt") and pm.has_prompt("date_event_generation"))
	if not pm.has_method("resolve_with_vars"):
		return
	var text: String = str(pm.resolve_with_vars("date_event_generation", {
		"next_day": "2",
	})).strip_edges()
	_assert("prompt 非空", not text.is_empty())
	_assert("prompt 包含 [DATE_EVENT]", text.find("[DATE_EVENT]") >= 0)
	_assert("prompt 强调公开字段只写出发前信息", text.find("出发前就能知道") >= 0)
	_assert("prompt 明确 detail_prompt 承载隐藏展开", text.find("detail_prompt") >= 0)
	print("  prompt 长度: %d 字符" % text.length())


func _test_parse_mock_output() -> void:
	print("[Test] 模拟 LLM 输出解析")
	var mock_output := """
[DATE_EVENT]
event_id=day3_ramen_fest
title=拉面祭·限定一夜
location_title=旧港区
location_id=harbor
subtitle=港口边搭起了临时拉面摊
description=旧港区今晚有民间拉面比赛，五六家摊位冒着蒸汽抢客人。可以一家一碗轮着吃。
detail_prompt=港口边的临时市集，灯泡串起暖黄光线，蒸汽和酱油味混在海风里。摊主吆喝声此起彼伏。
activity_hint=一起逛夜市吃拉面，边吃边评价哪家最好吃。
valid_phases=NIGHT
map_position=0.8|0.7
accent_color=#5B9BD5
reward_affection=2
reward_stress=-2
[/DATE_EVENT]

[DATE_EVENT]
event_id=day3_library_rain
title=图书馆靠窗位
location_title=蓝鲸大学
location_id=school
subtitle=午后的云压得很低，图书馆里刚好还有空位
description=教学楼这边有点闷，图书馆二楼靠窗的位置居然空着。可以先进去坐会儿，顺手翻翻杂志再决定待多久。
detail_prompt=刚坐下没多久，窗外就突然下起了暴雨，玻璃上很快全是水痕。空调嗡嗡响，远处有人在小声打电话。
activity_hint=一起在图书馆避雨，翻翻杂志，或者什么都不做就坐着听雨。
valid_phases=AFTERNOON
map_position=0.4|0.55
accent_color=#7D8FE8
reward_affection=3
reward_stress=-1
[/DATE_EVENT]
"""
	# 使用 ActivityCatalogProtocol 做完整解析
	var parsed: Array[Dictionary] = ActivityCatalogProtocolClass.parse_date_events(mock_output, 3, 4)
	_assert("解析出 2 个事件", parsed.size() == 2)

	if parsed.size() >= 1:
		var first: Dictionary = parsed[0]
		_assert("第1个有 title", first.has("title"))
		_assert("第1个 title=拉面祭·限定一夜", str(first.get("title", "")) == "拉面祭·限定一夜")
		_assert("第1个 location_id=harbor", str(first.get("location_id", "")) == "harbor")
		_assert("第1个有 rewards", first.has("rewards"))
		var rewards: Dictionary = first.get("rewards", {}) as Dictionary
		_assert("第1个 reward_affection=2", int(rewards.get("affection", 0)) == 2)
		_assert("第1个有 valid_phases", first.has("valid_phases"))
		_assert("第1个有 source_type", first.has("source_type"))
		_assert("第1个 source_type=llm_block", str(first.get("source_type", "")) == "llm_block")
		_assert("第1个有 map_position", first.has("map_position"))
		print("  Event 1: %s (%s) - %s" % [
			str(first.get("title", "")),
			str(first.get("location_id", "")),
			str(first.get("subtitle", "")),
		])

	if parsed.size() >= 2:
		var second: Dictionary = parsed[1]
		_assert("第2个 title=图书馆靠窗位", str(second.get("title", "")) == "图书馆靠窗位")
		_assert("第2个 location_id=school", str(second.get("location_id", "")) == "school")
		var phases: Variant = second.get("valid_phases", [])
		_assert("第2个 valid_phases 包含 AFTERNOON", phases is Array and "AFTERNOON" in phases)
		print("  Event 2: %s (%s) - %s" % [
			str(second.get("title", "")),
			str(second.get("location_id", "")),
			str(second.get("subtitle", "")),
		])


func _test_initial_events() -> void:
	print("[Test] 初始事件加载")
	var dm: Node = get_node_or_null("/root/DateManager")
	if dm == null:
		print("  [SKIP] DateManager autoload 不可用")
		return

	var events: Array = dm.get_daily_events()
	_assert("Day 1 有初始事件", not events.is_empty())
	print("  当前事件数量: %d" % events.size())
	for i in range(events.size()):
		var ev: Dictionary = events[i]
		print("    [%d] %s (%s) - %s" % [
			i,
			str(ev.get("title", "?")),
			str(ev.get("location_id", "?")),
			str(ev.get("subtitle", "?")),
		])


func _test_live_llm_request() -> void:
	print("[Test] 实际 LLM 约会事件生成")
	var dm: Node = get_node_or_null("/root/DateManager")
	if dm == null:
		print("  [SKIP] DateManager autoload 不可用")
		return

	print("  DateManager 已加载，触发 generate_next_day_events(2)...")
	dm.generate_next_day_events(2)
	print("  LLM 请求已发送，等待响应...")


func _assert(label: String, condition: bool) -> void:
	if condition:
		print("  ✓ %s" % label)
	else:
		print("  ✗ %s [FAILED]" % label)
