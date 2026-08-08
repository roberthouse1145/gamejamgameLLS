extends Control
## Card / Slot / Deck 手感验收：真卡跟手、压缩间隔、hover 展开、过滤、锁定、交换。

const CARD_SCENE: PackedScene = preload("res://scenes/apps/obs_live/components/live_stream_card.tscn")
const DECK_SCENE: PackedScene = preload("res://scenes/ui/cards/card_deck.tscn")
const SLOT_SCENE: PackedScene = preload("res://scenes/apps/obs_live/components/card_drop_slot.tscn")
const DRAG_CONTROLLER_SCENE: PackedScene = preload("res://scenes/ui/cards/card_drag_controller.tscn")
const PSEUDO_CURSOR_SCENE: PackedScene = preload("res://scenes/pseudo_os/pseudo_cursor.tscn")

const BEHAVIOR_PATHS: Array[String] = [
	"res://resources/live_stream/cards/behavior/talk/daily_greeting.tres",
	"res://resources/live_stream/cards/behavior/talk/passionate_rant.tres",
	"res://resources/live_stream/cards/behavior/talk/recovery.tres",
	"res://resources/live_stream/cards/behavior/game/clear_reflection.tres",
	"res://resources/live_stream/cards/behavior/game/hardcore_guide.tres",
	"res://resources/live_stream/cards/behavior/game/serious_game_opening.tres",
	"res://resources/live_stream/cards/behavior/game/stuck_rage.tres",
	"res://resources/live_stream/cards/behavior/song/acapella.tres",
	"res://resources/live_stream/cards/behavior/song/asmr_whisper.tres",
	"res://resources/live_stream/cards/behavior/song/encore.tres",
	"res://resources/live_stream/cards/behavior/song/warmup_humming.tres",
	"res://resources/live_stream/cards/behavior/act/cute_appeal.tres",
	"res://resources/live_stream/cards/behavior/act/instant_voice.tres",
	"res://resources/live_stream/cards/behavior/act/plead.tres",
	"res://resources/live_stream/cards/behavior/tech/comedy_effects.tres",
	"res://resources/live_stream/cards/behavior/tech/fake_disconnect.tres",
]
const MODIFIER_PATHS: Array[String] = [
	"res://resources/live_stream/cards/modifiers/motherly_tone.tres",
	"res://resources/live_stream/cards/modifiers/seamless_transition.tres",
	"res://resources/live_stream/cards/modifiers/polite_business.tres",
	"res://resources/live_stream/cards/modifiers/toxic_commentator.tres",
]

@onready var status_label: Label = %StatusLabel
@onready var stage: Control = %Stage

var _controller: CardDragController = null
var _single_deck: CardDeck = null
var _multi_deck: CardDeck = null
var _slot_empty: CardSlot = null
var _slot_filled: CardSlot = null
var _slot_behavior_only: CardSlot = null
var _slot_locked: CardSlot = null


func _ready() -> void:
	_controller = DRAG_CONTROLLER_SCENE.instantiate() as CardDragController
	add_child(_controller)
	_controller.move_committed.connect(_on_move_committed)
	_controller.drop_rejected.connect(_on_drop_rejected)
	_controller.drag_finished.connect(_on_drag_finished)

	var cursor: Control = PSEUDO_CURSOR_SCENE.instantiate() as Control
	add_child(cursor)

	_build_slots()
	_build_decks()
	_set_status("悬停看 glow；拖到 Slot / Deck；试过滤、锁定与交换")


func _build_slots() -> void:
	var row := HBoxContainer.new()
	row.position = Vector2(40, 96)
	row.add_theme_constant_override("separation", 24)
	stage.add_child(row)

	_slot_empty = _make_slot("空槽", [], "任意卡", false)
	_slot_filled = _make_slot("已占用", [], "已有卡", false)
	_slot_behavior_only = _make_slot("仅行为卡", ["behavior"], "只收行为卡", false)
	_slot_locked = _make_slot("锁定", [], "锁定", true)

	for slot: CardSlot in [_slot_empty, _slot_filled, _slot_behavior_only, _slot_locked]:
		var wrap := Control.new()
		wrap.custom_minimum_size = CardDisplayMetrics.FULL_SIZE + Vector2(0, 36)
		var label := Label.new()
		label.text = String(slot.slot_key)
		label.position = Vector2(0, 0)
		label.add_theme_font_size_override("font_size", 20)
		wrap.add_child(label)
		slot.position = Vector2(0, 28)
		slot.custom_minimum_size = CardDisplayMetrics.FULL_SIZE
		slot.size = slot.custom_minimum_size
		wrap.add_child(slot)
		row.add_child(wrap)
		_controller.register_container(slot)

	var starter: LiveStreamCardView = _make_card(MODIFIER_PATHS[0], "modifier")
	_controller.bind_card(starter)
	_slot_filled.set_card(starter)

	var locked_card: LiveStreamCardView = _make_card(BEHAVIOR_PATHS[0], "behavior", true)
	_controller.bind_card(locked_card)
	_slot_locked.set_card(locked_card)


func _build_decks() -> void:
	_single_deck = DECK_SCENE.instantiate() as CardDeck
	_single_deck.position = Vector2(40, 780)
	_single_deck.custom_minimum_size = Vector2(1800, 640)
	_single_deck.size = _single_deck.custom_minimum_size
	_single_deck.row_count = 1
	_single_deck.card_size = CardDisplayMetrics.FULL_SIZE
	_single_deck.normal_gap = 18.0
	_single_deck.min_gap = -360.0
	_single_deck.hover_extra_gap = 56.0
	stage.add_child(_single_deck)
	_controller.register_container(_single_deck)
	_single_deck.card_clicked.connect(func(card: Control) -> void:
		_set_status("点击：%s" % _card_title(card))
	)

	var single_title := Label.new()
	single_title.text = "单行 Deck（卡多会压缩间距，hover 局部展开）"
	single_title.position = Vector2(40, 748)
	single_title.add_theme_font_size_override("font_size", 22)
	stage.add_child(single_title)

	for i: int in range(10):
		var card: LiveStreamCardView = _make_card(BEHAVIOR_PATHS[i], "behavior")
		_controller.bind_card(card)
		_single_deck.add_card(card)

	_multi_deck = DECK_SCENE.instantiate() as CardDeck
	_multi_deck.position = Vector2(40, 1460)
	_multi_deck.custom_minimum_size = Vector2(1800, 1240)
	_multi_deck.size = _multi_deck.custom_minimum_size
	_multi_deck.row_count = 2
	_multi_deck.card_size = CardDisplayMetrics.FULL_SIZE
	_multi_deck.normal_gap = 14.0
	_multi_deck.min_gap = -280.0
	_multi_deck.hover_extra_gap = 48.0
	_multi_deck.accepted_kinds = ["behavior", "modifier"]
	stage.add_child(_multi_deck)
	_controller.register_container(_multi_deck)

	var multi_title := Label.new()
	multi_title.text = "双行 Deck（可重排；可与 Slot 交换）"
	multi_title.position = Vector2(40, 1428)
	multi_title.add_theme_font_size_override("font_size", 22)
	stage.add_child(multi_title)

	for i: int in range(8):
		var is_modifier: bool = i >= 4
		var path: String = MODIFIER_PATHS[i - 4] if is_modifier else BEHAVIOR_PATHS[10 + i]
		var kind: String = "modifier" if is_modifier else "behavior"
		var card: LiveStreamCardView = _make_card(path, kind)
		_controller.bind_card(card)
		_multi_deck.add_card(card)


func _make_slot(key: String, kinds: Array, text: String, is_locked: bool) -> CardSlot:
	var slot: CardSlot = SLOT_SCENE.instantiate() as CardSlot
	slot.setup(key, kinds, text, CardDisplayMetrics.FULL_SIZE)
	slot.locked = is_locked
	return slot


func _make_card(path: String, kind: String, is_locked: bool = false) -> LiveStreamCardView:
	var resource: LiveStreamCardResource = load(path) as LiveStreamCardResource
	assert(resource != null, "Playtest card resource missing: %s" % path)
	var card: LiveStreamCardView = CARD_SCENE.instantiate() as LiveStreamCardView
	card.configure(resource, false, is_locked)
	card.drag_payload = {} if is_locked else {
		"kind": kind,
		"card_id": String(resource.content_id),
		"title": resource.display_name,
	}
	return card


func _on_move_committed(card: Control, payload: Dictionary, source: Node, target: Node) -> void:
	_set_status("移动成功：%s  %s -> %s" % [
		String(payload.get("title", "?")),
		_container_name(source),
		_container_name(target),
	])
	print("[Playtest] move_committed title=%s source=%s target=%s" % [
		String(payload.get("title", "")),
		_container_name(source),
		_container_name(target),
	])


func _on_drop_rejected(card: Control, payload: Dictionary, target: Node) -> void:
	_set_status("拒绝：%s -> %s" % [String(payload.get("title", "?")), _container_name(target)])
	print("[Playtest] drop_rejected title=%s target=%s" % [
		String(payload.get("title", "")),
		_container_name(target),
	])


func _on_drag_finished(success: bool, card: Control, payload: Dictionary, target: Node) -> void:
	if success:
		return
	_set_status("回弹：%s（目标=%s）" % [String(payload.get("title", "?")), _container_name(target)])


func _container_name(node: Node) -> String:
	if node == null:
		return "无"
	if node is CardSlot:
		return "Slot(%s)" % str((node as CardSlot).slot_key)
	if node is CardDeck:
		if node == _single_deck:
			return "Deck(单行)"
		if node == _multi_deck:
			return "Deck(双行)"
		return "Deck"
	return node.name


func _card_title(card: Control) -> String:
	if card is LiveStreamCardView:
		var view := card as LiveStreamCardView
		return view.content_resource.display_name if view.content_resource != null else "?"
	return card.name


func _set_status(text: String) -> void:
	status_label.text = text
