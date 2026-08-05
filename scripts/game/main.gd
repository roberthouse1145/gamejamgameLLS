class_name Main extends Control
## 游戏唯一入口：创建桌面、连接剧情动作，并启动场景配置的开场章节。

const DesktopScene: PackedScene = preload("res://scenes/pseudo_os/desktop.tscn")
const GameStoryActionsClass = preload("res://scripts/story/game_story_actions.gd")

@export var opening_chapter_id: String = ""


func _ready() -> void:
	var desktop: Control = DesktopScene.instantiate()
	desktop.name = "Desktop"
	add_child(desktop)

	var story_actions: Node = GameStoryActionsClass.new()
	story_actions.name = "GameStoryActions"
	add_child(story_actions)
	call_deferred("_start_opening_chapter")


func _start_opening_chapter() -> void:
	var director: Node = get_node_or_null("/root/StoryDirector")
	if director == null or opening_chapter_id.is_empty() or director.has_active_story():
		return
	if director.completed_chapters.has(opening_chapter_id):
		return
	if director.get_chapter(opening_chapter_id) != null:
		director.start_chapter(opening_chapter_id)
