extends Node2D
## Draws the race in fake 3D, the way classic arcade racers did.
##
## How it works: the camera floats behind and above Chacha. Each road segment
## ahead is a flat strip. We project its near edge onto the screen with
##   scale = CAM_DEPTH / (distance from camera)
## so far segments shrink towards the horizon. Bends are faked by sliding each
## further segment sideways a little more than the last (dx grows by the
## segment's curve). Then we paint from far to near: every strip, and the
## sprites standing on it, cover what is behind them. No 3D engine needed.

const Track := preload("res://scripts/track.gd")
const Sprites := preload("res://scripts/sprites.gd")

const CAM_HEIGHT := 900.0
const CAM_DEPTH := 0.84            # 1 / tan(field of view / 2), about 100 degrees
const PLAYER_Z := CAM_HEIGHT * CAM_DEPTH   # camera distance behind Chacha
const DRAW_SEGS := 150

const SKY_TOP := Color("ffb35c")
const SKY_LOW := Color("ffe2a8")
const GRASS_A := Color("9bc53d")
const GRASS_B := Color("8cb738")
const DIRT_A := Color("d9a066")
const DIRT_B := Color("cf955c")
const ROAD_A := Color("8d8a86")
const ROAD_B := Color("85827e")
const LINE := Color(1, 1, 1, 0.75)

var race                     # race.gd instance, set by game.gd
var _font: Font


func _ready() -> void:
	_font = ThemeDB.fallback_font


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if race == null:
		return
	var size := get_viewport_rect().size
	var w := size.x
	var h := size.y
	# One pixel scale for x and y. k is how many pixels one "camera height"
	# covers at the player; the horizon sits k above the road under Chacha.
	# Portrait (phones, Shorts): a closer camera, so the riders fill the
	# narrow screen and the sky doesn't take over.
	var k := w * 0.85 if h > w else minf(h * 0.5, w * 0.62)
	var hy := h - k - h * 0.03
	var p = race.player
	# Camera roll: the whole view tilts a little into bends, around the point
	# under Chacha's wheel, as if the cameraman leans with him. Rotating about
	# a pivot c means: x' = R(x - c) + c, so the transform's origin is c - R c.
	var pct: float = p.speed / race.MAX_SPEED
	var roll: float = clampf(race.track.curve_at(p.z) * pct * 0.012, -0.07, 0.07)
	_roll = lerpf(_roll, roll, 0.08)
	var pivot := Vector2(w * 0.5, hy + k)
	var sh: float = race.shake * 9.0
	var shake := Vector2(sin(race.t * 61.0), cos(race.t * 53.0)) * sh
	var world := Transform2D(_roll, Vector2.ZERO)
	world.origin = pivot - world.basis_xform(pivot) + shake
	draw_set_transform_matrix(world)
	Sprites.vp = Vector2(w * 0.5, hy)
	Sprites.depth_k = CAM_DEPTH * k
	Sprites.fog = 0.0

	var cam_z: float = p.z - PLAYER_Z
	var base: int = race.track.seg_index(cam_z)
	var base_frac: float = fposmod(cam_z, Track.SEG_LEN) / Track.SEG_LEN
	var cam_y: float = race.track.height_at(p.z) + CAM_HEIGHT
	# The camera follows Chacha sideways with a little lag, so he swings
	# across the screen when he steers instead of being glued to the middle.
	_cam_x = lerpf(_cam_x, p.x, 0.08)
	if absf(_cam_x - p.x) > 0.6:
		_cam_x = p.x - signf(p.x - _cam_x) * 0.6
	var cam_x: float = _cam_x * Track.ROAD_W
	_draw_sky(w, hy)

	# Pass 1, near to far: project every segment edge and accumulate the bend.
	var proj: Array = []
	var x_off := 0.0
	var dx: float = -race.track.curves[base] * base_frac
	for n in DRAW_SEGS + 1:
		var i: int = mini(base + n, race.track.curves.size() - 1)
		var z: float = maxf((base + n) * Track.SEG_LEN - cam_z, 1.0)
		var s := CAM_DEPTH / z * k
		proj.append({
			"x": w * 0.5 + s * (x_off - cam_x),
			"y": hy - s * (race.track.heights[i] - cam_y),
			"w": s * Track.ROAD_W,
			"s": s,
		})
		x_off += dx
		dx += race.track.curves[i]

	# Pass 2, far to near: road strips, then what stands on them.
	_bubble_spots.clear()
	_pole_tops.clear()
	var buckets := _sprite_buckets(base, proj, cam_z)
	for n in range(DRAW_SEGS - 1, -1, -1):
		var a: Dictionary = proj[n]
		var b: Dictionary = proj[n + 1]
		var haze := _haze(n)
		if b.y < a.y:   # skip strips hidden behind a hill crest
			_draw_segment(w, a, b, base + n, n)
		if buckets.has(n):
			Sprites.fog = haze
			for spr in buckets[n]:
				_draw_sprite(spr)
	Sprites.fog = 0.0

	_draw_wires(w, hy)

	# Chacha last, on the road PLAYER_Z ahead of the camera. Airborne off a
	# speed breaker, he hops.
	var ps := k / CAM_HEIGHT
	var lift := sin(clampf(p.air / 0.45, 0.0, 1.0) * PI) * 120.0 * ps
	var feet := Vector2(w * 0.5 + (p.x - _cam_x) * Track.ROAD_W * ps, hy + k - lift)
	Sprites.dust(self, feet, ps, p, race.t, absf(p.x) > 1.0)
	Sprites.rider(self, feet, ps, p, race.t)
	Sprites.fight_fx(self, feet, ps, p, race.t, _font)
	_speed_streaks(w, h, hy, pct + (0.3 if p.boost > 0.0 else 0.0))
	_bubble_spots.append([p, feet, ps])
	_bubble_boxes.clear()
	for spot in _bubble_spots:
		var r = spot[0]
		if r.line_time > 0.0:
			var col := Color("fff8e7") if r.is_player else (Color("ffe1ef") if r.look == "aunty" else Color("e7f6ff"))
			_bubble(spot[1] - Vector2(0, 400.0 * float(spot[2])), r.line, col)
	draw_set_transform(Vector2.ZERO)
	_grade(w, h, hy)


var _bubble_spots: Array = []
var _pole_tops: Array = []       # this frame's poles, far to near: [left, mid, right, scale]
var _roll := 0.0
var _cam_x := 0.0
var _sun := Vector2.ZERO
var _vignette: GradientTexture2D
var _bubble_boxes: Array = []    # bubbles already drawn this frame, to avoid overlaps


## Faint streaks rushing out from the vanishing point when flying along.
func _speed_streaks(w: float, h: float, hy: float, amount: float) -> void:
	var a := clampf((amount - 0.8) * 2.5, 0.0, 1.0)
	if a <= 0.0:
		return
	var vp := Vector2(w * 0.5, hy)
	for i in 14:
		var ang := TAU * _hash(i * 7)
		var dir := Vector2.from_angle(ang)
		var f := fposmod(race.t * 2.2 + _hash(i), 1.0)
		var r0 := lerpf(0.35, 1.1, f) * w * 0.5
		var p0 := vp + dir * r0
		if p0.y < hy * 0.9:
			continue   # keep the sky clean
		draw_line(p0, vp + dir * (r0 + w * 0.08), Color(1, 1, 1, 0.12 * a * (1.0 - f)), 3.0)


## Colour grade over the finished frame: warm light from the top, the sun
## spilling over everything, and darkened corners (a vignette) to pull the eye
## to the middle. Drawn once more with a radial GradientTexture2D, which Godot
## builds in memory, so it's still no image files.
func _grade(w: float, h: float, hy: float) -> void:
	_grad_rect(0, 0, w, hy, Color(1.0, 0.55, 0.2, 0.10), Color(1.0, 0.7, 0.3, 0.0))
	_grad_rect(0, hy, w, h, Color(1.0, 0.75, 0.4, 0.10), Color(0.2, 0.1, 0.0, 0.08))
	if _vignette == null:
		_vignette = GradientTexture2D.new()
		_vignette.fill = GradientTexture2D.FILL_RADIAL
		_vignette.fill_from = Vector2(0.5, 0.5)
		_vignette.fill_to = Vector2(1.0, 1.0)
		var g := Gradient.new()
		g.set_color(0, Color(0, 0, 0, 0))
		g.set_color(1, Color(0.18, 0.06, 0.0, 0.55))
		g.add_point(0.55, Color(0, 0, 0, 0))
		_vignette.gradient = g
		_vignette.width = 256
		_vignette.height = 256
	draw_texture_rect(_vignette, Rect2(0, 0, w, h), false)


## Three wires from each pole to the next, sagging in the middle. They belong
## to the poles, so they slide past as Chacha rides. The nearest pole's wires
## also run on towards the camera, off the top of the screen.
func _draw_wires(w: float, hy: float) -> void:
	var col := Color(0.18, 0.13, 0.1, 0.75)
	for i in _pole_tops.size():
		var a: Array = _pole_tops[i]
		var nxt: Array
		if i + 1 < _pole_tops.size():
			nxt = _pole_tops[i + 1]
		else:
			# Past the nearest pole: carry on up and out of view, as if to
			# a pole behind the camera.
			var lift := Vector2(-w * 0.35, -hy * 1.2)
			nxt = [a[0] + lift, a[1] + lift, a[2] + lift, a[3] * 3.0]
		for k in 3:
			var p0: Vector2 = a[k]
			var p1: Vector2 = nxt[k]
			var sag: float = 70.0 * (float(a[3]) + float(nxt[3])) * 0.5 * 4.0
			var pts := PackedVector2Array()
			for q in 13:
				var u := q / 12.0
				pts.append(p0.lerp(p1, u) + Vector2(0, sin(u * PI) * sag))
			draw_polyline(pts, col, clampf(float(a[3]) * 6.0, 1.0, 2.5), true)


# ---------------------------------------------------------------- sky and road

## hy is the horizon's screen height. Everything below it gets painted over
## by grass and road.
func _draw_sky(w: float, hy: float) -> void:
	# draw_polygon takes one colour per corner and blends between them, which
	# gives smooth gradients without any image files.
	var x0 := -w * 0.3
	var x1 := w * 1.3
	_grad_rect(x0, -w * 0.2, x1, hy * 0.55, SKY_TOP.darkened(0.08), SKY_TOP)
	_grad_rect(x0, hy * 0.55, x1, hy + 1, SKY_TOP, SKY_LOW)
	draw_rect(Rect2(x0, hy, x1 - x0, get_viewport_rect().size.y - hy + w * 0.2), GRASS_B)
	# Sun and far hills slide sideways in bends, at different speeds (parallax).
	var drift := fposmod(_sky_scroll(), 1.0)
	var u := minf(w, hy * 2.0)
	var sun := Vector2(fposmod(w * 0.75 - drift * w * 0.4, w), hy * 0.45)
	_sun = sun
	for i in 7:
		draw_circle(sun, u * (0.06 + 0.035 * (7 - i)), Color(1.0, 0.92, 0.65, 0.05))   # glow
	draw_circle(sun, u * 0.06, Color("fff3c4"))
	draw_circle(sun, u * 0.045, Color("fffbe8"))
	_hills(w, hy, drift * 0.5, hy - u * 0.05, u * 0.07, Color("e8a76b"), 5)
	_hills(w, hy, drift, hy - u * 0.01, u * 0.05, Color("c98a5a"), 7)


var _scroll := 0.0
var _last_z := 0.0

func _sky_scroll() -> float:
	var p = race.player
	var dz: float = p.z - _last_z
	_last_z = p.z
	if absf(dz) < 2000.0:
		_scroll += race.track.curve_at(p.z) * dz * 0.0000025
	return _scroll


func _hills(w: float, hy: float, off: float, base_y: float, amp: float, col: Color, n: int) -> void:
	var pts := PackedVector2Array([Vector2(-w * 0.3, hy + 2)])
	for j in 49:
		var fx := -0.3 + j / 30.0
		var u := (fx + off) * n
		var y := base_y - (absf(sin(u * PI)) * 0.7 + 0.3 * sin(u * 2.7)) * amp
		pts.append(Vector2(fx * w, y))
	pts.append(Vector2(w * 1.3, hy + 2))
	var cols := PackedColorArray()
	for q in pts.size():
		pts[q].y = minf(pts[q].y, hy + 2)
		# Ridges catch the low sun; the feet of the hills sink into haze.
		var f := clampf((hy - pts[q].y) / maxf(amp * 1.2, 1.0), 0.0, 1.0)
		cols.append(col.lerp(SKY_LOW, 0.45).lerp(col.lightened(0.12), f))
	draw_polygon(pts, cols)


func _grad_rect(x0: float, y0: float, x1: float, y1: float, top: Color, bottom: Color) -> void:
	draw_polygon(PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)]),
			PackedColorArray([top, top, bottom, bottom]))


## How hazy segment n is: nothing up close, thickening towards the horizon.
## Far things fading into the sky colour is one of the strongest depth cues.
func _haze(n: int) -> float:
	return 0.85 * pow(float(n) / DRAW_SEGS, 1.4)


func _draw_segment(w: float, a: Dictionary, b: Dictionary, seg: int, n: int) -> void:
	var alt := (seg / 3) % 2 == 0
	var fog := SKY_LOW
	var ha := _haze(n)        # near edge
	var hb := _haze(n + 1)    # far edge: blending the two gives smooth haze
	var grass: Color = GRASS_A if alt else GRASS_B
	# Grass band, wider than the screen so the camera roll never shows an edge.
	draw_polygon(PackedVector2Array([Vector2(-w * 0.3, a.y + 1), Vector2(-w * 0.3, b.y), Vector2(w * 1.3, b.y), Vector2(w * 1.3, a.y + 1)]),
			PackedColorArray([grass.lerp(fog, ha), grass.lerp(fog, hb), grass.lerp(fog, hb), grass.lerp(fog, ha)]))
	_gquad(a, b, 1.35, 0.0, DIRT_A if alt else DIRT_B, ha, hb)
	# A low kerb: a darker lip just inside the dirt, so the road reads as raised.
	# Far away it is thinner than a pixel, so skip it (the same goes for the
	# other details below: drawing costs time, especially in the browser).
	if n < 110:
		_gquad(a, b, 1.06, 0.0, Color("6b655e"), ha, hb)
	_gquad(a, b, 1.0, 0.0, ROAD_A if alt else ROAD_B, ha, hb)
	# Worn wheel tracks: smoother, slightly darker strips where everyone rides.
	if n < 70:
		for o in [-0.35, 0.35]:
			_gquad(a, b, 0.09, o, Color(0.42, 0.41, 0.4, 0.35), ha, hb)
	if alt and n < 110:
		_gquad(a, b, 0.025, 0.0, LINE, ha, hb)
	# Patchy repairs: every few segments a darker tar patch, off-centre.
	if seg % 11 == 0:
		_gquad(a, b, 0.15, 0.45 if seg % 2 == 0 else -0.5, Color(0.3, 0.29, 0.28, 0.25), ha, hb)
	if n < 45:
		_texture(a, b, seg, w)


## Fake detail on nearby road and grass: grit specks, a crack now and then,
## and grass tufts. A hash of the segment number places them, so they stay put
## from frame to frame.
func _texture(a: Dictionary, b: Dictionary, seg: int, w: float) -> void:
	var fade := clampf(a.w / 300.0, 0.0, 1.0)   # thin out as the road narrows
	if fade < 0.05:
		return
	for i in 7:
		var u := _hash(seg * 13 + i) * 2.0 - 1.0
		var v := _hash(seg * 31 + i * 7)
		var y: float = lerpf(a.y, b.y, v)
		var rw: float = lerpf(a.w, b.w, v)
		var x: float = lerpf(a.x, b.x, v) + u * rw * 0.95
		var sz := maxf(rw * (0.006 + 0.006 * _hash(seg + i)), 1.0)
		var light := i % 3 == 0
		draw_rect(Rect2(x, y, sz * 1.6, sz * 0.6), Color(1, 1, 1, 0.16 * fade) if light else Color(0, 0, 0, 0.18 * fade))
	if seg % 7 == 3:
		# A hairline crack wandering across a lane.
		var pts := PackedVector2Array()
		var u0 := _hash(seg) * 1.2 - 0.6
		for j in 6:
			var v := j / 5.0
			var rw: float = lerpf(a.w, b.w, v)
			pts.append(Vector2(lerpf(a.x, b.x, v) + (u0 + (_hash(seg * 5 + j) - 0.5) * 0.08) * rw + j * rw * 0.03, lerpf(a.y, b.y, v)))
		draw_polyline(pts, Color(0.15, 0.13, 0.12, 0.45 * fade), maxf(a.w * 0.004, 1.0), true)
	for i in 6:
		var side := -1.0 if i % 2 == 0 else 1.0
		var v := _hash(seg * 17 + i)
		var rw: float = lerpf(a.w, b.w, v)
		var x: float = lerpf(a.x, b.x, v) + side * rw * (1.45 + 1.6 * _hash(seg * 3 + i))
		var y: float = lerpf(a.y, b.y, v)
		var hgt := rw * 0.03
		var c := Color(0.25, 0.45, 0.12, 0.6 * fade)
		draw_line(Vector2(x, y), Vector2(x - hgt * 0.4, y - hgt), c, maxf(rw * 0.004, 1.0))
		draw_line(Vector2(x, y), Vector2(x + hgt * 0.1, y - hgt * 1.2), c, maxf(rw * 0.004, 1.0))
		draw_line(Vector2(x, y), Vector2(x + hgt * 0.5, y - hgt * 0.9), c, maxf(rw * 0.004, 1.0))


static func _hash(i: int) -> float:
	return fposmod(sin(float(i) * 12.9898) * 43758.5453, 1.0)


## A road-shaped strip between two projected edges, `half` road-widths wide,
## shifted sideways by `off`, hazed separately at its near and far edge.
func _gquad(a: Dictionary, b: Dictionary, half: float, off: float, c: Color, ha: float, hb: float) -> void:
	var w1: float = a.w * half
	var w2: float = b.w * half
	if a.y - b.y < 0.5 or w1 < 0.3:
		return   # a strip thinner than a pixel can't be triangulated
	var x1: float = a.x + a.w * off
	var x2: float = b.x + b.w * off
	var ca := Color(c.lerp(SKY_LOW, ha), c.a)
	var cb := Color(c.lerp(SKY_LOW, hb), c.a)
	draw_polygon(PackedVector2Array([Vector2(x1 - w1, a.y), Vector2(x2 - w2, b.y), Vector2(x2 + w2, b.y), Vector2(x1 + w1, a.y)]),
			PackedColorArray([ca, cb, cb, ca]))


func _quad(x1: float, y1: float, w1: float, x2: float, y2: float, w2: float, c: Color) -> void:
	if y1 - y2 < 0.5 or w1 < 0.3:
		return   # a strip thinner than a pixel can't be triangulated
	draw_colored_polygon(PackedVector2Array([
		Vector2(x1 - w1, y1), Vector2(x2 - w2, y2), Vector2(x2 + w2, y2), Vector2(x1 + w1, y1)]), c)


# ---------------------------------------------------------------- sprites

## Groups everything drawable by the segment it stands on, so the far-to-near
## pass can paint each group right after its strip of road.
func _sprite_buckets(base: int, proj: Array, cam_z: float) -> Dictionary:
	var out := {}
	var now: float = maxf(race.t, 0.0)
	for n in DRAW_SEGS:
		var seg: int = base + n
		if seg < race.track.props.size():
			for pr in race.track.props[seg]:
				_bucket(out, n, {"kind": pr[0], "x": pr[1], "text": pr[2], "n": n, "f": 0.0, "proj": proj, "seed": seg})
	for hz in race.hazards:
		if hz.taken:
			continue
		var z: float = hz.z_at(now)
		var n := int(floor(z / Track.SEG_LEN)) - base
		if n >= 0 and n < DRAW_SEGS:
			_bucket(out, n, {"kind": hz.kind, "x": hz.x_at(now), "n": n,
				"f": fposmod(z, Track.SEG_LEN) / Track.SEG_LEN, "proj": proj, "hz": hz})
	var others: Array = race.riders.slice(1)
	if race.aunty:
		others.append(race.aunty)
	for r in others:
		var n := int(floor(r.z / Track.SEG_LEN)) - base
		if n >= 1 and n < DRAW_SEGS and r.z > cam_z + 520.0:
			_bucket(out, n, {"kind": "rider", "x": r.x, "n": n,
				"f": fposmod(r.z, Track.SEG_LEN) / Track.SEG_LEN, "proj": proj, "rider": r})
	return out


func _bucket(out: Dictionary, n: int, spr: Dictionary) -> void:
	if not out.has(n):
		out[n] = []
	out[n].append(spr)


func _draw_sprite(spr: Dictionary) -> void:
	var proj: Array = spr.proj
	var a: Dictionary = proj[spr.n]
	var b: Dictionary = proj[mini(spr.n + 1, proj.size() - 1)]
	var f: float = spr.f
	var s: float = lerpf(a.s, b.s, f)              # screen pixels per world unit
	var road_w: float = lerpf(a.w, b.w, f)
	var cx: float = lerpf(a.x, b.x, f) + road_w * float(spr.x)
	var cy: float = lerpf(a.y, b.y, f)
	if s < 0.004:
		return   # a speck on the horizon
	var pos := Vector2(cx, cy)
	var t: float = race.t
	if String(spr.kind) == "line_pole":
		# Remember where the insulators are on screen, to string wires later.
		_pole_tops.append([Sprites.P(pos, s, -150, 888), Sprites.P(pos, s, 0, 888), Sprites.P(pos, s, 150, 888), s])
	match String(spr.kind):
		"rider":
			Sprites.rider(self, pos, s, spr.rider, t)
			Sprites.fight_fx(self, pos, s, spr.rider, t, _font)
			_bubble_spots.append([spr.rider, pos, s])
		"pothole", "puddle", "breaker":
			Sprites.road_mark(self, pos, s, String(spr.kind), road_w)
		"billboard":
			Sprites.billboard(self, pos, s, String(spr.text), _font)
		"finish":
			Sprites.finish_banner(self, pos, s, road_w, _font)
		_:
			var facing := 1.0
			if spr.has("hz"):
				facing = spr.hz.facing(maxf(t, 0.0))
			Sprites.thing(self, pos, s, String(spr.kind), t, facing, int(spr.get("seed", 0)))


func _bubble(anchor: Vector2, text: String, col: Color) -> void:
	# Readable on phones and in 1080p recordings: scale with the screen.
	var vs := get_viewport_rect().size
	var fs := int(clampf(minf(vs.x, vs.y) / 27.0, 22.0, 44.0))
	var tw := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var box := Rect2(anchor.x - tw * 0.5 - 14, anchor.y - fs * 2.4, tw + 28, fs * 1.8)
	var vw := get_viewport_rect().size.x
	box.position.x = clampf(box.position.x, 8.0, vw - box.size.x - 8.0)
	# Stack upwards past any bubble already on screen.
	var moved := true
	while moved:
		moved = false
		for other in _bubble_boxes:
			if box.grow(4).intersects(other):
				box.position.y = other.position.y - box.size.y - 8
				moved = true
	_bubble_boxes.append(box)
	draw_colored_polygon(PackedVector2Array([Vector2(anchor.x - 10, box.end.y - 1),
		Vector2(anchor.x + 10, box.end.y - 1), Vector2(anchor.x, box.end.y + 14)]), col)
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(14)
	sb.set_border_width_all(3)
	sb.border_color = Color("3a2a1a")
	draw_style_box(sb, box)
	draw_string(_font, Vector2(box.position.x + 14, box.position.y + fs * 1.27), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("3a2a1a"))
