class_name SbeamGameList
extends ItemList


func _get_tooltip(_at_position: Vector2) -> String:
	# Sbeam uses the custom activity preview layer; disable ItemList's built-in tooltip.
	return ""
