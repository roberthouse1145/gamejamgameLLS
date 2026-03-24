extends Node

func _ready() -> void:
	print("\n=== Shop DSL 加载测试 ===\n")
	_test_block_parser()
	_test_effects_loaded()
	_test_blueprints_loaded()
	_test_core_items_loaded()
	_test_config_loaded()
	_test_display_lookups()
	_test_weight_rules()
	_test_backward_compat()
	print("\n=== Shop DSL 测试完成 ===\n")


func _test_block_parser() -> void:
	print("[Test] ShopItemBlockParser.parse_blocks")
	var dsl := """
[ITEM]
title=测试商品
price=99
giftable=true
tags=标签1|标签2
[/ITEM]

[ITEM]
title=第二件
price=50
giftable=false
[/ITEM]
"""
	var items := ShopItemBlockParser.parse_blocks(dsl, "ITEM")
	_assert("解析出2个ITEM块", items.size() == 2)
	_assert("第一个title", str(items[0].get("title", "")) == "测试商品")
	_assert("price自动转int", items[0].get("price", 0) == 99)
	_assert("giftable自动转bool", items[0].get("giftable", false) == true)
	_assert("tags竖线分隔", items[0].get("tags", []).size() == 2)
	_assert("第二个giftable=false", items[1].get("giftable", true) == false)


func _test_effects_loaded() -> void:
	print("[Test] 效果定义加载")
	var keys := ShopCatalogStaticData.get_effect_archetype_keys()
	_assert("至少10个效果", keys.size() >= 10)
	_assert("包含sleep_recovery_small", keys.has("sleep_recovery_small"))
	_assert("包含flavor_no_effect", keys.has("flavor_no_effect"))

	var effect := ShopCatalogStaticData.get_effect_definition("sleep_recovery_small")
	_assert("use_mode=equip", str(effect.get("use_mode", "")) == "equip")
	_assert("modifier_slot=sleep", str(effect.get("modifier_slot", "")) == "sleep")
	_assert("instant_stats有stress", effect.get("instant_stats", {}).has("stress"))
	_assert("stress=-2", int(effect.get("instant_stats", {}).get("stress", 0)) == -2)
	_assert("有persistent_modifiers", (effect.get("persistent_modifiers", []) as Array).size() > 0)
	var mod: Dictionary = effect.get("persistent_modifiers", [{}])[0]
	_assert("modifier key", str(mod.get("key", "")) == "sleep_stress_recovery_mult")
	_assert("modifier value=0.12", absf(float(mod.get("value", 0)) - 0.12) < 0.001)


func _test_blueprints_loaded() -> void:
	print("[Test] 蓝图加载")
	var bps := ShopCatalogStaticData.get_local_blueprints()
	_assert("至少6个蓝图", bps.size() >= 6)
	var first: Dictionary = bps[0]
	_assert("有blueprint_id", not str(first.get("blueprint_id", "")).is_empty())
	_assert("有category", not str(first.get("category", "")).is_empty())
	_assert("title_prefix是数组", first.get("title_prefix", []) is Array)
	_assert("title_prefix非空", (first.get("title_prefix", []) as Array).size() > 0)
	_assert("price_range是数组", first.get("price_range", []) is Array)


func _test_core_items_loaded() -> void:
	print("[Test] 核心商品加载")
	var items := ShopCatalogStaticData.get_fixed_core_items()
	_assert("4个核心商品", items.size() == 4)
	var pillow: Dictionary = items[0]
	_assert("item_id=core_pillow", str(pillow.get("item_id", "")) == "core_pillow")
	_assert("price=128", int(pillow.get("price", 0)) == 128)
	_assert("giftable=true", bool(pillow.get("giftable", false)) == true)
	_assert("tags是数组", pillow.get("tags", []) is Array)
	_assert("desc包含换行", str(pillow.get("desc", "")).find("\n") >= 0)


func _test_config_loaded() -> void:
	print("[Test] 配置加载")
	var cats := ShopCatalogStaticData.ALLOWED_CATEGORIES
	_assert("4个分类", cats.size() == 4)
	_assert("包含gift", cats.has("gift"))

	var bands := ShopCatalogStaticData.ALLOWED_PRICE_BANDS
	_assert("3个价格区间", bands.size() == 3)

	var banned := ShopCatalogStaticData.get_banned_terms()
	_assert("禁词非空", banned.size() > 0)
	_assert("包含淘宝", banned.has("淘宝"))

	var sellers := ShopCatalogStaticData.get_seller_names()
	_assert("店铺名非空", sellers.size() > 0)

	var low_range := ShopCatalogStaticData.get_price_range("low")
	_assert("low价格区间有2个值", low_range.size() == 2)
	_assert("low最低15", int(low_range[0]) == 15)

	var absurdity := ShopCatalogStaticData.get_absurdity("gift")
	_assert("gift荒诞度=0.18", absf(absurdity - 0.18) < 0.001)


func _test_display_lookups() -> void:
	print("[Test] 显示文本查询")
	_assert("gift→礼物", ShopCatalogStaticData.get_category_display("gift") == "礼物")
	_assert("life→生活", ShopCatalogStaticData.get_category_display("life") == "生活")
	_assert("unknown→商品", ShopCatalogStaticData.get_category_display("unknown") == "商品")

	_assert("sleep_recovery_small→改善睡眠", ShopCatalogStaticData.get_effect_display("sleep_recovery_small") == "改善睡眠")
	_assert("flavor_no_effect→纯风味", ShopCatalogStaticData.get_effect_display("flavor_no_effect") == "纯风味")

	_assert("stress→压力", ShopCatalogStaticData.get_stat_label("stress") == "压力")
	_assert("ready→可使用", ShopCatalogStaticData.get_state_label("ready") == "可使用")


func _test_weight_rules() -> void:
	print("[Test] 权重规则加载")
	var rules := ShopCatalogStaticData.get_weight_rules()
	_assert("至少6条规则", rules.size() >= 6)
	var first: Dictionary = rules[0]
	_assert("有stat_field", first.has("stat_field"))
	_assert("有weight_bonus", first.has("weight_bonus"))


func _test_backward_compat() -> void:
	print("[Test] 向后兼容")
	# ShopCardBuilder 的函数应该正常工作
	_assert("ShopCardBuilder.category_text", ShopCardBuilder.category_text("gift") == "礼物")
	_assert("ShopCardBuilder.effect_summary", ShopCardBuilder.effect_summary("sleep_recovery_small") == "改善睡眠")
	_assert("ShopCardBuilder.state_text", ShopCardBuilder.state_text("ready") == "可使用")
	_assert("ShopCardBuilder.stat_label", ShopCardBuilder.stat_label("stress") == "压力")

	# ShopCatalogFactory 的函数应该正常工作
	var effect := ShopCatalogFactory.get_effect_definition("mood_up_small")
	_assert("Factory.get_effect_definition", str(effect.get("use_mode", "")) == "consume")


func _assert(desc: String, condition: bool) -> void:
	if condition:
		print("  [OK] %s" % desc)
	else:
		print("  [FAIL] %s" % desc)
