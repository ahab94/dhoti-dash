extends RefCounted
## One race: the road, the riders, the hazards and the rules. Pure logic, no
## drawing, so tests and the autopilot can run it without a screen. game.gd
## calls `step(dt, input)` 60 times a second; renderer.gd draws the state.
##
## Input is a Dictionary: {pedal, brake, steer (-1..1), swing, bell}.

const Track := preload("res://scripts/track.gd")
const Hazard := preload("res://scripts/hazard.gd")
const Rider := preload("res://scripts/rider.gd")

const MAX_SPEED := 5600.0     # world units per second: Chacha's flat-out pace
const KMH_AT_MAX := 34.0      # what the speedometer shows at MAX_SPEED
const ACCEL := 1700.0
const COAST_DRAG := 260.0     # an old roadster rolls a long way
const BRAKE := 5200.0
const HILL_PULL := 9000.0     # how hard slopes speed you up or slow you down
const OFFROAD_MAX := 0.42     # share of top speed on the dirt verge
const STEER := 1.6            # road widths per second at full speed (x units)
const CENTRIFUGAL := 0.12     # bends push you outwards
const LAT_ACCEL := 4.5        # how quickly sideways speed builds or dies (road widths/s²)
const PUSH := 0.9             # sideways shove from a hit, as a sideways speed
const RIDER_W := 0.07         # half width of a cycle in road units
const DRAIN := 0.11           # stamina per second pedalling flat out
const REGEN := 0.2            # stamina per second coasting
const PANT_REGEN := 0.06      # stamina per second while out of breath
const PANT_SPEED := 0.68      # share of top speed while panting
const PANT_RECOVER := 0.35
const FALL_TIME := 1.5
const SWING_TIME := 0.35
const SWING_REACH_Z := 300.0
const SWING_REACH_X := 0.45
const COUNTDOWN := 2.5
const TIME_LIMIT := 240.0
const AUNTY_CHAT := 3.0
const PACK_BEHIND := 150.0    # rivals closer than this behind Chacha sprint to catch up
const PACK_AHEAD := 900.0     # up to this far ahead, they ride at his pace
const FINAL_STRETCH := 0.8   # share of the race after which it's a straight race
const RIVAL_VS_RIVAL := 8.0  # back pain when rivals hit each other
const RIVAL_CRASH_PAIN := 15.0
const DOG_TOP := MAX_SPEED * 0.93   # a cycle ridden flat out is faster
const DOG_TURN := 1.0                # sideways; cycles swerve faster (STEER)
const DOG_CHASE := 6.0               # seconds before it loses interest
const NEAR_SOUNDS := ["buffalo", "cow", "goats", "hens", "bullock", "tractor"]
const HIT_WORDS := ["DHISHOOM!", "THWACK!", "DHAM!", "PATAAK!", "KHATAK!"]

const AUNTY_LINES := [
	"Beta! My niece is a doctor. Abroad!",
	"Just look at ONE photo, Chacha!",
	"What does your grandson earn? Exactly?",
	"She cooks, she sings, she has a green card... of a library!",
]
const CHACHA_AUNTY_REPLIES := [
	"Married since 1968, sister!",
	"He is nine years old!",
	"My dahi is melting!",
	"I have to go. My cycle is calling.",
]

var data: Dictionary = {}
var track
var riders: Array = []        # player first, then rivals
var player
var aunty                     # null unless the race has one
var aunty_wait := 0.0
var aunty_count := 0
var hazards: Array = []
var t := -COUNTDOWN           # race clock; negative during the countdown
var difficulty := 0.0
var result := ""              # "", "finished", "retired", "timeout"
var events: Array = []        # [time, text] for the video tools
var shake := 0.0              # screen shake amount, decays
var feed: Array = []          # [time, text] knockout news for the HUD
var last_standing := false    # won by knocking everyone out
var _line_index := 0


func setup(race: Dictionary) -> void:
	data = race
	difficulty = float(race.difficulty)
	track = Track.new()
	track.build(race.road, int(race.seed), race.boards)
	_place_hazards(race)

	riders.clear()
	player = Rider.make_player()
	riders.append(player)
	for id in race.rivals:
		riders.append(Rider.make_rival(String(id), difficulty))
	# Starting grid: rivals in pairs ahead, Chacha at the back like an underdog.
	for i in range(1, riders.size()):
		var r = riders[i]
		var row := (riders.size() - 1 - i) / 2
		r.z = 700.0 + row * 450.0
		r.x = -0.35 if i % 2 == 0 else 0.35
		r.target_x = r.x
		r.plan_timer = 0.05 * i    # stagger their thinking
	player.z = 200.0
	player.x = 0.0

	aunty = null
	if race.get("aunty", false):
		aunty = Rider.new()
		aunty.id = "aunty"
		aunty.name = "Rishta Aunty"
		aunty.look = "aunty"
		aunty.shirt = Color("ff4f9a")
		aunty.top = 0.87 + 0.07 * difficulty
		aunty.skill = 0.8
		aunty.z = -3500.0
		aunty_wait = 6.0          # she finishes her current gossip first


func _place_hazards(race: Dictionary) -> void:
	hazards.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(race.seed) * 7919
	var used: Array = []
	for e in race.events:
		_add_hazard(String(e[0]), int(e[1]), float(e[2]))
		used.append(int(e[1]))
	for kind in race.scatter:
		for n in int(race.scatter[kind]):
			var seg := 0
			for attempt in 30:
				seg = rng.randi_range(60, track.count - 40)
				var clear := true
				for u in used:
					if absi(u - seg) < 9:
						clear = false
						break
				if clear:
					break
			used.append(seg)
			var x := rng.randf_range(-0.72, 0.72)
			if kind == "breaker":
				x = 0.0
			var h = _add_hazard(String(kind), seg, x)
			h.phase = rng.randf()


func _add_hazard(kind: String, seg: int, x: float):
	var h = Hazard.new()
	h.setup(kind, seg * Track.SEG_LEN, x)
	if kind == "ball" or kind == "baraat":
		h.phase = x
	if kind == "ball":
		track.props[seg].append(["kids", -1.45, ""])
		track.props[seg].append(["stumps", 1.35, ""])
	hazards.append(h)
	return h


# ---------------------------------------------------------------- the step

func step(dt: float, input: Dictionary) -> void:
	if result != "":
		_coast_after_end(dt)
		return
	t += dt
	shake = maxf(shake - dt * 3.0, 0.0)
	if t < 0.0:
		return   # countdown: everyone waits at the line
	_step_player(dt, input)
	for i in range(1, riders.size()):
		_step_rival(riders[i], dt)
	if aunty:
		_step_aunty(dt)
	for r in riders:
		_resolve_swing(r)
		_check_hazards(r)
		_tick_timers(r, dt)
	_bump_riders()
	_check_finish()
	_step_dogs(dt)
	# Animals and machines announce themselves as they come into view.
	for h in hazards:
		if not h.heard and h.kind in NEAR_SOUNDS:
			var dz: float = h.z_at(t) - player.z
			if dz > 0.0 and dz < 6000.0:
				h.heard = true
				_log("near " + h.kind)


func _step_player(dt: float, input: Dictionary) -> void:
	var p = player
	if p.finished:
		_ride(p, dt, true, false, 0.0)
		return
	if input.get("swing", false) and p.cooldown <= 0.0 and not p.is_down() and p.stopped <= 0.0:
		_start_swing(p, _swing_side_for(p, float(input.get("steer", 0.0))))
	if input.get("bell", false) and p.bell <= 0.0 and not p.is_down():
		_ring_bell(p)
	_ride(p, dt, bool(input.get("pedal", false)), bool(input.get("brake", false)),
			float(input.get("steer", 0.0)))


## Shared riding physics for everyone. Rivals pass in pedal/brake/steer from
## their AI, the player from the keyboard or the autopilot.
func _ride(r, dt: float, pedal: bool, brake: bool, steer: float) -> void:
	if r.out:
		# Out of the race: roll to a stop and shuffle off to the verge.
		r.speed = move_toward(r.speed, 0.0, BRAKE * dt)
		r.z += r.speed * dt
		r.x = move_toward(r.x, 1.25 if r.x >= 0.0 else -1.25, 0.8 * dt)
		return
	if r.is_down():
		r.fallen -= dt
		r.speed = move_toward(r.speed, 0.0, BRAKE * dt)
		r.z += r.speed * dt
		if r.fallen <= 0.0:
			r.fallen = 0.0
			r.x = clampf(r.x, -0.85, 0.85)
		return
	if r.stopped > 0.0:
		r.speed = move_toward(r.speed, 0.0, BRAKE * dt)
		r.z += r.speed * dt
		return

	var pct: float = r.speed / MAX_SPEED
	var slope: float = track.slope_at(r.z)
	var top: float = r.top * (1.25 if r.boost > 0.0 else 1.0)
	if r.panting:
		top *= PANT_SPEED
	top *= clampf(1.0 - slope * 5.0, 0.7, 1.15)   # hills slow the top speed
	if pedal:
		# Legs push hard from a standstill but have less to give near top
		# speed, so acceleration fades out instead of stopping dead.
		var want := MAX_SPEED * top
		if r.speed < want:
			var ease := clampf(1.15 - r.speed / want, 0.15, 1.0)
			r.speed = minf(r.speed + ACCEL * ease * dt, want)
		else:
			r.speed = move_toward(r.speed, want, COAST_DRAG * dt)
	elif brake:
		r.speed = maxf(r.speed - BRAKE * dt, 0.0)
	else:
		r.speed = maxf(r.speed - COAST_DRAG * dt, 0.0)
	r.speed = maxf(r.speed - HILL_PULL * slope * dt, 0.0)   # downhill pulls you along
	r.speed = minf(r.speed, MAX_SPEED * 1.35)

	_breathe(r, dt, pedal, pct, slope)

	# Off the tarmac: dirt, stones, a goat. Slow down hard.
	if absf(r.x) > 1.0 and r.speed > MAX_SPEED * OFFROAD_MAX:
		r.speed = move_toward(r.speed, MAX_SPEED * OFFROAD_MAX, 4000.0 * dt)
		r.wobble = maxf(r.wobble, 0.15)

	# Sideways momentum: steering sets the sideways speed you're aiming for,
	# and the cycle's actual sideways speed (vx) eases towards it. So turns
	# build up, carry on for a moment when you let go, and shoves from hits
	# and bumps play out instead of teleporting the rider.
	var steer_gain := STEER * (0.3 + 0.7 * minf(pct, 1.0))
	var want_vx := clampf(steer, -1.0, 1.0) * steer_gain
	r.vx = move_toward(r.vx, want_vx, LAT_ACCEL * dt)
	r.x += r.vx * dt
	r.x -= track.curve_at(r.z) * pct * pct * CENTRIFUGAL * dt
	if absf(r.x) > 1.6:
		r.x = clampf(r.x, -1.6, 1.6)
		r.vx = 0.0
	r.z += r.speed * dt
	r.pedal_phase += r.speed * dt * 0.004 if pedal else 0.0


func _breathe(r, dt: float, pedal: bool, pct: float, slope: float) -> void:
	if r.boost > 0.0:
		return   # sugar rush: no breath needed
	if r.panting:
		r.stamina += PANT_REGEN * dt if pedal else REGEN * dt
		if r.stamina >= PANT_RECOVER:
			r.panting = false
	elif pedal:
		r.stamina -= DRAIN * r.lungs * clampf(pct, 0.2, 1.0) * clampf(1.0 + slope * 25.0, 0.5, 2.0) * dt
		if r.stamina <= 0.0:
			r.stamina = 0.0
			r.panting = true
			if r.is_player:
				r.say("Haah... haah... one minute...")
				_log("panting")
			else:
				r.say("Haah... haah...", 1.5)
				_log("rival_panting " + String(r.id))
	else:
		r.stamina += REGEN * dt
	r.stamina = clampf(r.stamina, 0.0, 1.0)


func _tick_timers(r, dt: float) -> void:
	r.immune = maxf(r.immune - dt, 0.0)
	r.stopped = maxf(r.stopped - dt, 0.0)
	r.boost = maxf(r.boost - dt, 0.0)
	r.wobble = maxf(r.wobble - dt, 0.0)
	r.air = maxf(r.air - dt, 0.0)
	r.swing = maxf(r.swing - dt, 0.0)
	r.cooldown = maxf(r.cooldown - dt, 0.0)
	r.bell = maxf(r.bell - dt, 0.0)
	r.yield_for = maxf(r.yield_for - dt, 0.0)
	r.line_time = maxf(r.line_time - dt, 0.0)
	r.hit_flash = maxf(r.hit_flash - dt, 0.0)
	# Lean into the turn: a bicycle tips the way it's turning, more when
	# turning hard at speed. Smoothed so it rolls in and out.
	var pct: float = r.speed / MAX_SPEED
	var tip := clampf(r.vx * (0.15 + 0.15 * pct), -0.25, 0.25) if not r.is_down() else 0.0
	r.lean = lerpf(r.lean, tip, 0.1)


# ---------------------------------------------------------------- rivals

func _step_rival(r, dt: float) -> void:
	r.plan_timer -= dt
	if r.plan_timer <= 0.0 and not r.is_down():
		r.plan_timer = 0.3 - 0.15 * r.skill
		r.target_x = plan_lane(r, 1200.0 + 2600.0 * r.skill)
	var want_x: float = r.target_x
	# Pick a fight: aggressive rivals drift towards the nearest rider beside
	# them, Chacha above all (everybody has a grudge against the old man).
	var foe = _nearest_foe(r, 700.0)
	if foe != null and r.out == false and not r.is_down():
		var side := 1.0 if r.x < foe.x else -1.0
		var keen: float = r.aggr * (0.8 if foe.is_player else 0.5)
		want_x = lerpf(want_x, clampf(foe.x - side * 0.28, -0.85, 0.85), clampf(keen, 0.0, 0.8))
	if r.yield_for > 0.0:
		want_x = clampf(r.target_x + r.yield_dir * 0.5, -0.85, 0.85)

	var keep_top: float = r.top
	r.top = _pack_pace(r)
	_ride(r, dt, _rival_pedals(r), false, _steer_towards(r, want_x))
	r.top = keep_top

	# A dog at their ankles gets the weapon first.
	for h in hazards:
		if h.kind == "dog" and h.state == "chase" and h.target == r and absf(h.lz - r.z) < 220.0 \
				and r.cooldown <= 0.0 and not r.is_down():
			_start_swing(r, signf(h.lx - r.x) if h.lx != r.x else 1.0)
	# Swing at whoever lingers in reach.
	var target = _nearest_foe(r, 260.0)
	if target != null and not r.is_down() and absf(target.x - r.x) < r.weapon_stats().reach:
		r.adjacent_for += dt
		if r.adjacent_for > 0.55 - 0.35 * r.aggr and r.cooldown <= 0.0:
			var dx: float = target.x - r.x
			_start_swing(r, signf(dx) if dx != 0.0 else 1.0)
			r.adjacent_for = 0.0
	else:
		r.adjacent_for = 0.0


## Rivals get tired too. Each one pedals until his breath drops to rest_at,
## then coasts until it's back up to rest_until. Careful riders (high skill)
## rest early and never run dry; reckless ones leave it late and end up
## panting, crawling at two-thirds speed, which is Chacha's chance. Nobody
## rests in the final stretch: it's a sprint for the line.
func _rival_pedals(r) -> bool:
	if r.panting or r.z > track.length * FINAL_STRETCH:
		r.resting = false
		return true
	if r.resting:
		if r.stamina >= r.rest_until:
			r.resting = false
	elif r.stamina <= r.rest_at:
		r.resting = true
		if r.line_time <= 0.0:
			r.say(["Ek minute... saans le loon.", "Phew. Hot day.", "Let me catch my breath..."][_line_index % 3], 1.6)
			_line_index += 1
		_log("rival_rest " + String(r.id))
	return not r.resting


## How fast a rival rides (as a share of MAX_SPEED), so the pack stays around
## Chacha where he can see it. In a fake-3D view only riders ahead of the
## camera are visible, so the pack sits alongside and just ahead of him:
##   behind him        sprint until back in view,
##   alongside / just ahead (up to PACK_AHEAD)  match his speed, each rival
##                     drifting a little faster or slower so they jostle,
##   far ahead         ease off so he can reel them in.
## In the final stretch the band lets go and rivals ride at their own pace,
## a little tired, so a well-ridden Chacha can sprint past.
func _pack_pace(r) -> float:
	var top: float = r.top
	if r.z > track.length * FINAL_STRETCH:
		return top * 0.98   # tired legs: Chacha has a fair shot at a final sprint
	var dz: float = r.z - player.z
	if dz < PACK_BEHIND:
		# The further back (after a crash, say), the harder they sprint.
		return minf(top * 1.3 + (-dz) / 12000.0, 1.45)
	if dz < PACK_AHEAD:
		if player.is_down() or player.stopped > 0.0:
			return top   # he's on the ground or with the aunty: ride on
		var drift := 0.03 * sin(t * 0.6 + float(r.id.hash() % 100))
		return clampf(player.speed / MAX_SPEED + drift, 0.5, 1.1)
	return top * clampf(1.0 - (dz - PACK_AHEAD) / 5000.0, 0.55, 1.0)


## The closest upright rider within `reach` along the road, or null.
func _nearest_foe(r, reach: float):
	var best = null
	var best_d := INF
	for o in riders:
		if o == r or o.is_down() or o.finished:
			continue
		var dz: float = absf(o.z - r.z)
		if dz > reach or absf(o.x - r.x) > 0.7:
			continue
		var d: float = dz + absf(o.x - r.x) * 400.0 - (150.0 if o.is_player else 0.0)
		if d < best_d:
			best_d = d
			best = o
	return best


## Steering command towards a lane, plus a nudge that cancels the bend's push.
## Now that the cycle has sideways momentum, steering must also brake that
## momentum before arriving, or the rider overshoots: aim for a sideways
## speed proportional to the distance left (the error), and the momentum
## settles in smoothly.
func _steer_towards(r, want_x: float) -> float:
	var pct: float = r.speed / MAX_SPEED
	var gain := STEER * (0.3 + 0.7 * minf(pct, 1.0))
	var drift: float = track.curve_at(r.z) * pct * pct * CENTRIFUGAL
	return clampf(((want_x - r.x) * 3.5 + drift) / gain, -1.0, 1.0)


## Picks the sideways position with the fewest hazards on the way. Tries 21
## lanes; for each it forecasts where every hazard will be when the rider gets
## there, and where the rider can get to by then (steering is not instant).
## The autopilot, the rivals and the aunty all use this.
func plan_lane(r, lookahead: float) -> float:
	var best: float = r.x
	var best_cost := INF
	for i in 21:
		var c := -0.85 + 0.085 * i
		var cost := absf(c - r.x) * 1.5 + absf(c) * 0.3 + lane_cost(r, c, lookahead)
		if cost < best_cost:
			best_cost = cost
			best = c
	return best


## How bad riding towards sideways position c looks over the next `lookahead`
## world units: hazards forecast to be in the way, plus riders blocking it.
func lane_cost(r, c: float, lookahead: float) -> float:
	var now := maxf(t, 0.0)
	var cost := 0.0
	for h in hazards:
		if h.taken:
			continue
		var hz: float = h.z_at(now)
		var dz: float = hz - r.z
		if dz < -150.0 or dz > lookahead:
			continue
		var closing := maxf(r.speed - h.vz, 500.0)
		var t_arr := maxf(dz, 0.0) / closing
		var reach := 1.1 * t_arr * (0.3 + 0.7 * minf(r.speed / MAX_SPEED, 1.0))
		var pos: float = r.x + clampf(c - r.x, -reach, reach)
		var gap: float = h.w() + RIDER_W + 0.06
		var hit := false
		for dtv in [-0.25, 0.0, 0.25]:
			if absf(h.x_at(now + t_arr + dtv) - pos) < gap:
				hit = true
		if hit:
			cost += _hazard_cost(r, h)
	for o in riders:
		if o == r:
			continue
		var odz: float = o.z - r.z
		if odz > 0.0 and odz < 900.0 and absf(o.x - c) < 0.16:
			cost += 60.0 if o.is_down() else 5.0
	return cost


func _hazard_cost(r, h) -> float:
	match h.hit():
		"crash":
			return 100.0
		"bump":
			return 25.0
		"ball":
			return 30.0
		"splash":
			return 6.0
		"bounce":
			return 70.0
		"scatter":
			return 40.0
		"flap":
			return 12.0
		"chai":
			if r.is_player:
				return -14.0 if r.stamina < 0.7 or r.pain > 20.0 else -3.0
			return 0.0
		"jalebi":
			return -10.0 if r.is_player else 0.0
		"weapon":
			return -6.0 if r.is_player else 0.0
	return 0.0


# ---------------------------------------------------------------- the aunty

func _step_aunty(dt: float) -> void:
	var a = aunty
	var p = player
	a.line_time = maxf(a.line_time - dt, 0.0)
	if a.stopped > 0.0:
		a.stopped -= dt
		a.z = p.z + 90.0            # pulled up alongside, just ahead
		a.x = clampf(p.x + 0.3, -0.9, 0.9)
		a.speed = 0.0
		if a.stopped <= 0.0:
			aunty_wait = 5.0     # she waves you off, then remembers another niece
		return
	if aunty_wait > 0.0:
		aunty_wait -= dt
		a.speed = move_toward(a.speed, 0.0, BRAKE * dt)
		a.z += a.speed * dt
		return
	a.plan_timer -= dt
	if a.plan_timer <= 0.0:
		a.plan_timer = 0.2
		a.target_x = clampf(p.x, -0.85, 0.85)
	var behind: float = p.z - a.z
	var want: float = MAX_SPEED * a.top
	if behind < 0.0:
		want = p.speed * 0.7   # overshot: let him come back to her
	a.speed = move_toward(a.speed, want, ACCEL * dt)
	var pct: float = a.speed / MAX_SPEED
	a.x += clampf((a.target_x - a.x) * 3.0, -1.0, 1.0) * STEER * (0.3 + 0.7 * minf(pct, 1.0)) * dt
	a.z += a.speed * dt
	if p.finished or p.is_down():
		return
	if behind > -80.0 and behind < 160.0 and absf(p.x - a.x) < 0.3:
		a.stopped = AUNTY_CHAT
		p.stopped = AUNTY_CHAT
		a.say(AUNTY_LINES[aunty_count % AUNTY_LINES.size()], AUNTY_CHAT)
		p.say(CHACHA_AUNTY_REPLIES[aunty_count % CHACHA_AUNTY_REPLIES.size()], AUNTY_CHAT)
		aunty_count += 1
		_log("aunty_caught")


## Metres between the aunty and Chacha, for the mirror on the HUD.
func aunty_gap() -> float:
	if aunty == null:
		return INF
	return (player.z - aunty.z) / 40.0


# ---------------------------------------------------------------- dogs

## Stray dogs wait on the verge and chase whoever rides past, rival or
## Chacha, switching to whoever is nearest, and nip at whoever they catch.
## Ways to shake one off:
##  - outrun it: a dog tops out a bit below Chacha's flat-out speed, so a
##    sprint (or a jalebi) leaves it behind and it gives up,
##  - weave: it turns slower than a cycle, so a swerve makes it miss,
##  - ring the bell: it startles and stops for a moment,
##  - swing at it: it runs off yelping.
func _step_dogs(dt: float) -> void:
	for h in hazards:
		if h.kind != "dog":
			continue
		h.bite_cd = maxf(h.bite_cd - dt, 0.0)
		match h.state:
			"wait":
				var prey = _dog_prey(h, 1800.0)
				if prey != null:
					h.state = "chase"
					h.timer = DOG_CHASE
					h.target = prey
					_log("bark")
			"startled":
				h.timer -= dt
				if h.timer <= 0.0:
					h.state = "chase"
					h.timer = DOG_CHASE * 0.5
			"chase":
				_chase(h, dt)
			"flee":
				h.lx = move_toward(h.lx, 1.8 * signf(h.lx) if h.lx != 0.0 else 1.8, 2.0 * dt)
				h.lz += 300.0 * dt


func _chase(h, dt: float) -> void:
	h.timer -= dt
	# Go after whoever is nearest now; a dog is easily distracted.
	var prey = _dog_prey(h, 900.0)
	if prey != null:
		h.target = prey
	var r = h.target
	if r == null or r.is_down() or r.finished or h.timer <= 0.0:
		h.state = "flee"
		return
	# Run: fast, but not as fast as a cycle ridden flat out.
	var dog_speed := minf(r.speed + 1400.0, DOG_TOP)
	h.lz = move_toward(h.lz, r.z - 40.0, dog_speed * dt)
	var side: float = -1.0 if h.lx < r.x else 1.0
	h.lx = move_toward(h.lx, r.x + side * 0.1, DOG_TURN * dt)
	var dz: float = h.lz - r.z
	if dz < -900.0:
		h.state = "flee"   # left in the dust
		if r.is_player:
			r.say("Outran you! Seventy-two years young!")
		_log("dog_outrun")
		return
	# Any swing that reaches it sends it off.
	for o in riders:
		if o.swing > 0.0 and not o.is_down() and absf(h.lz - o.z) < SWING_REACH_Z \
				and absf(h.lx - o.x) < float(o.weapon_stats().reach):
			h.state = "flee"
			if o.is_player:
				o.say("Shoo! Go home!")
			_log("dog_flee")
			return
	if absf(dz) < 170.0 and absf(h.lx - r.x) < 0.2 and h.bite_cd <= 0.0 and r.immune <= 0.0:
		h.bite_cd = 1.1
		r.speed *= 0.88
		r.wobble = 0.5
		r.vx += side * -0.4
		if r.is_player:
			r.pain += 3.0
			r.say(["Not the dhoti!", "Bhaago! Bad dog!", "I have no biscuits!"][_line_index % 3])
			_log("bite")
		else:
			r.pain += 4.0
			r.say(["Kutta! Not my pants!", "Uncle, call off your dog!", "Aaaa, my ankle!"][_line_index % 3], 1.6)
			_log("bite_rival " + String(r.id))
		_line_index += 1


## The nearest upright rider within `reach` of a dog, or null.
func _dog_prey(h, reach: float):
	var best = null
	var best_d := INF
	for r in riders:
		if r.is_down() or r.finished:
			continue
		var d: float = absf(h.lz - r.z) + absf(h.lx - r.x) * 300.0
		if absf(h.lz - r.z) < reach and d < best_d:
			best_d = d
			best = r
	return best


# ---------------------------------------------------------------- hits

func _check_hazards(r) -> void:
	if r.is_down() or r.immune > 0.0:
		return
	var now := maxf(t, 0.0)
	for h in hazards:
		if h.taken:
			continue
		var dz: float = h.z_at(now) - r.z
		if absf(dz) > h.depth() * 0.5 + 40.0:
			continue
		if absf(h.x_at(now) - r.x) > h.w() + RIDER_W:
			continue
		if h.is_pickup():
			if r.is_player:
				_pickup(r, h)
			continue
		if h.hit() == "dog":
			continue   # dogs bite in _step_dogs
		if r.air > 0.0 and h.hit() != "crash":
			continue   # flying over it, like a hero
		if r.is_player and h.hit() == "crash":
			_log("crash_into " + h.kind)
		_apply_hit(r, h.hit(), h.kind)
		return


func _pickup(r, h) -> void:
	h.taken = true
	if h.hit() == "weapon":
		r.weapon = h.kind
		r.say("%s in hand. Who's next?" % r.weapon_stats().name)
		_log("weapon " + h.kind)
		return
	if h.kind == "chai":
		r.stamina = 1.0
		r.panting = false
		r.pain = maxf(r.pain - 20.0, 0.0)
		r.say("Ahh, chai! Ten years younger.")
		_log("chai")
	else:
		r.boost = 3.5
		r.stamina = minf(r.stamina + 0.3, 1.0)
		r.panting = false
		r.say("JALEBI POWER!")
		_log("jalebi")


func _apply_hit(r, hit: String, cause := "") -> void:
	var pct: float = r.speed / MAX_SPEED
	match hit:
		"bump":
			r.speed *= 0.6
			r.wobble = 0.6
			r.immune = 0.4
			if r.is_player:
				r.pain += 5.0
				r.say("Hai, my back!")
				shake = 0.5
				_log("pothole")
		"splash":
			r.speed *= 0.85
			r.wobble = 0.3
			r.immune = 0.4
			if r.is_player:
				r.say("My dhoti! Freshly ironed!")
				_log("puddle")
		"breaker":
			r.immune = 0.5
			if pct > 0.55:
				r.air = 0.45
				r.speed *= 0.88
				if r.is_player:
					r.pain += 2.0
					r.say("Speed breaker? Back breaker!")
					shake = 0.4
					_log("air")
		"bounce":
			# The cow doesn't budge. Chacha stops dead and wobbles backwards.
			r.speed *= 0.15
			r.wobble = 0.9
			r.immune = 0.8
			r.vx = -signf(r.vx) * 0.6 if r.vx != 0.0 else 0.6
			if r.is_player:
				r.pain += 5.0
				r.say("Sorry, cow-ji! After you.")
				shake = 0.6
				_log("bounce")
		"scatter":
			r.speed *= 0.5
			r.wobble = 0.7
			r.immune = 0.8
			if r.is_player:
				r.pain += 4.0
				r.say("Goats everywhere! Baa to you too!")
				shake = 0.4
				_log("scatter")
		"flap":
			r.speed *= 0.85
			r.wobble = 0.6
			r.immune = 0.6
			if r.is_player:
				r.pain += 2.0
				r.say("Feathers in my moustache!")
				_log("flap")
		"ball":
			r.speed *= 0.9
			r.wobble = 0.5
			r.immune = 0.6
			if r.is_player:
				r.pain += 6.0
				r.say("HOWZAT?! Not out!")
				shake = 0.4
				_log("ball")
		"crash":
			_fall(r, cause)


func _fall(r, cause := "") -> void:
	r.fallen = FALL_TIME
	r.immune = FALL_TIME + 0.8
	r.vx = 0.0
	r.fall_dir = 1.0 if r.x < 0.0 else -1.0
	r.speed *= 0.3
	r.swing = 0.0
	if r.is_player:
		r.pain += 12.0
		r.say("ARREY BABA!")
		shake = 1.0
		_log("crash")
	else:
		r.say("Uff!", 1.2)
		r.pain += RIVAL_CRASH_PAIN
		_log("rival_crash " + String(r.id))
		if r.pain >= 100.0:
			_knock_out(r, null, cause)


# ---------------------------------------------------------------- swings and bells

func _swing_side_for(r, steer: float) -> float:
	var best := INF
	var side: float = signf(steer) if steer != 0.0 else r.swing_side
	for o in riders:
		if o == r or o.is_down():
			continue
		var dz: float = o.z - r.z
		var dx: float = o.x - r.x
		if absf(dz) < SWING_REACH_Z and absf(dx) < float(r.weapon_stats().reach) and absf(dz) + absf(dx) * 500.0 < best:
			best = absf(dz) + absf(dx) * 500.0
			side = signf(dx) if dx != 0.0 else side
	return side


func _start_swing(r, side: float) -> void:
	if r.is_player:
		_log("swing")
	r.swing = SWING_TIME
	r.swing_side = side
	r.swing_hit_done = false
	# Rivals swing at most every 0.9 s whatever they hold, so a fast chappal
	# doesn't turn one rival into a blender.
	r.cooldown = float(r.weapon_stats().cd) if r.is_player else maxf(float(r.weapon_stats().cd) * 1.6, 0.9)


## The swing lands halfway through the animation, so a quick dodge can still
## make it miss. Anyone can hit anyone; the first rider in reach on the swing
## side takes it.
func _resolve_swing(r) -> void:
	if r.swing <= 0.0 or r.swing > SWING_TIME * 0.5 or r.swing_hit_done:
		return
	r.swing_hit_done = true
	var w: Dictionary = r.weapon_stats()
	if r.is_player and aunty and absf(aunty.z - r.z) < SWING_REACH_Z and absf(aunty.x - r.x) < float(w.reach):
		r.say("Not the aunty! Manners, Chacha!")
	for o in riders:
		if o == r or o.is_down():
			continue
		var dz: float = o.z - r.z
		var dx: float = o.x - r.x
		if absf(dz) > SWING_REACH_Z or absf(dx) > float(w.reach):
			continue
		if absf(dx) > 0.05 and signf(dx) != r.swing_side:
			continue
		_land_hit(r, o, w)
		return


func _land_hit(r, o, w: Dictionary) -> void:
	o.wobble = 0.9
	o.vx += r.swing_side * PUSH
	o.speed *= 0.86
	o.hit_flash = 0.45
	o.hit_word = HIT_WORDS[_line_index % HIT_WORDS.size()]
	o.last_hit = t
	_line_index += 1
	if o.is_player:
		o.pain += 3.0 + 2.5 * difficulty
		shake = maxf(shake, 0.35)
		r.say(String(r.lines[_line_index % r.lines.size()]))
		_log("hit_by " + String(r.id))
	else:
		o.pain += float(w.dmg) if r.is_player else RIVAL_VS_RIVAL
		if r.is_player:
			shake = maxf(shake, 0.2)
			_log("hit " + String(o.id))
		else:
			_log("brawl %s>%s" % [r.id, o.id])
		if o.pain >= 100.0:
			_knock_out(o, r, "")
		elif r.is_player:
			o.say(["Oye!", "Arey uncle!", "My paint job!", "Not the face!"][_line_index % 4], 1.2)


## Out for the rest of the race. If Chacha did it, he takes their weapon.
func _knock_out(o, by, cause: String) -> void:
	if o.out:
		return
	o.out = true
	o.fallen = 1.0
	o.pain = 100.0
	o.speed *= 0.3
	o.fall_dir = 1.0 if o.x < 0.0 else -1.0
	o.say("I'm OUT!", 2.5)
	var why := "by a %s" % cause if cause != "" else "by a mystery"
	if by != null:
		why = "by Chacha" if by.is_player else "by %s" % by.name
		by.knocked_out += 1
		if by.is_player:
			if o.weapon != by.weapon:
				by.weapon = o.weapon
				by.say("Chacha grabs the %s!" % String(o.weapon_stats().name).to_lower())
			else:
				by.say("Respect your elders!")
	o.out_by = why
	feed.append([t, "%s is OUT, %s!" % [o.name, why]])
	_log("knockout " + String(o.id) + (" by_player" if by != null and by.is_player else ""))
	if standing() == 1 and not player.out and result == "":
		# Last man standing: everyone else is sitting on the verge.
		last_standing = true
		player.finished = true
		player.finish_time = t
		result = "finished"
		_log("last_standing")


## Riders still in the race (not knocked out), Chacha included.
func standing() -> int:
	var n := 0
	for r in riders:
		if not r.out:
			n += 1
	return n


func _ring_bell(r) -> void:
	r.bell = 0.9
	_log("bell")
	for h in hazards:
		if h.kind == "dog" and h.state == "chase" and absf(h.lz - r.z) < 500.0:
			h.state = "startled"
			h.timer = 1.0
			if r.is_player:
				r.say("Tring tring! ...It worked!")
			_log("dog_startled")
	var moved := false
	for o in riders:
		if o == r or o.is_down():
			continue
		var dz: float = o.z - r.z
		if dz > 0.0 and dz < 1100.0 and absf(o.x - r.x) < 0.35:
			o.yield_for = 1.6
			var away: float = o.x - r.x
			o.yield_dir = signf(away) if absf(away) > 0.02 else (-1.0 if o.x > 0.0 else 1.0)
			moved = true
	if not moved:
		for h in hazards:
			var dz: float = h.z_at(maxf(t, 0.0)) - r.z
			if h.kind == "buffalo" and dz > 0.0 and dz < 2500.0:
				r.say("Tring tring! ...The buffalo does not care.")
				return
	r.say("Tring tring!", 0.8)


# ---------------------------------------------------------------- contact and finish

## Cycles can't overlap: the one behind is held up and both are nudged apart.
func _bump_riders() -> void:
	for i in riders.size():
		for j in range(i + 1, riders.size()):
			var a = riders[i]
			var b = riders[j]
			if a.is_down() or b.is_down():
				continue
			var dz: float = a.z - b.z
			var dx: float = a.x - b.x
			if absf(dz) > 160.0 or absf(dx) > 0.14:
				continue
			var front = a if dz > 0.0 else b
			var back = b if dz > 0.0 else a
			back.speed = minf(back.speed, front.speed * 0.97)
			# Elbows out: each gets a sideways shove away from the other, and
			# a nudge apart so they don't stay overlapped.
			var dir := signf(dx) if dx != 0.0 else 1.0
			var overlap := 0.14 - absf(dx)
			a.vx += dir * overlap * 6.0
			b.vx -= dir * overlap * 6.0
			a.x += dir * overlap * 0.15
			b.x -= dir * overlap * 0.15


func _check_finish() -> void:
	for r in riders:
		if not r.finished and r.z >= track.length:
			r.finished = true
			r.finish_time = t
			if r.is_player:
				result = "finished"
				_log("finish pos=%d" % position())
	if player.pain >= 100.0 and result == "":
		player.pain = 100.0
		if not player.is_down():
			_fall(player)
		player.out = true
		result = "retired"
		_log("retired")
	if t > TIME_LIMIT and result == "":
		result = "timeout"


## After the end the riders keep rolling so the camera has something to show.
func _coast_after_end(dt: float) -> void:
	t += dt
	for r in riders:
		if r == player and result != "finished":
			_ride(r, dt, false, true, 0.0)
		else:
			_ride(r, dt, true, false, _steer_towards(r, r.target_x))
		_tick_timers(r, dt)
		if not r.finished and r.z >= track.length:
			r.finished = true
			r.finish_time = t


## Chacha's place: 1 + everyone who finished before him or is ahead on the road.
func position() -> int:
	var pos := 1
	for i in range(1, riders.size()):
		var r = riders[i]
		if r.out and not r.finished:
			continue   # knocked out: off the leaderboard
		if player.finished:
			if r.finished and r.finish_time < player.finish_time:
				pos += 1
		elif r.finished or r.z > player.z:
			pos += 1
	return pos


func progress() -> float:
	return clampf(player.z / track.length, 0.0, 1.0)


func kmh(r) -> float:
	return r.speed / MAX_SPEED * KMH_AT_MAX


func _log(text: String) -> void:
	events.append([t, text])
