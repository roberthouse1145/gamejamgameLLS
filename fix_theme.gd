@tool
extends EditorScript

func _run():
var proj_file = "res://project.godot"

# Can't easily use engine to write project settings from EditorScript reliably in a quick way,
var project = ConfigFile.new()
if project.load("res://project.godot") != OK:
print("Failed to load project.godot")
return

project.set_value("gui", "theme/custom_font", "res://Assets/fonts/宅在家自動筆.ttf")
project.set_value("gui", "theme/custom", "res://resources/themes/global_theme.tres")

project.save("res://project.godot")
print("Updated project.godot")

