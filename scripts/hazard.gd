extends RefCounted
## One thing on the road: a pothole, a buffalo, a donkey cart, a cup of chai.
## Every hazard moves by a fixed formula of race time, so `x_at(t)` and
## `z_at(t)` answer "where will it be?" exactly. The autopilot and the rival
## riders use those forecasts to plan their line.

## w: half width in road units (1.0 = half the road). depth: how long it is
## along the road in world units. hit: what touching it does.
const KINDS := {
	"pothole": {"w": 0.11, "depth": 140.0, "hit": "bump"},
	"puddle":  {"w": 0.17, "depth": 260.0, "hit": "splash"},
	"breaker": {"w": 2.5,  "depth": 120.0, "hit": "breaker"},
	"buffalo": {"w": 0.2,  "depth": 300.0, "hit": "crash"},
	"donkey":  {"w": 0.17, "depth": 420.0, "hit": "crash"},
	"rickshaw": {"w": 0.19, "depth": 360.0, "hit": "crash"},
	"ball":    {"w": 0.05, "depth": 90.0,  "hit": "ball"},
	"baraat":  {"w": 0.36, "depth": 420.0, "hit": "crash"},
	"chai":    {"w": 0.11, "depth": 160.0, "hit": "chai"},
	"jalebi":  {"w": 0.11, "depth": 160.0, "hit": "jalebi"},
	"ganna":   {"w": 0.12, "depth": 160.0, "hit": "weapon"},
	"lauki":   {"w": 0.12, "depth": 160.0, "hit": "weapon"},
	# Village traffic and livestock.
	"cow":     {"w": 0.21, "depth": 420.0, "hit": "bounce"},   # unmoved; you bounce off
	"goats":   {"w": 0.3,  "depth": 300.0, "hit": "scatter"},  # a herd crossing
	"hens":    {"w": 0.13, "depth": 150.0, "hit": "flap"},     # flapping across
	"bullock": {"w": 0.22, "depth": 460.0, "hit": "crash"},    # bullock cart, slow
	"tractor": {"w": 0.3,  "depth": 620.0, "hit": "crash"},    # with a sugarcane trolley
	"thela":   {"w": 0.15, "depth": 260.0, "hit": "crash"},    # vegetable handcart
	"bricks":  {"w": 0.14, "depth": 200.0, "hit": "bump"},
	"dog":     {"w": 0.08, "depth": 120.0, "hit": "dog"},      # chases; see race.gd
}

var kind := ""
var z0 := 0.0
var x0 := 0.0
var vz := 0.0        # forward speed (carts and rickshaws drive along the road)
var amp := 0.0       # sideways wander
var period := 1.0
var phase := 0.0
var taken := false   # pickups disappear once collected
var heard := false   # its warning sound (moo, baa, putt-putt) has played
# Dogs don't follow a formula: they chase Chacha, so race.gd moves them and
# these hold where they are now.
var live := false
var lx := 0.0
var lz := 0.0
var state := "wait"  # dog: wait, chase, startled, flee
var target           # dog: the rider it's after
var timer := 0.0
var bite_cd := 0.0


func setup(k: String, z: float, x: float) -> void:
	kind = k
	z0 = z
	x0 = x
	match k:
		"buffalo":
			amp = 0.28
			period = 9.0
		"donkey":
			vz = 1400.0
		"rickshaw":
			vz = 2600.0
			amp = 0.12
			period = 5.0
		"ball":
			period = 2.4      # one crossing of the road per period
		"hens":
			period = 3.2
		"goats":
			period = 9.0      # the herd ambles across and back
		"bullock":
			vz = 1000.0
		"tractor":
			vz = 1900.0
			amp = 0.05
			period = 6.0
		"thela":
			vz = 550.0
		"dog":
			live = true
			lz = z
			lx = -1.35 if x < 0.0 else 1.35   # waits on the verge
		"cow":
			amp = 0.02        # shifts its weight, chewing
			period = 7.0
		"baraat":
			period = 18.0     # the procession snakes across and back, slowly


func w() -> float:
	return float(KINDS[kind].w)


func depth() -> float:
	return float(KINDS[kind].depth)


func hit() -> String:
	return String(KINDS[kind].hit)


func is_pickup() -> bool:
	return hit() in ["chai", "jalebi", "weapon"]


func z_at(t: float) -> float:
	if live:
		return lz
	return z0 + vz * t


func x_at(t: float) -> float:
	if live:
		return lx
	match kind:
		"hens":
			var f := fposmod(t / period + phase, 1.0)
			return -1.3 + 2.6 * f
		"goats":
			var f := fposmod(t / period + phase, 1.0)
			var tri := 1.0 - absf(2.0 * f - 1.0)
			return lerpf(-0.8, 0.8, smoothstep(0.0, 1.0, tri))
		"ball":
			# The kids bowl from the left verge to the right one, again and again.
			var f := fposmod(t / period + phase, 1.0)
			return -1.25 + 2.5 * f
		"baraat":
			# Ping-pong between the verges: a triangle wave, smoothed.
			var f := fposmod(t / period + phase, 1.0)
			var tri := 1.0 - absf(2.0 * f - 1.0)
			return lerpf(-0.75, 0.75, smoothstep(0.0, 1.0, tri))
	if amp > 0.0:
		return x0 + amp * sin(TAU * (t / period + phase))
	return x0


## Which way it is heading sideways, for drawing the buffalo's head.
func facing(t: float) -> float:
	if kind == "cow":
		return 1.0 if fposmod(z0, 2.0) < 1.0 else -1.0
	return signf(x_at(t + 0.1) - x_at(t)) if amp > 0.0 or kind in ["baraat", "goats", "hens"] else 1.0
