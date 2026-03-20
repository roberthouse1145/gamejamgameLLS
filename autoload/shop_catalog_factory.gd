class_name ShopCatalogFactory
## 商店目录工厂：负责本地蓝图生成、LLM prompt 构建、LLM 结果清洗

const CATALOG_SIZE: int = 8

const ALLOWED_CATEGORIES := ["gift", "life", "creative", "weird"]
const ALLOWED_PRICE_BANDS := ["low", "mid", "high"]
const BANNED_TERMS := [
	"淘宝", "天猫", "京东", "apple", "任天堂",
	"自杀", "枪", "炸弹", "血腥",
]

const EFFECT_ARCHETYPES: Dictionary = {
	"sleep_recovery_small": {
		"use_mode": "equip",
		"modifier_slot": "sleep",
		"instant_stats": {"stress": -2},
		"persistent_modifiers": [
			{"key": "sleep_stress_recovery_mult", "label": "睡眠时压力恢复 +12%", "type": "multiplier", "value": 0.12},
		],
		"summary": "睡眠恢复会更好一点。",
	},
	"sleep_recovery_medium": {
		"use_mode": "equip",
		"modifier_slot": "sleep",
		"instant_stats": {"stress": -3},
		"persistent_modifiers": [
			{"key": "sleep_stress_recovery_mult", "label": "睡眠时压力恢复 +20%", "type": "multiplier", "value": 0.20},
		],
		"summary": "明显改善睡眠恢复效果。",
	},
	"creative_focus_small": {
		"use_mode": "equip",
		"modifier_slot": "desk",
		"instant_stats": {"passion": 2},
		"persistent_modifiers": [
			{"key": "creative_focus_mult", "label": "创作专注效率 +12%", "type": "multiplier", "value": 0.12},
		],
		"summary": "更容易进入创作状态。",
	},
	"creative_focus_with_stress": {
		"use_mode": "equip",
		"modifier_slot": "desk",
		"instant_stats": {"stress": 2},
		"persistent_modifiers": [
			{"key": "creative_focus_mult", "label": "夜间创作效率 +15%", "type": "multiplier", "value": 0.15},
			{"key": "chat_interrupt_mult", "label": "闲聊打断触发率 -15%", "type": "multiplier", "value": -0.15},
		],
		"summary": "会更专注，但也更像把自己锁进桌面里。",
	},
	"mood_up_small": {
		"use_mode": "consume",
		"modifier_slot": "",
		"instant_stats": {"stress": -5, "passion": 2},
		"persistent_modifiers": [],
		"summary": "立刻让心情好一点。",
	},
	"gift_affection_small": {
		"use_mode": "gift",
		"modifier_slot": "",
		"instant_stats": {"affection": 6},
		"persistent_modifiers": [],
		"summary": "适合送给她，主要提升好感。",
	},
	"gift_trust_small": {
		"use_mode": "gift",
		"modifier_slot": "",
		"instant_stats": {"affection": 4, "passion": 2},
		"persistent_modifiers": [],
		"summary": "更像是“你有在认真记得她”的那种礼物。",
	},
	"late_night_efficiency_small": {
		"use_mode": "consume",
		"modifier_slot": "",
		"instant_stats": {"completion": 2, "stress": 3},
		"persistent_modifiers": [],
		"summary": "短期推进效率更高，但也更伤神。",
	},
	"room_ambience_small": {
		"use_mode": "equip",
		"modifier_slot": "ambience",
		"instant_stats": {"stress": -1},
		"persistent_modifiers": [
			{"key": "ambient_stress_recovery_bonus", "label": "日常减压恢复 +1", "type": "flat", "value": 1},
		],
		"summary": "房间会更有“待在这里也行”的感觉。",
	},
	"flavor_no_effect": {
		"use_mode": "flavor",
		"modifier_slot": "",
		"instant_stats": {},
		"persistent_modifiers": [],
		"summary": "主要提供生活气息，没有直接数值收益。",
	},
}

const LOCAL_BLUEPRINTS: Array[Dictionary] = [
	{
		"blueprint_id": "sleep_aid",
		"category": "life",
		"sub_category": "sleep_aid",
		"effect_archetype": "sleep_recovery_small",
		"giftable": true,
		"price_band": "mid",
		"price_range": [58, 118],
		"shipping_range": [1, 2],
		"title_prefix": ["回弹", "云朵", "午睡", "安静"],
		"title_suffix": ["记忆枕", "靠垫", "抱枕", "助眠枕"],
		"subtitles": ["熬夜人自救计划", "把脖子先哄好", "今晚先别那么硬扛"],
		"short_descs": [
			"看起来没什么黑科技，但摸上去就让人想早点关灯。",
			"适合在赶工之后把脑子先放一边。",
		],
		"detail_descs": [
			"普通材质加一点过分温柔的触感，卖点不是性能，而是终于像认真照顾自己了一回。",
			"没有奇迹，只是会让你在床上多赖五分钟，顺便少一点起床前的敌意。",
		],
		"tags": ["助眠", "柔软", "居家"],
		"seller_styles": ["认真过头型文案", "治愈系主图"],
		"user_comments": [
			"睡前一抱，突然觉得明天也不是不能活。",
			"不是药，但比嘴硬有用。",
		],
		"reaction_hints": [
			"她会说你最近终于开始把自己当人照顾了。",
			"她大概会先拿它拍你一下，再认真摸摸看。",
		],
	},
	{
		"blueprint_id": "desk_focus",
		"category": "creative",
		"sub_category": "desk_focus",
		"effect_archetype": "creative_focus_small",
		"giftable": true,
		"price_band": "mid",
		"price_range": [42, 138],
		"shipping_range": [1, 3],
		"title_prefix": ["分镜", "专注", "深夜", "截稿"],
		"title_suffix": ["便签纸", "桌面灯", "理线器", "任务板"],
		"subtitles": ["桌面乱的时候脑子也会乱", "把零碎想法先留下", "适合赶工桌的一点秩序"],
		"short_descs": [
			"不会直接帮你写完剧本，但至少能让灵感别继续散落在桌面边缘。",
			"是那种看起来没什么，却常常能救回半小时创作杂物。",
		],
		"detail_descs": [
			"小物件、轻工具，不夸张，但足够让桌面看起来像真的在认真推进项目。",
			"会让“我之后整理”这件事稍微变得更像现在就能开始。",
		],
		"tags": ["创作", "桌面", "效率"],
		"seller_styles": ["文具控种草", "桌搭效率风"],
		"user_comments": [
			"没买之前觉得可有可无，买了以后会开始嫌弃原来那团线。",
			"不是灵感来源，但能让灵感别逃跑。",
		],
		"reaction_hints": [
			"她会觉得这东西很像你们项目当前需要的那一点秩序。",
			"她可能会顺手拿去帮你整理桌面。",
		],
	},
	{
		"blueprint_id": "snack",
		"category": "life",
		"sub_category": "snack",
		"effect_archetype": "mood_up_small",
		"giftable": true,
		"price_band": "low",
		"price_range": [16, 48],
		"shipping_range": [1, 2],
		"title_prefix": ["临期", "加班后", "夜宵", "草莓"],
		"title_suffix": ["夹心饼干", "黄油曲奇", "软糖", "小零食箱"],
		"subtitles": ["饿的时候比计划更重要", "有些糖分就是比道理快", "写不动的时候先嚼点什么"],
		"short_descs": [
			"不一定健康，但很适合在情绪快要碎掉的时候先垫一口。",
			"属于桌边常备，吃完才想起刚刚自己差点又跟世界翻脸。",
		],
		"detail_descs": [
			"味道也许普通，但在熬夜、赶工、情绪低的时候，普通反而比惊艳更可靠。",
			"小包装好拿，深夜嘴馋、低气压、改稿卡住的时候都能提供一点短暂宽容。",
		],
		"tags": ["零食", "减压", "便宜"],
		"seller_styles": ["办公室囤货风", "深夜补给站"],
		"user_comments": [
			"吃到一半的时候，确实会没那么想辞职了。",
			"谈不上高级，但在该出现的时候很会出现。",
		],
		"reaction_hints": [
			"她会边吐槽边顺走一半。",
			"她大概会说你在用碳水缓冲现实。",
		],
	},
	{
		"blueprint_id": "gift_cute",
		"category": "gift",
		"sub_category": "cute_gift",
		"effect_archetype": "gift_trust_small",
		"giftable": true,
		"price_band": "mid",
		"price_range": [25, 99],
		"shipping_range": [1, 3],
		"title_prefix": ["会发光的", "小小的", "桌边", "睡前"],
		"title_suffix": ["毛绒挂件", "手账贴纸", "便签印章", "迷你摆件"],
		"subtitles": ["不是必要，但会被记住", "看起来像“我有在想到你”", "小礼物最怕敷衍，也最容易真诚"],
		"short_descs": [
			"数值意义不大，但非常适合让某个人在看到的时候停一下。",
			"不是贵重礼物，更像把一个微小的偏爱装进盒子里。",
		],
		"detail_descs": [
			"这类东西不会改变项目进度，却很可能改变今晚说话的语气。",
			"送得好的时候很轻，留下来的感觉却会比价格久一点。",
		],
		"tags": ["礼物", "可爱", "随手买"],
		"seller_styles": ["送礼灵感页", "收藏夹里反复出现的那种"],
		"user_comments": [
			"贵不贵不重要，重要的是对的人会记住。",
			"这种小东西的杀伤力，通常只对特定的人生效。",
		],
		"reaction_hints": [
			"她会装作很平静，但之后大概会把它放到看得见的地方。",
			"她可能会先问你怎么会想到买这个。",
		],
	},
	{
		"blueprint_id": "ambience",
		"category": "weird",
		"sub_category": "desk_decor",
		"effect_archetype": "room_ambience_small",
		"giftable": true,
		"price_band": "mid",
		"price_range": [33, 109],
		"shipping_range": [2, 3],
		"title_prefix": ["会呼吸的", "据说转运的", "发呆专用", "桌面用的"],
		"title_suffix": ["小夜灯", "仙人掌摆件", "香薰石", "风铃球"],
		"subtitles": ["看着就会慢一点", "有点怪，但也确实有氛围", "桌面不该只有文件和咖啡"],
		"short_descs": [
			"你很难解释它为什么有用，但没有它的时候桌面又确实少了点什么。",
			"属于电商平台会认真推荐给你的那种小怪东西。",
		],
		"detail_descs": [
			"不负责解决问题，只负责让这个房间不那么像纯粹的赶工现场。",
			"很适合放在电脑边，提醒自己你们不是生产线，也还是会过日子的人。",
		],
		"tags": ["氛围", "摆件", "怪东西"],
		"seller_styles": ["算法瞎推荐", "桌搭疗愈风"],
		"user_comments": [
			"买之前觉得离谱，摆上以后又觉得它本来就该在这儿。",
			"一看就不刚需，但每天都会多看它两眼。",
		],
		"reaction_hints": [
			"她会怀疑这是不是智商税，但最后可能比你先开始摸它。",
			"她大概会先笑你乱买，然后把它摆到顺手的位置。",
		],
	},
	{
		"blueprint_id": "late_night_supply",
		"category": "creative",
		"sub_category": "late_night_supply",
		"effect_archetype": "late_night_efficiency_small",
		"giftable": false,
		"price_band": "low",
		"price_range": [19, 59],
		"shipping_range": [1, 2],
		"title_prefix": ["熬夜", "通宵", "赶稿", "清醒"],
		"title_suffix": ["咖啡包", "浓缩冲剂", "功能饮料箱", "薄荷糖罐"],
		"subtitles": ["短期强力，长期可疑", "今天很有用，明天不好说", "写完这一段再说睡觉"],
		"short_descs": [
			"这类东西最擅长的，是让你以为自己还能再多撑一会儿。",
			"效率会上来，脾气和心率通常也会跟着上来。",
		],
		"detail_descs": [
			"适合最后冲刺前的物资补给，不适合把它当作长期生活方式。",
			"它会让“今晚再收个尾”这句话显得更像真的，但后劲也通常写在第二天。",
		],
		"tags": ["熬夜", "补给", "效率"],
		"seller_styles": ["社畜求生", "深夜冲刺区"],
		"user_comments": [
			"推进是真的推进了，代价也是真的代价。",
			"喝下去那一刻很燃，凌晨四点就没那么浪漫了。",
		],
		"reaction_hints": [
			"她会觉得你又想和凌晨三点做朋友了。",
			"她大概会提醒你别把身体也拿去赶工。",
		],
	},
]


static func get_effect_definition(effect_id: String) -> Dictionary:
	if not EFFECT_ARCHETYPES.has(effect_id):
		return EFFECT_ARCHETYPES["flavor_no_effect"].duplicate(true)
	return (EFFECT_ARCHETYPES[effect_id] as Dictionary).duplicate(true)


static func get_effect_archetype_keys() -> PackedStringArray:
	var keys: PackedStringArray = []
	for k in EFFECT_ARCHETYPES.keys():
		keys.append(str(k))
	return keys


static func generate_local_daily_catalog(day: int, fixed_core_items: Array[Dictionary], gm: Node) -> Array[Dictionary]:
	var catalog: Array[Dictionary] = []
	var index: int = 0
	for fixed_item in fixed_core_items:
		var decorated := _decorate_catalog_item((fixed_item as Dictionary).duplicate(true), day, index)
		catalog.append(decorated)
		index += 1

	var rng := RandomNumberGenerator.new()
	rng.seed = abs(hash("shop_local_day_%d" % day))
	var local_needed: int = maxi(0, CATALOG_SIZE - catalog.size())
	var selected_blueprints := _pick_local_blueprints(local_needed, rng, gm)
	for blueprint in selected_blueprints:
		catalog.append(_build_local_item_from_blueprint(blueprint, day, index, rng))
		index += 1

	return catalog


static func build_generation_system_prompt() -> String:
	return "\n".join([
		"你是恋爱共创 SLG 中的电商商品生成器。",
		"你只输出 JSON 对象，格式为 {\"items\":[...]}。",
		"不要输出 markdown，不要解释。",
		"商品必须像大学生会在电商平台看到的普通商品，可以略怪，但不要超现实。",
		"禁止真实品牌、真实平台名、知名 IP、政治、血腥、违法、露骨内容。",
		"effect_archetype 只能使用白名单中的值。",
	])


static func build_generation_prompt(day: int, fixed_core_count: int, gm: Node) -> String:
	var state_prompt: String = gm.get_llm_state_prompt() if gm != null and gm.has_method("get_llm_state_prompt") else ""
	var parts: PackedStringArray = []
	parts.append("请生成 %d 个架空电商商品。" % maxi(1, CATALOG_SIZE - fixed_core_count))
	parts.append("时间背景：Day %d 的 GameJam 期间。" % day)
	parts.append("类别限定：gift, life, creative, weird。")
	parts.append("effect_archetype 白名单：%s。" % ", ".join(EFFECT_ARCHETYPES.keys()))
	parts.append("price_band 只能是 low / mid / high。")
	parts.append("每个商品需要字段：category, sub_category, effect_archetype, title, subtitle, short_desc, detail_desc, price_band, giftable, tags, seller_style, user_comments, heroine_reaction_hint。")
	if not state_prompt.is_empty():
		parts.append("当前游戏状态：%s" % state_prompt)
	parts.append("请让商品既像真实电商商品，也要留出让女主吐槽或记住的空间。")
	return "\n".join(parts)


static func parse_llm_catalog_items(raw_text: String, day: int, max_count: int) -> Array[Dictionary]:
	var cleaned: String = raw_text.strip_edges()
	if cleaned.begins_with("```json"):
		cleaned = cleaned.trim_prefix("```json").strip_edges()
	elif cleaned.begins_with("```"):
		cleaned = cleaned.trim_prefix("```").strip_edges()
	if cleaned.ends_with("```"):
		cleaned = cleaned.trim_suffix("```").strip_edges()

	var parsed: Variant = JSON.parse_string(cleaned)
	if parsed == null:
		return []

	var items: Array = []
	if parsed is Dictionary and (parsed as Dictionary).has("items") and (parsed as Dictionary).get("items") is Array:
		items = (parsed as Dictionary).get("items", [])
	elif parsed is Array:
		items = parsed
	else:
		return []

	var sanitized: Array[Dictionary] = []
	var local_index: int = 0
	for raw_item in items:
		if not raw_item is Dictionary:
			continue
		var item := _sanitize_llm_item(raw_item as Dictionary, day, local_index)
		if item.is_empty():
			continue
		sanitized.append(item)
		local_index += 1
		if sanitized.size() >= max_count:
			break
	return sanitized


static func decorate_catalog_item(item: Dictionary, day: int, index: int) -> Dictionary:
	return _decorate_catalog_item(item, day, index)


static func _pick_local_blueprints(count: int, rng: RandomNumberGenerator, gm: Node) -> Array[Dictionary]:
	var picked: Array[Dictionary] = []
	if count <= 0:
		return picked

	var available_indices: Array[int] = []
	for i in range(LOCAL_BLUEPRINTS.size()):
		available_indices.append(i)

	while not available_indices.is_empty() and picked.size() < count:
		var total_weight: int = 0
		for blueprint_index in available_indices:
			total_weight += _get_blueprint_weight(LOCAL_BLUEPRINTS[blueprint_index], gm)

		var roll: int = rng.randi_range(1, maxi(1, total_weight))
		var cursor: int = 0
		var chosen_list_index: int = 0
		for i in range(available_indices.size()):
			var blueprint_weight: int = _get_blueprint_weight(LOCAL_BLUEPRINTS[available_indices[i]], gm)
			cursor += blueprint_weight
			if roll <= cursor:
				chosen_list_index = i
				break
		var chosen_blueprint_index: int = available_indices[chosen_list_index]
		picked.append((LOCAL_BLUEPRINTS[chosen_blueprint_index] as Dictionary).duplicate(true))
		available_indices.remove_at(chosen_list_index)
	return picked


static func _get_blueprint_weight(blueprint: Dictionary, gm: Node) -> int:
	var weight: int = 1
	var stress: int = int(gm.get("stress")) if gm != null else 0
	var money: int = int(gm.get("money")) if gm != null else 0
	var passion: int = int(gm.get("passion")) if gm != null else 0
	var category: String = str(blueprint.get("category", ""))
	var effect_archetype: String = str(blueprint.get("effect_archetype", ""))
	var price_band: String = str(blueprint.get("price_band", "mid"))

	if stress >= 60 and (category == "life" or effect_archetype == "mood_up_small"):
		weight += 3
	if passion <= 45 and (effect_archetype == "creative_focus_small" or effect_archetype == "room_ambience_small"):
		weight += 2
	if money <= 180 and price_band == "low":
		weight += 2
	if category == "gift":
		weight += 1
	return weight


static func _build_local_item_from_blueprint(blueprint: Dictionary, day: int, index: int, rng: RandomNumberGenerator) -> Dictionary:
	var title_prefixes: Array = blueprint.get("title_prefix", [])
	var title_suffixes: Array = blueprint.get("title_suffix", [])
	var subtitles: Array = blueprint.get("subtitles", [])
	var short_descs: Array = blueprint.get("short_descs", [])
	var detail_descs: Array = blueprint.get("detail_descs", [])
	var seller_styles: Array = blueprint.get("seller_styles", [])
	var user_comments: Array = blueprint.get("user_comments", [])
	var reaction_hints: Array = blueprint.get("reaction_hints", [])
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
		"heroine_reaction_hint": _pick_seeded(reaction_hints, rng, "她大概会先吐槽一下，然后记住你买了这个。"),
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
		var seller_names: PackedStringArray = [
			"日用好物精选",
			"深夜补给站",
			"桌面生活馆",
			"创意杂货铺",
			"小确幸商店",
			"宿舍生存指南",
			"文具控联盟",
			"零食研究所",
		]
		item["seller_name"] = seller_names[fake_rng.randi_range(0, seller_names.size() - 1)]
	return item


static func _sanitize_llm_item(raw_item: Dictionary, day: int, index: int) -> Dictionary:
	var title: String = str(raw_item.get("title", "")).strip_edges()
	if title.is_empty():
		return {}
	var lowered_title: String = title.to_lower()
	for banned in BANNED_TERMS:
		if lowered_title.find(str(banned).to_lower()) >= 0:
			return {}

	var category: String = str(raw_item.get("category", "weird")).strip_edges().to_lower()
	if not ALLOWED_CATEGORIES.has(category):
		category = "weird"

	var effect_archetype: String = str(raw_item.get("effect_archetype", "flavor_no_effect")).strip_edges()
	if not EFFECT_ARCHETYPES.has(effect_archetype):
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
		"heroine_reaction_hint": str(raw_item.get("heroine_reaction_hint", "她应该会对这件东西给出一点态度。")).strip_edges(),
	}


static func _estimate_absurdity(item: Dictionary) -> float:
	var category: String = str(item.get("category", "weird"))
	match category:
		"gift":
			return 0.18
		"life":
			return 0.12
		"creative":
			return 0.21
		"weird":
			return 0.36
	return 0.2


static func _normalize_price_band(price_band: String) -> String:
	var normalized: String = price_band.strip_edges().to_lower()
	if ALLOWED_PRICE_BANDS.has(normalized):
		return normalized
	return "mid"


static func _resolve_price_from_band(price_band: String, rng: RandomNumberGenerator) -> int:
	match price_band:
		"low":
			return rng.randi_range(15, 59)
		"high":
			return rng.randi_range(120, 268)
		_:
			return rng.randi_range(45, 129)


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
