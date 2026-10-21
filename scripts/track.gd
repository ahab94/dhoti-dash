extends RefCounted
## The road as a list of short segments, the way 80s and 90s racing games did
## it. Each segment is SEG_LEN world units long and stores two numbers: how
## much the road bends there (curve) and how high it is (y). The renderer
## stacks the segments in front of the camera to fake 3D. Gameplay only
## needs `z` (distance along the road) and `x` (sideways, -1 and +1 are the
## road edges), so everything else in the game is simple 2D maths.

const SEG_LEN := 200.0
const ROAD_W := 1000.0       # half the road width in world units (x = ±1)
const POLE_EVERY := 14       # segments between electricity poles

var curves := PackedFloat32Array()
var heights := PackedFloat32Array()
var props: Array = []        # per segment: Array of [kind, x, text]
var count := 0               # segments in the race
var length := 0.0            # world units from start line to finish line


## sections: [[segments, curve, hill], ...]. Curve eases in over the first
## quarter of a section and out over the last quarter, so bends don't snap.
## Hill is the height change across the section, eased the same way.
func build(sections: Array, seed: int, billboards: Array) -> void:
	curves.clear()
	heights.clear()
	var y := 0.0
	for s in sections:
		var n := int(s[0])
		var c := float(s[1])
		var dy := float(s[2])
		for i in n:
			var f := float(i) / n
			var ease_c := smoothstep(0.0, 0.25, f) * (1.0 - smoothstep(0.75, 1.0, f))
			curves.append(c * ease_c)
			heights.append(y + dy * smoothstep(0.0, 1.0, f))
		y += dy
	count = curves.size()
	# Extra flat road past the finish so the camera has something to look at.
	for i in 300:
		curves.append(0.0)
		heights.append(y)
	length = count * SEG_LEN
	_scatter_props(seed, billboards)


func seg_index(z: float) -> int:
	return clampi(int(floor(z / SEG_LEN)), 0, curves.size() - 1)


func curve_at(z: float) -> float:
	return curves[seg_index(z)]


func height_at(z: float) -> float:
	var i := seg_index(z)
	var j := mini(i + 1, heights.size() - 1)
	var f := fposmod(z, SEG_LEN) / SEG_LEN
	return lerpf(heights[i], heights[j], f)


## Rise per unit of road: positive means uphill.
func slope_at(z: float) -> float:
	return (height_at(z + SEG_LEN) - height_at(z)) / SEG_LEN


## Roadside scenery. A seeded random number generator makes every run of a
## race look the same, which keeps screenshots and videos reproducible.
func _scatter_props(seed: int, billboards: Array) -> void:
	props.clear()
	props.resize(curves.size())
	for i in props.size():
		props[i] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var kinds := ["tree", "tree", "palm", "house", "house", "charpai", "stall", "haystack"]
	var i := 4
	var board := 0
	while i < props.size():
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		if board < billboards.size() and i > 30 + board * 120:
			props[i].append(["billboard", side * 1.55, billboards[board]])
			board += 1
		else:
			var k: String = kinds[rng.randi() % kinds.size()]
			props[i].append([k, side * rng.randf_range(1.35, 2.6), ""])
		i += rng.randi_range(3, 7)
	# The electricity line: evenly spaced poles down the left verge, with
	# wires strung between them (the renderer draws the wires).
	for j in range(6, props.size(), POLE_EVERY):
		props[j].append(["line_pole", -1.3, ""])
	# The finish banner sits over the road on the finish segment.
	props[count].append(["finish", 0.0, ""])
