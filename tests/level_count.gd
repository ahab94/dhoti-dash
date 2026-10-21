extends SceneTree
## Prints how many races there are, for checks/autoplay.sh.
func _initialize() -> void:
	print("LEVELS ", load("res://scripts/races.gd").count())
	quit(0)
