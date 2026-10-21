extends RefCounted
## A cyclist: Chacha Jee himself or one of his rivals. Plain data. race.gd
## moves riders and resolves hits; renderer.gd draws them.

## The rivals. look picks the outfit and the thing they carry; top is their
## top speed as a share of Chacha's; aggr is how keen they are to swing at you;
## skill is how far ahead they look for buffaloes (0..1).
const ROSTER := {
	"pappu":  {"name": "Pappu Paperwala", "shirt": Color("4d96ff"), "look": "papers", "weapon": "akhbaar", "top": 0.86, "aggr": 0.5, "skill": 0.6,
		"lines": ["Chacha, read the news: you LOST!", "Extra! Extra! Old man overtaken!"]},
	"bablu":  {"name": "Bablu Doodhwala", "shirt": Color("f4f1de"), "look": "cans", "weapon": "doodh", "top": 0.84, "aggr": 0.3, "skill": 0.5,
		"lines": ["Careful! My milk will curdle!", "Fresh milk, fresh speed!"]},
	"chintu": {"name": "Chintu Chaiwala", "shirt": Color("e07a5f"), "look": "kettle", "weapon": "kadchi", "top": 0.88, "aggr": 0.4, "skill": 0.6,
		"lines": ["One cutting chai for the loser!", "Too hot to handle, Chacha!"]},
	"bunty":  {"name": "Bunty Selfie", "shirt": Color("ff70a6"), "look": "selfie", "weapon": "chappal", "top": 0.9, "aggr": 0.6, "skill": 0.35,
		"lines": ["Smile, Chacha! You're going viral!", "Like and subscribe, uncle!"]},
	"guddu":  {"name": "Guddu Tiffin", "shirt": Color("70c1b3"), "look": "tiffin", "weapon": "belan", "top": 0.89, "aggr": 0.5, "skill": 0.7,
		"lines": ["Forty lunches, zero delays!", "Your daal is getting cold, Chacha!"]},
	"tinku":  {"name": "Tinku Tailor", "shirt": Color("9b5de5"), "look": "tape", "weapon": "jhaadu", "top": 0.92, "aggr": 0.7, "skill": 0.7,
		"lines": ["Let me measure your defeat!", "Ready by Tuesday. Which Tuesday? Ha!"]},
	"master": {"name": "Master Jee", "shirt": Color("8d6e63"), "look": "ruler", "weapon": "scale", "top": 0.97, "aggr": 0.8, "skill": 0.9,
		"lines": ["Homework not done, Chacha?", "Stand on the bench! Oh wait, you're on a cycle."]},
}

## What each rider swings. A knocked-out rival drops theirs and Chacha grabs
## it. dmg: back pain per hit; reach: how far sideways it reaches (road units);
## cd: seconds between swings.
const WEAPONS := {
	"chhatri": {"name": "Chhatri", "dmg": 26.0, "reach": 0.45, "cd": 0.6},
	"akhbaar": {"name": "Rolled Akhbaar", "dmg": 20.0, "reach": 0.45, "cd": 0.4},
	"doodh":   {"name": "Doodh Can", "dmg": 45.0, "reach": 0.4, "cd": 1.0},
	"kadchi":  {"name": "Kadchi", "dmg": 34.0, "reach": 0.45, "cd": 0.7},
	"chappal": {"name": "Chappal", "dmg": 24.0, "reach": 0.5, "cd": 0.35},
	"belan":   {"name": "Belan", "dmg": 38.0, "reach": 0.42, "cd": 0.8},
	"jhaadu":  {"name": "Jhaadu", "dmg": 22.0, "reach": 0.65, "cd": 0.5},
	"scale":   {"name": "Master Jee's Scale", "dmg": 32.0, "reach": 0.5, "cd": 0.45},
	"ganna":   {"name": "Ganna", "dmg": 40.0, "reach": 0.6, "cd": 0.7},
	"lauki":   {"name": "Lauki", "dmg": 50.0, "reach": 0.4, "cd": 1.0},
}

var id := ""
var name := ""
var shirt := Color.WHITE
var look := "dhoti"
var is_player := false
var top := 1.0
var aggr := 0.0
var skill := 1.0
var lines: Array = []

var z := 0.0
var x := 0.0
var speed := 0.0
var stamina := 1.0       # "saans": breath. Pedalling spends it, coasting refills it.
var panting := false     # out of breath until stamina climbs back to PANT_RECOVER
var pain := 0.0          # "kamar dard": back pain. 100 means retired hurt.
var fallen := 0.0        # seconds left lying in the road
var fall_dir := 1.0
var immune := 0.0        # brief grace after a hit so one buffalo isn't five crashes
var stopped := 0.0       # seconds held up (by a rishta aunty)
var boost := 0.0         # jalebi sugar rush, seconds left
var wobble := 0.0        # visual shake after a bump, decays
var air := 0.0           # airborne off a speed breaker, seconds left
var swing := 0.0         # umbrella swing animation, seconds left
var swing_side := 1.0
var swing_hit_done := false
var cooldown := 0.0      # seconds until the next swing
var bell := 0.0          # "tring tring" animation, seconds left
var yield_for := 0.0     # a rival moves aside for this long after hearing the bell
var yield_dir := 0.0
var adjacent_for := 0.0  # how long the player has been in reach (rival attack timing)
var target_x := 0.0      # where the rival or the autopilot wants to ride
var plan_timer := 0.0
var weapon := "chhatri"
var out := false         # knocked out: sitting on the verge for the rest of the race
var out_by := ""
var hit_flash := 0.0     # "DHISHOOM!" burst, seconds left
var hit_word := ""
var last_hit := 0.0      # race time of the last hit taken, to show the health bar
var finished := false
var finish_time := 0.0
var knocked_out := 0     # rivals this rider has knocked off (player only)
var line := ""           # speech bubble
var line_time := 0.0
var pedal_phase := 0.0   # animation: crank angle
var lean := 0.0          # animation: tilt into the turn (radians)
var vx := 0.0            # sideways speed, road widths per second


static func make_player() -> RefCounted:
	var r = load("res://scripts/rider.gd").new()
	r.id = "chacha"
	r.name = "Chacha Jee"
	r.is_player = true
	r.look = "dhoti"
	r.shirt = Color("fbfbf2")
	return r


static func make_rival(rival_id: String, difficulty: float) -> RefCounted:
	var d: Dictionary = ROSTER[rival_id]
	var r = load("res://scripts/rider.gd").new()
	r.id = rival_id
	r.name = d.name
	r.shirt = d.shirt
	r.look = d.look
	# Difficulty 0..1 pushes every rival a little closer to Chacha's speed.
	r.top = minf(float(d.top) + 0.05 + 0.1 * difficulty, 1.0)
	r.aggr = float(d.aggr) * (0.6 + 0.6 * difficulty)
	r.skill = clampf(float(d.skill) + 0.2 * difficulty, 0.0, 1.0)
	r.lines = d.lines
	r.weapon = d.weapon
	return r


func say(text: String, seconds := 2.2) -> void:
	line = text
	line_time = seconds


func is_down() -> bool:
	return fallen > 0.0 or out


func weapon_stats() -> Dictionary:
	return WEAPONS.get(weapon, WEAPONS.chhatri)
