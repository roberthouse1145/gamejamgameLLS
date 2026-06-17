extends Node

## 测试 SbeamManager 的 LLM 目录生成流程
## 验证：AIService 配置、prompt 加载、LLM 请求发送、结果解析

const ActivityBlockParserClass = preload("res://scripts/activity/activity_block_parser.gd")

func _ready() -> void:
	print("\n=== Sbeam LLM 目录生成测试 ===\n")
	_test_ai_config_role()
	_test_prompt_loading()
	_test_parse_mock_output()
	_test_live_llm_request()
	print("\n=== 静态测试完成，等待 LLM 响应... ===\n")


func _test_ai_config_role() -> void:
	print("[Test] AIConfigManager role 配置")
	var config_mgr := AIConfigManager.new()
	var loaded: bool = config_mgr.load_config()
	_assert("配置文件已加载", loaded)

	var sbeam_config: Dictionary = config_mgr.get_config_for_role("sbeam_catalog_generator")
	print("  sbeam_catalog_generator config: %s" % str(sbeam_config))
	if sbeam_config.is_empty():
		print("  [INFO] sbeam_catalog_generator 未配置，将 fallback 到 chat_default")

	var fallback_config: Dictionary = config_mgr.get_config_for_role("chat_default")
	_assert("chat_default 有配置", not fallback_config.is_empty())
	print("  chat_default model: %s" % str(fallback_config.get("model", "")))


func _test_prompt_loading() -> void:
	print("[Test] PromptManager 加载 SBEAM prompt")
	var pm: Node = get_node_or_null("/root/PromptManager")
	_assert("PromptManager 可用", pm != null)
	if pm == null:
		return
	_assert("prompt key 存在", pm.has_method("has_prompt") and pm.has_prompt("sbeam_catalog_generation"))
	if not pm.has_method("resolve_with_vars"):
		return
	var text: String = str(pm.resolve_with_vars("sbeam_catalog_generation", {
		"count": "4",
		"target_day": "3",
	})).strip_edges()
	_assert("prompt 非空", not text.is_empty())
	_assert("prompt 包含 [SBEAM_GAME]", text.find("[SBEAM_GAME]") >= 0)
	_assert("prompt 已替换数量", text.find("生成 4 个") >= 0)
	print("  prompt 长度: %d 字符" % text.length())
	print("  填充后前200字: %s" % text.left(200))


func _test_parse_mock_output() -> void:
	print("[Test] 模拟 LLM 输出解析")
	var mock_output := """
[SBEAM_GAME]
game_id=llm_sbeam_001
title=深海快递员
genre=叙事冒险
publisher=Abyssal Post Office
pitch=你在深海里送快递，每个包裹里都装着别人不敢说出口的话。
hook_moment=有一个包裹的收件人写的是自己。
reaction_bias=aftertaste
review_summary=节奏偏慢但最后十分钟直接破防。
price=42
[/SBEAM_GAME]

[SBEAM_GAME]
game_id=llm_sbeam_002
title=猫猫咖啡厅大逃杀
genre=粪作竞速
publisher=CatFight Studios
pitch=八只猫在咖啡厅里互相使绊子，最后站着的猫成为店长。
hook_moment=你推下去的那只猫回头看了你一眼。
reaction_bias=laugh
review_summary=脑子坏掉的时候玩最好。
price=18
[/SBEAM_GAME]
"""
	var blocks: Array[Dictionary] = ActivityBlockParserClass.parse_blocks(mock_output, "SBEAM_GAME")
	_assert("解析出 2 个块", blocks.size() == 2)

	if blocks.size() >= 1:
		var first: Dictionary = blocks[0]
		_assert("第1个有 title", first.has("title"))
		_assert("第1个 title=深海快递员", str(first.get("title", "")) == "深海快递员")
		_assert("第1个有 game_id", first.has("game_id"))
		_assert("第1个有 price", first.has("price"))
		_assert("第1个 price=42", int(first.get("price", 0)) == 42)
		print("  Block 1: %s" % str(first))

	if blocks.size() >= 2:
		var second: Dictionary = blocks[1]
		_assert("第2个有 title", second.has("title"))
		_assert("第2个 reaction_bias=laugh", str(second.get("reaction_bias", "")) == "laugh")
		print("  Block 2: %s" % str(second))

	# 测试 normalize
	if blocks.size() >= 1:
		var normalized := _test_normalize(blocks[0], 3, 0)
		_assert("normalize 后有 source_type", normalized.has("source_type"))
		_assert("source_type=llm_block", str(normalized.get("source_type", "")) == "llm_block")
		print("  Normalized: %s" % str(normalized))


func _test_normalize(raw: Dictionary, target_day: int, local_index: int) -> Dictionary:
	var title: String = str(raw.get("title", "")).strip_edges()
	if title.is_empty():
		return {}
	var game_id: String = str(raw.get("game_id", "")).strip_edges()
	if game_id.is_empty():
		game_id = "llm_sbeam_d%d_%02d" % [maxi(1, target_day), local_index]
	return {
		"game_id": game_id,
		"title": title,
		"genre": str(raw.get("genre", "独立游戏")).strip_edges(),
		"publisher": str(raw.get("publisher", "独立发行")).strip_edges(),
		"pitch": str(raw.get("pitch", "")).strip_edges(),
		"hook_moment": str(raw.get("hook_moment", "")).strip_edges(),
		"reaction_bias": str(raw.get("reaction_bias", "cozy")).strip_edges(),
		"review_summary": str(raw.get("review_summary", "")).strip_edges(),
		"price": int(raw.get("price", 0)),
		"is_featured_today": false,
		"source_type": "llm_block",
	}


func _test_live_llm_request() -> void:
	print("[Test] 实际 LLM 请求")
	var sbeam: Node = get_node_or_null("/root/SbeamManager")
	if sbeam == null:
		print("  [SKIP] SbeamManager autoload 不可用")
		return

	print("  SbeamManager 已加载")
	var catalog: Array = sbeam.get_catalog()
	print("  当前 catalog 数量: %d" % catalog.size())
	for i in range(catalog.size()):
		var entry: Dictionary = catalog[i]
		print("    [%d] %s (%s) - %s | source: %s" % [
			i,
			str(entry.get("title", "?")),
			str(entry.get("genre", "?")),
			str(entry.get("pitch", "")).left(40),
			str(entry.get("source_type", "seed_pool")),
		])

	# 监听 catalog_refreshed 信号（当 LLM 预生成完成后 pending 激活时会触发）
	if sbeam.has_signal("catalog_refreshed"):
		sbeam.catalog_refreshed.connect(_on_catalog_refreshed)
		print("  已连接 catalog_refreshed 信号，等待 LLM 生成...")


func _on_catalog_refreshed(catalog: Array) -> void:
	print("\n=== catalog_refreshed 信号触发 ===")
	print("  收到 %d 个条目:" % catalog.size())
	for i in range(catalog.size()):
		var entry: Dictionary = catalog[i] if catalog[i] is Dictionary else {}
		print("    [%d] %s" % [i, str(entry.get("title", "?"))])
		print("         genre: %s" % str(entry.get("genre", "?")))
		print("         pitch: %s" % str(entry.get("pitch", "")))
		print("         hook: %s" % str(entry.get("hook_moment", "")))
		print("         bias: %s | price: %s" % [
			str(entry.get("reaction_bias", "?")),
			str(entry.get("price", "?"))])
		print("         source: %s" % str(entry.get("source_type", "?")))


func _assert(label: String, condition: bool) -> void:
	if condition:
		print("  ✓ %s" % label)
	else:
		print("  ✗ FAIL: %s" % label)
