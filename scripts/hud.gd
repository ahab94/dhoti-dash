extends Control
## Everything drawn over the road: position, timer, breath and back-pain
## meters, the progress strip, the aunty mirror, the countdown, the results
## card, the race menu and the touch buttons.
##
## Most of the HUD is drawn by hand in `_draw()` (one Control that repaints
## every frame). The menus are real Buttons inside PanelContainers, because
## Buttons give us mouse, touch and keyboard focus for free.

signal retry_pressed
signal next_pressed
signal menu_pressed
signal race_chosen(index: int)

const INK := Color("3a2a1a")
const CREAM := Color("fff8e7")
const SUN := Color("ffd23f")
const BREATH := Color("4d96ff")
const PAIN := Color("ff4d6d")
const PINK := Color("ff4f9a")
const TOUCH_R := 62.0         # base button radius; _layout scales it to the screen

var race                     # race.gd, or null in the menu
var racing := false
var show_touch := false
var touch_r := TOUCH_R
var _font: Font
var _result_panel: PanelContainer
var _result_title: Label
var _result_info: Label
var _next_button: Button
var _menu_panel: PanelContainer
var _race_list: VBoxContainer
var _menu_money: Label
var _touch: Node2D
var _buttons: Dictionary = {}   # action -> TouchScreenButton
var _pause: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = _make_theme()
	_font = ThemeDB.fallback_font
	_pause = _button("Menu", func() -> void: menu_pressed.emit())
	_pause.focus_mode = Control.FOCUS_NONE
	add_child(_pause)
	_build_result_panel()
	_build_menu()
	_build_touch()
	resized.connect(_layout)
	_layout()


func _process(_delta: float) -> void:
	queue_redraw()
	_touch.visible = show_touch and racing
	_touch.queue_redraw()
	_pause.visible = racing


# ---------------------------------------------------------------- the racing HUD

func _draw() -> void:
	if race == null or not racing:
		return
	var w := size.x
	var p = race.player
	var narrow := w < 900.0
	# Top left: position, then who's still riding (and the race name when
	# there's room).
	var n: int = race.riders.size()
	var pos_text := "%s / %d" % [ordinal(race.position()), n]
	_text(Vector2(24, 64), pos_text, 52, SUN)
	_text(Vector2(24, 100), "Still riding: %d / %d" % [race.standing(), n], 24, CREAM)
	if not show_touch and not narrow:
		_text(Vector2(24, 136), String(race.data.name), 24, CREAM)
	# Clock, left of the Menu button.
	var t := maxf(race.t, 0.0)
	_text(Vector2(w - 290, 64), "%d:%04.1f" % [int(t) / 60, fmod(t, 60.0)], 40, CREAM)

	# Progress strip along the top with a dot for every rider (on its own row
	# on narrow screens).
	var strip := Rect2(w * 0.5 - minf(w * 0.3, 300.0), 22, minf(w * 0.6, 600.0), 10)
	if narrow:
		strip = Rect2(24, 124, w - 48, 10)
	draw_rect(strip, Color(0, 0, 0, 0.35))
	draw_rect(Rect2(strip.position, Vector2(strip.size.x * race.progress(), strip.size.y)), SUN)
	for i in range(n - 1, -1, -1):
		var r = race.riders[i]
		var f: float = clampf(r.z / race.track.length, 0.0, 1.0)
		var c: Color = SUN if r.is_player else r.shirt
		draw_circle(Vector2(strip.position.x + f * strip.size.x, strip.position.y + 5), 9 if r.is_player else 6, c)
		draw_arc(Vector2(strip.position.x + f * strip.size.x, strip.position.y + 5), 9 if r.is_player else 6, 0, TAU, 12, INK, 2.0)

	# Meters. On touch screens they go top left, keeping the bottom free for
	# thumbs; with keys they sit bottom left.
	var my := (strip.end.y + 30.0 if narrow else 150.0) if show_touch else size.y - 120.0
	_meter(Vector2(24, my), "BREATH", p.stamina, BREATH if not p.panting else Color("9aa0a6"),
			"PANTING!" if p.panting else "")
	_meter(Vector2(24, my + 42), "BACK PAIN", p.pain / 100.0, PAIN, "")
	var info_y := my + 104.0 if show_touch else my - 16.0
	_text(Vector2(24, info_y), "%d km/h   %s" % [int(race.kmh(p)), p.weapon_stats().name], 26, CREAM)
	if p.boost > 0.0:
		_text(Vector2(24, info_y + 34), "JALEBI POWER", 26, Color("f77f00"))
	# Knockout news: right-hand side on wide screens, under the meters on narrow.
	var shown := 0
	for i in range(race.feed.size() - 1, -1, -1):
		var item: Array = race.feed[i]
		if race.t - float(item[0]) > 5.0 or shown >= 3:
			break
		if narrow:
			_text(Vector2(24, info_y + 70 + shown * 30), String(item[1]), 22, PAIN.lightened(0.3), w - 48)
		else:
			_text(Vector2(w - 640, 110 + shown * 32), String(item[1]), 24, PAIN.lightened(0.3), 620)
		shown += 1

	# The cycle mirror: shows the rishta aunty closing in from behind.
	if race.aunty:
		var gap: float = race.aunty_gap()
		var mc := Vector2(w * 0.5 if not narrow else w - 120.0, strip.position.y + 70 if not narrow else strip.end.y + 60)
		var mr := Rect2(mc - Vector2(90, 30), Vector2(180, 60))
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("dbe9f4")
		sb.set_corner_radius_all(30)
		sb.set_border_width_all(4)
		sb.border_color = Color("555555")
		draw_style_box(sb, mr)
		var close := clampf(1.0 - gap / 150.0, 0.0, 1.0)
		if gap > 0.0 and gap < 150.0:
			draw_circle(mc + Vector2(0, 4), 6.0 + close * 18.0, PINK)
			draw_circle(mc + Vector2(0, -6.0 - close * 10.0), 3.0 + close * 9.0, Color("1d1d1d"))
		var label := "AUNTY: %d m" % int(gap) if gap > 0.0 else "AUNTY AHEAD!"
		if race.aunty.stopped > 0.0:
			label = "CAUGHT!"
		_text(Vector2(mc.x - 90, mr.end.y + 26), label, 22, PINK if close > 0.6 else CREAM, 180)

	# Countdown and errand at the start.
	if race.t < 0.0:
		var c := int(ceil(-race.t))
		_text(Vector2(0, size.y * 0.36), str(c), 110, SUN, w)
		var lines: PackedStringArray = String(race.data.errand).split("\n")
		if show_touch:
			lines.append("Pedalling is automatic. Hold REST to get your breath back.")
		for i in lines.size():
			_text(Vector2(0, size.y * 0.36 + 60 + i * 34), lines[i], 26, CREAM, w)
	elif race.t < 0.8:
		_text(Vector2(0, size.y * 0.36), "GO, CHACHA!", 84, SUN, w)


func _meter(at: Vector2, label: String, f: float, c: Color, warn: String) -> void:
	var bar := Rect2(at + Vector2(0, 8), Vector2(220, 22))
	draw_rect(bar.grow(3), INK)
	draw_rect(bar, Color(1, 1, 1, 0.2))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(f, 0.0, 1.0), bar.size.y)), c)
	_text(at + Vector2(232, 28), warn if warn != "" else label, 22, CREAM)


func _text(at: Vector2, msg: String, fs: int, c: Color, width := -1.0) -> void:
	var align := HORIZONTAL_ALIGNMENT_CENTER if width > 0.0 else HORIZONTAL_ALIGNMENT_LEFT
	draw_string_outline(_font, at, msg, align, width, fs, 8, INK)
	draw_string(_font, at, msg, align, width, fs, c)


static func ordinal(n: int) -> String:
	match n:
		1:
			return "1st"
		2:
			return "2nd"
		3:
			return "3rd"
	return "%dth" % n


# ---------------------------------------------------------------- results

func show_result(title: String, info: String, has_next: bool) -> void:
	_menu_panel.visible = false
	_result_title.text = title
	_result_info.text = info
	_next_button.visible = has_next
	_result_panel.visible = true
	_layout()
	(_next_button if has_next else _result_panel.find_child("Retry", true, false)).grab_focus()


func hide_panels() -> void:
	_result_panel.visible = false
	_menu_panel.visible = false


func _build_result_panel() -> void:
	_result_panel = _panel()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	_result_panel.add_child(box)
	_result_title = _label(48, SUN)
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_result_title)
	_result_info = _label(24, INK, false)
	_result_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result_info.custom_minimum_size.x = 520
	box.add_child(_result_info)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var retry := _button("Retry", func() -> void: retry_pressed.emit())
	retry.name = "Retry"
	row.add_child(retry)
	_next_button = _button("Next errand", func() -> void: next_pressed.emit())
	row.add_child(_next_button)
	row.add_child(_button("Menu", func() -> void: menu_pressed.emit()))
	_result_panel.visible = false
	add_child(_result_panel)


# ---------------------------------------------------------------- menu

func show_menu(races: Array, best_pos: Dictionary, money: int) -> void:
	_result_panel.visible = false
	for c in _race_list.get_children():
		c.queue_free()
	var first: Button = null   # focus the newest unbeaten errand
	for i in races.size():
		var unlocked := i == 0 or int(best_pos.get(i - 1, 99)) <= 3
		var best := int(best_pos.get(i, 0))
		var label := "%d. %s" % [i + 1, races[i].name]
		if best > 0:
			label += "   (best: %s)" % ordinal(best)
		if not unlocked:
			label = "%d. ???   (locked: top 3 in the errand before)" % (i + 1)
		var b := _button(label, func() -> void: race_chosen.emit(i))
		b.disabled = not unlocked
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_race_list.add_child(b)
		if unlocked and (first == null or best == 0):
			first = b
	_menu_money.text = "Rupees in the dhoti fold: %d" % money
	_menu_panel.visible = true
	_layout()
	if first:
		first.grab_focus.call_deferred()


func _build_menu() -> void:
	_menu_panel = _panel()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_menu_panel.add_child(box)
	var title := _label(64, SUN)
	title.text = "DHOTI DASH"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := _label(24, INK, false)
	sub.text = "Chacha Jee, 72, one black cycle, zero brakes worth mentioning."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size.x = 560
	box.add_child(sub)
	_race_list = VBoxContainer.new()
	_race_list.add_theme_constant_override("separation", 8)
	box.add_child(_race_list)
	_menu_money = _label(22, INK, false)
	_menu_money.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_menu_money)
	var help := _label(18, INK, false)
	help.text = "Up: pedal   Down: brake   Left/Right: steer   Space: swing   B: bell"
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size.x = 560
	box.add_child(help)
	_menu_panel.visible = false
	add_child(_menu_panel)


# ---------------------------------------------------------------- touch buttons

## Phone controls. Pedalling is automatic on touch (game.gd), so two thumbs
## are enough: steering on the left; swing, bell and rest on the right.
## TouchScreenButtons press input actions while a finger is on them, and
## several work at once (multi-touch).
func _build_touch() -> void:
	_touch = Node2D.new()
	_touch.draw.connect(_draw_touch)
	add_child(_touch)
	for a in ["left", "right", "swing", "bell", "rest"]:
		var b := TouchScreenButton.new()
		b.shape = CircleShape2D.new()
		b.shape_centered = true
		b.action = a
		b.visibility_mode = TouchScreenButton.VISIBILITY_ALWAYS
		_touch.add_child(b)
		_buttons[a] = b


func _button_r(a: String) -> float:
	return touch_r * (1.2 if a == "swing" else (0.8 if a == "bell" or a == "rest" else 1.0))


func _draw_touch() -> void:
	var labels := {"left": "<", "right": ">", "swing": "SWING", "bell": "BELL", "rest": "REST"}
	var colors := {"left": CREAM, "right": CREAM, "swing": Color("e63946"), "bell": SUN, "rest": BREATH}
	for a in _buttons:
		var b: TouchScreenButton = _buttons[a]
		var r := _button_r(a)
		var c: Color = colors[a]
		c.a = 0.85 if b.is_pressed() else 0.45
		_touch.draw_circle(b.position, r, c)
		_touch.draw_arc(b.position, r, 0, TAU, 40, INK, 4.0, true)
		var fs := int(r * 0.7) if a == "left" or a == "right" else int(r * 0.36)
		_touch.draw_string_outline(_font, b.position + Vector2(-r, fs * 0.35), labels[a],
				HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fs, 6, INK)
		_touch.draw_string(_font, b.position + Vector2(-r, fs * 0.35), labels[a],
				HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fs, CREAM)


# ---------------------------------------------------------------- layout and helpers

func _layout() -> void:
	if _menu_panel == null or _touch == null:
		return   # still building; _ready calls this again at the end
	var s := size
	_pause.position = Vector2(s.x - 120, 14)
	# Thumb-sized on any screen: about a tenth of the short side.
	touch_r = clampf(minf(s.x, s.y) * 0.1, 56.0, 96.0)
	var r := touch_r
	var m := r * 1.2 + 24.0
	_buttons.left.position = Vector2(m, s.y - m)
	_buttons.right.position = Vector2(m + r * 2.35, s.y - m)
	_buttons.swing.position = Vector2(s.x - m, s.y - m)
	_buttons.rest.position = Vector2(s.x - m - r * 2.3, s.y - m + r * 0.25)
	_buttons.bell.position = Vector2(s.x - m - r * 0.2, s.y - m - r * 2.2)
	for a in _buttons:
		# The touch area is a bit bigger than the drawn circle, for sloppy thumbs.
		(_buttons[a].shape as CircleShape2D).radius = _button_r(a) * 1.2
	for p in [_result_panel, _menu_panel]:
		p.reset_size()
		p.position = (s - p.size) * 0.5


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 24
	var normal := StyleBoxFlat.new()
	normal.bg_color = SUN
	normal.set_corner_radius_all(14)
	normal.set_border_width_all(3)
	normal.border_color = INK
	normal.set_content_margin_all(10)
	var hover := normal.duplicate()
	hover.bg_color = Color("ffe27a")
	var focus := normal.duplicate()
	focus.bg_color = Color("ffe27a")
	focus.set_border_width_all(5)
	var disabled := normal.duplicate()
	disabled.bg_color = Color("d8cfc0")
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", hover)
	t.set_stylebox("focus", "Button", focus)
	t.set_stylebox("disabled", "Button", disabled)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(k, "Button", INK)
	t.set_color("font_disabled_color", "Button", Color("8a7f70"))
	return t


func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = CREAM
	sb.set_corner_radius_all(24)
	sb.set_border_width_all(4)
	sb.border_color = INK
	sb.set_content_margin_all(26)
	sb.shadow_color = Color(0, 0, 0, 0.25)
	sb.shadow_size = 10
	p.add_theme_stylebox_override("panel", sb)
	p.resized.connect(_layout)
	return p


func _label(font_size: int, color: Color, outlined := true) -> Label:
	var l := Label.new()
	var ls := LabelSettings.new()
	ls.font_size = font_size
	ls.font_color = color
	if outlined:
		ls.outline_size = 10
		ls.outline_color = INK
	l.label_settings = ls
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(on_press)
	return b
