extends Node

func _ready() -> void:
	print("\n=== Activity Block Protocol 测试 ===\n")
	_test_block_parser()
	_test_part_time_protocol()
	_test_date_event_protocol()
	print("\n=== Activity Block Protocol 测试完成 ===\n")


func _test_block_parser() -> void:
	print("[Test] ActivityBlockParser.parse_blocks")
	var text := """
[JOB]
job_id=test_job
reward_money=120
valid=true
phases=MORNING|NIGHT
[/JOB]
"""
	var blocks := ActivityBlockParser.parse_blocks(text, "JOB")
	_assert("解析出 1 个 JOB 块", blocks.size() == 1)
	_assert("reward_money 自动转 int", int(blocks[0].get("reward_money", 0)) == 120)
	_assert("valid 自动转 bool", bool(blocks[0].get("valid", false)) == true)
	_assert("phases 自动转数组", (blocks[0].get("phases", []) as Array).size() == 2)


func _test_part_time_protocol() -> void:
	print("[Test] Part Time 协议解析")
	var text := """
[JOB]
job_id=night_cafe_shift
job_title=深夜咖啡店打烊助手
company_name=街角慢冲
district=商业街后巷
reward_money=135
subtitle=安静夜班 / 双人收尾
description=打烊前需要一起清点豆子、擦吧台、搬回门口的小黑板。两个人分工会更顺，也更像一起撑过一段夜班。
zone_path=res://resources/maps/zone_commercial.tres
accent_color=#22C55E
detail_prompt=店里只剩磨豆机余热和晚间爵士乐，空气里有咖啡和洗洁精混在一起的味道。你和林夏一边收尾一边对当天的客人碎碎念。
[/JOB]
"""
	var catalog := ActivityCatalogProtocol.parse_part_time_catalog(text, 3, 2)
	_assert("解析出 1 个兼职岗位", catalog.size() == 1)
	if catalog.is_empty():
		return
	var job: Dictionary = catalog[0]
	_assert("job_id 正确", str(job.get("job_id", "")) == "night_cafe_shift")
	_assert("reward 写入 rewards.money", int((job.get("rewards", {}) as Dictionary).get("money", 0)) == 135)
	_assert("enabled=true", bool(job.get("enabled", false)) == true)
	_assert("source_type=llm_block", str(job.get("source_type", "")) == "llm_block")


func _test_date_event_protocol() -> void:
	print("[Test] Date Event 协议解析")
	var text := """
[DATE_EVENT]
event_id=day9_harbor_noodle
title=港口夜面摊
location_title=旧港区
location_id=harbor
subtitle=夜风很凉，汤面很热
description=旧港区今晚临时多摆了一家只卖到午夜的面摊。排队的人不多，适合慢慢等，也适合边吃边看海。
detail_prompt=海边步道有点潮，灯光从防波堤一路打到小摊车的铝锅上。煮面声和远处船声混在一起，气氛安静但不冷。
activity_hint=一起排队吃面，聊聊最近压力和毕业前想做的事
valid_phases=NIGHT
map_position=0.8|0.7
accent_color=#5B9BD5
reward_affection=2
reward_stress=-18
reward_passion=2
[/DATE_EVENT]
"""
	var events := ActivityCatalogProtocol.parse_date_events(text, 9, 4)
	_assert("解析出 1 个约会事件", events.size() == 1)
	if events.is_empty():
		return
	var event_data: Dictionary = events[0]
	_assert("location_id 正确", str(event_data.get("location_id", "")) == "harbor")
	_assert("valid_phases 解析正确", (event_data.get("valid_phases", []) as Array).has("NIGHT"))
	var rewards: Dictionary = event_data.get("rewards", {}) as Dictionary
	_assert("reward_affection 不进入主奖励", not rewards.has("affection"))
	_assert("reward_stress 已写入 rewards", int(rewards.get("stress", 0)) == -18)
	_assert("map_position 是 Vector2", event_data.get("map_position", null) is Vector2)


func _assert(desc: String, condition: bool) -> void:
	if condition:
		print("  [OK] %s" % desc)
	else:
		print("  [FAIL] %s" % desc)
