extends SceneTree
func _init():
    var gm = preload("res://autoload/game_manager.gd").new()
    gm._ready()
    print("Initial money: ", gm.money)
    gm.modify_stat("money", -38)
    print("Money after modify_stat("money", -38): ", gm.money)
    quit()
