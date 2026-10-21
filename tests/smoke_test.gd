extends SceneTree
## Loads the main scene, then starts and renders every race for a moment.
##   godot --headless --path . --script res://tests/smoke_test.gd

func _initialize() -> void:
	var game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	game.save_enabled = false
	root.add_child(game)
	_run.call_deferred(game)


func _run(game) -> void:
	await process_frame
	var races = load("res://scripts/races.gd")
	for i in races.count():
		game.start_race(i)
		for f in 5:
			await physics_frame
		await process_frame
	# Phone play: with touch mode on, Chacha pedals by himself.
	game.start_race(0)
	game._touch_mode = true
	for f in 300:
		await physics_frame
	if game.race.player.z < 1000.0:
		print("FAIL: touch mode should pedal automatically (z=%.0f)" % game.race.player.z)
		quit(1)
		return
	game.show_menu()
	await process_frame
	print("SMOKE OK")
	quit(0)
