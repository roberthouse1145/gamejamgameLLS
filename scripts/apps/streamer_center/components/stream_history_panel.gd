extends Control
## 直播记录浏览器；没有正式结算时只显示真实空状态。

const TIME_SLOT_NAMES: Array[String] = ["上午", "下午", "晚上"]

@onready var empty_state: Control = %EmptyState
@onready var history_body: HBoxContainer = %HistoryBody
@onready var record_list: VBoxContainer = %RecordList
@onready var detail_title: Label = %DetailTitle
@onready var detail_meta: Label = %DetailMeta
@onready var detail_setup: Label = %DetailSetup
@onready var detail_cards: Label = %DetailCards
@onready var heat_value: Label = %HeatValue
@onready var revenue_value: Label = %RevenueValue
@onready var fans_value: Label = %FansValue
@onready var stress_value: Label = %StressValue
@onready var detail_summary: Label = %DetailSummary

var _records: Array[StreamSessionRecord] = []
var _selected_session_id: String = ""


func _ready() -> void:
	StreamHistoryManager.history_changed.connect(refresh)
	refresh()


func refresh() -> void:
	_records = StreamHistoryManager.get_records()
	empty_state.visible = _records.is_empty()
	history_body.visible = not _records.is_empty()
	for child: Node in record_list.get_children():
		child.queue_free()
	if _records.is_empty():
		_selected_session_id = ""
		return
	if _selected_session_id.is_empty() or not _has_record(_selected_session_id):
		_selected_session_id = _records[0].session_id
	for record: StreamSessionRecord in _records:
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 106)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text = "第 %d 天 · %s\n%s" % [record.day, _time_slot_name(record.time_slot), record.title]
		button.theme_type_variation = &"HistoryEntrySelected" if record.session_id == _selected_session_id else &"HistoryEntry"
		button.pressed.connect(_on_record_selected.bind(record.session_id))
		record_list.add_child(button)
	_render_record(_find_record(_selected_session_id))


func _render_record(record: StreamSessionRecord) -> void:
	if record == null:
		return
	detail_title.text = record.title
	detail_meta.text = "第 %d 天 · %s" % [record.day, _time_slot_name(record.time_slot)]
	detail_setup.text = "形象：%s　　素材：%s" % [record.persona_name, record.material_name]
	var card_names: Array[String] = []
	for card_id: StringName in record.card_ids:
		var card: LiveStreamCardResource = CardLibraryManager.get_card(card_id)
		card_names.append(card.display_name if card != null else String(card_id))
	detail_cards.text = "节目单：%s" % " → ".join(card_names)
	heat_value.text = str(record.heat)
	revenue_value.text = "¥%d" % record.revenue
	fans_value.text = "%+d" % record.fan_delta
	stress_value.text = "%+d" % record.stress_delta
	detail_summary.text = record.summary if not record.summary.strip_edges().is_empty() else "这场直播没有留下额外备注。"


func _has_record(session_id: String) -> bool:
	return _find_record(session_id) != null


func _find_record(session_id: String) -> StreamSessionRecord:
	for record: StreamSessionRecord in _records:
		if record.session_id == session_id:
			return record
	return null


func _time_slot_name(time_slot: int) -> String:
	return TIME_SLOT_NAMES[clampi(time_slot, 0, TIME_SLOT_NAMES.size() - 1)]


func _on_record_selected(session_id: String) -> void:
	_selected_session_id = session_id
	refresh()
