extends RefCounted
## Rides for Chacha. It is the "this race can be won" gate in the checks and
## the stunt double for video footage.
##
## rookie = true makes it ride like a new player (late reactions, short
## lookahead, no breath management, forgets the umbrella), which is how
## tests/sim.gd measures how hard each race feels.

var rookie := false
var rookie_seed := 0         # varies the rookie's reactions, for averaging
var _plan_timer := 0.0
var _target := 0.0
var _resting := false


func drive(race, dt: float) -> Dictionary:
	var p = race.player
	_plan_timer -= dt
	if _plan_timer <= 0.0:
		if rookie:
			# Each rookie reacts a little differently: think every 0.3 to 0.45 s,
			# look 1200 to 1700 units ahead.
			var j := fposmod(rookie_seed * 0.618 + race.t * 0.37, 1.0)
			_plan_timer = 0.3 + 0.15 * j
			_target = race.plan_lane(p, 1200.0 + 500.0 * fposmod(rookie_seed * 0.382, 1.0))
		else:
			_plan_timer = 0.1
			_target = race.plan_lane(p, 4200.0)
			# Brawl rules: pull alongside the nearest rival to give him the
			# umbrella, unless that lane is about to hold a buffalo.
			var foe = race._nearest_foe(p, 900.0)
			if foe != null and p.z < race.track.length * 0.85:   # near the end, just race
				var side := 1.0 if p.x < foe.x else -1.0
				var lane: float = clampf(foe.x - side * 0.3, -0.85, 0.85)
				if race.lane_cost(p, lane, 2500.0) < 20.0:
					_target = lerpf(_target, lane, 0.7)
	var input := {"pedal": true, "brake": false, "steer": 0.0, "swing": false, "bell": false}
	input.steer = race._steer_towards(p, _target)

	# Breath: rest before running out, unless the aunty is close. Near the
	# end, plan the final sprint: once there's enough breath to pedal flat
	# out to the line, go; until then, top up first.
	if not rookie:
		var aunty_close: bool = race.aunty_gap() < 70.0
		var to_go: float = race.track.length - p.z
		var need: float = to_go / race.MAX_SPEED * race.DRAIN * 1.1
		var sprint: bool = p.stamina >= need
		var want := 0.45
		if to_go < race.track.length * 0.35:
			want = clampf(need, 0.45, 0.95)
		if p.stamina < 0.12 and not aunty_close and not sprint:
			_resting = true
		if p.stamina > want or sprint or aunty_close or p.boost > 0.0:
			_resting = false
		input.pedal = not _resting

	# A dog on Chacha's heels: swing at it if it's in reach, otherwise ring.
	for h in race.hazards:
		if h.kind == "dog" and h.state == "chase" and h.target == p and absf(h.lz - p.z) < 300.0:
			if absf(h.lx - p.x) < float(p.weapon_stats().reach) - 0.05:
				input.swing = true
			elif not rookie:
				input.bell = true
	# Umbrella anyone in reach; ring at anyone blocking the lane ahead.
	for i in range(1, race.riders.size()):
		var o = race.riders[i]
		if o.is_down():
			continue
		if rookie and int(race.t * 2.0) % 3 != 0:
			continue   # a rookie only remembers the umbrella now and then
		var dz: float = o.z - p.z
		var dx: float = absf(o.x - p.x)
		if absf(dz) < 250.0 and dx < float(p.weapon_stats().reach) - 0.03:
			input.swing = true
		if dz > 200.0 and dz < 1000.0 and dx < 0.2:
			input.bell = true
	return input
