extends SceneTree
## Race data checks plus live mechanics, on race.gd directly (no screen).
##   godot --headless --path . --script res://tests/game_test.gd

const Races := preload("res://scripts/races.gd")
const Race := preload("res://scripts/race.gd")
const Hazard := preload("res://scripts/hazard.gd")
const Rider := preload("res://scripts/rider.gd")

const DT := 1.0 / 60.0
const IDLE := {"pedal": false, "brake": false, "steer": 0.0, "swing": false, "bell": false}
const PEDAL := {"pedal": true, "brake": false, "steer": 0.0, "swing": false, "bell": false}

var failures := 0


func _initialize() -> void:
	_check_data()
	_check_breath()
	_check_pothole_and_crash()
	_check_pickups()
	_check_umbrella()
	_check_brawl_and_last_standing()
	_check_weapon_pickup()
	_check_dogs()
	_check_bell()
	_check_aunty()
	_check_finish_and_position()
	_check_retired()
	print("GAME OK" if failures == 0 else "GAME FAILED (%d)" % failures)
	quit(0 if failures == 0 else 1)


func expect(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


## A race with the field cleared away, so one mechanic can be tested alone.
func bare_race(index := 0) -> Object:
	var r = Race.new()
	r.setup(Races.get_race(index))
	r.hazards.clear()
	r.riders = [r.player]
	r.aunty = null
	r.t = 0.0
	return r


func run(r, seconds: float, input: Dictionary) -> void:
	for i in int(seconds / DT):
		r.step(DT, input)


func _check_data() -> void:
	for i in Races.count():
		var d: Dictionary = Races.get_race(i)
		for k in ["name", "errand", "win_line", "difficulty", "rivals", "seed", "road", "scatter", "events", "boards"]:
			expect(d.has(k), "race %d has %s" % [i, k])
		for id in d.rivals:
			expect(Rider.ROSTER.has(id), "race %d rival %s exists" % [i, id])
		for k in d.scatter:
			expect(Hazard.KINDS.has(k), "race %d scatter kind %s exists" % [i, k])
		for e in d.events:
			expect(Hazard.KINDS.has(e[0]), "race %d event kind %s exists" % [i, e[0]])
		if i > 0:
			expect(float(d.difficulty) >= float(Races.get_race(i - 1).difficulty), "difficulty rises at race %d" % i)
		var r = Race.new()
		r.setup(d)
		expect(r.track.count > 800, "race %d is long enough" % i)


func _check_breath() -> void:
	var r = bare_race()
	run(r, 13.0, PEDAL)
	expect(r.player.panting, "pedalling flat out runs out of breath")
	run(r, 2.5, PEDAL)
	expect(r.player.panting and r.player.speed < Race.MAX_SPEED * 0.8, "panting caps the speed")
	run(r, 2.0, IDLE)
	expect(not r.player.panting, "coasting gets the breath back")


func _check_pothole_and_crash() -> void:
	var r = bare_race()
	run(r, 3.0, PEDAL)
	var h = Hazard.new()
	h.setup("pothole", r.player.z + 300.0, r.player.x)
	r.hazards.append(h)
	var v: float = r.player.speed
	run(r, 0.3, PEDAL)
	expect(r.player.pain > 0.0, "pothole hurts the back")
	expect(r.player.speed < v, "pothole slows you")
	var b = Hazard.new()
	b.setup("buffalo", r.player.z + 600.0, r.player.x)
	b.amp = 0.0
	r.hazards.append(b)
	r.player.immune = 0.0
	run(r, 0.6, PEDAL)
	expect(r.player.is_down(), "buffalo knocks Chacha down")
	run(r, 3.0, PEDAL)
	expect(not r.player.is_down(), "Chacha gets back up")


func _check_pickups() -> void:
	var r = bare_race()
	r.player.stamina = 0.1
	var c = Hazard.new()
	c.setup("chai", r.player.z + 200.0, 0.0)
	r.hazards.append(c)
	run(r, 1.5, PEDAL)
	expect(c.taken and r.player.stamina > 0.8, "chai refills breath")
	var j = Hazard.new()
	j.setup("jalebi", r.player.z + 400.0, r.player.x)
	r.hazards.append(j)
	run(r, 0.5, PEDAL)
	expect(r.player.boost > 0.0, "jalebi gives a boost")


func _check_umbrella() -> void:
	var r = bare_race()
	var rival = Rider.make_rival("pappu", 0.0)
	r.riders.append(rival)
	var other = Rider.make_rival("bablu", 0.0)
	other.z = -50000.0   # far behind, so the race isn't over when Pappu is out
	r.riders.append(other)
	for n in 4:
		rival.z = r.player.z + 100.0
		rival.x = r.player.x + 0.25
		rival.speed = 0.0
		r.player.cooldown = 0.0
		r.step(DT, {"pedal": false, "brake": false, "steer": 0.0, "swing": true, "bell": false})
		run(r, 0.4, IDLE)
	expect(rival.out, "four chhatri hits knock a rival out of the race")
	expect(r.player.knocked_out == 1, "knockouts are counted")
	expect(r.player.weapon == "akhbaar", "Chacha grabs the knocked-out rival's weapon")
	expect(r.feed.size() == 1, "the knockout makes the news feed")
	expect(r.result == "", "one rival still riding: the race goes on")


func _check_brawl_and_last_standing() -> void:
	var r = bare_race()
	var a = Rider.make_rival("tinku", 1.0)
	var b = Rider.make_rival("bablu", 0.0)
	r.riders.append(a)
	r.riders.append(b)
	a.z = r.player.z + 3000.0
	b.z = a.z + 100.0
	b.x = a.x + 0.3
	b.pain = 95.0
	a.speed = 0.0
	b.speed = 0.0
	r._start_swing(a, 1.0)
	run(r, 0.3, IDLE)
	expect(b.out, "rivals knock each other out too")
	a.pain = 99.0
	a.immune = 0.0
	var h = Hazard.new()
	h.setup("buffalo", a.z + 200.0, a.x)
	h.amp = 0.0
	r.hazards.append(h)
	run(r, 1.0, IDLE)
	expect(a.out, "a buffalo can knock a rival out")
	expect(r.result == "finished" and r.last_standing, "last man standing wins the race")
	expect(r.position() == 1, "last man standing is first")


## Dogs chase rivals too, and can be outrun, startled by the bell, or shooed.
func _check_dogs() -> void:
	var r = bare_race()
	var rival = Rider.make_rival("bablu", 0.0)
	r.riders.append(rival)
	rival.z = r.player.z + 20000.0
	rival.speed = 1500.0
	r.player.z = 0.0
	var d = Hazard.new()
	d.setup("dog", rival.z + 500.0, 0.5)
	r.hazards.append(d)
	run(r, 3.0, IDLE)
	expect(d.target == rival, "a dog goes after a rival who rides past")
	expect(rival.pain > 0.0 or d.state == "flee", "the rival gets bitten or shoos the dog off")

	# Outrun: Chacha flat out leaves a dog behind.
	r = bare_race()
	r.player.speed = Race.MAX_SPEED
	r.player.boost = 10.0
	d = Hazard.new()
	d.setup("dog", r.player.z + 300.0, 0.5)
	r.hazards.append(d)
	run(r, 6.0, PEDAL)
	expect(d.state == "flee", "sprinting Chacha outruns the dog")

	# Bell: startles a chasing dog.
	r = bare_race()
	r.player.speed = 2000.0
	d = Hazard.new()
	d.setup("dog", r.player.z + 600.0, 0.5)
	r.hazards.append(d)
	run(r, 1.0, IDLE)
	r.step(DT, {"pedal": false, "brake": false, "steer": 0.0, "swing": false, "bell": true})
	expect(d.state == "startled", "the bell startles a chasing dog")


func _check_weapon_pickup() -> void:
	var r = bare_race()
	var g = Hazard.new()
	g.setup("ganna", r.player.z + 300.0, r.player.x)
	r.hazards.append(g)
	run(r, 1.5, PEDAL)
	expect(r.player.weapon == "ganna", "riding over a ganna arms Chacha with it")


func _check_bell() -> void:
	var r = bare_race()
	var rival = Rider.make_rival("bablu", 0.0)
	rival.z = r.player.z + 500.0
	rival.x = r.player.x
	r.riders.append(rival)
	r.step(DT, {"pedal": false, "brake": false, "steer": 0.0, "swing": false, "bell": true})
	expect(rival.yield_for > 0.0, "the bell makes a rival move aside")


func _check_aunty() -> void:
	var r = bare_race(3)
	r.setup(Races.get_race(3))
	r.hazards.clear()
	r.riders = [r.player]
	r.t = 0.0
	r.aunty_wait = 0.0
	r.aunty.z = r.player.z - 1500.0
	run(r, 6.0, IDLE)   # Chacha dawdles; she catches him
	expect(r.aunty_count >= 1, "the aunty catches a dawdling Chacha")


func _check_finish_and_position() -> void:
	var r = bare_race()
	var rival = Rider.make_rival("pappu", 0.0)
	rival.z = r.track.length - 50.0
	r.riders.append(rival)
	r.player.z = r.track.length - 3000.0
	r.player.speed = Race.MAX_SPEED
	expect(r.position() == 2, "behind a rival means 2nd")
	run(r, 2.0, PEDAL)
	expect(r.result == "finished", "crossing the line finishes the race")
	expect(r.position() == 2, "the rival who finished first stays ahead")


func _check_retired() -> void:
	var r = bare_race()
	r.player.pain = 99.0
	var h = Hazard.new()
	h.setup("pothole", r.player.z + 100.0, r.player.x)
	r.hazards.append(h)
	run(r, 2.0, PEDAL)
	expect(r.result == "retired", "full back pain retires Chacha")
