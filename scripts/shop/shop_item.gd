class_name ShopItem
extends Resource
## 商店商品数据类 — 替代裸 Dictionary，提供类型安全的字段访问。
## 所有商品（核心/蓝图/LLM）统一使用此类。

# ── ID ────────────────────────────────────────────────
@export var item_id: String = ""          ## 模板 ID（如 daily_sleep_aid_1）
@export var instance_id: String = ""      ## 唯一实例 ID（如 daily_sleep_aid_1_day_1_00）
@export var source_type: String = ""      ## "core" / "local_blueprint" / "llm_wrapped"

# ── 基础信息 ──────────────────────────────────────────
@export var category: String = ""
@export var sub_category: String = ""
@export var effect_archetype: String = "mood_up_small"
@export var title: String = ""
@export var subtitle: String = ""
@export var short_desc: String = ""
@export var desc: String = ""             ## detail_desc 或 desc，统一为 desc
@export var price: int = 0
@export var price_band: String = "mid"
@export var shipping_days: int = 1
@export var giftable: bool = false
@export var tags: PackedStringArray = []
@export var seller_style: String = ""
@export var seller_name: String = ""
@export var user_comments: PackedStringArray = []
@export var instant_stats: Dictionary = {}

# ── 装饰字段（由 decorate 填充）─────────────────────
@export var day: int = 0
@export var available: bool = true
@export var absurdity: float = 0.2
@export var sales_count: int = 0
@export var rating: float = 4.8
@export var review_count: int = 0


# ══════════════════════════════════════════════════════
#  构造
# ══════════════════════════════════════════════════════

static func from_dict(d: Dictionary) -> ShopItem:
	var item := ShopItem.new()
	item.item_id = str(d.get("item_id", ""))
	item.instance_id = str(d.get("instance_id", ""))
	item.source_type = str(d.get("source_type", ""))
	item.category = str(d.get("category", ""))
	item.sub_category = str(d.get("sub_category", ""))
	item.effect_archetype = str(d.get("effect_archetype", "mood_up_small"))
	item.title = str(d.get("title", ""))
	item.subtitle = str(d.get("subtitle", ""))
	item.short_desc = str(d.get("short_desc", ""))
	var raw_desc: String = str(d.get("desc", d.get("detail_desc", "")))
	item.desc = raw_desc.replace("\\n", "\n")
	item.price = maxi(0, int(d.get("price", 0)))
	item.price_band = str(d.get("price_band", "mid"))
	item.shipping_days = clampi(int(d.get("shipping_days", 1)), 1, 3)
	item.giftable = bool(d.get("giftable", false))
	item.tags = _to_string_array(d.get("tags", []))
	item.seller_style = str(d.get("seller_style", ""))
	item.seller_name = str(d.get("seller_name", ""))
	item.user_comments = _to_string_array(d.get("user_comments", []))
	item.instant_stats = _parse_stats_field(d.get("instant_stats", null))
	item.day = int(d.get("day", 0))
	item.available = bool(d.get("available", true))
	item.absurdity = float(d.get("absurdity", 0.2))
	item.sales_count = int(d.get("sales_count", 0))
	item.rating = float(d.get("rating", 4.8))
	item.review_count = int(d.get("review_count", 0))
	return item


# ══════════════════════════════════════════════════════
#  序列化
# ══════════════════════════════════════════════════════

func to_dict() -> Dictionary:
	return {
		"item_id": item_id,
		"instance_id": instance_id,
		"source_type": source_type,
		"category": category,
		"sub_category": sub_category,
		"effect_archetype": effect_archetype,
		"title": title,
		"subtitle": subtitle,
		"short_desc": short_desc,
		"desc": desc,
		"price": price,
		"price_band": price_band,
		"shipping_days": shipping_days,
		"giftable": giftable,
		"tags": Array(tags),
		"seller_style": seller_style,
		"seller_name": seller_name,
		"user_comments": Array(user_comments),
		"instant_stats": instant_stats.duplicate(),
		"day": day,
		"available": available,
		"absurdity": absurdity,
		"sales_count": sales_count,
		"rating": rating,
		"review_count": review_count,
	}


# ══════════════════════════════════════════════════════
#  描述
# ══════════════════════════════════════════════════════

func get_prompt() -> String:
	var tags_str: String = ", ".join(tags) if tags.size() > 0 else "无"
	var effect := ShopCatalogFactory.get_effect_definition(effect_archetype)
	var summary: String = str(effect.get("summary", ""))
	return "「%s」（%s）。标签：%s。效果：%s。" % [
		title, category, tags_str, summary if not summary.is_empty() else "无",
	]


## 构建赠送时在 linkchat 中显示的商品分享卡片数据。
func build_gift_card() -> Dictionary:
	var card: Dictionary = {
		"type": "product",
		"title": title,
		"subtitle": short_desc if not short_desc.is_empty() else desc.substr(0, 40),
		"price": "¥%d" % price,
		"badge": category,
	}
	var tags_str: String = " · ".join(tags) if tags.size() > 0 else ""
	if not tags_str.is_empty():
		card["footer"] = tags_str
	return card


# ══════════════════════════════════════════════════════
#  工具
# ══════════════════════════════════════════════════════

static func _to_string_array(raw: Variant) -> PackedStringArray:
	var result: PackedStringArray = []
	if raw is Array:
		for item in raw:
			var s: String = str(item).strip_edges()
			if not s.is_empty():
				result.append(s)
	elif raw is PackedStringArray:
		result = raw as PackedStringArray
	return result


static func _parse_stats_field(raw: Variant) -> Dictionary:
	var result: Dictionary = {}
	if raw == null:
		return result
	var pairs: Array = []
	if raw is String:
		if (raw as String).is_empty():
			return result
		pairs = [(raw as String)]
	elif raw is Array:
		pairs = raw as Array
	elif raw is Dictionary:
		return raw as Dictionary
	for entry in pairs:
		var s: String = str(entry).strip_edges()
		var sep: int = s.find(":")
		if sep > 0:
			result[s.substr(0, sep).strip_edges()] = int(s.substr(sep + 1).strip_edges())
	return result
