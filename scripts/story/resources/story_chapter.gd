class_name StoryChapter extends Resource
## 剧本章节资源
## 一个章节包含一组有序的 StoryStep，代表一段连续的叙事流程（如"第一天"）

const StoryStepClass = preload("res://scripts/story/resources/story_step.gd")

## 章节唯一 ID（如 "day1"）
@export var chapter_id: String = ""

## 章节显示名称
@export var chapter_name: String = ""

## 章节描述
@export var description: String = ""

## 自动触发配置（空 = 仅支持手动/链式启动）
@export var trigger: Dictionary = {}

## 触发优先级（值越大越先触发）
@export var priority: int = 0

## 步骤列表（Array of StoryStep）
@export var steps: Array[Resource] = []

## 章节完成后的下一个章节 ID（空 = 无后续）
@export var next_chapter: String = ""


## 按 step_id 查找步骤
func get_step(step_id: String) -> Resource:
	for step in steps:
		if step is StoryStepClass and step.step_id == step_id:
			return step
	return null


## 获取第一个步骤
func get_first_step() -> Resource:
	if steps.is_empty():
		return null
	return steps[0]


## 获取所有 step_id
func get_step_ids() -> Array[String]:
	var ids: Array[String] = []
	for step in steps:
		if step is StoryStepClass:
			ids.append(step.step_id)
	return ids


func has_trigger() -> bool:
	return not trigger.is_empty()
