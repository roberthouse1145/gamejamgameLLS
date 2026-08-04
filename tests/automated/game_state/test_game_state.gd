extends Node
## GameState 契约测试：属性 clamp、阈值信号、关系读写、粉丝向量归一化、序列化往返。
## 运行方式：运行本场景后观察输出；不自动退出，由用户手动关闭或 stop_project 停止。

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_attribute_clamp()
	_test_threshold_signal()
	_test_relationship()
	_test_fan_vector_normalize()
	_test_fans_signal()
	_test_serialization_roundtrip()
	print("[TestGameState] 结果: %d 通过, %d 失败" % [_passed, _failed])


func _check(condition: bool, test_name: String) -> void:
	if condition:
		_passed += 1
		print("[TestGameState] PASS: " + test_name)
	else:
		_failed += 1
		push_error("[TestGameState] FAIL: " + test_name)


func _test_attribute_clamp() -> void:
	GameState.set_attribute(GameState.ATTR_STRESS, 150)
	_check(GameState.stress == 100, "属性上限 clamp 到 100")
	GameState.set_attribute(GameState.ATTR_STRESS, -20)
	_check(GameState.stress == 0, "属性下限 clamp 到 0")
	GameState.adjust_attribute(GameState.ATTR_OTAKU_DESIRE, 30)
	GameState.adjust_attribute(GameState.ATTR_OTAKU_DESIRE, 15)
	_check(GameState.otaku_desire == 45, "adjust_attribute 累加")


func _test_threshold_signal() -> void:
	var events: Array = []
	var callback := func(attr_name: String, threshold: int, crossed_up: bool) -> void:
		events.append([attr_name, threshold, crossed_up])
	GameState.attribute_threshold_crossed.connect(callback)

	GameState.set_attribute(GameState.ATTR_STRESS, 59)
	_check(events.is_empty(), "未达阈值不发信号")
	GameState.set_attribute(GameState.ATTR_STRESS, 60)
	_check(events.size() == 1 and events[0] == [GameState.ATTR_STRESS, 60, true], "上跨 60 发信号")
	GameState.set_attribute(GameState.ATTR_STRESS, 65)
	_check(events.size() == 1, "阈值之间移动不重复发信号")
	GameState.set_attribute(GameState.ATTR_STRESS, 85)
	_check(events.size() == 2 and events[1] == [GameState.ATTR_STRESS, 80, true], "上跨 80 发信号")
	GameState.set_attribute(GameState.ATTR_STRESS, 70)
	_check(events.size() == 3 and events[2] == [GameState.ATTR_STRESS, 80, false], "回落跨 80 发信号")

	GameState.attribute_threshold_crossed.disconnect(callback)
	GameState.set_attribute(GameState.ATTR_STRESS, 0)


func _test_relationship() -> void:
	var character: StreamerCharacter = load("res://resources/characters/lu_yuanyuan.tres")
	_check(character != null and character.character_key == "lu_yuanyuan", "角色资源可加载")
	_check(character.role == StreamerCharacter.ROLE_CHILDHOOD_FRIEND
		and character.address_to_heroine == "柚柚"
		and not character.persona_prompt.is_empty(), "角色字段完整")

	var named_fan: StreamerCharacter = load("res://resources/characters/lu_ling.tres")
	_check(named_fan != null and named_fan.is_named_fan, "鹿铃具名例外标记")

	GameState.init_relationship(character)
	_check(GameState.get_relationship("lu_yuanyuan") == {"favor": 0, "trust": 0, "dependence": 0}, "关系建档初值")
	GameState.change_relationship("lu_yuanyuan", 5, 3)
	_check(GameState.get_relationship("lu_yuanyuan") == {"favor": 5, "trust": 3, "dependence": 0}, "关系增减")


func _test_fan_vector_normalize() -> void:
	GameState.set_fan_vector({"r": 30.0, "m": 10.0, "w": 10.0})
	var total: float = 0.0
	for key: String in GameState.FAN_VECTOR_KEYS:
		total += GameState.fan_vector[key]
	_check(absf(total - 100.0) < 0.001, "粉丝向量归一化到 100")
	_check(absf(GameState.fan_vector["r"] - 60.0) < 0.001, "粉丝向量按比例分配")
	_check(GameState.fan_vector["b"] == 0.0, "缺失键补 0")


func _test_fans_signal() -> void:
	var events: Array = []
	var callback := func(value: int) -> void:
		events.append(value)
	GameState.fans_changed.connect(callback)
	GameState.set_fans(100)
	GameState.set_fans(100)
	_check(events == [100], "set_fans 仅变化时发信号")
	GameState.set_fans(-5)
	_check(events == [100, 0], "set_fans 下限 clamp 到 0")
	GameState.fans_changed.disconnect(callback)


func _test_serialization_roundtrip() -> void:
	GameState.set_attribute(GameState.ATTR_LONELINESS, 42)
	GameState.add_money(880)
	GameState.set_fans(12458)
	GameState.streamer_name = "柚柚子"
	GameState.flame_value = 12.5
	GameState.contract = {"debt": 500000, "period_results": [true, false]}

	var snapshot: Dictionary = GameState.to_dict()
	GameState.set_attribute(GameState.ATTR_LONELINESS, 0)
	GameState.add_money(-880)
	GameState.set_fans(0)
	GameState.streamer_name = ""
	GameState.from_dict(snapshot)

	_check(GameState.loneliness == 42 and GameState.money == 880
		and GameState.fans == 12458
		and GameState.streamer_name == "柚柚子"
		and GameState.contract["debt"] == 500000, "序列化往返还原数值")
	_check(JSON.stringify(GameState.to_dict()) == JSON.stringify(snapshot), "序列化往返一致")
