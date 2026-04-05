class_name WorkOrderData extends Resource
## 工单数据结构

enum Status {
	DRAFT, ## 草稿，刚创建
	PENDING_SPEC, ## 等待 AI 生成 Spec
	READY, ## Spec 已生成，等待发送
	IN_PROGRESS, ## 正在执行
	NEEDS_INPUT, ## 需要玩家输入（需求澄清）
	AWAITING_PLAYER, ## 等待玩家参与创意讨论
	MILESTONE_READY, ## 阶段成果就绪，待展示
	DELIVERED, ## 成果已展示给玩家
	COMPLETED, ## 已完成
	FAILED ## 失败
}

## 工单唯一 ID
@export var id: String = ""

## 工单标题
@export var title: String = ""

## 玩家原始需求描述
@export_multiline var description: String = ""

## 指派的 NPC ID
@export var assignee_npc_id: String = ""

## 优先级 (1=低 2=中 3=高)
@export_range(1, 3) var priority: int = 2

## 工单状态（旧字段，向后兼容，优先使用 surface_status）
@export var status: String = "draft"

## ===== 双层状态系统 =====

## 表层状态（玩家可见）
@export var surface_status: String = "pending"

## 表层进度：当前投入的 AP
@export var current_progress_ap: int = 0

## 表层要求：需要投入的总 AP
@export var required_ap: int = 3

## 里层状态（LLM 后台）
## idle / generating / awaiting_clarification / awaiting_discussion / milestone_ready / ready
@export var inner_status: String = "idle"

## 关联的 LLM KB 快照 ID 列表
@export var linked_llm_kb_ids: Array[String] = []

## 派发当天的天数（用于追踪）
@export var dispatch_day: int = 0

## 老字段：Spec 内容（向后兼容）
@export var spec: Dictionary = {
	"requirements_text": "",
	"design_text": "",
	"tasks": []
}

## 父工单 ID（用于子任务）
@export var parent_order_id: String = ""

## 子工单 ID 列表
@export var children_order_ids: Array[String] = []

## 来源追踪：触发此工单的来源类型
@export var source_type: String = ""

## 来源追踪：来源对象 ID
@export var source_id: String = ""

## 等待澄清时持久化保存的问题列表，便于重载后重建话题
@export var pending_questions: Array[String] = []

## 创建时间戳
@export var created_at: int = 0

## 更新时间戳
@export var updated_at: int = 0


static func from_dict(data: Dictionary) -> Resource:
	var script := load("res://scripts/apps/work_order/work_order_data.gd")
	var order: Resource = script.new()
	order.id = data.get("id", "")
	order.title = data.get("title", "")
	order.description = data.get("description", "")
	order.assignee_npc_id = data.get("assignee_npc_id", "")
	order.priority = data.get("priority", 2)
	order.status = data.get("status", "draft")
	order.surface_status = data.get("surface_status", data.get("status", "pending"))
	order.current_progress_ap = data.get("current_progress_ap", 0)
	order.required_ap = data.get("required_ap", 3)
	order.inner_status = data.get("inner_status", "idle")

	var linked_ids: Array = data.get("linked_llm_kb_ids", [])
	order.linked_llm_kb_ids.assign(linked_ids)

	order.dispatch_day = data.get("dispatch_day", 0)
	order.spec = data.get("spec", {"requirements_text": "", "design_text": "", "tasks": []})
	order.parent_order_id = data.get("parent_order_id", "")

	var children: Array = data.get("children_order_ids", [])
	order.children_order_ids.assign(children)

	order.source_type = data.get("source_type", "")
	order.source_id = data.get("source_id", "")

	var pending: Array = data.get("pending_questions", [])
	order.pending_questions.assign(pending)

	order.created_at = data.get("created_at", 0)
	order.updated_at = data.get("updated_at", 0)
	return order


func to_dict() -> Dictionary:
	return {
		"id": id,
		"title": title,
		"description": description,
		"assignee_npc_id": assignee_npc_id,
		"priority": priority,
		"status": status,
		"surface_status": surface_status,
		"current_progress_ap": current_progress_ap,
		"required_ap": required_ap,
		"inner_status": inner_status,
		"linked_llm_kb_ids": linked_llm_kb_ids,
		"dispatch_day": dispatch_day,
		"spec": spec,
		"parent_order_id": parent_order_id,
		"children_order_ids": children_order_ids,
		"source_type": source_type,
		"source_id": source_id,
		"pending_questions": pending_questions,
		"created_at": created_at,
		"updated_at": updated_at,
	}


func get_status_display_name() -> String:
	var s: String = surface_status if not surface_status.is_empty() else status
	match s:
		"pending":
			return "待开发"
		"in_progress":
			if current_progress_ap < required_ap:
				return "制作中 (%d/%d AP)" % [current_progress_ap, required_ap]
			return "进行中"
		"needs_input":
			return "待确认"
		"awaiting_player":
			return "等待讨论"
		"milestone_ready":
			return "可预览"
		"delivered":
			return "已展示"
		"completed":
			return "已完成"
		"failed":
			return "失败"
		_:
			return s


func get_status_color() -> Color:
	var s: String = surface_status if not surface_status.is_empty() else status
	match s:
		"pending":
			return Color(0.9, 0.7, 0.2)
		"in_progress":
			return Color(0.2, 0.8, 0.4)
		"needs_input":
			return Color(0.9, 0.5, 0.2)
		"awaiting_player":
			return Color(0.8, 0.5, 0.9)
		"milestone_ready":
			return Color(0.3, 0.7, 0.9)
		"delivered":
			return Color(0.5, 0.8, 0.6)
		"completed":
			return Color(0.4, 0.8, 0.4)
		"failed":
			return Color(0.9, 0.3, 0.3)
		_:
			return Color.WHITE


func has_spec() -> bool:
	if spec.is_empty():
		return false
	var req: String = spec.get("requirements_text", "")
	var tasks: Array = spec.get("tasks", [])
	return not req.is_empty() or tasks.size() > 0


func get_task_progress() -> float:
	var tasks: Array = spec.get("tasks", [])
	if tasks.is_empty():
		return 0.0
	var done_count: int = 0
	for task in tasks:
		if task is Dictionary and task.get("done", false):
			done_count += 1
	return float(done_count) / float(tasks.size())
