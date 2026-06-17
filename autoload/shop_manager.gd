extends Node
## ShopManager — 商店门面：对外 API 不变，内部委托给 OrderService / InventoryService
## 目录生成委托给 ShopCatalogFactory

const _ShopItem = preload("res://scripts/shop/shop_item.gd")
const _OrderSvc = preload("res://scripts/shop/shop_order_service.gd")
const _InvSvc = preload("res://scripts/shop/shop_inventory_service.gd")
const ActivityLockUtilsClass = preload("res://scripts/activity/activity_lock_utils.gd")

signal catalog_refreshed(catalog: Array)
signal catalog_generation_started(day: int)
signal catalog_generation_failed(error_msg: String)
signal purchase_completed(order: Dictionary)
signal order_status_changed(order_id: String, status: String)
signal delivery_arrived(order_id: String, inventory_item: Dictionary)
signal inventory_changed(inventory: Array)
signal active_effects_changed(active_effects: Array)
signal item_gifted(shop_item: ShopItem)
signal shop_state_changed()

const SHOP_ROLE: String = "shop_generator"
const FALLBACK_ROLE: String = "chat_default"

var _ai_service: AIService = null
var _llm_enabled: bool = false
var _catalog_request_id: String = ""
var _catalog_request_day: int = -1
var _is_generating_catalog: bool = false
var _catalog: Array = []  # Array[ShopItem]
var _catalog_day: int = -1
var _pending_next_day_catalog: Array = []  # Array[ShopItem]

var _order_svc = _OrderSvc.new()
var _inv_svc = _InvSvc.new()


func _is_background_llm_disabled() -> bool:
	return AIConfigManager.get_instance().is_background_llm_disabled()


func _log_debug(message: String) -> void:
	if AIConfigManager.get_instance().is_quiet_logs_enabled():
		return
	print(message)


func _ready() -> void:
	name = "ShopManager"
	_setup_ai_service()
	_connect_signals()
	# Day 1: local catalog, then async pre-generate Day 2
	var current_day: int = _get_current_day()
	_apply_catalog(ShopCatalogFactory.generate_local_daily_catalog(current_day, _get_gm()), current_day)


func _connect_signals() -> void:
	var glm: Node = get_node_or_null("/root/GameLoopManager")
	if glm != null and glm.has_signal("day_changed") \
			and not glm.day_changed.is_connected(_on_day_changed):
		glm.day_changed.connect(_on_day_changed)

	# 转发 service 信号
	_order_svc.purchase_completed.connect(func(o): purchase_completed.emit(o))
	_order_svc.order_status_changed.connect(func(oid, s): order_status_changed.emit(oid, s))
	_order_svc.delivery_arrived.connect(func(oid, inv):
		delivery_arrived.emit(oid, inv)
		inventory_changed.emit(_inv_svc.get_inventory())
		_emit_state_changed()
	)
	_inv_svc.inventory_changed.connect(func(inv): inventory_changed.emit(inv))
	_inv_svc.active_effects_changed.connect(func(eff): active_effects_changed.emit(eff))


func _setup_ai_service() -> void:
	if _is_background_llm_disabled():
		_llm_enabled = false
		return
	_ai_service = AIService.new()
	_ai_service.name = "ShopAIService"
	_ai_service.max_history_messages = 0
	_ai_service.auto_execute_tools = false
	_ai_service.stream_enabled = false
	_ai_service.max_concurrent_requests = 1
	_ai_service.default_temperature = 0.9
	add_child(_ai_service)

	if not _ai_service.request_completed.is_connected(_on_ai_request_completed):
		_ai_service.request_completed.connect(_on_ai_request_completed)
	if not _ai_service.request_failed.is_connected(_on_ai_request_failed):
		_ai_service.request_failed.connect(_on_ai_request_failed)

	var config_mgr := AIConfigManager.get_instance()
	if not config_mgr.get_config_for_role(SHOP_ROLE).is_empty():
		_llm_enabled = config_mgr.apply_to_service(_ai_service, SHOP_ROLE)
	if not _llm_enabled and not config_mgr.get_config_for_role(FALLBACK_ROLE).is_empty():
		_llm_enabled = config_mgr.apply_to_service(_ai_service, FALLBACK_ROLE)


# ══════════════════════════════════════════════════════
#  公共查询 API（保持对外接口不变）
# ══════════════════════════════════════════════════════

func get_catalog() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in _catalog:
		result.append(item.to_dict())
	return result


func get_orders() -> Array[Dictionary]:
	return _order_svc.get_orders()


func get_inventory() -> Array[Dictionary]:
	return _inv_svc.get_inventory()


func get_catalog_day() -> int:
	return _catalog_day


func get_active_effects() -> Array[Dictionary]:
	return _inv_svc.get_active_effects()


func get_active_modifier_map() -> Dictionary:
	return _inv_svc.get_active_modifier_map()


func has_pending_requests() -> bool:
	return _is_generating_catalog and not _catalog_request_id.is_empty()


func pre_generate_next_day_catalog() -> void:
	_generate_catalog_for_day(_get_current_day() + 1)


func has_purchased_item(item_id: String) -> bool:
	return _order_svc.has_purchased_item(item_id)


# ══════════════════════════════════════════════════════
#  目录刷新
# ══════════════════════════════════════════════════════

func refresh_daily_catalog(force: bool = false, use_local_only: bool = false) -> void:
	var day: int = _get_current_day()
	if not force and day == _catalog_day and not _catalog.is_empty():
		catalog_refreshed.emit(get_catalog())
		return

	if use_local_only or _ai_service == null or not _llm_enabled:
		_cancel_pending_catalog_request()
		_apply_catalog(ShopCatalogFactory.generate_local_daily_catalog(day, _get_gm()), day)
		return

	# Fallback to local if no pending catalog available
	_cancel_pending_catalog_request()
	_apply_catalog(ShopCatalogFactory.generate_local_daily_catalog(day, _get_gm()), day)


## Internal: send LLM request to pre-generate catalog for target_day
func _generate_catalog_for_day(target_day: int) -> void:
	if _is_background_llm_disabled():
		return
	if _ai_service == null or not _llm_enabled:
		return
	if _is_generating_catalog:
		return
	_is_generating_catalog = true
	_catalog_request_day = target_day
	catalog_generation_started.emit(target_day)
	_catalog_request_id = _ai_service.chat_simple(
		ShopCatalogFactory.build_generation_prompt(target_day, _get_gm()),
		ShopCatalogFactory.build_generation_system_prompt(),
		{"prompt_key": "shop/catalog_generation_user"}
	)
	if _catalog_request_id.is_empty():
		_is_generating_catalog = false
		push_warning("[ShopManager] Failed to send LLM catalog request for day %d" % target_day)


# ══════════════════════════════════════════════════════
#  购买 / 使用（委托给 service）
# ══════════════════════════════════════════════════════

func purchase_item(item_ref: String) -> Dictionary:
	var item = _find_catalog_item(item_ref)
	if item == null:
		return {"success": false, "error": "没有找到这件商品。"}

	var price: int = item.price
	var gm: Node = _get_gm()
	if gm == null:
		return {"success": false, "error": "GameManager 不存在。"}
	if int(gm.get("money")) < price:
		return {"success": false, "error": "余额不足。"}

	gm.modify_stat("money", -price)
	var current_day: int = _get_current_day()
	var storage: Node = get_node_or_null("/root/StorageManager")
	var is_debug: bool = storage != null and bool(storage.get("developer_mode"))

	var result: Dictionary = _order_svc.create_order(
		item, current_day, is_debug, _inv_svc.add_inventory_item)
	if bool(result.get("success", false)):
		_emit_state_changed()
	return result


func use_inventory_item(inventory_id: String, target: String = "self") -> Dictionary:
	var blocking_reason := _get_inventory_use_blocking_reason(inventory_id)
	if not blocking_reason.is_empty():
		ActivityLockUtilsClass.notify_blocked(self, blocking_reason)
		return {"success": false, "error": blocking_reason}
	var result: Dictionary = _inv_svc.use_item(
		inventory_id, target, _get_current_day(), _get_gm())
	if bool(result.get("success", false)):
		_emit_state_changed()
		if str(result.get("mode", "")) == "gift":
			var shop_item := ShopItem.from_dict(result.get("item", {}))
			item_gifted.emit(shop_item)
			_trigger_gift_topic(shop_item)
	return result


func process_day_transition(day: int) -> void:
	var did_deliver: bool = _order_svc.advance_orders_for_day(
		day, _inv_svc.add_inventory_item)
	if did_deliver:
		inventory_changed.emit(_inv_svc.get_inventory())
		_emit_state_changed()


# ══════════════════════════════════════════════════════
#  存档
# ══════════════════════════════════════════════════════

func get_run_state() -> Dictionary:
	var order_state: Dictionary = _order_svc.get_state()
	var inv_state: Dictionary = _inv_svc.get_state()
	var pending_dicts: Array = []
	for item in _pending_next_day_catalog:
		pending_dicts.append(item.to_dict())
	return {
		"catalog_day": _catalog_day,
		"catalog": get_catalog(),
		"pending_next_day_catalog": pending_dicts,
		"orders": order_state.get("orders", []),
		"id_counter": int(order_state.get("id_counter", 0)),
		"inventory": inv_state.get("inventory", []),
		"active_effects": inv_state.get("active_effects", {}),
		"last_gift_day": int(inv_state.get("last_gift_day", -1)),
	}


func load_run_state(data: Dictionary) -> bool:
	_cancel_pending_catalog_request()
	_catalog_day = int(data.get("catalog_day", -1))
	_catalog.clear()

	for item in data.get("catalog", []):
		if item is Dictionary:
			_catalog.append(_ShopItem.from_dict(item as Dictionary))

	_pending_next_day_catalog.clear()
	for item in data.get("pending_next_day_catalog", []):
		if item is Dictionary:
			_pending_next_day_catalog.append(_ShopItem.from_dict(item as Dictionary))

	_order_svc.load_state({
		"orders": data.get("orders", []),
		"id_counter": int(data.get("id_counter", 0)),
	})
	_inv_svc.load_state({
		"inventory": data.get("inventory", []),
		"active_effects": data.get("active_effects", {}),
		"last_gift_day": int(data.get("last_gift_day", -1)),
	})
	var normalized_orders: bool = _order_svc.normalize_orders_for_instant_inventory(_inv_svc.add_inventory_item)

	if _catalog.is_empty():
		_apply_catalog(ShopCatalogFactory.generate_local_daily_catalog(
			_get_current_day(), _get_gm()), _get_current_day())
	else:
		catalog_refreshed.emit(get_catalog())
		inventory_changed.emit(_inv_svc.get_inventory())
		active_effects_changed.emit(_inv_svc.get_active_effects())
		if normalized_orders:
			_emit_state_changed()
		_emit_state_changed()
	return true


func reset_runtime_state() -> void:
	_cancel_pending_catalog_request()
	_catalog.clear()
	_pending_next_day_catalog.clear()
	_order_svc.reset()
	_inv_svc.reset()
	var current_day: int = _get_current_day()
	_apply_catalog(ShopCatalogFactory.generate_local_daily_catalog(current_day, _get_gm()), current_day)
	_generate_catalog_for_day(current_day + 1)


# ══════════════════════════════════════════════════════
#  内部：LLM 回调
# ══════════════════════════════════════════════════════

func _on_day_changed(new_day: int) -> void:
	var did_deliver: bool = _order_svc.advance_orders_for_day(
		new_day, _inv_svc.add_inventory_item)
	if did_deliver:
		inventory_changed.emit(_inv_svc.get_inventory())
		_emit_state_changed()
	# Activate pre-generated catalog if available
	if not _pending_next_day_catalog.is_empty():
		_apply_catalog(_pending_next_day_catalog, new_day)
		_pending_next_day_catalog.clear()
		_log_debug("[ShopManager] Activated %d pre-generated items for day %d" % [_catalog.size(), new_day])
	else:
		# No pending: fallback to local
		_apply_catalog(ShopCatalogFactory.generate_local_daily_catalog(new_day, _get_gm()), new_day)
	# Pre-generate for next day
	_generate_catalog_for_day(new_day + 1)


func _on_ai_request_completed(request_id: String, response: Dictionary) -> void:
	if request_id != _catalog_request_id:
		return

	var request_day: int = _catalog_request_day
	_cancel_pending_catalog_request()

	var raw_text: String = AIService.extract_content(response).strip_edges()
	var max_llm: int = ShopCatalogFactory.CATALOG_SIZE
	var llm_items: Array = ShopCatalogFactory.parse_llm_catalog_items(raw_text, request_day, max_llm)
	if llm_items.is_empty():
		catalog_generation_failed.emit("LLM 商品预生成解析失败（Day %d）" % request_day)
		return

	var catalog: Array = []
	var index: int = 0
	for llm_item in llm_items:
		var decorated := ShopCatalogFactory.decorate_catalog_item(
			llm_item.to_dict(), request_day, index)
		catalog.append(_ShopItem.from_dict(decorated))
		index += 1
		if catalog.size() >= ShopCatalogFactory.CATALOG_SIZE:
			break

	var local_fill: Array = ShopCatalogFactory.generate_local_daily_catalog(
		request_day, _get_gm())
	var used_ids: Dictionary = {}
	for existing in catalog:
		used_ids[existing.item_id] = true

	while catalog.size() < ShopCatalogFactory.CATALOG_SIZE:
		var appended: bool = false
		for candidate in local_fill:
			if used_ids.has(candidate.item_id):
				continue
			catalog.append(candidate.duplicate())
			used_ids[candidate.item_id] = true
			appended = true
			break
		if not appended:
			break

	_pending_next_day_catalog = catalog
	_log_debug("[ShopManager] Pre-generated %d items (pending activation on next day)" % catalog.size())


func _on_ai_request_failed(request_id: String, error_msg: String, _error_code: int) -> void:
	if request_id != _catalog_request_id:
		return
	_cancel_pending_catalog_request()
	catalog_generation_failed.emit("LLM 商品预生成失败：%s" % error_msg)


# ══════════════════════════════════════════════════════
#  内部：工具函数
# ══════════════════════════════════════════════════════

func _apply_catalog(items: Array, day: int) -> void:
	_catalog = []
	for item in items:
		_catalog.append(item.duplicate())
	_catalog_day = day
	catalog_refreshed.emit(get_catalog())
	_emit_state_changed()


func _find_catalog_item(item_ref: String):
	for item in _catalog:
		if item.instance_id == item_ref or item.item_id == item_ref:
			return item
	return null


func _cancel_pending_catalog_request() -> void:
	_catalog_request_id = ""
	_catalog_request_day = -1
	_is_generating_catalog = false


func _get_current_day() -> int:
	var glm: Node = get_node_or_null("/root/GameLoopManager")
	if glm == null:
		return 1
	return maxi(1, int(glm.get("current_day")))


func _get_gm() -> Node:
	return get_node_or_null("/root/GameManager")


func _get_inventory_use_blocking_reason(inventory_id: String) -> String:
	var inventory_item := _find_inventory_item(inventory_id)
	if inventory_item.is_empty():
		return ""
	var effect_id: String = str(inventory_item.get("effect_archetype", ""))
	var effect := ShopCatalogFactory.get_effect_definition(effect_id)
	if str(effect.get("use_mode", "consume")) != "gift":
		return ""
	return ActivityLockUtilsClass.get_blocking_reason(self)


func _find_inventory_item(inventory_id: String) -> Dictionary:
	for item_data in _inv_svc.get_inventory():
		if not (item_data is Dictionary):
			continue
		var item: Dictionary = item_data
		if str(item.get("inventory_id", "")) == inventory_id:
			return item.duplicate(true)
	return {}


func _trigger_gift_topic(shop_item: ShopItem) -> void:
	var chat: Node = get_node_or_null("/root/ChatManager")
	if chat == null or not chat.has_method("activate_topic"):
		return
	const DM_CHANNEL := "dm_lin_xia"
	if chat.has_method("has_active_topic") and chat.has_active_topic(DM_CHANNEL):
		return

	# 1) 玩家发送商品分享卡片
	if chat.has_method("store_player_message_data"):
		chat.store_player_message_data(DM_CHANNEL, {
			"content": "",
			"card": shop_item.build_gift_card(),
		})

	# 2) 打开 linkchat 并定位到 DM 频道
	_open_linkchat_dm(DM_CHANNEL)

	# 3) 激活 topic，让 NPC 回复
	var prompt := "玩家刚刚送了你一件礼物：%s\n请根据你对这件礼物的感受自然地回应，简短即可。" % shop_item.get_prompt()

	const ChatTopicClass = preload("res://scripts/chat/resources/chat_topic.gd")
	var topic := ChatTopicClass.new()
	topic.topic_id = "gift_%s_%d" % [shop_item.item_id, Time.get_ticks_msec()]
	topic.topic_type = "relationship_event"
	topic.display_title = "收到礼物"
	topic.npc_id = "npc_lin_xia"
	topic.channel_id = DM_CHANNEL
	topic.system_prompt = prompt
	topic.goal_description = "对收到的礼物做出反应"
	topic.timeout_seconds = 30
	topic.context_data = {"suppress_system_notice": true}

	if not chat.activate_topic(topic):
		return
	chat.request_topic_npc_reply(DM_CHANNEL, "", false, true)


func _open_linkchat_dm(channel_id: String) -> void:
	var app_manager: Node = get_node_or_null("/root/AppManager")
	if app_manager == null or not app_manager.has_method("launch_app"):
		return
	if app_manager.get("window_manager") == null:
		return
	var window: Control = app_manager.launch_app("linkchat", true)
	if window == null or not is_instance_valid(window):
		return
	call_deferred("_select_linkchat_channel", window, channel_id)


func _select_linkchat_channel(window: Control, channel_id: String) -> void:
	if window == null or not is_instance_valid(window):
		return
	var content: Variant = window.get("content")
	if content != null and content.has_method("select_channel"):
		content.select_channel(channel_id)


func _emit_state_changed() -> void:
	shop_state_changed.emit()
