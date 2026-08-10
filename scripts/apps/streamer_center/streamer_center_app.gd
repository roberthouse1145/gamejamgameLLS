extends Control
## V-Stream 主播中心：长期状态、卡牌、成长与直播记录的统一入口。

const TAB_OVERVIEW: StringName = &"overview"
const TAB_CARDS: StringName = &"cards"
const TAB_SKILLS: StringName = &"skills"
const TAB_HISTORY: StringName = &"history"

@onready var header_account: Label = %HeaderAccount
@onready var header_day: Label = %HeaderDay

@onready var tab_buttons: Dictionary = {
	TAB_OVERVIEW: %OverviewTab,
	TAB_CARDS: %CardsTab,
	TAB_SKILLS: %SkillsTab,
	TAB_HISTORY: %HistoryTab,
}

@onready var tab_panels: Dictionary = {
	TAB_OVERVIEW: %OverviewPanel,
	TAB_CARDS: %CardLibraryPanel,
	TAB_SKILLS: %SkillTreePanel,
	TAB_HISTORY: %StreamHistoryPanel,
}

var _current_tab: StringName = TAB_OVERVIEW


func _ready() -> void:
	for tab_id: StringName in tab_buttons:
		var button: Button = tab_buttons[tab_id]
		button.pressed.connect(_show_tab.bind(tab_id))
	GameState.fans_changed.connect(_on_profile_changed)
	GameState.persona_changed.connect(_on_persona_changed)
	_update_header()
	_show_tab(TAB_OVERVIEW)


func _show_tab(tab_id: StringName) -> void:
	if not tab_panels.has(tab_id):
		return
	_current_tab = tab_id
	for current_id: StringName in tab_panels:
		var panel: Control = tab_panels[current_id]
		var button: Button = tab_buttons[current_id]
		var active: bool = current_id == tab_id
		panel.visible = active
		button.theme_type_variation = &"TabButtonSelected" if active else &"TabButton"
	if tab_panels[tab_id].has_method("refresh"):
		tab_panels[tab_id].call("refresh")
	_update_header()


func _update_header() -> void:
	var persona: StreamPersonaResource = _get_active_persona()
	header_account.text = persona.channel_name if persona != null else "暂无频道"
	header_day.text = "第 %d 天" % GameState.day


func _get_active_persona() -> StreamPersonaResource:
	var catalog: LiveStreamCatalog = CardLibraryManager.get_catalog()
	if catalog == null:
		return null
	return catalog.get_persona(StringName(GameState.active_persona_id))


func _on_profile_changed(_value: int) -> void:
	_update_header()


func _on_persona_changed(_old_persona_id: String, _new_persona_id: String) -> void:
	_update_header()
