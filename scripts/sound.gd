extends Node
## Music and sound effects. Every file in audio/ is synthesized by
## tools/make_audio.py (dhol, tabla, tumbi, harmonium, shehnai, a bicycle
## bell, a buffalo), so don't hand-edit the WAVs.
##
## Godot audio basics: an AudioStreamPlayer plays one stream at a time, and
## players route into named buses (Music, SFX) that mix into Master, so each
## group's volume can be set in one place. A small pool of players lets
## several effects overlap.

const SFX := {
	"bell": preload("res://audio/sfx/bell.wav"),
	"swing": preload("res://audio/sfx/swing.wav"),
	"dhishoom": preload("res://audio/sfx/dhishoom.wav"),
	"thwack": preload("res://audio/sfx/thwack.wav"),
	"crash": preload("res://audio/sfx/crash.wav"),
	"moo": preload("res://audio/sfx/moo.wav"),
	"bump": preload("res://audio/sfx/bump.wav"),
	"splash": preload("res://audio/sfx/splash.wav"),
	"hop": preload("res://audio/sfx/hop.wav"),
	"chai": preload("res://audio/sfx/chai.wav"),
	"jalebi": preload("res://audio/sfx/jalebi.wav"),
	"weapon": preload("res://audio/sfx/weapon.wav"),
	"out": preload("res://audio/sfx/out.wav"),
	"aunty": preload("res://audio/sfx/aunty.wav"),
	"tick": preload("res://audio/sfx/tick.wav"),
	"go": preload("res://audio/sfx/go.wav"),
	"win": preload("res://audio/sfx/win.wav"),
	"sad": preload("res://audio/sfx/sad.wav"),
	"click": preload("res://audio/sfx/click.wav"),
	"whistle_down": preload("res://audio/sfx/whistle_down.wav"),
	"whistle_up": preload("res://audio/sfx/whistle_up.wav"),
	"bonk": preload("res://audio/sfx/bonk.wav"),
	"boing": preload("res://audio/sfx/boing.wav"),
	"dizzy": preload("res://audio/sfx/dizzy.wav"),
	"splat": preload("res://audio/sfx/splat.wav"),
	"bark": preload("res://audio/sfx/bark.wav"),
	"yelp": preload("res://audio/sfx/yelp.wav"),
	"bite": preload("res://audio/sfx/bite.wav"),
	"baa": preload("res://audio/sfx/baa.wav"),
	"cluck": preload("res://audio/sfx/cluck.wav"),
	"bells": preload("res://audio/sfx/bells.wav"),
	"tractor": preload("res://audio/sfx/tractor.wav"),
}
## Voice lines. These are real recordings: drop phone recordings into
## voices_in/ and run tools/import_voices.sh, which writes
## audio/voice_rec/<line>.wav. Any line without a recording is simply skipped,
## and the cartoon effects carry the moment.
const VOICE_LINES := ["chacha_oteri", "chacha_arey", "chacha_baapre", "chacha_hai",
	"chacha_oof", "chacha_hehe", "chacha_scream", "rival_ow", "rival_oteri",
	"rival_scream", "aunty_haaw"]
## Race event -> voice lines to take turns with.
const VOICE_EVENTS := {
	"hit_by": ["chacha_hai", "chacha_oteri", "chacha_oof", "chacha_arey"],
	"bite": ["chacha_hai", "chacha_baapre"],
	"pothole": ["chacha_oof", "chacha_hai"],
	"ball": ["chacha_oteri"],
	"bounce": ["chacha_oteri", "chacha_arey"],
	"scatter": ["chacha_baapre"],
	"crash": ["chacha_scream", "chacha_baapre"],
	"retired": ["chacha_scream"],
	"hit": ["rival_ow", "rival_oteri"],
	"knockout": ["rival_scream"],
	"aunty_caught": ["aunty_haaw"],
}
## Cartoon effects layered on top of the plain sounds: [sound, dB, delay s].
const CARTOON := {
	"crash": [["whistle_down", -4.0, 0.0], ["bonk", 0.0, 0.55], ["dizzy", -6.0, 0.8]],
	"retired": [["whistle_down", -2.0, 0.0], ["bonk", 0.0, 0.6]],
	"knockout": [["bonk", 0.0, 0.0], ["whistle_down", -6.0, 0.1], ["dizzy", -8.0, 0.6]],
	"bounce": [["boing", -2.0, 0.0]],
	"air": [["whistle_up", -8.0, 0.0]],
	"scatter": [["boing", -6.0, 0.1]],
	"dog_flee": [["whistle_up", -8.0, 0.0]],
}

const MUSIC := {
	"race": preload("res://audio/music/race.wav"),
	"menu": preload("res://audio/music/menu.wav"),
}
const POOL_SIZE := 14

## Race event (the first word of a race.gd log line) -> [sound, volume dB].
const EVENT_SOUNDS := {
	"bell": ["bell", -2.0], "swing": ["swing", -6.0], "hit": ["dhishoom", 0.0],
	"hit_by": ["dhishoom", -2.0], "brawl": ["thwack", -12.0], "crash": ["crash", 0.0],
	"rival_crash": ["crash", -10.0], "pothole": ["bump", -3.0],
	"puddle": ["splash", -4.0], "air": ["hop", -2.0], "ball": ["dhishoom", -6.0],
	"chai": ["chai", 0.0], "jalebi": ["jalebi", 0.0], "weapon": ["weapon", -2.0],
	"knockout": ["out", 0.0], "aunty_caught": ["aunty", 0.0],
	"bark": ["bark", -3.0], "bite": ["bite", 0.0], "dog_flee": ["yelp", -3.0],
	"bite_rival": ["bite", -6.0], "dog_startled": ["yelp", -6.0], "dog_outrun": ["bark", -10.0],
	"bounce": ["moo", -2.0], "scatter": ["baa", -2.0], "flap": ["cluck", -2.0],
}
## "near <kind>" events: the warning as something comes into view.
const NEAR_SOUNDS := {
	"buffalo": ["moo", -6.0], "cow": ["moo", -6.0], "goats": ["baa", -6.0],
	"hens": ["cluck", -8.0], "bullock": ["bells", -6.0], "tractor": ["tractor", -4.0],
}

var music_on := true
var _turn := {}               # event -> which voice line is next
var _voices := {}             # line -> AudioStream, only for recorded lines
var _current := ""
var _music: AudioStreamPlayer
var _pool: Array[AudioStreamPlayer] = []


func _ready() -> void:
	_ensure_bus("Music", -9.0)
	_ensure_bus("SFX", -3.0)
	for stream in MUSIC.values():
		_make_loop(stream)
	_music = _player("Music")
	for line in VOICE_LINES:
		var path := "res://audio/voice_rec/%s.wav" % line
		if ResourceLoader.exists(path):
			_voices[line] = load(path)
	for i in POOL_SIZE:
		_pool.append(_player("SFX"))


## One-shot effect. `pitch_jitter` varies the pitch a little each time so
## repeated sounds don't sound mechanical.
func play(sound: String, volume_db := 0.0, pitch_jitter := 0.05) -> void:
	var p := _pool[0]
	for candidate in _pool:
		if not candidate.playing:
			p = candidate
			break
	p.stream = SFX[sound]
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()


func play_event(text: String) -> void:
	var words := text.split(" ")
	var key := words[0]
	if key == "near" and words.size() > 1 and NEAR_SOUNDS.has(words[1]):
		var n: Array = NEAR_SOUNDS[words[1]]
		play(String(n[0]), float(n[1]))
	elif EVENT_SOUNDS.has(key):
		var e: Array = EVENT_SOUNDS[key]
		play(String(e[0]), float(e[1]))
	if CARTOON.has(key):
		for c in CARTOON[key]:
			play_later(String(c[0]), float(c[1]), float(c[2]))
	if VOICE_EVENTS.has(key):
		var pool: Array = VOICE_EVENTS[key]
		var i := int(_turn.get(key, 0))
		_turn[key] = i + 1
		play_voice(String(pool[i % pool.size()]))
		# Chacha chuckles when he's the one who knocked a rival out.
		if key == "knockout" and text.ends_with("by_player"):
			play_voice("chacha_hehe", 0.9)


func play_later(sound: String, volume_db: float, delay: float) -> void:
	if delay <= 0.0:
		play(sound, volume_db)
	else:
		get_tree().create_timer(delay, true, false, true).timeout.connect(play.bind(sound, volume_db, 0.05))


## Recorded voice lines, with some pitch variety so repeats sound like new
## takes. Lines nobody has recorded yet are skipped.
func play_voice(line: String, delay := 0.0) -> void:
	if not _voices.has(line):
		return
	if delay > 0.0:
		get_tree().create_timer(delay, true, false, true).timeout.connect(play_voice.bind(line))
		return
	var p := _free_player()
	p.stream = _voices[line]
	p.volume_db = 1.0
	p.pitch_scale = randf_range(0.92, 1.1)
	p.play()


func _free_player() -> AudioStreamPlayer:
	for candidate in _pool:
		if not candidate.playing:
			return candidate
	return _pool[0]


func play_music(track: String) -> void:
	if track == _current:
		return
	_current = track
	_music.stop()
	if music_on and track != "":
		_music.stream = MUSIC[track]
		_music.play()


func _player(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	add_child(p)
	return p


static func _make_loop(stream: AudioStreamWAV) -> void:
	# The files are written to loop exactly, so loop the whole thing.
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = int(round(stream.get_length() * stream.mix_rate))


static func _ensure_bus(bus_name: String, volume_db: float) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	AudioServer.add_bus()
	var i := AudioServer.bus_count - 1
	AudioServer.set_bus_name(i, bus_name)
	AudioServer.set_bus_send(i, "Master")
	AudioServer.set_bus_volume_db(i, volume_db)
