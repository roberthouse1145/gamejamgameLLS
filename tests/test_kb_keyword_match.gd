extends Node
## 测试 ChatProjectContextBuilder 的 KB 关键词命中段
## 覆盖三种场景：命中单篇 / 未命中 / 命中超额（>3 篇）

const ChatProjectContextBuilderClass = preload("res://scripts/chat/chat_project_context_builder.gd")


func _ready() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var kb: Node = get_node_or_null("/root/KnowledgeBaseManager")
	if kb == null:
		print("[FAIL] KnowledgeBaseManager autoload not found")
		return

	var original_docs: Array = kb.documents.duplicate(true)
	kb.documents.clear()
	await get_tree().process_frame

	# 准备 5 篇文档：覆盖不同 doc_kind 用于优先级测试
	kb.upsert_document("char_yulian", "尤里安", "尤里安是塞拉菲娜学院王子，性格高傲，对平民有偏见。", "characters", ["主角", "王室"])
	kb.upsert_document("char_melu", "梅露", "梅露是平民出身的学院特招生，努力但自卑。", "characters", ["主角", "平民"])
	kb.upsert_document("world_academy", "塞拉菲娜王立魔法学院", "六大魔法属性体系，禁书库为剧情核心场景。", "world", ["世界观", "学院"])
	kb.upsert_document("story_main", "主线剧情大纲", "主角入学 → 揭秘禁书库 → 阶级冲突 → 双结局分支。", "story", ["主线"])
	kb.upsert_document("notes_open", "待确认问题", "梅露第一次施法的暴露程度未定。", "notes", ["待确认"])

	var builder := ChatProjectContextBuilderClass.new()

	_test_no_match(builder)
	_test_single_hit_by_title(builder)
	_test_single_hit_by_tag(builder)
	_test_min_key_length_filter(builder)
	_test_overflow_truncation(builder)

	# 还原 KB 状态
	kb.documents = original_docs.duplicate(true)
	print("[Test] KB keyword match tests done")


func _assert(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		print("[OK] %s" % label)
	else:
		push_error("[FAIL] %s :: %s" % [label, detail])


func _test_no_match(builder) -> void:
	# 玩家随口闲聊，与 KB 任何文档无关
	var output: String = builder.build_kb_context("我饿了，想吃火锅")
	_assert("无关消息不触发命中段",
		output.contains("项目设定索引") and not output.contains("当前对话相关条目"),
		output)


func _test_single_hit_by_title(builder) -> void:
	# 命中 title "尤里安"
	var output: String = builder.build_kb_context("尤里安今天怎么样了")
	_assert("title 包含匹配命中",
		output.contains("当前对话相关条目") \
		and output.contains("尤里安是塞拉菲娜学院王子"),
		output)


func _test_single_hit_by_tag(builder) -> void:
	# 命中 tag "世界观"
	var output: String = builder.build_kb_context("我们的世界观需要再讨论一下")
	_assert("tag 包含匹配命中",
		output.contains("当前对话相关条目") \
		and output.contains("六大魔法属性体系"),
		output)


func _test_min_key_length_filter(builder) -> void:
	# 添加一篇 title 为 "AI" 的文档（长度 2）以验证最小长度门槛仍接受 ≥2 字符的 title
	var kb: Node = get_node_or_null("/root/KnowledgeBaseManager")
	kb.upsert_document("test_ai_short", "AI", "AI placeholder doc.", "notes", [])
	# scan_text 含小写"ai"，应命中（contains 是小写比较）
	var output_hit: String = builder.build_kb_context("AI 这部分还要细化")
	_assert("≥2 字符 title 仍可命中",
		output_hit.contains("AI placeholder doc"),
		output_hit)
	kb.delete_document("test_ai_short")


func _test_overflow_truncation(builder) -> void:
	# 五个 tag 都设成 "主角" 让 4 篇命中，验证 KB_MAX_HITS=3 截断
	var kb: Node = get_node_or_null("/root/KnowledgeBaseManager")
	# 给原 5 篇之外再加 2 篇带"主角"tag 的文档
	kb.upsert_document("over_a", "Over A", "AAA content.", "characters", ["主角"])
	kb.upsert_document("over_b", "Over B", "BBB content.", "characters", ["主角"])

	# 现在带"主角" tag 的有：char_yulian, char_melu, over_a, over_b 共 4 篇
	# 命中段应只取前 3 篇（按 doc_kind=canonical 同级 → doc_id 字典序）
	var output: String = builder.build_kb_context("我们聊聊主角设定")
	# 字典序：char_melu < char_yulian < over_a < over_b
	# canonical 优先级最高，所有文档默认 canonical → 全部同级
	# 所以前 3 应是 char_melu / char_yulian / over_a，过滤掉 over_b
	_assert("命中数超额时按 KB_MAX_HITS=3 截断",
		output.contains("BBB content") == false \
		and output.contains("AAA content") \
		and output.contains("梅露是平民出身") \
		and output.contains("尤里安是塞拉菲娜学院王子"),
		output)

	# 清理
	kb.delete_document("over_a")
	kb.delete_document("over_b")
