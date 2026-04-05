@tool
extends EditorScript

const StoryCompilerClass = preload("res://scripts/story/story_compiler.gd")
const StoryChapterIndexClass = preload("res://scripts/story/resources/story_chapter_index.gd")


func _run() -> void:
	var index_resource: Resource = StoryCompilerClass.compile_all()
	if index_resource == null or not (index_resource is StoryChapterIndexClass):
		push_error("[StoryRebuild] Failed to rebuild story cache")
		return

	print("[StoryRebuild] Rebuilt story cache: %d chapters" % index_resource.chapters.size())