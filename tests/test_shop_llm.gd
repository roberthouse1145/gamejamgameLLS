extends Node

## 测试 ShopManager 的 LLM 商品生成流程
## 验证：AIService 配置、prompt 构建、LLM 请求发送、结果解析

func _ready() -> void:
	print("\n=== Shop LLM 生成测试 ===\n")
	_test_ai_config_role()
	_test_prompt_building()
	_test_parse_llm_output()
	_test_shop_manager_state()
	_test_llm_catalog_request()
	print("\n=== 测试完成，等待 LLM 响应... ===\n")


func _test_ai_config_role() -> void:
	print("[Test] AIConfigManager role 配置")
	var config_mgr := AIConfigManager.new()
	var loaded: bool = config_mgr.load_config()
	_assert("配置文件已加载", loaded)

	var shop_config: Dictionary = config_mgr.get_config_for_role("shop_generator")
	print("  shop_generator config: %s" % str(shop_config))
	if shop_config.is_empty():
		print("  [INFO] shop_generator 未配置，将 fallback 到 chat_default")

	var fallback_config: Dictionary = config_mgr.get_config_for_role("chat_default")
	_assert("chat_default 有配置", not fallback_config.is_empty())
	print("  chat_default model: %s" % str(fallback_config.get("model", "")))
	print("  chat_default base_url: %s" % str(fallback_config.get("base_url", "")))


func _test_prompt_building() -> void:
	print("[Test] Prompt 构建")
	var system_prompt: String = ShopCatalogFactory.build_generation_system_prompt()
	_assert("system prompt 非空", not system_prompt.is_empty())
	_assert("system prompt 包含 [ITEM]", system_prompt.find("[ITEM]") >= 0)
	print("  system prompt 长度: %d" % system_prompt.length())

	var fixed_core_count: int = ShopCatalogStaticData.get_fixed_core_items().size()
	var user_prompt: String = ShopCatalogFactory.build_generation_prompt(5, fixed_core_count, null)
	_assert("user prompt 非空", not user_prompt.is_empty())
	_assert("user prompt 包含商品数量", user_prompt.find(str(ShopCatalogFactory.CATALOG_SIZE - fixed_core_count)) >= 0)
	_assert("user prompt 包含 Day", user_prompt.find("Day") >= 0)
	print("  user prompt 长度: %d" % user_prompt.length())
	print("  user prompt 前200字: %s" % user_prompt.left(200))


func _test_parse_llm_output() -> void:
	print("[Test] LLM 输出解析（模拟）")
	var fake_llm_output := """
[ITEM]
category=gift
sub_category=cute_gift
effect_archetype=gift_trust_small
title=星空便签本
subtitle=写给自己也写给她
short_desc=封面会反光，内页有淡淡的星座图案。
detail_desc=不是什么贵重文具，但很适合在深夜写下一些不好意思当面说的话。
price_band=low
giftable=true
tags=礼物|文具|手写
seller_style=文具控种草
user_comments=买来写了两页就送人了|封面比内容好看，但这不重要
[/ITEM]

[ITEM]
category=life
sub_category=snack
effect_archetype=mood_up_small
title=深夜芝士薯片
subtitle=咔嚓一声解决情绪问题
short_desc=不健康但很及时。
detail_desc=适合在改了三遍剧本之后，先用碳水安慰一下自己。
price_band=low
giftable=true
tags=零食|减压|深夜
seller_style=深夜补给站
user_comments=吃完手指是黄的但心情是好的|配可乐效果翻倍
[/ITEM]
"""
	var items := ShopCatalogFactory.parse_llm_catalog_items(fake_llm_output, 5, 4)
	_assert("解析出2个商品", items.size() == 2)
	if items.size() >= 1:
		var first = items[0]  # ShopItem
		_assert("第一个title=星空便签本", first.title == "星空便签本")
		_assert("source_type=llm_wrapped", first.source_type == "llm_wrapped")
		_assert("category=gift", first.category == "gift")
		_assert("effect_archetype=gift_trust_small", first.effect_archetype == "gift_trust_small")
		_assert("有price", first.price > 0)
		print("  LLM商品价格: %d (price_band=%s)" % [first.price, first.price_band])


func _test_shop_manager_state() -> void:
	print("[Test] ShopManager 运行状态")
	var sm: Node = get_node_or_null("/root/ShopManager")
	_assert("ShopManager autoload 存在", sm != null)
	if sm == null:
		return

	var catalog: Array = sm.get_catalog()
	_assert("初始目录非空", catalog.size() > 0)
	print("  当前目录商品数: %d" % catalog.size())
	print("  目录 day: %d" % sm.get_catalog_day())

	for i in range(mini(3, catalog.size())):
		var item: Dictionary = catalog[i]
		print("  [%d] %s (¥%d, %s, %s)" % [
			i,
			str(item.get("title", "")),
			int(item.get("price", 0)),
			str(item.get("category", "")),
			str(item.get("effect_archetype", "")),
		])


func _test_llm_catalog_request() -> void:
	print("[Test] 触发 LLM 目录生成请求")
	var sm: Node = get_node_or_null("/root/ShopManager")
	if sm == null:
		print("  [SKIP] ShopManager 不存在")
		return

	# 连接信号监听结果
	if sm.has_signal("catalog_refreshed"):
		sm.catalog_refreshed.connect(_on_catalog_refreshed)
	if sm.has_signal("catalog_generation_started"):
		sm.catalog_generation_started.connect(_on_generation_started)
	if sm.has_signal("catalog_generation_failed"):
		sm.catalog_generation_failed.connect(_on_generation_failed)

	# 强制刷新，使用 LLM
	print("  正在发送 LLM 请求...")
	sm.refresh_daily_catalog(true, false)

	var has_pending: bool = sm.has_pending_requests()
	print("  has_pending_requests: %s" % str(has_pending))
	if not has_pending:
		print("  [INFO] 没有挂起的请求，可能 LLM 未启用或已立即回退到本地")


func _on_generation_started(day: int) -> void:
	print("\n  >> catalog_generation_started: Day %d" % day)


func _on_catalog_refreshed(catalog: Array) -> void:
	print("\n  >> catalog_refreshed: %d 件商品" % catalog.size())
	for i in range(catalog.size()):
		var item: Dictionary = catalog[i]
		var source: String = str(item.get("source_type", "unknown"))
		print("    [%d] [%s] %s (¥%d, %s)" % [
			i, source,
			str(item.get("title", "")),
			int(item.get("price", 0)),
			str(item.get("category", "")),
		])


func _on_generation_failed(error_msg: String) -> void:
	print("\n  >> catalog_generation_failed: %s" % error_msg)


func _assert(desc: String, condition: bool) -> void:
	if condition:
		print("  [OK] %s" % desc)
	else:
		print("  [FAIL] %s" % desc)
