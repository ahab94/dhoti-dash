extends SceneTree
## Rides every race with the autopilot, no screen, and prints the outcome.
##   godot --headless --path . --script res://tests/sim.gd              expert, once
##   godot --headless --path . --script res://tests/sim.gd -- --rookie  5 rookies, averaged
## near: share of the race with a rival on screen and close (alongside or
## up to 1500 units ahead). lag: seconds behind the winner (0 = Chacha won). For the rookie it is the
## difficulty curve; it should climb race by race (see README).

const Races := preload("res://scripts/races.gd")
const Race := preload("res://scripts/race.gd")
const Autopilot := preload("res://scripts/autopilot.gd")


func _initialize() -> void:
	var rookie := "--rookie" in OS.get_cmdline_user_args()
	var runs := 8 if rookie else 1
	for i in Races.count():
		var lag_sum := 0.0
		var pos_sum := 0.0
		var pain_sum := 0.0
		var line := ""
		var pain_from := {}   # what hurt Chacha, summed over the runs
		var contact_sum := 0.0   # share of the race with a rival close by
		for k in runs:
			var race = Race.new()
			race.setup(Races.get_race(i))
			var bot = Autopilot.new()
			bot.rookie = rookie
			bot.rookie_seed = k
			var dt := 1.0 / 60.0
			var near := 0
			var steps := 0
			while race.result == "":
				race.step(dt, bot.drive(race, dt))
				steps += 1
				# On screen and close: alongside or just ahead (riders behind
				# the camera can't be seen).
				for j in range(1, race.riders.size()):
					var o = race.riders[j]
					var dz: float = o.z - race.player.z
					if not o.out and dz > -230.0 and dz < 1500.0:
						near += 1
						break
			contact_sum += float(near) / maxf(steps, 1.0)
			var lag := 0.0
			if race.result != "finished":
				lag = 60.0   # retired: count it as a minute behind
			for j in range(1, race.riders.size()):
				var o = race.riders[j]
				if o.finished and o.finish_time < race.player.finish_time:
					lag = maxf(lag, race.player.finish_time - o.finish_time)
			for e in race.events:
				var ev: String = String(e[1])
				if ev.begins_with("crash_into") or ev.begins_with("hit_by") or ev in ["pothole", "ball", "air"]:
					ev = ev.split(" ")[0] + ("_" + ev.split(" ")[1] if ev.begins_with("crash_into") else "")
					pain_from[ev] = int(pain_from.get(ev, 0)) + 1
			lag_sum += lag
			pos_sum += race.position()
			pain_sum += race.player.pain
			line += " %s%d(ko%d,out%d)" % ["" if race.result == "finished" else "R", race.position(),
				race.player.knocked_out, race.riders.size() - race.standing()]
		print("RACE %d lag=%.1fs pos=%.1f pain=%.0f near=%d%% places:%s" % [i, lag_sum / runs, pos_sum / runs,
			pain_sum / runs, int(100.0 * contact_sum / runs), line])
		if rookie:
			print("       hurt by: ", pain_from)
	quit(0)
