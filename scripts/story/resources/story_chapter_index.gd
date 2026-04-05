class_name StoryChapterIndex extends Resource
## 编译后的章节索引资源
## 通过显式 Resource 引用把所有章节纳入导出依赖链，避免导出版依赖目录遍历或字符串路径猜测

const StoryChapterClass = preload("res://scripts/story/resources/story_chapter.gd")

@export var chapters: Array[Resource] = []
@export var chapter_sources: Dictionary = {}
@export var compiled_paths: Dictionary = {}


func get_chapter_ids() -> Array[String]:
	var ids: Array[String] = []
	for chapter in chapters:
		if chapter is StoryChapterClass and not chapter.chapter_id.is_empty():
			ids.append(chapter.chapter_id)
	return ids


func get_chapter(chapter_id: String) -> Resource:
	for chapter in chapters:
		if chapter is StoryChapterClass and chapter.chapter_id == chapter_id:
			return chapter
	return null