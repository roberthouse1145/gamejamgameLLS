extends Node

const ChatDslParserClass = preload("res://scripts/chat/chat_dsl_parser.gd")
const ChatTopicClass = preload("res://scripts/chat/resources/chat_topic.gd")
const TopicManagerScene = preload("res://scenes/chat/topic_manager.tscn")

var _failures: int = 0
var _messages: Array[Dictionary] = []
var _choices: Array = []
var _completed_result: Dictionary = {}
var _generation_prompt: String = ""


func _ready() -> void:
	_test_validation()
	_test_location_card_flow()
	_test_conditions()
	_test_local_flow()
	_test_elif_flow()
	_test_jump()
	_test_llm_flow()
	_test_same_channel_queue()

	if _failures == 0:
		print("[PASS] chat dsl")
	else:
		push_error("[FAIL] chat dsl: %d checks failed" % _failures)


func _test_validation() -> void:
	var valid: Dictionary = ChatDslParserClass.parse(
		"player: 已经写定的回复。\nfriend: 收到。\nEND viewed",
		["friend"],
		[]
	)
	_check(bool(valid.get("ok", false)), "player is always a valid reserved speaker")

	var unknown_speaker: Dictionary = ChatDslParserClass.parse("stranger: 你好。\nEND viewed", ["friend"], [])
	_check(not bool(unknown_speaker.get("ok", true)), "unknown channel speaker is rejected")

	var unknown_path: Dictionary = ChatDslParserClass.parse(
		"IF state.unknown > 0\nplayer: test\nENDIF\nEND viewed",
		[],
		["state.stress"]
	)
	_check(not bool(unknown_path.get("ok", true)), "unknown variable path is rejected")

	var no_fallback: Dictionary = ChatDslParserClass.parse(
		"CHOICE\nOPTION only \"唯一选项\" -> end IF state.stress > 0\nENDCHOICE\nLABEL end\nEND viewed",
		[],
		["state.stress"]
	)
	_check(not bool(no_fallback.get("ok", true)), "choice requires an unconditional option")


func _test_conditions() -> void:
	var result: Dictionary = ChatDslParserClass.evaluate_condition(
		"NOT story.blocked AND (state.stress >= 80 OR relationship.friend.trust >= 30)",
		{
			"story": {"blocked": false},
			"state": {"stress": 85},
			"relationship": {"friend": {"trust": 10}},
		}
	)
	_check(bool(result.get("ok", false)) and bool(result.get("value", false)), "boolean condition supports NOT, AND, OR and parentheses")


func _test_location_card_flow() -> void:
	_reset_events()
	var manager: TopicManager = _create_manager()
	var topic: ChatTopic = ChatTopicClass.new()
	topic.topic_id = "location_card"
	topic.channel_id = "location_card_channel"
	topic.local_script = """player: 今天风挺大诶。
player: [card:location|test_activity]
player: 要不要去河边走走？
END invited"""

	_check(manager.activate_topic(topic), "location card topic activates")
	_check(
		_messages.size() == 1 \
			and _messages[0].get("text") == "今天风挺大诶。" \
			and (_messages[0].get("card", {}) as Dictionary).is_empty(),
		"text before the card remains an unchanged standalone message"
	)
	manager.advance_topic(topic.channel_id)
	var location_card: Dictionary = {}
	if _messages.size() > 1:
		location_card = _messages[1].get("card", {}) as Dictionary
	_check(
		_messages.size() == 2 \
			and str(_messages[1].get("text", "")).is_empty() \
			and str(location_card.get("type", "")) == "location" \
			and str(location_card.get("activity_id", "")) == "test_activity",
		"location card carries only the activity id; display fields are filled by the runtime"
	)
	manager.advance_topic(topic.channel_id)
	_check(
		_messages.size() == 3 and _messages[2].get("text") == "要不要去河边走走？",
		"text after the card keeps its generated order"
	)
	manager.advance_topic(topic.channel_id)
	manager.queue_free()


func _test_local_flow() -> void:
	_reset_events()
	var manager: TopicManager = _create_manager()
	var topic: ChatTopic = ChatTopicClass.new()
	topic.topic_id = "local_branch"
	topic.channel_id = "friend_chat"
	topic.mode = ChatTopic.Mode.LOCAL
	topic.local_script = """LABEL start
IF state.stress >= 80
friend: 你今天是不是又在硬撑？
ELSE
friend: 今天过得怎么样？
ENDIF
CHOICE
OPTION confess "说实话" -> confess IF relationship.friend.trust >= 30
OPTION avoid "先敷衍过去" -> avoid
ENDCHOICE
LABEL confess
player: 其实今天不太好。
friend: 那就别装没事。
END confessed
LABEL avoid
player: 没什么。
END avoided"""

	_check(manager.activate_topic(topic, {
		"state": {"stress": 90},
		"relationship": {"friend": {"trust": 40}},
	}, ["friend"]), "LOCAL topic activates")
	_check(_messages.size() == 1 and _messages[0].get("text") == "你今天是不是又在硬撑？", "IF selects the matching message branch")
	if not _messages.is_empty():
		_check(not bool(_messages[0].get("is_player", true)), "non-player message is marked for the left side")

	_check(manager.advance_topic(topic.channel_id), "LOCAL topic advances to choice")
	_check(_choices.size() == 2, "eligible fixed choices are presented")
	_check(manager.choose_topic_option(topic.channel_id, "confess"), "fixed choice selects its label")
	_check(_messages.size() == 2 and bool(_messages[1].get("is_player", false)), "player message is marked for the right side")
	_check(_messages[1].get("speaker") == "player", "player speaker id is preserved")

	manager.advance_topic(topic.channel_id)
	_check(_messages.size() == 3 and _messages[2].get("speaker") == "friend", "execution continues after player message")
	manager.advance_topic(topic.channel_id)
	_check(_completed_result.get("result_id") == "confessed", "END returns its result id")
	_check(_completed_result.get("choice_id") == "confess", "selected option id is returned")
	_check(not manager.has_active_topic(topic.channel_id), "completed topic leaves the active channel")
	manager.queue_free()


func _test_jump() -> void:
	_reset_events()
	var manager: TopicManager = _create_manager()
	var topic: ChatTopic = ChatTopicClass.new()
	topic.topic_id = "jump"
	topic.channel_id = "jump_channel"
	topic.local_script = "JUMP ending\nfriend: skipped\nLABEL ending\nplayer: arrived\nEND jumped"
	_check(manager.activate_topic(topic, {}, ["friend"]), "JUMP topic activates")
	_check(_messages.size() == 1 and _messages[0].get("text") == "arrived", "JUMP skips directly to its top-level label")
	manager.advance_topic(topic.channel_id)
	_check(_completed_result.get("result_id") == "jumped", "jumped topic completes")
	manager.queue_free()


func _test_elif_flow() -> void:
	_reset_events()
	var manager: TopicManager = _create_manager()
	var topic: ChatTopic = ChatTopicClass.new()
	topic.topic_id = "elif"
	topic.channel_id = "elif_channel"
	topic.local_script = "IF state.stress >= 80\nplayer: high\nELIF state.stress >= 40\nplayer: middle\nELSE\nplayer: low\nENDIF\nEND branched"
	_check(manager.activate_topic(topic, {"state": {"stress": 60}}), "ELIF topic activates")
	_check(_messages.size() == 1 and _messages[0].get("text") == "middle", "ELIF selects the first matching branch")
	manager.advance_topic(topic.channel_id)
	_check(_completed_result.get("result_id") == "branched", "ELIF branch reaches END")
	manager.queue_free()


func _test_llm_flow() -> void:
	_reset_events()
	var manager: TopicManager = _create_manager()
	var topic: ChatTopic = ChatTopicClass.new()
	topic.topic_id = "generated"
	topic.channel_id = "generated_channel"
	topic.mode = ChatTopic.Mode.LLM
	topic.local_script = "player: LOCAL text remains stored.\nEND local"
	topic.prompt = "写一段朋友确认近况的聊天。"

	_check(manager.activate_topic(topic, {"state": {"stress": 20}}, ["friend"]), "LLM topic enters generation state")
	_check(_messages.is_empty(), "LLM mode does not execute preserved local_script")
	_check(_generation_prompt.contains("player") and _generation_prompt.contains("state.stress"), "PromptManager receives reserved speaker and available paths")
	_check(manager.submit_generated_script(topic.channel_id, "friend: 最近还好吗？\nplayer: 还好。\nEND generated"), "generated DSL enters the shared runner")
	_check(_messages.size() == 1 and _messages[0].get("speaker") == "friend", "generated DSL emits its first message")
	manager.advance_topic(topic.channel_id)
	_check(_messages.size() == 2 and bool(_messages[1].get("is_player", false)), "generated player message uses the right-side marker")
	manager.advance_topic(topic.channel_id)
	_check(_completed_result.get("result_id") == "generated", "generated DSL completes through the shared result path")
	_check(topic.local_script.contains("LOCAL text remains stored"), "switching mode preserves local_script")
	manager.queue_free()


func _test_same_channel_queue() -> void:
	_reset_events()
	var manager: TopicManager = _create_manager()
	var first_topic: ChatTopic = ChatTopicClass.new()
	first_topic.topic_id = "queue_first"
	first_topic.channel_id = "shared_channel"
	first_topic.mode = ChatTopic.Mode.LOCAL
	first_topic.local_script = "friend: 第一段还没有结束。\nEND first"

	var second_topic: ChatTopic = ChatTopicClass.new()
	second_topic.topic_id = "queue_second"
	second_topic.channel_id = "shared_channel"
	second_topic.mode = ChatTopic.Mode.LLM
	second_topic.prompt = "生成第二段聊天。"

	_check(manager.activate_topic(first_topic, {}, ["friend"]), "first same-channel topic activates")
	_check(manager.activate_topic(second_topic, {}, ["friend"]), "second same-channel topic is accepted into the queue")
	_check(manager.get_active_topic("shared_channel") == first_topic, "queued topic does not replace the active topic")
	_check(not _generation_prompt.is_empty(), "queued LLM topic requests generation while the first topic is playing")
	_check(
		manager.submit_generated_topic_script(second_topic, "friend: 第二段开始。\nEND second"),
		"queued LLM result is cached against its topic"
	)
	_check(_messages.size() == 1, "generated queued topic does not display before the first END")

	manager.advance_topic("shared_channel")
	_check(manager.get_active_topic("shared_channel") == second_topic, "queued topic activates after the previous END")
	_check(_messages.size() == 2 and _messages[1].get("text") == "第二段开始。", "cached queued topic starts immediately after the first END")
	manager.advance_topic("shared_channel")
	_check(not manager.has_active_topic("shared_channel"), "same-channel queue drains after completion")
	manager.queue_free()


func _create_manager() -> TopicManager:
	var manager: TopicManager = TopicManagerScene.instantiate() as TopicManager
	manager.auto_request_llm = false
	add_child(manager)
	manager.topic_message_emitted.connect(_on_message)
	manager.topic_choices_presented.connect(_on_choices)
	manager.topic_completed.connect(_on_completed)
	manager.topic_generation_requested.connect(_on_generation_requested)
	return manager


func _reset_events() -> void:
	_messages.clear()
	_choices.clear()
	_completed_result.clear()
	_generation_prompt = ""


func _on_message(_topic: ChatTopic, speaker_id: String, text: String, is_player: bool, card: Dictionary) -> void:
	_messages.append({
		"speaker": speaker_id,
		"text": text,
		"is_player": is_player,
		"card": card.duplicate(true),
	})


func _on_choices(_topic: ChatTopic, choices: Array) -> void:
	_choices = choices.duplicate(true)


func _on_completed(_topic: ChatTopic, result: Dictionary) -> void:
	_completed_result = result.duplicate(true)


func _on_generation_requested(_topic: ChatTopic, resolved_prompt: String) -> void:
	_generation_prompt = resolved_prompt


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[OK] %s" % label)
		return
	_failures += 1
	push_error("[CHECK FAILED] %s" % label)
