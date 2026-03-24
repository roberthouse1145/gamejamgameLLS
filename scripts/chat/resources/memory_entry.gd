class_name MemoryEntry extends Resource
## 记忆条目资源
## 存储NPC对玩家的记忆

enum MemoryType {
	EPISODIC,   ## 事件记忆：具体发生的事情
	SEMANTIC,   ## 语义记忆：抽象知识/偏好
	EMOTIONAL,  ## 情感记忆：情感关联强的事件
}

## 记忆唯一标识
@export var memory_id: String = ""

## 所属NPC
@export var npc_id: String = ""

## 记忆类型
@export var memory_type: MemoryType = MemoryType.EPISODIC

## 时间戳
@export var timestamp: int = 0

## 记忆内容
@export_multiline var content: String = ""

## 标签（用于检索）
@export var tags: Array[String] = []

## 相关实体
@export var related_entities: Array[String] = []

## 重要性（0-1）
@export_range(0.0, 1.0) var importance: float = 0.5

## 情感倾向（-1到1，负面到正面）
@export_range(-1.0, 1.0) var emotional_valence: float = 0.0

## 被访问次数
@export var access_count: int = 0

## 最后访问时间
@export var last_access_time: int = 0

## 来源频道ID
@export var source_channel_id: String = ""

## 来源Topic ID
@export var source_topic_id: String = ""

## 来源类型
@export var source_type: String = ""


## 计算记忆强度（随时间衰减）
func get_memory_strength() -> float:
	var time_decay := _calculate_time_decay()
	var access_boost := minf(access_count * 0.1, 0.5)
	return clampf(importance * time_decay + access_boost, 0.0, 1.0)


func _calculate_time_decay() -> float:
	var days_passed := float(Time.get_unix_time_from_system() - timestamp) / 86400.0
	var decay_rate := 0.1 * (1.0 - importance)
	return exp(-decay_rate * days_passed)
