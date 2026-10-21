extends RefCounted
## Every picture in the game, drawn with shapes in code (no image files).
##
## Each function gets a CanvasItem to draw on, `pos` (the screen point where
## the thing touches the road) and `s` (screen pixels per world unit at that
## distance). Inside, shapes are laid out in world units with y pointing UP
## from the road, and P() turns them into screen points. So one drawing works
## at every distance: far buffaloes are just small buffaloes.

const INK := Color("3a2a1a")
const SKIN := Color("c68642")
const SKIN_DARK := Color("a86b32")
const DHOTI := Color("fbfbf2")
const STEEL := Color("c9ccd1")
const TYRE := Color("2b2b2b")

## Set by the renderer before each sprite: how hazy it is (0 near, 1 at the
## horizon), where the vanishing point is, and depth_k, which turns a sprite's
## scale back into its distance (z = depth_k / s). box() uses those to draw
## real side walls and rooftops that shrink towards the horizon.
static var fog := 0.0
static var fog_col := Color("ffe2a8")
static var vp := Vector2.ZERO
static var depth_k := 1.0


## A colour faded into the evening haze by the current fog amount.
static func fc(c: Color) -> Color:
	return Color(c.lerp(fog_col, fog), c.a)


## Where a point on the front of an object would appear if pushed `d` world
## units further away: it slides towards the vanishing point.
static func back(pt: Vector2, s: float, d: float) -> Vector2:
	var z := depth_k / s
	return vp + (pt - vp) * (z / (z + d))


## A solid box: front face, plus the side wall that faces the road and the
## top (we look down on anything shorter than the camera). x, y is the front
## face's bottom-left corner in world units, d is how deep the box is.
static func box(ci: CanvasItem, pos: Vector2, s: float, x: float, y: float, w: float, h: float, d: float, c: Color, top := true) -> void:
	var bl := P(pos, s, x, y)
	var br := P(pos, s, x + w, y)
	var tl := P(pos, s, x, y + h)
	var tr := P(pos, s, x + w, y + h)
	# The side we can see is the one nearer the middle of the screen.
	if bl.x > vp.x:
		_face(ci, [bl, tl, back(tl, s, d), back(bl, s, d)], c.darkened(0.3))
	elif br.x < vp.x:
		_face(ci, [br, tr, back(tr, s, d), back(br, s, d)], c.darkened(0.3))
	if top and tl.y > vp.y:
		_face(ci, [tl, tr, back(tr, s, d), back(tl, s, d)], c.lightened(0.18))
	# Front face: brighter at the top where the low sun hits, darker at the
	# foot where the ground shades it.
	gface(ci, [tl, tr, br, bl], [c.lightened(0.1), c.lightened(0.1), c.darkened(0.15), c.darkened(0.15)])


## A polygon with one colour per corner, blended smoothly (draw_polygon).
static func gface(ci: CanvasItem, pts: Array, cols: Array) -> void:
	var out := PackedVector2Array(pts)
	var cs := PackedColorArray()
	for c in cols:
		cs.append(fc(c))
	if absf((out[2] - out[0]).cross(out[3] - out[1])) < 2.0:
		return
	ci.draw_polygon(out, cs)


## Like poly(), in world units, with a colour per corner.
static func gpoly(ci: CanvasItem, pos: Vector2, s: float, pts: Array, cols: Array) -> void:
	if s < 0.01:
		return
	var out: Array = []
	for q in pts:
		out.append(P(pos, s, q[0], q[1]))
	gface(ci, out, cols)


## A soft shadow: a few stacked, faint ellipses, nudged away from the sun
## (the sun sits ahead and to the right, so shadows fall back and left).
static func shadow(ci: CanvasItem, pos: Vector2, s: float, rx: float, ry: float) -> void:
	for i in 4:
		var k := 1.0 - i * 0.18
		ellipse(ci, pos, s, -rx * 0.18, -ry * 0.25, rx * (k + 0.25), ry * (k + 0.25), Color(0.15, 0.08, 0.02, 0.09))


## Dust kicked up behind the back wheel. More of it on the dirt verge.
static func dust(ci: CanvasItem, pos: Vector2, s: float, r, t: float, dirt: bool) -> void:
	var amount: float = clampf(r.speed / 5600.0, 0.0, 1.2) * (2.0 if dirt else 0.6)
	if amount < 0.15 or r.is_down():
		return
	s *= 1.3
	for i in 6:
		var f := fposmod(t * 2.5 + i / 6.0, 1.0)
		var side := -1.0 if i % 2 == 0 else 1.0
		var x := side * (30.0 + f * 120.0)
		var y := 10.0 + f * 70.0
		var rad := 20.0 + f * 60.0
		ellipse(ci, pos + Vector2(0, f * 40.0 * s), s, x, y, rad, rad * 0.7,
				Color(0.85, 0.7, 0.5, 0.22 * amount * (1.0 - f)))


static func _face(ci: CanvasItem, pts: Array, c: Color) -> void:
	var out := PackedVector2Array(pts)
	var area := 0.0
	for i in out.size():
		var a: Vector2 = out[i]
		var b: Vector2 = out[(i + 1) % out.size()]
		area += a.x * b.y - b.x * a.y
	if absf(area) < 2.0:
		return   # edge-on: nothing to see, and it would fail to triangulate
	ci.draw_colored_polygon(out, fc(c))


## Tilt (radians) applied around `pos` to everything drawn through P(). The
## rider sets it to lean the whole cycle: rocking with the pedals, leaning
## into turns, and wobbling after a hit.
static var tilt := 0.0


static func P(pos: Vector2, s: float, x: float, y: float) -> Vector2:
	var v := Vector2(x, -y) * s
	if tilt != 0.0:
		v = v.rotated(tilt)
	return pos + v


static func rect(ci: CanvasItem, pos: Vector2, s: float, x: float, y: float, w: float, h: float, c: Color) -> void:
	# x, y: bottom-left corner in world units.
	if tilt == 0.0:
		ci.draw_rect(Rect2(P(pos, s, x, y + h), Vector2(w, h) * s), fc(c))
	elif w * s >= 0.5 and h * s >= 0.5:
		ci.draw_colored_polygon(PackedVector2Array([P(pos, s, x, y), P(pos, s, x + w, y),
			P(pos, s, x + w, y + h), P(pos, s, x, y + h)]), fc(c))


static func circ(ci: CanvasItem, pos: Vector2, s: float, x: float, y: float, r: float, c: Color) -> void:
	ci.draw_circle(P(pos, s, x, y), maxf(r * s, 0.5), fc(c))


static func line(ci: CanvasItem, pos: Vector2, s: float, x1: float, y1: float, x2: float, y2: float, width: float, c: Color) -> void:
	ci.draw_line(P(pos, s, x1, y1), P(pos, s, x2, y2), fc(c), maxf(width * s, 1.0), true)


static func poly(ci: CanvasItem, pos: Vector2, s: float, pts: Array, c: Color) -> void:
	var out := PackedVector2Array()
	for q in pts:
		out.append(P(pos, s, q[0], q[1]))
	if s < 0.01 or out.size() < 3:
		return   # too small to see; also avoids degenerate triangles
	var box := Rect2(out[0], Vector2.ZERO)
	for q in out:
		box = box.expand(q)
	if box.size.x < 1.5 or box.size.y < 1.5:
		return   # a sliver under a pixel and a half: skip it, it can't triangulate
	ci.draw_colored_polygon(out, fc(c))


static func ellipse(ci: CanvasItem, pos: Vector2, s: float, x: float, y: float, rx: float, ry: float, c: Color) -> void:
	if minf(rx, ry) * s < 0.5:
		return
	var out := PackedVector2Array()
	for i in 18:
		var a := TAU * i / 18.0
		out.append(P(pos, s, x + cos(a) * rx, y + sin(a) * ry))
	ci.draw_colored_polygon(out, fc(c))


static func text(ci: CanvasItem, pos: Vector2, s: float, x: float, y: float, width: float, size: float, msg: String, c: Color, font: Font) -> void:
	var fs := int(size * s)
	if fs < 7:
		return
	ci.draw_string(font, P(pos, s, x, y), msg, HORIZONTAL_ALIGNMENT_CENTER, width * s, fs, fc(c))


# ---------------------------------------------------------------- riders

## A cyclist seen from behind. Works for Chacha, the rivals and the aunty.
static func rider(ci: CanvasItem, pos: Vector2, s: float, r, t: float) -> void:
	s *= 1.3   # cartoon riders are drawn a bit larger than life
	shadow(ci, pos, s, 110, 24)
	if r.look == "aunty":
		_aunty(ci, pos, s, r, t)
		return
	if r.is_down():
		_fallen(ci, pos, s, r, t)
		return
	# How the cycle moves under him. All of it tilts around the tyre's contact
	# with the road, like a real bike:
	#  - each pedal stroke rocks it a little (more when he's straining),
	#  - it leans into the direction he is steering,
	#  - a hit makes it wobble: a fast swing back and forth that dies away.
	var effort: float = 1.6 if r.panting else (1.0 if r.speed > 300.0 else 0.0)
	var rock: float = sin(r.pedal_phase) * 0.035 * effort
	var wob: float = sin(t * 21.0) * r.wobble * 0.45
	tilt = rock + r.lean + wob
	# Weight shifts down onto each pedal: the body bobs twice per crank turn.
	var bob: float = absf(sin(r.pedal_phase)) * 6.0 * effort
	var p := pos
	var b := pos + Vector2(0, bob * s * 0.5)   # body (bobs); the cycle stays put

	# Far-away riders: the detailed drawing is wasted below a few pixels per
	# body part, so draw a simple silhouette instead (also much cheaper).
	var detailed := s > 0.12
	_bike_rear(ci, p, s, r, detailed)
	_legs(ci, p, b, s, r, detailed)
	_handlebar(ci, p, s, r, detailed)
	if r.look == "dhoti":
		_chacha_body(ci, b, s, r, t, detailed)
	else:
		_rival_body(ci, b, s, r, detailed)
	_arms(ci, b, s, r, detailed)
	_head(ci, b, s, r, t, detailed)
	if r.look == "selfie" and r.swing <= 0.0:
		line(ci, b, s, 60, 270, 120, 470, 5, Color("333333"))
		rect(ci, b, s, 104, 466, 34, 50, Color("222222"))
	if r.boost > 0.0:
		for i in 4:
			var yy := 120.0 + i * 70.0
			line(ci, p, s, -150 - i * 10, yy, -110, yy, 6, Color(1, 0.6, 0.1, 0.7))
			line(ci, p, s, 110, yy, 150 + i * 10, yy, 6, Color(1, 0.6, 0.1, 0.7))
	if r.panting:
		var drop := fposmod(t * 1.5, 1.0)
		circ(ci, b, s, 46, 400 - drop * 60, 7, Color(0.4, 0.7, 1, 0.8))
		circ(ci, b, s, -50, 390 - fposmod(drop + 0.5, 1.0) * 60, 6, Color(0.4, 0.7, 1, 0.8))
	if r.bell > 0.0:
		for i in 3:
			var rr: float = 20.0 + (0.9 - r.bell) * 120.0 + i * 18.0
			ci.draw_arc(P(p, s, 70, 282), rr * s, -1.2, 1.2, 10, Color(1, 0.85, 0.2, r.bell), maxf(3.0 * s, 1.0))
	tilt = 0.0


# ---------------------------------------------------------------- rider parts
# Ink outlines are what make cartoon art read as finished: every main shape
# gets a dark edge. ink() is the line width in pixels for the current size.

static func ink(s: float) -> float:
	return clampf(3.2 * s * 4.0, 1.0, 3.5)


## A filled polygon with an ink outline (world units, y up).
static func opoly(ci: CanvasItem, pos: Vector2, s: float, pts: Array, c: Color, outline := true) -> void:
	poly(ci, pos, s, pts, c)
	if not outline or s < 0.05:
		return
	var out := PackedVector2Array()
	for q in pts:
		out.append(P(pos, s, q[0], q[1]))
	out.append(out[0])
	ci.draw_polyline(out, fc(INK), ink(s), true)


static func ocirc(ci: CanvasItem, pos: Vector2, s: float, x: float, y: float, r: float, c: Color) -> void:
	if s >= 0.05:
		circ(ci, pos, s, x, y, r + 1.6 / s * 0.5 * ink(s) / 1.0 * 0.5, INK)
	circ(ci, pos, s, x, y, r, c)


## A limb: a thick line with an ink edge and rounded ends.
static func limb(ci: CanvasItem, pos: Vector2, s: float, a: Vector2, b: Vector2, w: float, c: Color, outline := true) -> void:
	if outline and s >= 0.05:
		line(ci, pos, s, a.x, a.y, b.x, b.y, w + ink(s) * 2.0 / s, INK)
		circ(ci, pos, s, b.x, b.y, w * 0.5 + ink(s) / s, INK)
	line(ci, pos, s, a.x, a.y, b.x, b.y, w, c)
	circ(ci, pos, s, a.x, a.y, w * 0.5, c)
	circ(ci, pos, s, b.x, b.y, w * 0.5, c)


## Two-bone leg (or arm): where the knee goes, given hip, foot and the two
## bone lengths. Two circles (radius thigh around the hip, radius shin around
## the foot) meet at two points; `bend` picks the one on that side.
static func knee_ik(hip: Vector2, foot: Vector2, l1: float, l2: float, bend: float) -> Vector2:
	var d := hip.distance_to(foot)
	d = clampf(d, absf(l1 - l2) + 0.01, l1 + l2 - 0.01)
	var a := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var h := sqrt(maxf(l1 * l1 - a * a, 0.0))
	var dir := (foot - hip).normalized()
	var mid := hip + dir * a
	var perp := Vector2(-dir.y, dir.x) * bend
	return mid + perp * h


## The cycle seen from behind: tyre, mudguard, reflector, carrier and load,
## and a sprung leather saddle (the classic roadster's coil springs).
static func _bike_rear(ci: CanvasItem, p: Vector2, s: float, r, detailed: bool) -> void:
	# Tyre: dark rubber with a worn, shiny tread down the middle.
	opoly(ci, p, s, [[-12, 4], [12, 4], [12, 150], [-12, 150]], TYRE, detailed)
	if detailed:
		line(ci, p, s, 3, 12, 3, 140, 3, Color("4a4a4a"))
		circ(ci, p, s, 0, 75, 9, Color("b8bcc2"))             # hub peeking out
	# Mudguard: a black steel arch over the top of the tyre.
	opoly(ci, p, s, [[-17, 115], [17, 115], [19, 160], [14, 172], [-14, 172], [-19, 160]], Color("1f1f1f"), detailed)
	ocirc(ci, p, s, 0, 132, 8, Color("e63946"))                # reflector
	if detailed:
		circ(ci, p, s, 2, 135, 3, Color(1, 1, 1, 0.6))
	# Milk cans hang either side of the wheel.
	if r.look == "cans":
		for side in [-1.0, 1.0]:
			opoly(ci, p, s, [[side * 58 - 30, 40], [side * 58 + 30, 40], [side * 58 + 30, 160], [side * 58 - 30, 160]], STEEL, detailed)
			rect(ci, p, s, side * 58 - 22, 160, 44, 14, Color("9aa0a6"))
			line(ci, p, s, side * 58, 174, side * 20, 190, 4, Color("777777"))
	# Carrier: silver struts from the hub up to a flat rack.
	if detailed:
		for side in [-1.0, 1.0]:
			line(ci, p, s, side * 10, 80, side * 40, 165, 4, Color("9aa0a6"))
	opoly(ci, p, s, [[-48, 160], [48, 160], [48, 170], [-48, 170]], Color("8d9399"), detailed)
	_cargo(ci, p, s, r.look)
	# Saddle: brown leather, wide at the back, on two coil springs.
	if detailed:
		for side in [-1.0, 1.0]:
			var x: float = side * 16.0
			for k in 4:
				line(ci, p, s, x - 6, 188 + k * 5, x + 6, 191 + k * 5, 3, Color("9aa0a6"))
	opoly(ci, p, s, [[-30, 206], [30, 206], [26, 222], [-26, 222]], Color("5a3a22"), detailed)
	if detailed:
		line(ci, p, s, -22, 218, 22, 218, 2, Color("7a5434"))


## Legs that really pedal. The feet go round on the pedals (from behind, up
## and down), and a two-bone solver puts each knee where thigh and shin meet:
## an old man's knees splay outwards. The hips ride on the bobbing body.
static func _legs(ci: CanvasItem, p: Vector2, b: Vector2, s: float, r, detailed: bool) -> void:
	var ph: float = r.pedal_phase
	var off: Vector2 = (b - p) / s * Vector2(1, -1)   # the body's bob, in world units
	var dhoti: bool = r.look == "dhoti"
	var cloth: Color = DHOTI if dhoti else r.shirt.darkened(0.55)
	var knees := []
	for side in [-1.0, 1.0]:
		var a: float = ph + (0.0 if side < 0.0 else PI)
		var hip := Vector2(side * 18, 212) + off
		var foot := Vector2(side * 44, 72 + 34 * sin(a))
		# From behind, a knee mostly comes up towards you as the pedal rises,
		# with only a little outward splay: high pedal = knee near hip height
		# and a short-looking shin; low pedal = leg nearly straight.
		var ext := clampf((hip.y - foot.y - 100.0) / 76.0, 0.0, 1.0)
		var knee := Vector2(side * (24.0 + 10.0 * (1.0 - ext)) + off.x * 0.0,
			lerpf(hip.y - 22.0, (hip.y + foot.y) * 0.5, ext))
		knees.append(knee)
		# Crank arm and pedal under the foot.
		if detailed:
			line(ci, p, s, side * 30, 72, foot.x, foot.y, 6, Color("8d9399"))
		opoly(ci, p, s, [[foot.x - 18, foot.y - 8], [foot.x + 18, foot.y - 8], [foot.x + 18, foot.y - 1], [foot.x - 18, foot.y - 1]], Color("2b2b2b"), detailed)
		# Shin: bare and bony for Chacha, trousers for the rest.
		var shin_col: Color = SKIN if dhoti else cloth
		limb(ci, p, s, knee, foot + Vector2(0, 8), 19 if dhoti else 24, shin_col, detailed)
		if dhoti and detailed:
			line(ci, p, s, knee.x + side * 4, knee.y - 14, foot.x + side * 3, foot.y + 30, 3, SKIN_DARK)   # shin bone
		# Chappal: a brown sole with a strap, heel showing from behind.
		opoly(ci, p, s, [[foot.x - 15, foot.y - 1], [foot.x + 15, foot.y - 1], [foot.x + 13, foot.y + 7], [foot.x - 13, foot.y + 7]], Color("7a4a24"), detailed)
		if detailed:
			line(ci, p, s, foot.x - 10, foot.y + 14, foot.x + 10, foot.y + 14, 4, Color("c1121f"))
		if not dhoti:
			limb(ci, p, s, hip, knee, 30, cloth, detailed)
			if detailed:
				ellipse(ci, p, s, knee.x, knee.y, 14, 11, cloth.lightened(0.08))   # knee cap
	if dhoti:
		_dhoti(ci, p, s, knees, off, detailed)


## The dhoti: one long white cloth wrapped round the waist and legs, with the
## pleats tucked in at the back (the kachha) and a coloured border at the hem.
static func _dhoti(ci: CanvasItem, p: Vector2, s: float, knees: Array, off: Vector2, detailed: bool) -> void:
	var lk: Vector2 = knees[0]
	var rk: Vector2 = knees[1]
	var w := Vector2(0, 228) + off
	var crotch_y: float = minf(lk.y, rk.y) + 18.0
	# One piece of cloth: waist, out over each thigh, a loose hem below each
	# knee, and up between the legs to where it's gathered.
	var shape := [[w.x - 44, w.y], [w.x + 44, w.y],
		[rk.x + 26, rk.y - 4], [rk.x + 14, rk.y - 24], [rk.x - 14, rk.y - 18],
		[w.x, crotch_y],
		[lk.x + 14, lk.y - 18], [lk.x - 14, lk.y - 24], [lk.x - 26, lk.y - 4]]
	opoly(ci, p, s, shape, DHOTI.darkened(0.04), detailed)
	# Shade: the cloth is darker in the creases towards the middle.
	gpoly(ci, p, s, [[w.x - 40, w.y - 4], [w.x - 6, w.y - 4], [w.x - 4, crotch_y + 6], [lk.x - 12, lk.y - 16]],
		[DHOTI.darkened(0.1), DHOTI.darkened(0.04), DHOTI.darkened(0.18), DHOTI])
	gpoly(ci, p, s, [[w.x + 6, w.y - 4], [w.x + 40, w.y - 4], [rk.x + 12, rk.y - 16], [w.x + 4, crotch_y + 6]],
		[DHOTI, Color("fffdf4"), DHOTI, DHOTI.darkened(0.12)])
	if detailed:
		# Coloured border along each hem, and draped folds.
		line(ci, p, s, lk.x - 24, lk.y - 6, lk.x + 12, lk.y - 18, 6, Color("b5838d"))
		line(ci, p, s, rk.x + 24, rk.y - 6, rk.x - 12, rk.y - 18, 6, Color("b5838d"))
		for side in [-1.0, 1.0]:
			var k: Vector2 = rk if side > 0.0 else lk
			line(ci, p, s, w.x + side * 18, w.y - 8, k.x + side * 2, k.y - 10, 2, Color(0, 0, 0, 0.12))
			line(ci, p, s, w.x + side * 32, w.y - 8, k.x + side * 16, k.y - 4, 2, Color(0, 0, 0, 0.09))
	# The kachha: pleats gathered and tucked in at the back of the waist.
	var tuck := [[w.x - 14, w.y + 4], [w.x + 14, w.y + 4], [w.x + 10, w.y - 48], [w.x, w.y - 60], [w.x - 10, w.y - 48]]
	opoly(ci, p, s, tuck, Color("fffdf4"), detailed)
	if detailed:
		for fx in [-5.0, 0.0, 5.0]:
			line(ci, p, s, w.x + fx, w.y, w.x + fx * 0.6, w.y - 50, 1.5, Color(0, 0, 0, 0.16))
	# Waistband, rolled.
	opoly(ci, p, s, [[w.x - 44, w.y - 6], [w.x + 44, w.y - 6], [w.x + 42, w.y + 8], [w.x - 42, w.y + 8]], Color("f4efe1"), detailed)


## Wide, swept-back roadster handlebars with rubber grips, and the bell.
static func _handlebar(ci: CanvasItem, p: Vector2, s: float, r, detailed: bool) -> void:
	for side in [-1.0, 1.0]:
		line(ci, p, s, side * 28, 292, side * 62, 280, 7, Color("9aa0a6"))
		opoly(ci, p, s, [[side * 58, 271], [side * 78, 271], [side * 78, 288], [side * 58, 288]], Color("2b2b2b"), detailed)
	if detailed:
		# The bell: a chrome dome on the right bar, with a highlight.
		ocirc(ci, p, s, 46, 292, 9, Color("d9dde2"))
		circ(ci, p, s, 43, 295, 3, Color.WHITE)


## Chacha's back: bony bare shoulders, a ribbed cotton vest with the famous
## hole, a sweat patch, and the umbrella hooked on his collar.
static func _chacha_body(ci: CanvasItem, b: Vector2, s: float, r, t: float, detailed: bool) -> void:
	# Shoulders and upper back: skin, slightly hunched.
	opoly(ci, b, s, [[-34, 228], [34, 228], [44, 300], [52, 326], [40, 342], [-40, 342], [-52, 326], [-44, 300]], SKIN, detailed)
	# The vest: two straps over the shoulders, scooped at the neck.
	var vest := Color("fbfbf2")
	var pts := [[-35, 226], [35, 226], [38, 300], [32, 336], [16, 340], [10, 318], [-10, 318], [-16, 340], [-32, 336], [-38, 300]]
	gpoly(ci, b, s, [[-35, 226], [0, 226], [0, 318], [-38, 300]], [vest.darkened(0.15), vest.darkened(0.05), vest, vest.darkened(0.12)])
	gpoly(ci, b, s, [[0, 226], [35, 226], [38, 300], [0, 318]], [vest.darkened(0.04), vest, Color.WHITE, vest])
	poly(ci, b, s, [[-32, 336], [-16, 340], [-10, 318], [-38, 300]], vest.darkened(0.1))
	poly(ci, b, s, [[32, 336], [16, 340], [10, 318], [38, 300]], vest)
	if detailed:
		var out := PackedVector2Array()
		for q in pts:
			out.append(P(b, s, q[0], q[1]))
		out.append(out[0])
		ci.draw_polyline(out, fc(INK), ink(s), true)
		# Ribbed knit: fine vertical lines.
		for i in 9:
			var x := -28.0 + i * 7.0
			line(ci, b, s, x, 232, x * 1.06, 312, 1.5, Color(0, 0, 0, 0.07))
		# The hole (with a bit of skin showing) and a sweat patch.
		ellipse(ci, b, s, 16, 272, 7, 6, SKIN)
		ci.draw_arc(P(b, s, 16, 272), 7.5 * s, 0, TAU, 10, fc(Color(0, 0, 0, 0.3)), maxf(1.5 * s * 4.0, 1.0))
		ellipse(ci, b, s, -2, 300, 16, 12, Color(0.8, 0.75, 0.6, 0.25))
		# Shoulder blades.
		ci.draw_arc(P(b, s, -24, 318), 14 * s, 0.2, 2.6, 8, fc(SKIN_DARK), maxf(1.5 * s * 4.0, 1.0))
		ci.draw_arc(P(b, s, 24, 318), 14 * s, 0.5, 2.9, 8, fc(SKIN_DARK), maxf(1.5 * s * 4.0, 1.0))
	# The umbrella, hooked on his collar and hanging down his back.
	if r.swing <= 0.0 and r.weapon == "chhatri":
		var top := Vector2(26, 344)
		var tip := Vector2(46, 196)
		limb(ci, b, s, top, tip, 7, Color("1d1d1d"), detailed)
		var cone := top.lerp(tip, 0.35)
		var across := (tip - top).normalized().orthogonal() * 9.0
		opoly(ci, b, s, [[cone.x + across.x, cone.y + across.y], [tip.x, tip.y], [cone.x - across.x, cone.y - across.y]], Color("262626"), detailed)
		ci.draw_arc(P(b, s, 16, 344), 10 * s, PI, TAU, 8, fc(Color("8d5524")), maxf(5 * s, 1.0))


## A rival's back: a shirt with shading and a seam.
static func _rival_body(ci: CanvasItem, b: Vector2, s: float, r, detailed: bool) -> void:
	var body: Color = r.shirt
	opoly(ci, b, s, [[-38, 215], [38, 215], [48, 330], [30, 342], [-30, 342], [-48, 330]], body, detailed)
	gpoly(ci, b, s, [[-46, 330], [0, 336], [0, 215], [-36, 215]],
		[body.darkened(0.22), body, body.darkened(0.08), body.darkened(0.3)])
	gpoly(ci, b, s, [[0, 336], [46, 330], [36, 215], [0, 215]],
		[body, body.lightened(0.18), body.lightened(0.05), body.darkened(0.08)])
	if detailed:
		line(ci, b, s, 0, 222, 0, 334, 2, Color(0, 0, 0, 0.15))   # back seam
		opoly(ci, b, s, [[-26, 332], [26, 332], [20, 344], [-20, 344]], body.darkened(0.15), detailed)   # collar
	if r.look == "tape":
		line(ci, b, s, -30, 335, 30, 335, 7, Color("ffd23f"))
		line(ci, b, s, 28, 335, 34, 270, 7, Color("ffd23f"))


## Arms: shoulder to elbow to hand, solved like the legs so the elbows bend
## naturally, whether gripping the bars or swinging.
static func _arms(ci: CanvasItem, b: Vector2, s: float, r, detailed: bool) -> void:
	var sw: float = r.swing
	var dhoti: bool = r.look == "dhoti"
	var arm_col: Color = SKIN if dhoti else r.shirt.darkened(0.1)
	var up_w := 19.0 if dhoti else 24.0
	var lo_w := 15.0 if dhoti else 19.0
	var lower_col: Color = arm_col if dhoti else SKIN
	for side in [-1.0, 1.0]:
		var swinging: bool = sw > 0.0 and side == r.swing_side
		var shoulder := Vector2(side * 40, 324)
		# Riding: the upper arm hangs down and a little out to an elbow beside
		# the body; the forearm points forward to the grip, so from behind it
		# looks short (it's coming towards the bars, away from us).
		var elbow := shoulder + Vector2(side * 13, -30)
		var hand := Vector2(side * 66, 283)
		if swinging:
			var pose := _swing_pose(1.0 - sw / 0.35)
			elbow = shoulder + Vector2(side * pose[0].x, pose[0].y)
			hand = elbow + Vector2(side * pose[1].x, pose[1].y)
		taper(ci, b, s, shoulder, elbow, up_w, up_w * 0.78, arm_col, detailed)
		taper(ci, b, s, elbow, hand, lo_w, lo_w * 0.75, lower_col, detailed)
		ocirc(ci, b, s, shoulder.x, shoulder.y, up_w * 0.55, arm_col)       # rounded shoulder
		if dhoti and detailed:
			circ(ci, b, s, elbow.x, elbow.y, 3.5, SKIN_DARK)   # bony old elbow
		ocirc(ci, b, s, hand.x, hand.y, 9, SKIN)            # fist
		if detailed and not swinging:
			line(ci, b, s, hand.x - 6, hand.y + 3, hand.x + 6, hand.y + 3, 2, SKIN_DARK)
		if swinging:
			_weapon(ci, b, s, r.weapon, hand, side, sw, (hand - elbow).normalized())


## The swing as three key poses, blended smoothly. Each pose is
## [elbow offset from the shoulder, hand offset from the elbow], written for
## the right arm (x is mirrored for the left).
##   wind-up: elbow out and up, forearm raised with the weapon cocked back,
##   strike: the arm reaches out to the side,
##   follow-through: the arm comes down across.
static func _swing_pose(k: float) -> Array:
	var keys := [
		[Vector2(26, 8), Vector2(6, 34)],      # wind-up
		[Vector2(32, -6), Vector2(30, 12)],    # strike (elbow kept a little bent)
		[Vector2(22, -26), Vector2(20, -24)],  # follow-through
	]
	var f := clampf(k, 0.0, 1.0) * 2.0
	var i := mini(int(f), 1)
	var u := smoothstep(0.0, 1.0, f - i)
	var a: Array = keys[i]
	var c: Array = keys[i + 1]
	return [a[0].lerp(c[0], u), a[1].lerp(c[1], u)]


## A limb that narrows from width wa at a to wb at b, with an ink edge and
## rounded ends.
static func taper(ci: CanvasItem, pos: Vector2, s: float, a: Vector2, b: Vector2, wa: float, wb: float, c: Color, outline := true) -> void:
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x)
	var pts := [[a.x + n.x * wa * 0.5, a.y + n.y * wa * 0.5], [b.x + n.x * wb * 0.5, b.y + n.y * wb * 0.5],
		[b.x - n.x * wb * 0.5, b.y - n.y * wb * 0.5], [a.x - n.x * wa * 0.5, a.y - n.y * wa * 0.5]]
	if outline and s >= 0.05:
		var e := ink(s) / s
		circ(ci, pos, s, a.x, a.y, wa * 0.5 + e, INK)
		circ(ci, pos, s, b.x, b.y, wb * 0.5 + e, INK)
		poly(ci, pos, s, [[pts[0][0] + n.x * e, pts[0][1] + n.y * e], [pts[1][0] + n.x * e, pts[1][1] + n.y * e],
			[pts[2][0] - n.x * e, pts[2][1] - n.y * e], [pts[3][0] - n.x * e, pts[3][1] - n.y * e]], INK)
	poly(ci, pos, s, pts, c)
	circ(ci, pos, s, a.x, a.y, wa * 0.5, c)
	circ(ci, pos, s, b.x, b.y, wb * 0.5, c)


static func _head(ci: CanvasItem, b: Vector2, s: float, r, t: float, detailed: bool) -> void:
	# Neck, with a couple of wrinkles for Chacha.
	opoly(ci, b, s, [[-14, 336], [14, 336], [16, 362], [-16, 362]], SKIN_DARK, detailed)
	if r.look == "dhoti" and detailed:
		for k in 3:
			line(ci, b, s, -11, 344 + k * 6, 11, 345 + k * 6, 1.5, Color(0, 0, 0, 0.18))
	# Ears.
	for side in [-1.0, 1.0]:
		ocirc(ci, b, s, side * 38, 384, 10, SKIN_DARK)
		if detailed:
			circ(ci, b, s, side * 38, 384, 5, SKIN.darkened(0.25))
	# The skull from behind: an egg, lit from the upper right.
	var head := [[]]
	head.clear()
	for i in 20:
		var a := TAU * i / 20.0
		head.append([cos(a) * 36.0, 388.0 + sin(a) * 40.0])
	opoly(ci, b, s, head, SKIN, detailed)
	ellipse(ci, b, s, -12, 382, 22, 30, SKIN.darkened(0.1))
	match r.look:
		"dhoti":
			# Bald, shiny dome; a fluffy white fringe from ear to ear round the
			# back; tufts sticking out above the ears; the arms of thick glasses.
			ellipse(ci, b, s, 12, 410, 14, 9, Color(1, 1, 1, 0.45))
			ellipse(ci, b, s, 8, 414, 6, 4, Color(1, 1, 1, 0.7))
			# White hair: grey at the nape, wild tufts over the ears.
			var grey := Color("dcdad3")
			for i in 6:
				var x := -20.0 + i * 8.0
				circ(ci, b, s, x, 366.0 + absf(x) * 0.15, 4.5, grey)
			for side in [-1.0, 1.0]:
				circ(ci, b, s, side * 37, 396, 8, Color("f4f4f0"))
				circ(ci, b, s, side * 45, 402, 6, Color("f4f4f0"))
				circ(ci, b, s, side * 43, 390, 5, Color("efede8"))
			# A gamchha tied round the head, village style: off-white cotton
			# with red checks, a rolled rim, a knot at the back and a loose tail.
			# The knot is what tells you you're looking at the back of his head.
			var cloth := Color("f4f1de")
			var wrap := [[-38, 386], [-36, 404], [-28, 420], [-14, 430], [0, 433], [14, 430], [28, 420], [36, 404], [38, 386]]
			opoly(ci, b, s, wrap, cloth, detailed)
			if detailed:
				for i in 3:
					var x := -18.0 + i * 18.0
					line(ci, b, s, x, 392, x * 0.8, 426, 2, Color("c1121f"))
				line(ci, b, s, -34, 410, 34, 410, 2, Color("c1121f"))
			# Rolled rim.
			opoly(ci, b, s, [[-40, 380], [40, 380], [40, 392], [-40, 392]], cloth.darkened(0.06), detailed)
			if detailed:
				line(ci, b, s, -38, 386, 38, 386, 2, Color("c1121f"))
			# The knot, and its tail hanging down to the shoulders, swaying.
			var sway := sin(t * 3.0) * 4.0
			opoly(ci, b, s, [[4, 388], [16, 388], [22 + sway, 340], [14 + sway, 336], [8, 352]], cloth.darkened(0.04), detailed)
			if detailed:
				line(ci, b, s, 12, 384, 18 + sway, 342, 2, Color("c1121f"))
			ocirc(ci, b, s, 8, 388, 9, cloth.darkened(0.1))
			# Arms of his thick glasses over the ears.
			for side in [-1.0, 1.0]:
				line(ci, b, s, side * 46, 384, side * 31, 388, 4, INK)
		"ruler":
			ellipse(ci, b, s, 0, 392, 36, 32, Color("b0b0b0"))
		"selfie":
			ellipse(ci, b, s, 0, 398, 39, 30, Color("1d1d1d"))
			poly(ci, b, s, [[-10, 418], [0, 448], [12, 420]], Color("1d1d1d"))   # the spike
		_:
			ellipse(ci, b, s, 0, 396, 37, 30, Color("1d1d1d"))
			if detailed:
				ellipse(ci, b, s, 10, 412, 12, 5, Color(1, 1, 1, 0.12))   # hair shine


## A comic-book burst with the hit sound written on it, and a back-pain bar
## over rivals who were hit recently (so you can see who is nearly out).
static func fight_fx(ci: CanvasItem, pos: Vector2, s: float, r, t: float, font: Font) -> void:
	s *= 1.3
	if s < 0.03:
		return   # too far away to read
	if r.hit_flash > 0.0:
		var k: float = 1.0 - r.hit_flash / 0.45
		var c := P(pos, s, 0, 300)
		var rad := (90.0 + 60.0 * k) * s
		var pts := PackedVector2Array()
		for i in 16:
			var rr := rad if i % 2 == 0 else rad * 0.55
			pts.append(c + Vector2.from_angle(i * TAU / 16.0 + k) * rr)
		ci.draw_colored_polygon(pts, Color(1, 0.85, 0.1, 1.0 - k * 0.6))
		var fs := int(maxf(30.0 * s * 1.6, 12.0))
		ci.draw_string_outline(font, c + Vector2(-rad, fs * 0.35), r.hit_word, HORIZONTAL_ALIGNMENT_CENTER, rad * 2.0, fs, 6, INK)
		ci.draw_string(font, c + Vector2(-rad, fs * 0.35), r.hit_word, HORIZONTAL_ALIGNMENT_CENTER, rad * 2.0, fs, Color("e63946"))
	if not r.is_player and not r.out and r.pain > 0.0 and t - r.last_hit < 4.0:
		var bar := Rect2(P(pos, s, -70, 500), Vector2(140, 16) * s)
		ci.draw_rect(bar.grow(2), INK)
		ci.draw_rect(Rect2(bar.position, Vector2(bar.size.x * (1.0 - r.pain / 100.0), bar.size.y)), Color("4dbb5f").lerp(Color("ff4d6d"), r.pain / 100.0))


static func _cargo(ci: CanvasItem, p: Vector2, s: float, look: String) -> void:
	match look:
		"dhoti":
			# Chacha's clay pot, tied on with string, and his trusty umbrella.
			ellipse(ci, p, s, 0, 205, 40, 34, Color("b5651d"))
			rect(ci, p, s, -18, 232, 36, 10, Color("8a4b14"))
		"papers":
			rect(ci, p, s, -44, 170, 88, 60, Color("eeeeee"))
			for i in 4:
				line(ci, p, s, -40, 182 + i * 12, 40, 182 + i * 12, 2, Color("999999"))
		"kettle":
			ellipse(ci, p, s, 0, 205, 38, 34, Color("b87333"))
			line(ci, p, s, 34, 210, 62, 236, 8, Color("b87333"))
			circ(ci, p, s, 0, 244, 8, INK)
		"tiffin":
			for i in 3:
				rect(ci, p, s, -32, 170 + i * 26, 64, 24, STEEL.darkened(i * 0.06))
			line(ci, p, s, 0, 248, 0, 262, 5, Color("777777"))
		"ruler":
			rect(ci, p, s, -40, 170, 80, 40, Color("6d4c41"))    # a bag of exam papers
		"tape":
			circ(ci, p, s, 0, 196, 26, Color("ffd23f"))
		"selfie":
			rect(ci, p, s, -36, 170, 72, 46, Color("ff70a6").darkened(0.3))   # ring light box


## The weapon is held in the fist and continues the forearm's line (dir).
static func _weapon(ci: CanvasItem, p: Vector2, s: float, weapon: String, hand: Vector2, side: float, sw: float, dir := Vector2.RIGHT) -> void:
	var tip := hand + dir * 150.0
	var mid := hand.lerp(tip, 0.5)
	match weapon:
		"chhatri":
			line(ci, p, s, hand.x, hand.y, tip.x, tip.y, 12, Color("1d1d1d"))
			# The folded canopy: a slim cone around the shaft, built across it
			# (perpendicular), so it stays a proper triangle at any angle.
			var cone := hand.lerp(tip, 0.45)
			var across := (tip - hand).normalized().orthogonal() * 18.0
			poly(ci, p, s, [[tip.x, tip.y], [cone.x + across.x, cone.y + across.y],
				[cone.x - across.x, cone.y - across.y]], Color("1d1d1d"))
			ci.draw_arc(P(p, s, hand.x - side * 14, hand.y), 14 * s, 0, PI, 8, Color("6d4c41"), maxf(6 * s, 1.0))
		"akhbaar":
			line(ci, p, s, hand.x, hand.y, tip.x, tip.y, 26, Color("eeeeee"))
			line(ci, p, s, hand.x, hand.y, tip.x, tip.y, 4, Color("999999"))
		"doodh":
			line(ci, p, s, hand.x, hand.y, tip.x, tip.y, 5, Color("777777"))
			rect(ci, p, s, tip.x - 28, tip.y - 50, 56, 100, STEEL)
			rect(ci, p, s, tip.x - 20, tip.y + 50, 40, 12, Color("9aa0a6"))
		"kadchi":
			line(ci, p, s, hand.x, hand.y, tip.x, tip.y, 10, Color("9aa0a6"))
			ellipse(ci, p, s, tip.x, tip.y, 26, 18, STEEL)
		"chappal":
			# A rubber slipper, held by the heel: the most feared object in any home.
			line(ci, p, s, hand.x, hand.y, mid.x, mid.y, 8, SKIN)
			ellipse(ci, p, s, mid.x + side * 40, mid.y, 55, 22, Color("2a9d8f"))
			line(ci, p, s, mid.x + side * 20, mid.y + 10, mid.x + side * 60, mid.y + 10, 6, Color("e63946"))
		"belan":
			line(ci, p, s, hand.x, hand.y, tip.x, tip.y, 26, Color("c68b59"))
			line(ci, p, s, hand.x, hand.y, hand.lerp(tip, 0.15).x, hand.lerp(tip, 0.15).y, 12, Color("8d5524"))
			line(ci, p, s, hand.lerp(tip, 0.85).x, hand.lerp(tip, 0.85).y, tip.x, tip.y, 12, Color("8d5524"))
		"jhaadu":
			# A long broom: a thin stick and a fan of grass bristles.
			var far := hand + (tip - hand) * 1.4
			line(ci, p, s, hand.x, hand.y, far.x, far.y, 7, Color("a47148"))
			for i in 5:
				var spread := (i - 2) * 14.0
				line(ci, p, s, far.x, far.y, far.x + side * 50, far.y + spread - 10, 5, Color("e9c46a"))
		"scale":
			line(ci, p, s, hand.x, hand.y, tip.x, tip.y, 16, Color("e9c46a"))
			for i in 4:
				var m := hand.lerp(tip, 0.2 + i * 0.2)
				line(ci, p, s, m.x, m.y, m.x, m.y + 8, 3, INK)
		"ganna":
			# Sugarcane: long, green-brown, with knuckles every so often.
			var far := hand + (tip - hand) * 1.3
			line(ci, p, s, hand.x, hand.y, far.x, far.y, 16, Color("7f8c3a"))
			for i in 4:
				var m := hand.lerp(far, 0.2 + i * 0.22)
				circ(ci, p, s, m.x, m.y, 10, Color("5c6b25"))
		"lauki":
			line(ci, p, s, hand.x, hand.y, mid.x, mid.y, 10, SKIN)
			ellipse(ci, p, s, tip.x, tip.y, 60, 26, Color("7cb342"))
			ellipse(ci, p, s, tip.x + side * 10, tip.y + 8, 40, 10, Color("aed581"))
		_:
			line(ci, p, s, hand.x, hand.y, tip.x, tip.y, 10, Color("8d6e63"))


## Flat on the road, cycle on its side, stars round his head.
static func _fallen(ci: CanvasItem, pos: Vector2, s: float, r, t: float) -> void:
	var d: float = r.fall_dir
	var k := 1.0 if r.out else clampf(1.0 - r.fallen / 1.5, 0.0, 1.0)
	var slide := d * (1.0 - pow(1.0 - minf(k * 3.0, 1.0), 2.0)) * 90.0
	var p := pos + Vector2(slide * s, 0)
	var detailed := s > 0.12
	var dhoti: bool = r.look == "dhoti"
	# The cycle on its side behind him: two wheels (the top one still
	# spinning), the black frame, the saddle.
	var spin := t * 9.0
	for wx in [-d * 80.0, -d * 215.0]:
		ci.draw_arc(P(p, s, wx, 52), 50 * s, 0, TAU, 18, fc(TYRE), maxf(9 * s, 1.0))
		if detailed:
			for q in 3:
				var a2 := spin + q * PI / 3.0
				line(ci, p, s, wx + cos(a2) * 44, 52 + sin(a2) * 44, wx - cos(a2) * 44, 52 - sin(a2) * 44, 2, Color("9aa0a6"))
	opoly(ci, p, s, [[-d * 80, 52], [-d * 150, 108], [-d * 215, 52], [-d * 150, 60]], Color("1f1f1f"), detailed)
	opoly(ci, p, s, [[-d * 132, 112], [-d * 172, 112], [-d * 168, 124], [-d * 136, 124]], Color("5a3a22"), detailed)
	if dhoti and detailed:
		# His clay pot, smashed: shards and a puddle of dahi.
		ellipse(ci, p, s, -d * 300, 8, 60, 14, Color(1, 1, 1, 0.85))
		for q in 4:
			opoly(ci, p, s, [[-d * (270 + q * 22), 6], [-d * (282 + q * 22), 22 + (q % 2) * 6], [-d * (292 + q * 22), 8]], Color("b5651d"), true)
	# The rider, sitting in the road, seen from behind: hips on the ground,
	# back upright and a bit hunched, one hand rubbing the small of the back,
	# the other propping him up.
	var cx := d * 30.0
	var cloth: Color = DHOTI if dhoti else r.shirt.darkened(0.55)
	opoly(ci, p, s, [[cx - 62, 0], [cx + 62, 0], [cx + 52, 44], [cx - 52, 44]], cloth, detailed)   # seat on the road
	var top: Color = Color("fbfbf2") if dhoti else r.shirt
	opoly(ci, p, s, [[cx - 40, 40], [cx + 40, 40], [cx + 46, 140], [cx + 30, 152], [cx - 30, 152], [cx - 46, 140]], top, detailed)
	var arm: Color = SKIN if dhoti else r.shirt.darkened(0.1)
	# Rubbing the back: elbow out, hand on the lower back.
	taper(ci, p, s, Vector2(cx - d * 40, 142), Vector2(cx - d * 70, 96), 18, 14, arm, detailed)
	taper(ci, p, s, Vector2(cx - d * 70, 96), Vector2(cx - d * 18, 70), 14, 11, arm if dhoti else SKIN, detailed)
	ocirc(ci, p, s, cx - d * 18, 70, 9, SKIN)
	# Propping up: straight arm down to the road.
	taper(ci, p, s, Vector2(cx + d * 40, 142), Vector2(cx + d * 78, 10), 18, 12, arm, detailed)
	ocirc(ci, p, s, cx + d * 78, 10, 9, SKIN)
	# Head (a little tilted: dazed).
	var hc := Vector2(cx + d * 4, 186)
	opoly(ci, p, s, [[hc.x - 13, 150], [hc.x + 13, 150], [hc.x + 14, 166], [hc.x - 14, 166]], SKIN_DARK, detailed)
	var head := []
	for i in 18:
		var a3 := TAU * i / 18.0
		head.append([hc.x + cos(a3) * 34.0, hc.y + sin(a3) * 37.0])
	opoly(ci, p, s, head, SKIN, detailed)
	if dhoti:
		var wrap := [[hc.x - 36, hc.y - 2], [hc.x - 34, hc.y + 16], [hc.x - 16, hc.y + 38], [hc.x + 16, hc.y + 38], [hc.x + 34, hc.y + 16], [hc.x + 36, hc.y - 2]]
		opoly(ci, p, s, wrap, Color("f4f1de"), detailed)
		if detailed:
			line(ci, p, s, hc.x - 34, hc.y + 6, hc.x + 34, hc.y + 6, 2, Color("c1121f"))
		ocirc(ci, p, s, hc.x + 8, hc.y, 8, Color("e8e4d0"))
		for side in [-1.0, 1.0]:
			circ(ci, p, s, hc.x + side * 36, hc.y + 6, 7, Color("f4f4f0"))
	else:
		ellipse(ci, p, s, hc.x, hc.y + 8, 35, 28, Color("1d1d1d"))
	for i in 3:
		var a := t * 5.0 + i * TAU / 3.0
		_star(ci, P(p, s, hc.x + cos(a) * 55, hc.y + 54 + sin(a) * 14), 11 * s, Color("ffd23f"))
	if r.out and not r.is_player:
		# The umpire's raised finger, the universal sign for OUT.
		opoly(ci, p, s, [[hc.x - 50, 270], [hc.x + 50, 270], [hc.x + 50, 316], [hc.x - 50, 316]], Color("c1121f"), detailed)
		text(ci, p, s, hc.x - 50, 282, 100, 40, "OUT", Color.WHITE, ThemeDB.fallback_font)
	if r.is_player:
		# His glasses flew off and landed a little way away.
		ci.draw_arc(P(p, s, d * 170, 14), 12 * s, 0, TAU, 10, fc(INK), maxf(3 * s, 1.0))
		ci.draw_arc(P(p, s, d * 200, 14), 12 * s, 0, TAU, 10, fc(INK), maxf(3 * s, 1.0))
		line(ci, p, s, d * 182, 14, d * 188, 14, 3, INK)


static func _star(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	if r < 2.0:
		return
	var pts := PackedVector2Array()
	for i in 10:
		var rad := r if i % 2 == 0 else r * 0.45
		pts.append(c + Vector2.from_angle(-PI / 2.0 + i * TAU / 10.0) * rad)
	ci.draw_colored_polygon(pts, fc(col))


## Rishta Aunty on her scooty: wide pink back, flowing dupatta, giant handbag.
static func _aunty(ci: CanvasItem, pos: Vector2, s: float, r, t: float) -> void:
	var p := pos
	rect(ci, p, s, -12, 0, 24, 90, TYRE)
	poly(ci, p, s, [[-70, 60], [70, 60], [80, 170], [-80, 170]], Color("ffe1ef"))
	rect(ci, p, s, -30, 120, 60, 18, Color("e63946"))           # tail light
	rect(ci, p, s, -60, 170, 120, 22, Color("333333"))          # seat
	poly(ci, p, s, [[-50, 190], [50, 190], [56, 320], [-56, 320]], r.shirt)
	# The dupatta streams out behind her in the wind.
	var flap := sin(t * 9.0) * 20.0
	poly(ci, p, s, [[-50, 315], [50, 315], [90, 230 + flap], [60, 170 + flap], [-70, 200 - flap]], Color("ffd23f"))
	rect(ci, p, s, 60, 200, 70, 60, Color("8e44ad"))            # the handbag (photos inside)
	line(ci, p, s, 70, 260, 50, 300, 6, Color("8e44ad"))
	circ(ci, p, s, 0, 345, 15, SKIN_DARK)
	circ(ci, p, s, 0, 372, 34, SKIN)
	ellipse(ci, p, s, 0, 382, 37, 30, Color("1d1d1d"))
	circ(ci, p, s, 0, 410, 22, Color("1d1d1d"))                 # the bun
	line(ci, p, s, -70, 290, 70, 290, 7, Color("555555"))


# ---------------------------------------------------------------- road marks

static func road_mark(ci: CanvasItem, pos: Vector2, s: float, kind: String, road_w: float) -> void:
	match kind:
		"pothole":
			ellipse(ci, pos, s, 0, 0, 125, 34, Color("5e5a55"))
			ellipse(ci, pos, s, 0, -3, 98, 24, Color("2e2a26"))
			ellipse(ci, pos, s, 30, 26, 22, 10, Color("8d8a86"))   # a loose stone
		"puddle":
			ellipse(ci, pos, s, 0, 0, 180, 34, Color("6fa8dc"))
			ellipse(ci, pos, s, -40, 4, 70, 10, Color(1, 1, 1, 0.45))
		"breaker":
			# Fat yellow-and-black hump across the whole road.
			var half := road_w / s
			var n := 12
			for i in n:
				var x0 := -half + 2.0 * half * i / n
				rect(ci, pos, s, x0, 0, 2.0 * half / n + 1.0, 70, Color("ffd23f") if i % 2 == 0 else Color("222222"))


# ---------------------------------------------------------------- the rest

## seed varies the look per prop (house colours) and stays the same every frame.
static func thing(ci: CanvasItem, pos: Vector2, s: float, kind: String, t: float, facing: float, seed := 0) -> void:
	match kind:
		"tree":
			rect(ci, pos, s, -35, 0, 70, 420, Color("7a5230"))
			shadow(ci, pos, s, 300, 60)
			rect(ci, pos, s, -35, 0, 70, 420, Color("7a5230"))
			circ(ci, pos, s, 0, 560, 260, Color("3f8a2e"))
			circ(ci, pos, s, -150, 470, 170, Color("468f33"))
			circ(ci, pos, s, 160, 480, 170, Color("3a7d2a"))
			circ(ci, pos, s, 60, 620, 170, Color("5fb548"))                # sunlit side
			circ(ci, pos, s, 110, 660, 90, Color("78c95d"))
		"palm":
			line(ci, pos, s, 0, 0, 60, 700, 40, Color("8b6b3d"))
			for a in [-2.6, -1.9, -1.2, -0.5, 0.2]:
				line(ci, pos, s, 60, 700, 60 + cos(a) * 280, 700 + sin(a) * 120 + 60, 26, Color("3f8f3f"))
		"house":
			var hues := [Color("f6bd60"), Color("84a59d"), Color("f28482"), Color("a2d2ff"), Color("cdb4db")]
			var c: Color = hues[seed % hues.size()]
			shadow(ci, pos, s, 480, 70)
			box(ci, pos, s, -360, 0, 720, 520, 600, c)
			box(ci, pos, s, -380, 520, 760, 30, 640, c.darkened(0.25))
			rect(ci, pos, s, -80, 0, 160, 280, Color("6d4c41"))              # door
			rect(ci, pos, s, -280, 260, 130, 120, Color("3d5a80"))           # windows
			rect(ci, pos, s, 150, 260, 130, 120, Color("3d5a80"))
			box(ci, pos, s, 120, 550, 170, 130, 160, Color("2a2a2a"))        # the rooftop water tank
			line(ci, pos, s, -360, 640, -120, 610, 3, Color("555555"))       # washing line
			for i in 3:
				rect(ci, pos, s, -330 + i * 75, 560, 50, 70, [Color("e63946"), Color("ffd23f"), Color("4d96ff")][i])
		"line_pole":
			# A concrete pole with a crossarm and three insulators; wires
			# hang from the insulator tops (see renderer _draw_wires).
			shadow(ci, pos, s, 60, 14)
			rect(ci, pos, s, -16, 0, 32, 900, Color("8a8a8a"))
			rect(ci, pos, s, 2, 0, 14, 900, Color("9c9c9c"))
			rect(ci, pos, s, -170, 846, 340, 20, Color("6b6b6b"))
			for ix in [-150.0, 0.0, 150.0]:
				rect(ci, pos, s, ix - 8, 866, 16, 22, Color("c9d6df"))
			if seed % 3 == 0:
				rect(ci, pos, s, -60, 600, 120, 110, Color("5c6b73"))        # transformer box
		"pole":
			rect(ci, pos, s, -18, 0, 36, 900, Color("7d7d7d"))
			rect(ci, pos, s, -160, 840, 320, 22, Color("6b6b6b"))
			rect(ci, pos, s, -60, 600, 120, 110, Color("5c6b73"))            # transformer box
		"charpai":
			# A string bed by the road, with an uncle napping on it.
			for x in [-200.0, 200.0]:
				rect(ci, pos, s, x - 12, 0, 24, 120, Color("7a5230"))
			rect(ci, pos, s, -220, 110, 440, 30, Color("d4a373"))
			ellipse(ci, pos, s, 20, 170, 150, 40, Color("e9ecef"))
			circ(ci, pos, s, -150, 175, 38, SKIN)
			text(ci, pos, s, -120, 260 + fposmod(t * 30.0, 60.0), 200, 60, "z z z", INK, ThemeDB.fallback_font)
		"stall":
			box(ci, pos, s, -260, 0, 520, 260, 260, Color("8d5524"))
			for i in 6:
				poly(ci, pos, s, [[-300 + i * 100, 460], [-200 + i * 100, 460], [-200 + i * 100, 400], [-300 + i * 100, 400]],
					Color("e63946") if i % 2 == 0 else Color("fff8e7"))
			line(ci, pos, s, -280, 260, -280, 400, 10, Color("5c3d1e"))
			line(ci, pos, s, 280, 260, 280, 400, 10, Color("5c3d1e"))
			ellipse(ci, pos, s, 0, 300, 60, 40, Color("b87333"))             # the big kettle
			text(ci, pos, s, -260, 130, 520, 90, "CHAI", Color("ffd23f"), ThemeDB.fallback_font)
		"haystack":
			ellipse(ci, pos, s, 0, 120, 260, 220, Color("e9c46a"))
			ellipse(ci, pos, s, 0, 60, 280, 80, Color("d4a948"))
		"kids":
			# Street cricket: a bowler and a fielder cheering.
			for i in 2:
				var x := -120.0 + i * 200.0
				var jump := absf(sin(t * 6.0 + i)) * 30.0
				rect(ci, pos, s, x - 14, jump, 12, 90, SKIN)
				rect(ci, pos, s, x + 2, jump, 12, 90, SKIN)
				rect(ci, pos, s, x - 30, 90 + jump, 60, 90, [Color("4d96ff"), Color("f94144")][i])
				circ(ci, pos, s, x, 210 + jump, 28, SKIN)
				ellipse(ci, pos, s, x, 222 + jump, 28, 16, Color("1d1d1d"))
		"stumps":
			for i in 3:
				rect(ci, pos, s, -40 + i * 34, 0, 12, 200, Color("f1e3c6"))
			rect(ci, pos, s, -46, 198, 94, 8, Color("f1e3c6"))
		"ball":
			var bob := absf(sin(t * 8.0)) * 60.0
			ellipse(ci, pos, s, 0, 0, 22, 6, Color(0, 0, 0, 0.25))
			circ(ci, pos, s, 0, 40 + bob, 22, Color("c1121f"))
			line(ci, pos, s, -16, 40 + bob, 16, 40 + bob, 3, Color(1, 1, 1, 0.7))
		"buffalo":
			_buffalo(ci, pos, s, t, facing)
		"cow":
			_cow(ci, pos, s, t, facing, seed)
		"goats":
			_goats(ci, pos, s, t, facing)
		"hens":
			_hens(ci, pos, s, t)
		"bullock":
			_bullock_cart(ci, pos, s, t)
		"tractor":
			_tractor(ci, pos, s, t)
		"thela":
			_thela(ci, pos, s, t)
		"bricks":
			_bricks(ci, pos, s)
		"dog":
			_dog(ci, pos, s, t, facing)
		"donkey":
			_donkey_cart(ci, pos, s, t)
		"rickshaw":
			_rickshaw(ci, pos, s)
		"baraat":
			_baraat(ci, pos, s, t)
		"chai":
			var b := sin(t * 4.0) * 20.0
			circ(ci, pos, s, 0, 150 + b, 90, Color(1, 0.9, 0.5, 0.35))
			ellipse(ci, pos, s, 0, 95 + b, 70, 14, Color("f1f1f1"))
			poly(ci, pos, s, [[-45, 100 + b], [45, 100 + b], [36, 190 + b], [-36, 190 + b]], Color("fdf0d5"))
			ellipse(ci, pos, s, 0, 190 + b, 36, 10, Color("a0522d"))
			for i in 2:
				var sx := -14.0 + i * 28.0
				line(ci, pos, s, sx, 205 + b, sx + sin(t * 6.0 + i) * 10.0, 260 + b, 5, Color(1, 1, 1, 0.6))
		"ganna", "lauki":
			var b := sin(t * 4.0 + 2.0) * 20.0
			circ(ci, pos, s, 0, 160 + b, 110, Color(1, 1, 0.6, 0.3))
			if kind == "ganna":
				line(ci, pos, s, -90, 90 + b, 90, 230 + b, 20, Color("7f8c3a"))
				for i in 3:
					circ(ci, pos, s, -45 + i * 45, 125 + i * 35 + b, 12, Color("5c6b25"))
			else:
				ellipse(ci, pos, s, 0, 160 + b, 95, 40, Color("7cb342"))
				ellipse(ci, pos, s, 15, 175 + b, 60, 14, Color("aed581"))
		"jalebi":
			var b := sin(t * 4.0 + 1.0) * 20.0
			circ(ci, pos, s, 0, 150 + b, 90, Color(1, 0.6, 0.2, 0.3))
			var pts := PackedVector2Array()
			for i in 40:
				var a := i * 0.45
				var rr := 8.0 + i * 1.6
				pts.append(P(pos, s, cos(a) * rr, 150 + b + sin(a) * rr))
			ci.draw_polyline(pts, fc(Color("f77f00")), maxf(14.0 * s, 1.5), true)


static func _buffalo(ci: CanvasItem, pos: Vector2, s: float, t: float, facing: float) -> void:
	var f := facing if facing != 0.0 else 1.0
	var c := Color("2e2b29")
	shadow(ci, pos, s, 260, 34)
	var step := sin(t * 3.0) * 12.0
	for lx in [-150.0, -90.0, 90.0, 150.0]:
		rect(ci, pos, s, lx - 18, 0, 36, 140 + (step if lx > 0 else -step), c)
	ellipse(ci, pos, s, 0, 210, 220, 100, c)
	ellipse(ci, pos, s, 40, 250, 150, 45, Color("4a4542"))             # sunlit back
	ellipse(ci, pos, s, f * 235, 235, 66, 52, c)                     # head
	ellipse(ci, pos, s, f * 285, 215, 32, 26, Color("4a4542"))        # nose
	# Big swept-back horns.
	ci.draw_arc(P(pos, s, f * 215, 290), 50 * s, PI * 0.9, PI * 1.9, 10, fc(Color("d6ccc2")), maxf(16 * s, 1.0))
	circ(ci, pos, s, f * 250, 255, 7, Color.WHITE)
	line(ci, pos, s, -f * 215, 230, -f * 260, 130 + sin(t * 4.0) * 20.0, 8, c)   # tail


## A village cow, side on, standing in the road as if she owns it (she does):
## a little hump, short curved horns, a tail swishing, jaw going round.
static func _cow(ci: CanvasItem, pos: Vector2, s: float, t: float, facing: float, seed: int) -> void:
	var f := facing
	var body := Color("f3efe6") if seed % 2 == 0 else Color("c8a27c")
	shadow(ci, pos, s, 250, 34)
	for lx in [-140.0, -90.0, 90.0, 140.0]:
		rect(ci, pos, s, lx - 16, 0, 32, 150, body.darkened(0.12))
		rect(ci, pos, s, lx - 18, 0, 36, 18, Color("3a2a1a"))            # hooves
	ellipse(ci, pos, s, 0, 215, 210, 90, body)
	ellipse(ci, pos, s, -40 * f, 200, 60, 40, body.darkened(0.25))       # a patch
	ellipse(ci, pos, s, f * 120, 300, 55, 35, body.darkened(0.05))       # the hump
	ellipse(ci, pos, s, f * 230, 250, 60, 46, body)                      # head
	ellipse(ci, pos, s, f * 275, 232 + sin(t * 6.0) * 4.0, 28, 22, Color("e8b4a0"))   # chewing muzzle
	line(ci, pos, s, f * 215, 290, f * 195, 335, 9, Color("d6ccc2"))      # horns
	line(ci, pos, s, f * 245, 290, f * 262, 335, 9, Color("d6ccc2"))
	circ(ci, pos, s, f * 240, 262, 6, INK)
	var swish := sin(t * 2.5) * 40.0
	line(ci, pos, s, -f * 205, 240, -f * 230 + swish, 110, 7, body.darkened(0.2))
	circ(ci, pos, s, -f * 230 + swish, 105, 14, Color("3a2a1a"))
	# A bell on a string round her neck.
	circ(ci, pos, s, f * 195, 200, 13, Color("e9c46a"))


## A herd of goats ambling across with the herder and his stick.
static func _goats(ci: CanvasItem, pos: Vector2, s: float, t: float, facing: float) -> void:
	var f := facing if facing != 0.0 else 1.0
	shadow(ci, pos, s, 330, 30)
	var spots := [[-230.0, 0.0], [-90.0, 30.0], [60.0, -10.0], [190.0, 20.0]]
	for i in spots.size():
		var gx: float = spots[i][0]
		var hop := absf(sin(t * 7.0 + i)) * 18.0
		var c: Color = [Color("f5f5f5"), Color("6d4c41"), Color("2b2b2b"), Color("d7ccc8")][i]
		for lx in [-40.0, -20.0, 20.0, 40.0]:
			rect(ci, pos, s, gx + lx - 6, hop, 12, 70, c.darkened(0.2))
		ellipse(ci, pos, s, gx, 100 + hop, 70, 36, c)
		ellipse(ci, pos, s, gx + f * 70, 130 + hop, 26, 20, c)
		line(ci, pos, s, gx + f * 66, 148 + hop, gx + f * 50, 175 + hop, 5, Color("8d8d8d"))   # horn
		line(ci, pos, s, gx + f * 80, 115 + hop, gx + f * 84, 92 + hop, 5, c.darkened(0.3))      # beard
	# The herder behind them: kurta, headcloth, a long stick.
	var hx := -f * 330.0
	rect(ci, pos, s, hx - 18, 0, 14, 110, SKIN)
	rect(ci, pos, s, hx + 4, 0, 14, 110, SKIN)
	rect(ci, pos, s, hx - 34, 100, 68, 130, Color("e9d8a6"))
	circ(ci, pos, s, hx, 258, 28, SKIN)
	ellipse(ci, pos, s, hx, 280, 34, 16, Color("c1121f"))
	line(ci, pos, s, hx + f * 30, 200, hx + f * 90, 0, 6, Color("8d5524"))


static func _hens(ci: CanvasItem, pos: Vector2, s: float, t: float) -> void:
	for i in 3:
		var hx := -90.0 + i * 90.0
		var flap := sin(t * 18.0 + i * 2.0) * 30.0
		var hop := absf(sin(t * 9.0 + i)) * 30.0
		ellipse(ci, pos, s, hx, 50 + hop, 36, 28, Color("fefae0") if i != 1 else Color("bc6c25"))
		circ(ci, pos, s, hx + 30, 80 + hop, 15, Color("fefae0") if i != 1 else Color("bc6c25"))
		poly(ci, pos, s, [[hx + 26, 96 + hop], [hx + 34, 96 + hop], [hx + 30, 108 + hop]], Color("e63946"))  # comb
		poly(ci, pos, s, [[hx + 44, 82 + hop], [hx + 56, 78 + hop], [hx + 44, 74 + hop]], Color("f4a261"))   # beak
		line(ci, pos, s, hx - 5, 60 + hop, hx - 40, 60 + hop + flap, 12, Color(1, 1, 1, 0.85))           # a wing
	# A few loose feathers floating about.
	for i in 3:
		circ(ci, pos, s, -60 + i * 70 + sin(t * 2.0 + i) * 20.0, 150 + fposmod(t * 40.0 + i * 30.0, 90.0), 6, Color.WHITE)


## From behind: a wooden cart on two big spoked wheels, two white bullocks
## with painted horns and bells ahead, and the farmer perched on top.
static func _bullock_cart(ci: CanvasItem, pos: Vector2, s: float, t: float) -> void:
	var sway := sin(t * 3.0) * 6.0
	shadow(ci, pos, s, 230, 34)
	for bx in [-70.0, 70.0]:
		ellipse(ci, pos, s, bx, 300 + sway, 55, 40, Color("f5f5f5"))      # bullock rumps
		line(ci, pos, s, bx - 20, 340, bx - 35, 400, 10, Color("e76f51")) # painted horns
		line(ci, pos, s, bx + 20, 340, bx + 35, 400, 10, Color("2a9d8f"))
	for x in [-190.0, 190.0]:
		ci.draw_arc(P(pos, s, x, 120), 110 * s, 0, TAU, 18, fc(Color("6d4c41")), maxf(14 * s, 1.0))
		for k in 4:
			var a := k * PI / 4.0 + t * 2.0
			line(ci, pos, s, x + cos(a) * 100, 120 + sin(a) * 100, x - cos(a) * 100, 120 - sin(a) * 100, 6, Color("8d6e63"))
	box(ci, pos, s, -180, 110, 360, 110, 360, Color("a0522d"))
	ellipse(ci, pos, s, 0, 260, 150, 50, Color("d9c08c"))               # a load of hay
	rect(ci, pos, s, -30, 280, 60, 80, Color("f4f1de"))                 # farmer's back
	circ(ci, pos, s, 0, 385, 26, SKIN)
	ellipse(ci, pos, s, 0, 405, 34, 16, Color("ffffff"))                # his pagdi


## A red tractor from behind: huge rear tyres, and a trolley of sugarcane
## sticking out in every direction.
static func _tractor(ci: CanvasItem, pos: Vector2, s: float, t: float) -> void:
	var jig := sin(t * 20.0) * 3.0
	shadow(ci, pos, s, 330, 40)
	box(ci, pos, s, -280, 60, 560, 170, 700, Color("6d4c41"))           # trolley
	for i in 9:
		var cx := -260.0 + i * 65.0
		line(ci, pos, s, cx, 230, cx + (i % 3 - 1) * 30.0, 430 + (i % 2) * 40.0, 16, Color("7f8c3a"))
	for x in [-230.0, 230.0]:
		rect(ci, pos, s, x - 40, 0, 80, 130, TYRE)
	# The tractor itself pokes up beyond the load, exhaust puffing.
	box(ci, pos, s, -90, 380 + jig, 180, 120, 300, Color("c1121f"))
	line(ci, pos, s, 70, 500 + jig, 70, 600 + jig, 14, Color("333333"))
	for k in 3:
		var f := fposmod(t * 1.5 + k / 3.0, 1.0)
		circ(ci, pos, s, 70 + f * 40.0, 620 + f * 160.0, 20 + f * 40.0, Color(0.3, 0.3, 0.3, 0.35 * (1.0 - f)))
	text(ci, pos, s, -280, 130, 560, 60, "HORN OK PLEASE", Color("ffd23f"), ThemeDB.fallback_font)


## A vegetable thela: a wooden handcart heaped with produce, pushed along.
static func _thela(ci: CanvasItem, pos: Vector2, s: float, t: float) -> void:
	shadow(ci, pos, s, 170, 26)
	for x in [-120.0, 120.0]:
		rect(ci, pos, s, x - 12, 0, 24, 90, TYRE)
	box(ci, pos, s, -150, 80, 300, 40, 300, Color("8d5524"))
	var veg := [Color("e63946"), Color("7cb342"), Color("f4a261"), Color("6a4c93"), Color("7cb342")]
	for i in 7:
		circ(ci, pos, s, -110 + i * 36, 140 + (i % 2) * 16, 26, veg[i % veg.size()])
	# The vendor's back, between the handles.
	var step := sin(t * 6.0) * 6.0
	rect(ci, pos, s, -26, 120 + step, 52, 120, Color("4d96ff"))
	circ(ci, pos, s, 0, 265 + step, 26, SKIN)
	ellipse(ci, pos, s, 0, 285 + step, 30, 12, Color("2b2b2b"))


static func _bricks(ci: CanvasItem, pos: Vector2, s: float) -> void:
	shadow(ci, pos, s, 150, 24)
	for row in 3:
		for i in 4 - row:
			rect(ci, pos, s, -120 + row * 30 + i * 62, row * 32, 58, 30, Color("b5523b").lightened(0.06 * ((i + row) % 2)))


## A stray: brown, skinny, ears up, legs going like the clappers.
static func _dog(ci: CanvasItem, pos: Vector2, s: float, t: float, facing: float) -> void:
	var run := sin(t * 22.0)
	var c := Color("a47148")
	shadow(ci, pos, s, 90, 16)
	line(ci, pos, s, -40, 60, -55 + run * 20.0, 0, 9, c.darkened(0.2))
	line(ci, pos, s, 40, 60, 55 - run * 20.0, 0, 9, c.darkened(0.2))
	ellipse(ci, pos, s, 0, 75, 65, 26, c)
	circ(ci, pos, s, 60, 105, 24, c)
	poly(ci, pos, s, [[50, 125], [62, 150], [70, 122]], c.darkened(0.3))     # ear
	ellipse(ci, pos, s, 84, 98, 16, 9, c.lightened(0.2))
	circ(ci, pos, s, 96, 100, 5, INK)
	line(ci, pos, s, -62, 85, -95, 115 + run * 10.0, 7, c)                  # wagging tail


static func _donkey_cart(ci: CanvasItem, pos: Vector2, s: float, t: float) -> void:
	# From behind: two donkey ears poke up beyond a cart piled with sacks.
	var bob := absf(sin(t * 5.0)) * 10.0
	poly(ci, pos, s, [[-30, 330 + bob], [-14, 330 + bob], [-34, 430 + bob]], Color("8d8d8d"))
	poly(ci, pos, s, [[14, 330 + bob], [30, 330 + bob], [36, 430 + bob]], Color("8d8d8d"))
	for x in [-170.0, 170.0]:
		rect(ci, pos, s, x - 14, 0, 28, 170, TYRE)
	box(ci, pos, s, -190, 110, 380, 120, 380, Color("a0522d"))
	for i in 5:
		ellipse(ci, pos, s, -140 + i * 70, 260 + (i % 2) * 30, 60, 50, Color("d9c08c"))
	rect(ci, pos, s, -60, 140, 120, 40, Color("f4f1de"))
	text(ci, pos, s, -60, 150, 120, 30, "SLOW", Color("c1121f"), ThemeDB.fallback_font)


static func _rickshaw(ci: CanvasItem, pos: Vector2, s: float) -> void:
	for x in [-150.0, 150.0]:
		rect(ci, pos, s, x - 18, 0, 36, 110, TYRE)
	box(ci, pos, s, -175, 70, 350, 230, 420, Color("2a9d8f"))
	box(ci, pos, s, -160, 300, 320, 170, 380, Color("1d1d1d"))                                # canvas top
	rect(ci, pos, s, -170, 70, 340, 60, Color("ffd23f"))
	rect(ci, pos, s, -120, 330, 240, 90, Color("264653"))                                   # back window
	text(ci, pos, s, -170, 82, 340, 40, "HORN OK PLEASE", Color("c1121f"), ThemeDB.fallback_font)
	for x in [-150.0, 150.0]:
		circ(ci, pos, s, x, 160, 18, Color("e63946"))
	for i in 4:
		circ(ci, pos, s, -120 + i * 80, 470, 14, [Color("f94144"), Color("f9c74f"), Color("90be6d"), Color("577590")][i])


## The wedding procession, side on, snaking across the road: a dancing uncle,
## a drummer, the groom on a white horse, a trumpeter, another dancing uncle.
static func _baraat(ci: CanvasItem, pos: Vector2, s: float, t: float) -> void:
	ellipse(ci, pos, s, 0, 0, 370, 30, Color(0, 0, 0, 0.2))
	var xs := [-300.0, -160.0, 0.0, 160.0, 300.0]
	for i in 5:
		var x: float = xs[i]
		var hop := absf(sin(t * 7.0 + i * 1.3)) * 30.0
		if i == 2:
			# The horse, with the groom in a flower-strand veil on top.
			for lx in [-90.0, -50.0, 50.0, 90.0]:
				rect(ci, pos, s, x + lx - 12, 0, 24, 150, Color("f5f5f5"))
			ellipse(ci, pos, s, x, 200, 130, 60, Color("f5f5f5"))
			poly(ci, pos, s, [[x + 100, 220], [x + 140, 330], [x + 180, 320], [x + 140, 200]], Color("f5f5f5"))
			rect(ci, pos, s, x - 60, 200, 120, 30, Color("c1121f"))                    # saddle cloth
			poly(ci, pos, s, [[x - 30, 250], [x + 30, 250], [x + 26, 380], [x - 26, 380]], Color("fdf0d5"))
			circ(ci, pos, s, x, 410, 30, SKIN)
			rect(ci, pos, s, x - 34, 430, 68, 40, Color("ffb703"))                     # turban
			for k in 5:
				line(ci, pos, s, x - 24 + k * 12, 430, x - 24 + k * 12, 380, 4, Color("fefae0"))
			continue
		var outfit: Color = [Color("c1121f"), Color("c1121f"), Color.WHITE, Color("c1121f"), Color("8338ec")][i]
		if i == 0 or i == 4:
			outfit = Color("8338ec") if i == 4 else Color("06d6a0")
		rect(ci, pos, s, x - 22, hop, 18, 110, Color("333333"))
		rect(ci, pos, s, x + 4, hop, 18, 110, Color("333333"))
		rect(ci, pos, s, x - 38, 110 + hop, 76, 120, outfit)
		circ(ci, pos, s, x, 262 + hop, 30, SKIN)
		if i == 1:
			ellipse(ci, pos, s, x + 50, 170 + hop, 34, 40, Color("e9c46a"))           # dhol drum
		elif i == 3:
			line(ci, pos, s, x + 20, 262 + hop, x + 110, 300 + hop, 10, Color("ffd23f"))   # trumpet
		else:
			# Dancing uncle: both hands in the air, screwing in a light bulb.
			var wave := sin(t * 10.0 + i) * 30.0
			line(ci, pos, s, x - 30, 220 + hop, x - 60 + wave, 330 + hop, 14, outfit)
			line(ci, pos, s, x + 30, 220 + hop, x + 60 + wave, 330 + hop, 14, outfit)
		if i == 1 or i == 3:
			rect(ci, pos, s, x - 30, 286 + hop, 60, 26, Color("c1121f"))               # band cap


static func billboard(ci: CanvasItem, pos: Vector2, s: float, msg: String, font: Font) -> void:
	rect(ci, pos, s, -420, 0, 24, 520, Color("6d4c41"))
	rect(ci, pos, s, 396, 0, 24, 520, Color("6d4c41"))
	box(ci, pos, s, -480, 480, 960, 300, 40, Color("fff8e7"))
	rect(ci, pos, s, -480, 740, 960, 40, Color("e63946"))
	ci.draw_rect(Rect2(P(pos, s, -480, 780), Vector2(960, 300) * s), fc(INK), false, maxf(6 * s, 1.0))
	# Wrap the slogan onto up to three lines.
	var words := msg.split(" ")
	var lines: Array = [""]
	for word in words:
		var cur: String = lines[-1]
		if cur.length() + word.length() > 18 and cur != "":
			lines.append(word)
		else:
			lines[-1] = (cur + " " + word).strip_edges()
	var n := mini(lines.size(), 3)
	for i in n:
		text(ci, pos, s, -470, 700 - i * 72 - (3 - n) * 36, 940, 60, lines[i], INK, font)


static func finish_banner(ci: CanvasItem, pos: Vector2, s: float, road_w: float, font: Font) -> void:
	var half := road_w / s + 80.0
	rect(ci, pos, s, -half - 20, 0, 40, 900, Color("c68b59"))     # bamboo poles
	rect(ci, pos, s, half - 20, 0, 40, 900, Color("c68b59"))
	rect(ci, pos, s, -half, 700, half * 2.0, 180, Color("e63946"))
	text(ci, pos, s, -half, 750, half * 2.0, 130, "FINISH", Color("fff8e7"), font)
	# Marigold garlands hanging under the banner.
	for i in 16:
		var x := -half + half * 2.0 * (i + 0.5) / 16.0
		var sag := sin(float(i) / 15.0 * PI) * 60.0
		circ(ci, pos, s, x, 680 - sag, 22, Color("ff9f1c") if i % 2 == 0 else Color("ffbf69"))
