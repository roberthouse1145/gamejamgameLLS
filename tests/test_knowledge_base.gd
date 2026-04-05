extends Node
## 测试 KnowledgeBaseManager 统一文档模型的 CRUD 和查询功能

func _ready() -> void:
	call_deferred("_run_test")

func _run_test() -> void:
	var kb: Node = get_node_or_null("/root/KnowledgeBaseManager")
	if kb == null:
		print("ERROR: KnowledgeBaseManager not found")
		return

	print("\n=== KnowledgeBase 统一文档模型 测试 ===\n")

	# 清空当前数据，确保干净环境
	kb.documents.clear()

	var pass_count := 0
	var fail_count := 0

	# --- Test 1: upsert_document 创建新文档 ---
	kb.upsert_document("char_001", "少女 Miku", "活泼的 17 岁少女。", "characters", ["主角"], "player")
	var doc = kb.get_document("char_001")
	if doc.get("title") == "少女 Miku" and doc.get("category") == "characters":
		print("PASS: Test1 - upsert 创建新文档")
		pass_count += 1
	else:
		print("FAIL: Test1 - upsert 创建新文档: %s" % str(doc))
		fail_count += 1

	# --- Test 2: upsert_document 更新已有文档 ---
	kb.upsert_document("char_001", "少女 Miku (改)", "活泼的 18 岁少女。性格开朗。", "characters", ["主角", "女主"])
	doc = kb.get_document("char_001")
	if doc.get("title") == "少女 Miku (改)" and doc.get("content") == "活泼的 18 岁少女。性格开朗。":
		print("PASS: Test2 - upsert 更新已有文档")
		pass_count += 1
	else:
		print("FAIL: Test2 - upsert 更新已有文档: %s" % str(doc))
		fail_count += 1

	# --- Test 3: tags 被更新 ---
	var tags: Array = doc.get("tags", [])
	if "女主" in tags and "主角" in tags:
		print("PASS: Test3 - tags 被正确更新")
		pass_count += 1
	else:
		print("FAIL: Test3 - tags 更新异常: %s" % str(tags))
		fail_count += 1

	# --- Test 4: get_document 查找不存在的 ID ---
	var empty = kb.get_document("nonexistent_999")
	if empty.is_empty():
		print("PASS: Test4 - get_document 不存在返回空 Dict")
		pass_count += 1
	else:
		print("FAIL: Test4 - get_document 应返回空: %s" % str(empty))
		fail_count += 1

	# --- Test 5: 添加更多文档用于查询测试 ---
	kb.upsert_document("world_001", "世界观概述", "未来 2077 年的赛博世界。", "world", ["设定"])
	kb.upsert_document("story_001", "第一章：相遇", "两人在比赛现场初次见面。", "story", ["第一章", "相遇"])
	kb.upsert_document("char_002", "男主 Ren", "沉默寡言的程序员。", "characters", ["主角", "男主"])
	kb.upsert_document("notes_001", "待办事项", "- 完善 Miku 立绘\n- 修改第一章节奏", "notes")

	# --- Test 5a: get_documents 无过滤 → 返回全部 ---
	var all_docs = kb.get_documents()
	if all_docs.size() == 5:
		print("PASS: Test5a - get_documents 无过滤返回全部 (5)")
		pass_count += 1
	else:
		print("FAIL: Test5a - 应为 5 篇，实际 %d" % all_docs.size())
		fail_count += 1

	# --- Test 5b: get_documents 按 category 过滤 ---
	var char_docs = kb.get_documents("characters")
	if char_docs.size() == 2:
		print("PASS: Test5b - category=characters 返回 2 篇")
		pass_count += 1
	else:
		print("FAIL: Test5b - characters 应为 2，实际 %d" % char_docs.size())
		fail_count += 1

	# --- Test 5c: get_documents 按 tags 过滤 ---
	var protagonist_docs = kb.get_documents("", ["主角"])
	if protagonist_docs.size() == 2:
		print("PASS: Test5c - tag=主角 返回 2 篇")
		pass_count += 1
	else:
		print("FAIL: Test5c - tag=主角 应为 2，实际 %d" % protagonist_docs.size())
		fail_count += 1

	# --- Test 5d: get_documents category + tag 组合过滤 ---
	var female_lead = kb.get_documents("characters", ["女主"])
	if female_lead.size() == 1 and female_lead[0].get("doc_id") == "char_001":
		print("PASS: Test5d - category=characters + tag=女主 返回 1 篇")
		pass_count += 1
	else:
		print("FAIL: Test5d - 组合过滤异常: %s" % str(female_lead))
		fail_count += 1

	# --- Test 6: delete_document ---
	var deleted = kb.delete_document("notes_001")
	var after_del = kb.get_document("notes_001")
	if deleted and after_del.is_empty():
		print("PASS: Test6 - delete_document 成功")
		pass_count += 1
	else:
		print("FAIL: Test6 - delete_document 异常: deleted=%s, after=%s" % [str(deleted), str(after_del)])
		fail_count += 1

	# --- Test 7: delete 不存在的文档 ---
	var del_missing = kb.delete_document("nonexistent_999")
	if not del_missing:
		print("PASS: Test7 - delete 不存在文档返回 false")
		pass_count += 1
	else:
		print("FAIL: Test7 - 应返回 false")
		fail_count += 1

	# --- Test 8: generate_doc_id ---
	var id1 = kb.generate_doc_id("characters")
	var id2 = kb.generate_doc_id("characters")
	if id1.begins_with("characters_") and id1 != id2:
		print("PASS: Test8 - generate_doc_id 前缀正确且唯一")
		pass_count += 1
	else:
		print("FAIL: Test8 - generate_doc_id 异常: %s, %s" % [id1, id2])
		fail_count += 1

	# --- Test 9: get_categories ---
	var cats = kb.get_categories()
	if "world" in cats and "characters" in cats and "story" in cats and "notes" not in cats:
		print("PASS: Test9 - get_categories 正确 (notes 已删除)")
		pass_count += 1
	else:
		print("FAIL: Test9 - get_categories 异常: %s" % str(cats))
		fail_count += 1

	# --- Test 10: _migrate_legacy ---
	kb.documents.clear()
	var legacy_data := {
		"game_title": "旧标题",
		"synopsis": "旧简介内容",
		"characters": [
			{"name": "角色A", "description": "描述A"},
			{"name": "角色B", "description": "描述B"},
		],
		"beats": [
			{"beat_id": "b1", "title": "节拍1", "content": "内容1"},
			{"beat_id": "b2", "title": "节拍2", "content": "内容2"},
		],
	}
	kb._migrate_legacy(legacy_data)
	var migrated_all = kb.get_documents()
	# 期望：1 world + 2 characters + 2 story = 5
	if migrated_all.size() == 5:
		print("PASS: Test10a - _migrate_legacy 总数 5 篇")
		pass_count += 1
	else:
		print("FAIL: Test10a - 迁移后应为 5，实际 %d" % migrated_all.size())
		fail_count += 1

	var migrated_world = kb.get_documents("world")
	if migrated_world.size() == 1 and migrated_world[0].get("title") == "旧标题":
		print("PASS: Test10b - world 迁移正确")
		pass_count += 1
	else:
		print("FAIL: Test10b - world 迁移异常: %s" % str(migrated_world))
		fail_count += 1

	var migrated_chars = kb.get_documents("characters")
	if migrated_chars.size() == 2:
		print("PASS: Test10c - characters 迁移正确 (2篇)")
		pass_count += 1
	else:
		print("FAIL: Test10c - characters 迁移异常: %d" % migrated_chars.size())
		fail_count += 1

	var migrated_story = kb.get_documents("story")
	if migrated_story.size() == 2:
		print("PASS: Test10d - story 迁移正确 (2篇)")
		pass_count += 1
	else:
		print("FAIL: Test10d - story 迁移异常: %d" % migrated_story.size())
		fail_count += 1

	# --- 汇总 ---
	print("\n=== 测试结果: %d PASS / %d FAIL ===" % [pass_count, fail_count])
	if fail_count == 0:
		print("ALL TESTS PASSED!")
	else:
		print("SOME TESTS FAILED!")
