extends Node2D
## Dhoti Dash. This script owns the current race, feeds it input (keys,
## touch or the autopilot), shows the results, and keeps the menu, saves and
## dev flags. The race rules live in race.gd, the drawing in renderer.gd.
##
## Dev flags go after `--`, e.g.
##   godot --path . -- --level=2 --autopilot --exit-on-end
## See CLAUDE.md for the full list.

const Races := preload("res://scripts/races.gd")
const Race := preload("res://scripts/race.gd")
const Renderer := preload("res://scripts/renderer.gd")
const Autopilot := preload("res://scripts/autopilot.gd")
const Hud := preload("res://scripts/hud.gd")
const Sound := preload("res://scripts/sound.gd")

const SAVE_PATH := "user://progress.cfg"
const RESULT_DELAY := 2.0     # let the finish (or the fall) play out first
const PRIZES := [500, 300, 150]
const KO_BONUS := 50

enum State { MENU, RACING, RESULT }

var state := State.MENU
var race_index := 0
var race
var renderer
var hud
var bot
var save_enabled := true
var best_pos := {}            # race index -> best finishing place
var best_times := {}
var money := 0
var sound
var _end_timer := 0.0
var _heard := 0               # race events already turned into sounds
var _last_t := -99.0
# Game feel, counted in drawn frames so it also works in recordings:
var _hitstop_frames := 0      # a near-freeze that sells a solid hit
var _slowmo_frames := 0       # slow motion for knockouts and crashes
var _sim_time := 0.0
var _flags := {}


func _ready() -> void:
	# Pick the layout size from the window's shape: a portrait phone gets a
	# 720x1280 canvas (instead of a squashed 1280x720), so text stays readable.
	get_tree().root.size_changed.connect(_fit_layout)
	_fit_layout()
	_setup_input()
	_parse_flags()
	_load_progress()
	renderer = Renderer.new()
	add_child(renderer)
	sound = Sound.new()
	sound.music_on = not _flags.has("no-music")
	add_child(sound)
	var hud_layer := CanvasLayer.new()
	hud_layer.layer = 10
	add_child(hud_layer)
	hud = Hud.new()
	hud.show_touch = DisplayServer.is_touchscreen_available() or _flags.has("touch")
	_touch_mode = hud.show_touch
	hud_layer.add_child(hud)
	hud.retry_pressed.connect(func() -> void: start_race(race_index))
	hud.next_pressed.connect(_next_race)
	hud.menu_pressed.connect(show_menu)
	hud.race_chosen.connect(start_race)
	if _flags.has("clean"):
		hud.visible = false   # for recordings: captions do the talking
	if _flags.has("touch"):
		Input.emulate_touch_from_mouse = true   # lets the mouse press the touch buttons
	if _flags.has("level"):
		start_race(int(_flags.level))
	else:
		show_menu()


func start_race(i: int) -> void:
	race_index = clampi(i, 0, Races.count() - 1)
	race = Race.new()
	race.setup(Races.get_race(race_index))
	renderer.race = race
	hud.race = race
	hud.racing = true
	hud.hide_panels()
	bot = null
	if _flags.has("autopilot") or _flags.has("rookie"):
		bot = Autopilot.new()
		bot.rookie = _flags.has("rookie")
	if _flags.has("skip"):
		# Dev: start the whole field this many segments down the road.
		for r in race.riders:
			r.z += float(_flags.skip) * 200.0
		race.t = 0.0
	state = State.RACING
	_end_timer = RESULT_DELAY
	_heard = 0
	sound.play_music("race")


## The menu sits over a demo race that the autopilot rides, like an arcade
## attract mode.
func show_menu() -> void:
	state = State.MENU
	race = Race.new()
	race.setup(Races.get_race(0))
	race.t = 0.0
	renderer.race = race
	hud.race = race
	hud.racing = false
	bot = Autopilot.new()
	_heard = 0
	sound.play_music("menu")
	hud.show_menu(Races.RACES, best_pos, money)


func _next_race() -> void:
	if race_index + 1 < Races.count():
		start_race(race_index + 1)
	else:
		show_menu()


# ---------------------------------------------------------------- the race

func _physics_process(delta: float) -> void:
	_sim_time += delta
	if _flags.has("timeout") and _sim_time > float(_flags.timeout):
		_report("timeout")
	if race == null:
		return
	var input: Dictionary = bot.drive(race, delta) if bot else _read_input()
	var before: float = race.t
	race.step(delta, input)
	if state == State.RACING:
		_race_sounds(before)
	if state == State.MENU and race.result != "":
		show_menu()   # loop the demo
		return
	if state == State.RACING and race.result != "":
		_end_timer -= delta
		if _end_timer <= 0.0:
			_finish()
	if _flags.has("mem") and fmod(_sim_time, 2.0) < delta:
		# Memory watch: static (engine) memory and video memory, in MB.
		print("MEM t=%.0f static=%.1f video=%.1f" % [_sim_time, OS.get_static_memory_usage() / 1048576.0,
			Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0])
	if _flags.has("trace") and fmod(_sim_time, 0.5) < delta:
		var p = race.player
		print("TRACE t=%.1f z=%.0f x=%.2f v=%.0f st=%.2f pain=%.0f pos=%d" % [
			race.t, p.z, p.x, p.speed, p.stamina, p.pain, race.position()])


## Turns new race events into sounds, and ticks the countdown.
func _race_sounds(before: float) -> void:
	for i in range(_heard, race.events.size()):
		var ev := String(race.events[i][1])
		_video_events.append([_video_time, float(race.events[i][0]), ev])
		sound.play_event(ev)
		_juice(ev)
	_heard = race.events.size()
	for mark in [-2.0, -1.0]:
		if before < mark and race.t >= mark:
			sound.play("tick")
	if before < 0.0 and race.t >= 0.0:
		sound.play("go")


## Game feel: a split-second freeze on a solid hit. Slow motion on
## knockouts is only for recordings (--slowmo): in play it felt like a
## penalty, watching the pack ride off while you were down.
func _juice(ev: String) -> void:
	if _flags.has("no-slowmo"):
		return
	var key := ev.split(" ")[0]
	match key:
		"hit", "hit_by", "knockout":
			_hitstop_frames = maxi(_hitstop_frames, 3)
	if _flags.has("slowmo") and key in ["knockout", "crash", "last_standing"]:
		_slowmo_frames = maxi(_slowmo_frames, 60)


func _read_input() -> Dictionary:
	# On a phone, Chacha pedals by himself unless you hold REST (coasting is
	# how he gets his breath back): steering, swinging and ringing need thumbs.
	var pedal := Input.is_action_pressed("pedal")
	if _touch_mode:
		pedal = not Input.is_action_pressed("rest")
	return {
		"pedal": pedal,
		"brake": Input.is_action_pressed("brake"),
		"steer": Input.get_axis("left", "right"),
		"swing": Input.is_action_pressed("swing"),
		"bell": Input.is_action_pressed("bell"),
	}


func _finish() -> void:
	state = State.RESULT
	hud.racing = false
	var pos: int = race.position()
	var p = race.player
	var title := ""
	var info := ""
	var won := false
	match String(race.result):
		"finished":
			won = pos <= 3
			var prize: int = (PRIZES[pos - 1] if won else 0) + KO_BONUS * p.knocked_out
			money += prize
			title = ["MOHALLA CHAMPION!", "SECOND! RESPECTABLE.", "THIRD! STILL GOT IT."][pos - 1] if won else "%s PLACE..." % Hud.ordinal(pos).to_upper()
			info = String(race.data.win_line) if won else "Chacha needs top three to finish the errand.\nMore chai. Fewer buffaloes."
			info += "\n\nTime %.1f s   Knocked off: %d   Prize: Rs %d" % [race.player.finish_time, p.knocked_out, prize]
			if won and (not best_pos.has(race_index) or pos < int(best_pos[race_index])):
				best_pos[race_index] = pos
			if won and (not best_times.has(race_index) or p.finish_time < float(best_times[race_index])):
				best_times[race_index] = p.finish_time
		"retired":
			title = "RETIRED HURT"
			info = "Chacha's back has filed for retirement.\nToo many potholes, buffaloes and chappal fights."
		_:
			title = "SHOP CLOSED"
			info = "Too slow. Everybody went home for lunch."
	_save_progress()
	sound.play_music("")
	sound.play("win" if won else "sad")
	hud.show_result(title, info, won and race_index + 1 < Races.count())
	_report(String(race.result))


# ---------------------------------------------------------------- input

func _fit_layout() -> void:
	var win := DisplayServer.window_get_size()
	if win.x <= 0 or win.y <= 0:
		return
	var want := Vector2i(720, 1280) if win.y > win.x else Vector2i(1280, 720)
	if get_tree().root.content_scale_size != want:
		get_tree().root.content_scale_size = want


## Whichever was used last, touch or keys, decides the controls: touching the
## screen shows the buttons and turns on auto-pedal; pressing a key turns
## auto-pedal off again.
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		if not _touch_mode:
			_touch_mode = true
			hud.show_touch = true
	elif event is InputEventKey and event.pressed and not event.echo:
		_touch_mode = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("retry") and state != State.MENU:
		start_race(race_index)
	elif event.is_action_pressed("menu"):
		if state != State.MENU:
			show_menu()
	elif event.is_action_pressed("next") and state == State.RESULT:
		if race.result == "finished" and race.position() <= 3:
			_next_race()
		else:
			start_race(race_index)


func _process(_delta: float) -> void:
	# macOS stops drawing a window it considers hidden (covered, screen
	# locked), and Movie Maker would then save frozen frames. Force a draw.
	if not DisplayServer.window_can_draw():
		RenderingServer.force_draw()
	if Engine.time_scale > 0.0:
		_video_time += _delta / Engine.time_scale
	# Engine.time_scale slows the whole game (physics included) for effect.
	var scale := 1.0
	if _hitstop_frames > 0:
		_hitstop_frames -= 1
		scale = 0.06
	elif _slowmo_frames > 0:
		_slowmo_frames -= 1
		scale = 0.35
	if state != State.RACING:
		scale = 1.0
	Engine.time_scale = scale
	if not _flags.has("screenshot"):
		return
	# --wait=S takes one shot; --wait=1,2.5,4 takes a numbered shot at each time.
	var waits: PackedStringArray = String(_flags.get("wait", "1.5")).split(",")
	if _shot < waits.size() and _sim_time >= float(waits[_shot]):
		var path := String(_flags.screenshot)
		if waits.size() > 1:
			path = path.get_basename() + "_%d.png" % _shot
		get_viewport().get_texture().get_image().save_png(path)
		print("SCREENSHOT ", path)
		_shot += 1
		if _shot >= waits.size():
			get_tree().quit()


var _shot := 0
var _video_time := 0.0        # seconds of output video (differs from race time in slow motion)
var _video_events: Array = [] # [video seconds, race seconds, event] for the video tools
var _reported := false
var _touch_mode := false        # last input was touch: auto-pedal


func _setup_input() -> void:
	_add_action("pedal", [KEY_UP, KEY_W])
	_add_action("brake", [KEY_DOWN, KEY_S])
	_add_action("left", [KEY_LEFT, KEY_A])
	_add_action("right", [KEY_RIGHT, KEY_D])
	_add_action("swing", [KEY_SPACE, KEY_J])
	_add_action("bell", [KEY_B, KEY_K])
	_add_action("rest", [])                # touch only: coast to get breath back
	_add_action("retry", [KEY_R])
	_add_action("next", [KEY_ENTER, KEY_KP_ENTER])
	_add_action("menu", [KEY_ESCAPE])


func _add_action(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)


# ---------------------------------------------------------------- saves, flags, reports

func _load_progress() -> void:
	var cfg := ConfigFile.new()
	if not save_enabled or cfg.load(SAVE_PATH) != OK:
		return
	money = int(cfg.get_value("wallet", "money", 0))
	for i in Races.count():
		if cfg.has_section_key("pos", str(i)):
			best_pos[i] = int(cfg.get_value("pos", str(i)))
		if cfg.has_section_key("times", str(i)):
			best_times[i] = float(cfg.get_value("times", str(i)))


func _save_progress() -> void:
	if not save_enabled or bot != null:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("wallet", "money", money)
	for i in best_pos:
		cfg.set_value("pos", str(i), best_pos[i])
	for i in best_times:
		cfg.set_value("times", str(i), best_times[i])
	cfg.save(SAVE_PATH)


func _parse_flags() -> void:
	for arg in OS.get_cmdline_user_args():
		var a := String(arg).trim_prefix("--")
		var eq := a.find("=")
		if eq >= 0:
			_flags[a.substr(0, eq)] = a.substr(eq + 1)
		else:
			_flags[a] = true


## With --exit-on-end, prints one machine-readable line and quits. The checks
## and the video tools parse it. --log-events also prints every race event
## with its time, for cutting videos.
func _report(outcome: String) -> void:
	if not _flags.has("exit-on-end") or _reported:
		return
	_reported = true
	if _flags.has("linger"):
		# Keep the end on screen a moment for recordings.
		await get_tree().create_timer(float(_flags.linger), true, false, true).timeout
	if _flags.has("log-events") and race:
		for e in _video_events:
			print("EVENT v=%.2f t=%.2f %s" % [e[0], e[1], e[2]])
	var pos: int = race.position() if race else 0
	var p = race.player if race else null
	print("RESULT level=%d %s pos=%d time=%.1f pain=%.0f ko=%d" % [race_index, outcome, pos,
		p.finish_time if p and p.finished else (race.t if race else 0.0),
		p.pain if p else 0.0, p.knocked_out if p else 0])
	get_tree().quit()

