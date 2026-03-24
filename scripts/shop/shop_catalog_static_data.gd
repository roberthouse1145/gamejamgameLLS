class_name ShopCatalogStaticData
## 商店静态数据管理：从 DSL 文件加载配置、效果原型、蓝图、核心商品

const DSL_PATH: String = "res://resources/data/shop/shop_data.dsl"

# ── 公共静态变量（外部直接访问）──────────────────────
static var ALLOWED_CATEGORIES: Array[String] = []
static var ALLOWED_PRICE_BANDS: Array[String] = []
static var BANNED_TERMS: Array[String] = []
static var EFFECT_ARCHETYPES: Dictionary = {}
static var LOCAL_BLUEPRINTS: Array[Dictionary] = []

# ── 内部缓存 ────────────────────────────────────────
static var _core_items: Array[Dictionary] = []
static var _category_display: Dictionary = {}
static var _seller_names: PackedStringArray = []
static var _price_ranges: Dictionary = {}
static var _absurdity: Dictionary = {}
static var _stat_labels: Dictionary = {}
static var _state_labels: Dictionary = {}
static var _weight_rules: Array[Dictionary] = []
static var _loaded: bool = false


static func _static_init() -> void:
	_load_all()


static func _ensure_loaded() -> void:
	if not _loaded:
		_load_all()


static func _load_all() -> void:
	if _loaded:
		return
	_loaded = true

	if not FileAccess.file_exists(DSL_PATH):
		push_error("[ShopCatalogStaticData] DSL 文件不存在: %s" % DSL_PATH)
		return
	var file := FileAccess.open(DSL_PATH, FileAccess.READ)
	if file == null:
		push_error("[ShopCatalogStaticData] 无法打开 DSL 文件")
		return
	var text: String = file.get_as_text()

	for raw in ShopItemBlockParser.parse_blocks(text, "EFFECT"):
		var eid: String = str(raw.get("id", ""))
		if not eid.is_empty():
			EFFECT_ARCHETYPES[eid] = _parse_effect(raw)

	LOCAL_BLUEPRINTS = ShopItemBlockParser.parse_blocks(text, "BLUEPRINT")

	for raw in ShopItemBlockParser.parse_blocks(text, "CORE_ITEM"):
		_core_items.append(_parse_core_item(raw))

	var config: Dictionary = ShopItemBlockParser.parse_multi(text, PackedStringArray([
		"CATEGORIES", "PRICE_BANDS", "PRICE_RANGES", "ABSURDITY",
		"BANNED_TERMS", "SELLER_NAMES", "STAT_LABELS", "STATE_LABELS", "WEIGHT_RULES",
	]))
	_parse_config(config)


# ╔════════════════════════════════════════════════════╗
# ║ 公共查询 API                                       ║
# ╚════════════════════════════════════════════════════╝

static func get_effect_definition(effect_id: String) -> Dictionary:
	_ensure_loaded()
	if EFFECT_ARCHETYPES.has(effect_id):
		return (EFFECT_ARCHETYPES[effect_id] as Dictionary).duplicate(true)
	return (EFFECT_ARCHETYPES.get("flavor_no_effect", {}) as Dictionary).duplicate(true)


static func get_effect_archetype_keys() -> PackedStringArray:
	_ensure_loaded()
	var keys: PackedStringArray = []
	for k in EFFECT_ARCHETYPES.keys():
		keys.append(str(k))
	return keys


static func get_fixed_core_items() -> Array[Dictionary]:
	_ensure_loaded()
	var result: Array[Dictionary] = []
	for item in _core_items:
		result.append((item as Dictionary).duplicate(true))
	return result


static func get_local_blueprints() -> Array[Dictionary]:
	_ensure_loaded()
	var result: Array[Dictionary] = []
	for bp in LOCAL_BLUEPRINTS:
		result.append((bp as Dictionary).duplicate(true))
	return result


static func get_weight_rules() -> Array[Dictionary]:
	_ensure_loaded()
	var result: Array[Dictionary] = []
	for rule in _weight_rules:
		result.append((rule as Dictionary).duplicate(true))
	return result


static func get_banned_terms() -> PackedStringArray:
	_ensure_loaded()
	return PackedStringArray(BANNED_TERMS)


static func get_seller_names() -> PackedStringArray:
	_ensure_loaded()
	return _seller_names


static func get_price_range(price_band: String) -> Array:
	_ensure_loaded()
	var key: String = price_band.strip_edges().to_lower()
	if _price_ranges.has(key):
		var val: Variant = _price_ranges[key]
		if val is Array and (val as Array).size() >= 2:
			return [int(val[0]), int(val[1])]
	return [45, 129]


static func get_absurdity(category: String) -> float:
	_ensure_loaded()
	var key: String = category.strip_edges().to_lower()
	if _absurdity.has(key):
		return float(_absurdity[key])
	return float(_absurdity.get("default", 0.2))


# ── 显示文本查询 ──────────────────────────────────

static func get_category_display(category: String) -> String:
	_ensure_loaded()
	return str(_category_display.get(category.strip_edges().to_lower(), "商品"))


static func get_effect_display(effect_id: String) -> String:
	_ensure_loaded()
	if EFFECT_ARCHETYPES.has(effect_id):
		return str((EFFECT_ARCHETYPES[effect_id] as Dictionary).get("display_name", "纯风味"))
	return "纯风味"


static func get_stat_label(key: String) -> String:
	_ensure_loaded()
	return str(_stat_labels.get(key.strip_edges().to_lower(), key))


static func get_state_label(state: String) -> String:
	_ensure_loaded()
	return str(_state_labels.get(state.strip_edges().to_lower(), state))


# ╔════════════════════════════════════════════════════╗
# ║ 内部：配置解析                                      ║
# ╚════════════════════════════════════════════════════╝

static func _parse_config(config: Dictionary) -> void:
	# CATEGORIES: items="gift|礼物||life|生活||..." → 含 || 保留为原始字符串
	var cat_blocks: Array = config.get("CATEGORIES", [])
	if not cat_blocks.is_empty():
		var raw_items: Variant = (cat_blocks[0] as Dictionary).get("items", "")
		if raw_items is String:
			for group in str(raw_items).split("||"):
				var parts: PackedStringArray = group.strip_edges().split("|")
				if parts.size() >= 1 and not parts[0].strip_edges().is_empty():
					var cat_id: String = parts[0].strip_edges()
					ALLOWED_CATEGORIES.append(cat_id)
					if parts.size() >= 2:
						_category_display[cat_id] = parts[1].strip_edges()

	# PRICE_BANDS: items=["low", "mid", "high"]
	var band_blocks: Array = config.get("PRICE_BANDS", [])
	if not band_blocks.is_empty():
		var band_items: Variant = (band_blocks[0] as Dictionary).get("items", [])
		if band_items is Array:
			for item in band_items:
				ALLOWED_PRICE_BANDS.append(str(item))

	# BANNED_TERMS: items=["淘宝", "天猫", ...]
	var ban_blocks: Array = config.get("BANNED_TERMS", [])
	if not ban_blocks.is_empty():
		var ban_items: Variant = (ban_blocks[0] as Dictionary).get("items", [])
		if ban_items is Array:
			for item in ban_items:
				BANNED_TERMS.append(str(item))

	# SELLER_NAMES: items=["日用好物精选", ...]
	var seller_blocks: Array = config.get("SELLER_NAMES", [])
	if not seller_blocks.is_empty():
		var seller_items: Variant = (seller_blocks[0] as Dictionary).get("items", [])
		if seller_items is Array:
			for item in seller_items:
				_seller_names.append(str(item))

	# PRICE_RANGES: { "low": [15, 59], ... }
	var range_blocks: Array = config.get("PRICE_RANGES", [])
	if not range_blocks.is_empty():
		_price_ranges = (range_blocks[0] as Dictionary).duplicate(true)

	# ABSURDITY: { "gift": 0.18, ... }
	var absurd_blocks: Array = config.get("ABSURDITY", [])
	if not absurd_blocks.is_empty():
		_absurdity = (absurd_blocks[0] as Dictionary).duplicate(true)

	# STAT_LABELS: { "stress": "压力", ... }
	var stat_blocks: Array = config.get("STAT_LABELS", [])
	if not stat_blocks.is_empty():
		_stat_labels = (stat_blocks[0] as Dictionary).duplicate(true)

	# STATE_LABELS: { "ready": "可使用", ... }
	var state_blocks: Array = config.get("STATE_LABELS", [])
	if not state_blocks.is_empty():
		_state_labels = (state_blocks[0] as Dictionary).duplicate(true)

	# WEIGHT_RULES: { "rule_1": ["stress", "gte", 60, ...], ... }
	var rule_blocks: Array = config.get("WEIGHT_RULES", [])
	if not rule_blocks.is_empty():
		var rules_dict: Dictionary = rule_blocks[0] as Dictionary
		for key in rules_dict:
			var parts: Variant = rules_dict[key]
			if parts is Array and (parts as Array).size() >= 7:
				var arr: Array = parts as Array
				_weight_rules.append({
					"stat_any": str(arr[0]) == "*",
					"stat_field": str(arr[0]),
					"stat_op": str(arr[1]),
					"stat_threshold": int(arr[2]),
					"match_field": str(arr[3]),
					"match_op": str(arr[4]),
					"match_value": str(arr[5]),
					"weight_bonus": int(arr[6]),
				})


# ╔════════════════════════════════════════════════════╗
# ║ 内部：效果 / 核心商品解析                           ║
# ╚════════════════════════════════════════════════════╝

static func _parse_effect(raw: Dictionary) -> Dictionary:
	var instant_stats: Dictionary = {}
	var raw_stats: Variant = raw.get("instant_stats", null)
	if raw_stats is String:
		_parse_stat_pair(str(raw_stats), instant_stats)
	elif raw_stats is Array:
		for stat_entry in raw_stats:
			_parse_stat_pair(str(stat_entry), instant_stats)

	var persistent_modifiers: Array[Dictionary] = []
	var raw_mods: Variant = raw.get("modifiers", null)
	if raw_mods is String:
		# 含 || 分隔的多组修正器
		for group in str(raw_mods).split("||"):
			var mod := _parse_modifier_str(group.strip_edges())
			if not mod.is_empty():
				persistent_modifiers.append(mod)
	elif raw_mods is Array:
		# 单组修正器，已被管道分隔解析为数组
		var mod := _parse_modifier_arr(raw_mods as Array)
		if not mod.is_empty():
			persistent_modifiers.append(mod)

	return {
		"use_mode": str(raw.get("use_mode", "flavor")),
		"modifier_slot": str(raw.get("modifier_slot", "")),
		"instant_stats": instant_stats,
		"persistent_modifiers": persistent_modifiers,
		"summary": str(raw.get("summary", "")),
		"display_name": str(raw.get("display_name", "")),
	}


static func _parse_stat_pair(pair: String, out: Dictionary) -> void:
	var sep: int = pair.find(":")
	if sep > 0:
		out[pair.substr(0, sep).strip_edges()] = int(pair.substr(sep + 1).strip_edges())


static func _parse_modifier_str(group_str: String) -> Dictionary:
	var parts: PackedStringArray = group_str.split("|")
	if parts.size() >= 4:
		return {
			"key": parts[0].strip_edges(),
			"label": parts[1].strip_edges(),
			"type": parts[2].strip_edges(),
			"value": float(parts[3].strip_edges()),
		}
	return {}


static func _parse_modifier_arr(arr: Array) -> Dictionary:
	if arr.size() >= 4:
		return {
			"key": str(arr[0]).strip_edges(),
			"label": str(arr[1]).strip_edges(),
			"type": str(arr[2]).strip_edges(),
			"value": float(arr[3]),
		}
	return {}


static func _parse_core_item(raw: Dictionary) -> Dictionary:
	var result: Dictionary = raw.duplicate(true)
	var desc: String = str(result.get("desc", ""))
	desc = desc.replace("\\n", "\n")
	result["desc"] = desc
	result["source_type"] = "fixed_core"
	result["detail_desc"] = desc
	result["short_desc"] = desc.split("\n", false)[0] if not desc.is_empty() else ""
	return result
