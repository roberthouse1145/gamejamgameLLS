class_name ShopCatalogFactory
## 商店目录工厂：负责本地蓝图生成、LLM prompt 构建、LLM 结果清洗

const _ShopItem = preload("res://scripts/shop/shop_item.gd")

const CATALOG_SIZE: int = 8
const SHOP_SYSTEM_PROMPT_KEY: String = "shop/catalog_generation_system"
const SHOP_USER_PROMPT_KEY: String = "shop/catalog_generation_user"

static func get_effect_definition(effect_id: String) -> Dictionary:
	return ShopCatalogStaticData.get_effect_definition(effect_id)


static func get_effect_archetype_keys() -> PackedStringArray:
	return ShopCatalogStaticData.get_effect_archetype_keys()


static func generate_local_daily_catalog(day: int, fixed_core_items: Array[Dictionary], gm: Node) -> Array:
	var catalog: Array = []
	var index: int = 0
	for fixed_item in fixed_core_items:
		var decorated := _decorate_catalog_item((fixed_item as Dictionary).duplicate(true), day, index)
		catalog.append(_ShopItem.from_dict(decorated))
		index += 1

	var rng := RandomNumberGenerator.new()
	rng.seed = abs(hash("shop_local_day_%d" % day))
	var local_needed: int = maxi(0, CATALOG_SIZE - catalog.size())
	var selected_blueprints := _pick_local_blueprints(local_needed, rng, gm)
	for blueprint in selected_blueprints:
		var decorated := _build_local_item_from_blueprint(blueprint, day, index, rng)
		catalog.append(_ShopItem.from_dict(decorated))
		index += 1

	return catalog


static func build_generation_system_prompt() -> String:
	var prompt_manager: Node = _get_prompt_manager()
	if prompt_manager != null and prompt_manager.has_method("has_prompt") and prompt_manager.has_method("resolve"):
		if prompt_manager.has_prompt(SHOP_SYSTEM_PROMPT_KEY):
			return str(prompt_manager.resolve(SHOP_SYSTEM_PROMPT_KEY)).strip_edges()

	return "\n".join([
		"你是恋爱共创 SLG 里的电商商品生成器。",
		"你只能输出纯文本商品块，不要输出 JSON，不要输出 markdown，不要补充任何解释。",
		"",
		"每个商品必须使用如下格式，并严格使用这些字段名：",
		"[ITEM]",
		"category=gift",
		"sub_category=cute_gift",
		"effect_archetype=gift_trust_small",
		"title=示例标题",
		"subtitle=示例副标题",
		"short_desc=示例短描述",
		"detail_desc=示例详细描述",
		"price_band=mid",
		"giftable=true",
		"tags=标签1|标签2|标签3",
		"seller_style=示例店铺风格",
		"user_comments=评论1|评论2",
		"[/ITEM]",
		"",
		"tags 和 user_comments 使用竖线 | 分隔，不要使用 JSON 数组。",
		"giftable 只能是 true 或 false。",
		"商品必须像大学生会在电商平台看到的普通商品，可以略怪，但不要超现实。",
		"禁止真实品牌、真实平台名、知名 IP、政治、血腥、违法、露骨内容。",
		"effect_archetype 只能使用白名单中的值。",
	]).strip_edges()

static func build_generation_prompt(day: int, fixed_core_count: int, gm: Node) -> String:
	var state_prompt: String = gm.get_llm_state_prompt() if gm != null and gm.has_method("get_llm_state_prompt") else ""
	var prompt_manager: Node = _get_prompt_manager()
	var vars := {
		"shop_target_count": str(maxi(1, CATALOG_SIZE - fixed_core_count)),
		"shop_day": str(day),
		"shop_effect_whitelist": ", ".join(get_effect_archetype_keys()),
		"shop_state_block": "",
	}
	if not state_prompt.is_empty():
		vars["shop_state_block"] = "当前游戏状态：%s" % state_prompt

	if prompt_manager != null and prompt_manager.has_method("has_prompt") and prompt_manager.has_method("resolve_with_vars"):
		if prompt_manager.has_prompt(SHOP_USER_PROMPT_KEY):
			return str(prompt_manager.resolve_with_vars(SHOP_USER_PROMPT_KEY, vars)).strip_edges()

	var parts: PackedStringArray = []
	parts.append("请生成 %s 个架空电商商品。" % vars["shop_target_count"])
	parts.append("时间背景：Day %s 的 GameJam 期间。" % vars["shop_day"])
	parts.append("类别限定：gift, life, creative, weird。")
	parts.append("effect_archetype 白名单：%s。" % vars["shop_effect_whitelist"])
	parts.append("price_band 只能是 low / mid / high。")
	parts.append("每个商品都必须用 [ITEM] ... [/ITEM] 块输出，字段必须完整，字段名必须精确一致。")
	parts.append("不要输出 JSON，不要输出代码块，不要在块外补充任何说明。")
	if not str(vars["shop_state_block"]).is_empty():
		parts.append(str(vars["shop_state_block"]))
	parts.append("商品既要像真实电商商品，也要留出让女主吐槽、记住、或者产生情绪反应的空间。")
	return "\n".join(parts).strip_edges()

static func parse_llm_catalog_items(raw_text: String, day: int, max_count: int) -> Array:
	var sanitized: Array = []
	var local_index: int = 0
	for raw_item in ShopItemBlockParser.parse_items(raw_text):
		var item_dict := _sanitize_llm_item(raw_item as Dictionary, day, local_index)
		if item_dict.is_empty():
			continue
		sanitized.append(_ShopItem.from_dict(item_dict))
		local_index += 1
		if sanitized.size() >= max_count:
			break
	return sanitized


static func decorate_catalog_item(item: Dictionary, day: int, index: int) -> Dictionary:
	return _decorate_catalog_item(item, day, index)


static func _get_prompt_manager() -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("PromptManager")


static func _pick_local_blueprints(count: int, rng: RandomNumberGenerator, gm: Node) -> Array[Dictionary]:
	var picked: Array[Dictionary] = []
	if count <= 0:
		return picked

	var available_indices: Array[int] = []
	for i in range(ShopCatalogStaticData.LOCAL_BLUEPRINTS.size()):
		available_indices.append(i)

	while not available_indices.is_empty() and picked.size() < count:
		var total_weight: int = 0
		for blueprint_index in available_indices:
			total_weight += _get_blueprint_weight(ShopCatalogStaticData.LOCAL_BLUEPRINTS[blueprint_index], gm)

		var roll: int = rng.randi_range(1, maxi(1, total_weight))
		var cursor: int = 0
		var chosen_list_index: int = 0
		for i in range(available_indices.size()):
			var blueprint_weight: int = _get_blueprint_weight(ShopCatalogStaticData.LOCAL_BLUEPRINTS[available_indices[i]], gm)
			cursor += blueprint_weight
			if roll <= cursor:
				chosen_list_index = i
				break
		var chosen_blueprint_index: int = available_indices[chosen_list_index]
		picked.append((ShopCatalogStaticData.LOCAL_BLUEPRINTS[chosen_blueprint_index] as Dictionary).duplicate(true))
		available_indices.remove_at(chosen_list_index)
	return picked


static func _get_blueprint_weight(blueprint: Dictionary, gm: Node) -> int:
	var weight: int = 1
	var rules: Array[Dictionary] = ShopCatalogStaticData.get_weight_rules()
	if rules.is_empty():
		return weight

	var gm_stats: Dictionary = {}
	if gm != null:
		for stat_key in ["stress", "money", "passion", "affection", "completion"]:
			gm_stats[stat_key] = int(gm.get(stat_key)) if gm.get(stat_key) != null else 0

	for rule in rules:
		# 检查 GM 状态条件
		var stat_ok: bool = bool(rule.get("stat_any", false))
		if not stat_ok:
			var stat_field: String = str(rule.get("stat_field", ""))
			var stat_op: String = str(rule.get("stat_op", ""))
			var stat_threshold: int = int(rule.get("stat_threshold", 0))
			var stat_val: int = int(gm_stats.get(stat_field, 0))
			match stat_op:
				"gte":
					stat_ok = stat_val >= stat_threshold
				"lte":
					stat_ok = stat_val <= stat_threshold
				"eq":
					stat_ok = stat_val == stat_threshold
				_:
					stat_ok = false
		if not stat_ok:
			continue

		# 检查蓝图字段匹配
		var match_field: String = str(rule.get("match_field", ""))
		var match_value: String = str(rule.get("match_value", ""))
		var bp_value: String = str(blueprint.get(match_field, ""))
		var match_op: String = str(rule.get("match_op", "eq"))
		var matched: bool = false
		match match_op:
			"eq":
				matched = bp_value == match_value
			_:
				matched = bp_value == match_value
		if matched:
			weight += int(rule.get("weight_bonus", 0))

	return weight


static func _build_local_item_from_blueprint(blueprint: Dictionary, day: int, index: int, rng: RandomNumberGenerator) -> Dictionary:
	var title_prefixes: Array = blueprint.get("title_prefix", [])
	var title_suffixes: Array = blueprint.get("title_suffix", [])
	var subtitles: Array = blueprint.get("subtitles", [])
	var short_descs: Array = blueprint.get("short_descs", [])
	var detail_descs: Array = blueprint.get("detail_descs", [])
	var seller_styles: Array = blueprint.get("seller_styles", [])
	var user_comments: Array = blueprint.get("user_comments", [])
	var price_range: Array = blueprint.get("price_range", [19, 99])
	var shipping_range: Array = blueprint.get("shipping_range", [1, 3])

	var title := "%s%s" % [
		_pick_seeded(title_prefixes, rng, "普通"),
		_pick_seeded(title_suffixes, rng, "小物件"),
	]
	var price_min: int = int(price_range[0]) if price_range.size() > 0 else 19
	var price_max: int = int(price_range[1]) if price_range.size() > 1 else price_min
	var shipping_min: int = int(shipping_range[0]) if shipping_range.size() > 0 else 1
	var shipping_max: int = int(shipping_range[1]) if shipping_range.size() > 1 else shipping_min

	var item := {
		"item_id": "daily_%s_%d" % [str(blueprint.get("blueprint_id", "item")), day],
		"source_type": "local_blueprint",
		"category": str(blueprint.get("category", "weird")),
		"sub_category": str(blueprint.get("sub_category", "")),
		"effect_archetype": str(blueprint.get("effect_archetype", "flavor_no_effect")),
		"title": title,
		"subtitle": _pick_seeded(subtitles, rng, "今天也会被算法推到你眼前的东西"),
		"short_desc": _pick_seeded(short_descs, rng, "普通商品，但挺像会在深夜被下单。"),
		"detail_desc": _pick_seeded(detail_descs, rng, "看起来有点多余，但又确实能给生活添点气味。"),
		"price": rng.randi_range(price_min, price_max),
		"price_band": str(blueprint.get("price_band", "mid")),
		"shipping_days": rng.randi_range(shipping_min, shipping_max),
		"giftable": bool(blueprint.get("giftable", false)),
		"tags": blueprint.get("tags", []).duplicate(true),
		"seller_style": _pick_seeded(seller_styles, rng, "普通商家"),
		"user_comments": _pick_unique_pair(user_comments, rng, "没想到还真挺有用。", "会想推荐给同样在熬的人。"),
	}
	return _decorate_catalog_item(item, day, index)


static func _decorate_catalog_item(item: Dictionary, day: int, index: int) -> Dictionary:
	item["instance_id"] = "%s_day_%d_%02d" % [str(item.get("item_id", "item")), day, index]
	item["day"] = day
	item["available"] = true
	item["absurdity"] = float(item.get("absurdity", _estimate_absurdity(item)))
	item["price"] = maxi(1, int(item.get("price", 1)))
	item["price_band"] = _normalize_price_band(str(item.get("price_band", "mid")))
	item["shipping_days"] = clampi(int(item.get("shipping_days", 1)), 1, 3)
	if not item.has("giftable"):
		item["giftable"] = false
	if not item.has("tags"):
		item["tags"] = []
	var fake_rng := RandomNumberGenerator.new()
	fake_rng.seed = abs(hash("%s_%d_%d" % [str(item.get("item_id", "")), day, index]))
	if not item.has("sales_count"):
		item["sales_count"] = fake_rng.randi_range(12, 9999)
	if not item.has("rating"):
		item["rating"] = snappedf(fake_rng.randf_range(4.3, 5.0), 0.1)
	if not item.has("review_count"):
		item["review_count"] = maxi(1, int(item.get("sales_count", 100) * fake_rng.randf_range(0.05, 0.25)))
	if not item.has("seller_name"):
		var seller_names: PackedStringArray = ShopCatalogStaticData.get_seller_names()
		if seller_names.is_empty():
			seller_names = PackedStringArray(["普通商家"])
		item["seller_name"] = seller_names[fake_rng.randi_range(0, seller_names.size() - 1)]
	return item


static func _sanitize_llm_item(raw_item: Dictionary, day: int, index: int) -> Dictionary:
	var title: String = str(raw_item.get("title", "")).strip_edges()
	if title.is_empty():
		return {}
	var lowered_title: String = title.to_lower()
	for banned in ShopCatalogStaticData.BANNED_TERMS:
		if lowered_title.find(str(banned).to_lower()) >= 0:
			return {}

	var category: String = str(raw_item.get("category", "weird")).strip_edges().to_lower()
	if not ShopCatalogStaticData.ALLOWED_CATEGORIES.has(category):
		category = "weird"

	var effect_archetype: String = str(raw_item.get("effect_archetype", "flavor_no_effect")).strip_edges()
	if not ShopCatalogStaticData.EFFECT_ARCHETYPES.has(effect_archetype):
		effect_archetype = "flavor_no_effect"

	var rng := RandomNumberGenerator.new()
	rng.seed = abs(hash("%s|%d|%d" % [title, day, index]))
	var price_band: String = _normalize_price_band(str(raw_item.get("price_band", "mid")))
	return {
		"item_id": "llm_%d_%02d" % [day, index],
		"source_type": "llm_wrapped",
		"category": category,
		"sub_category": str(raw_item.get("sub_category", "")).strip_edges(),
		"effect_archetype": effect_archetype,
		"title": title,
		"subtitle": str(raw_item.get("subtitle", "今天也可能会被算法推到你眼前")).strip_edges(),
		"short_desc": str(raw_item.get("short_desc", "普通商品，但像是会在深夜被点开。")).strip_edges(),
		"detail_desc": str(raw_item.get("detail_desc", "看起来像一件日常小物，重点是它会出现在生活里。")).strip_edges(),
		"price_band": price_band,
		"price": _resolve_price_from_band(price_band, rng),
		"shipping_days": rng.randi_range(1, 3),
		"giftable": bool(raw_item.get("giftable", false)),
		"tags": _sanitize_tags(raw_item.get("tags", [])),
		"seller_style": str(raw_item.get("seller_style", "普通商家")).strip_edges(),
		"user_comments": _sanitize_comments(raw_item.get("user_comments", [])),
	}


static func _estimate_absurdity(item: Dictionary) -> float:
	return ShopCatalogStaticData.get_absurdity(str(item.get("category", "weird")))


static func _normalize_price_band(price_band: String) -> String:
	var normalized: String = price_band.strip_edges().to_lower()
	if ShopCatalogStaticData.ALLOWED_PRICE_BANDS.has(normalized):
		return normalized
	return "mid"


static func _resolve_price_from_band(price_band: String, rng: RandomNumberGenerator) -> int:
	var range_arr: Array = ShopCatalogStaticData.get_price_range(price_band)
	var min_price: int = int(range_arr[0]) if range_arr.size() > 0 else 45
	var max_price: int = int(range_arr[1]) if range_arr.size() > 1 else min_price
	return rng.randi_range(min_price, max_price)


static func _sanitize_tags(raw_tags: Variant) -> Array[String]:
	var tags: Array[String] = []
	if raw_tags is Array:
		for raw_tag in raw_tags:
			var tag: String = str(raw_tag).strip_edges()
			if tag.is_empty():
				continue
			tags.append(tag)
	return tags


static func _sanitize_comments(raw_comments: Variant) -> Array[String]:
	var comments: Array[String] = []
	if raw_comments is Array:
		for raw_comment in raw_comments:
			var comment: String = str(raw_comment).strip_edges()
			if comment.is_empty():
				continue
			comments.append(comment)
			if comments.size() >= 2:
				break
	if comments.is_empty():
		comments.append("看起来很普通，但放在这段时间里也许刚好有用。")
	return comments


static func _pick_seeded(source: Array, rng: RandomNumberGenerator, fallback: String) -> String:
	if source.is_empty():
		return fallback
	return str(source[rng.randi_range(0, source.size() - 1)])


static func _pick_unique_pair(source: Array, rng: RandomNumberGenerator, fallback_a: String, fallback_b: String) -> Array:
	if source.size() < 2:
		var a: String = _pick_seeded(source, rng, fallback_a)
		return [a, fallback_b]
	var idx_a: int = rng.randi_range(0, source.size() - 1)
	var idx_b: int = rng.randi_range(0, source.size() - 2)
	if idx_b >= idx_a:
		idx_b += 1
	return [str(source[idx_a]), str(source[idx_b])]
