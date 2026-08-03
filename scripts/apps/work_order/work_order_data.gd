class_name WorkOrderData extends Resource
## 工单数据结构
## 描述一个工单的完整信息，包括标题、描述、Spec、状态等

## 工单状态枚举
enum Status {
	DRAFT, ## 草稿，刚创建
	PENDING_SPEC, ## 等待AI生成Spec
	READY, ## Spec已生成，等待发送
	IN_PROGRESS, ## 正在执行
	NEEDS_INPUT, ## 需要玩家输入（需求澄清）
	COMPLETED, ## 已完成
	FAILED ## 失败
}

## 工单唯一ID
@export var id: String = ""

## 工单标题
@export var title: String = ""

## 玩家原始需求描述
@export_multiline var description: String = ""

## 指派的NPC ID
@export var assignee_npc_id: String = ""

## 优先级 (1=低, 2=中, 3=高)
@export_range(1, 3) var priority: int = 2

## 工单状态（旧字段，向后兼容，优先使用 surface_status）
@export var status: String = "draft"

## ===== 双层状态系统 =====

## 表层状态 (玩家可见): pending / in_progress / completed
@export var surface_status: String = "pending"

## 表层进度: 当前投入的 AP
@export var current_progress_ap: int = 0

## 表层要求: 需要投入的总 AP (根据工作量评估)
@export var required_ap: int = 3

## 里层状态 (LLM 后台): generating / ready
@export var inner_status: String = "idle"

## 关联的 LLM KB 快照 ID 列表 (例如定稿的角色 ID 或剧情 ID)
@export var linked_llm_kb_ids: Array[String] = []

## 派发当天的天数 (用于追踪)
@export var dispatch_day: int = 0

## 老字段：Spec内容（可以废弃，因为我们现在直接从 LLM KB 读）
@export var spec: Dictionary = {
	"requirements_text": "",
	"design_text": "",
	"tasks": [] # Array[{description: String, done: bool}]
}

## 父工单ID（用于子任务）
@export var parent_order_id: String = ""

## 子工单ID列表
@export var children_order_ids: Array[String] = []

## 创建时间戳
@export var created_at: int = 0

## 更新时间戳
@export var updated_at: int = 0


## 从Dictionary创建WorkOrderData
static func from_dict(data: Dictionary) -> Resource:
	var script := load("res://scripts/apps/work_order/work_order_data.gd")
	var order: Resource = script.new()
	order.id = data.get("id", "")
	order.title = data.get("title", "")
	order.description = data.get("description", "")
	order.assignee_npc_id = data.get("assignee_npc_id", "")
	order.priority = data.get("priority", 2)
	order.status = data.get("status", "draft")
	# 双层状态：向后兼容 — 如果没有 surface_status 则从 status 迁移
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
	order.created_at = data.get("created_at", 0)
	order.updated_at = data.get("updated_at", 0)
	return order


## 转换为Dictionary（用于JSON序列化）
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
		"created_at": created_at,
		"updated_at": updated_at
	}


## 获取状态的中文显示名称（优先读取 surface_status）
func get_status_display_name() -> String:
	var s: String = surface_status if not surface_status.is_empty() else status
	match s:
		"pending": return "待开发"
		"in_progress":
			if current_progress_ap < required_ap:
				return "制作中 (%d/%d AP)" % [current_progress_ap, required_ap]
			return "进行中"
		"needs_input": return "待确认"
		"completed": return "已完成"
		"failed": return "失败"
		_: return s


## 获取状态颜色（优先读取 surface_status）
func get_status_color() -> Color:
	var s: String = surface_status if not surface_status.is_empty() else status
	match s:
		"pending": return Color(0.9, 0.7, 0.2) # 黄色
		"in_progress": return Color(0.2, 0.8, 0.4) # 绿色
		"needs_input": return Color(0.9, 0.5, 0.2) # 橙色
		"completed": return Color(0.4, 0.8, 0.4) # 浅绿
		"failed": return Color(0.9, 0.3, 0.3) # 红色
		_: return Color.WHITE


## 检查Spec是否已填写
func has_spec() -> bool:
	if spec.is_empty():
		return false
	var req: String = spec.get("requirements_text", "")
	var tasks: Array = spec.get("tasks", [])
	return not req.is_empty() or tasks.size() > 0


## 获取任务完成进度 (0.0 - 1.0)
func get_task_progress() -> float:
	var tasks: Array = spec.get("tasks", [])
	if tasks.is_empty():
		return 0.0
	var done_count: int = 0
	for task in tasks:
		if task is Dictionary and task.get("done", false):
			done_count += 1
	return float(done_count) / float(tasks.size())
