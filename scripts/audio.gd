extends Node
## Ses ve müzik (autoload: Audio). Tüm sesler CC0, bkz. CREDITS.md.
## - Gündüz: iki sakin piyano parçası sırayla; gece veya uyurken: gece müziği (yumuşak geçiş).
## - Oyun olaylarına (eylem, satın alma, olay, evre, ölüm) ses efekti.
## - Müzik/efekt açma-kapama ayarı user://settings.cfg'de saklanır.

const SETTINGS_PATH := "user://settings.cfg"
const MUSIC_DAY := [
	"res://assets/audio/music/day_catmint.ogg",
	"res://assets/audio/music/day_forget_me_not.ogg",
]
const MUSIC_NIGHT := "res://assets/audio/music/night_bluebonnet.ogg"
const SFX := {
	"click": "res://assets/audio/sfx/click_002.ogg",
	"tab": "res://assets/audio/sfx/switch_002.ogg",
	"action": "res://assets/audio/sfx/confirmation_001.ogg",
	"money": "res://assets/audio/sfx/confirmation_003.ogg",
	"error": "res://assets/audio/sfx/error_004.ogg",
	"open": "res://assets/audio/sfx/open_001.ogg",
	"close": "res://assets/audio/sfx/close_001.ogg",
	"question": "res://assets/audio/sfx/question_001.ogg",
	"levelup": "res://assets/audio/sfx/maximize_006.ogg",
	"drop": "res://assets/audio/sfx/drop_002.ogg",
	"good": "res://assets/audio/sfx/jingle_good.ogg",
	"bad": "res://assets/audio/sfx/jingle_bad.ogg",
}
const MUSIC_DB := -12.0
const FADE_TIME := 2.5
# Mesaj metninde bunlar geçerse eylem başarısız sayılır (hata sesi)
const ERROR_WORDS := ["gerekli", "yetmedi", "yetersiz", "yeterli", "yorgun", "olmalı", "açılamaz", "Henüz", "yok."]

var music_on := true
var sfx_on := true

var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _current: AudioStreamPlayer
var _current_path := ""
var _day_index := 0
var _sfx_players: Array[AudioStreamPlayer] = []
var _streams := {}
var _check_timer := 0.0
var _last_money := -1
var _quiet_until := 0.0  # Açılışta toplu sinyallerde ses çıkmasın


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_settings()
	_setup_buses()
	_music_a = _new_player("Music")
	_music_b = _new_player("Music")
	for i in 6:
		_sfx_players.append(_new_player("SFX"))
	_quiet_until = Time.get_ticks_msec() / 1000.0 + 1.5
	GameState.acted.connect(func(_k): play("action"))
	GameState.stage_changed.connect(func(_s): play("good"))
	GameState.died.connect(func(_c): play("bad"))
	GameState.message.connect(_on_message)
	Store.wallet_changed.connect(func(): play("money"))
	Events.event_happened.connect(_on_event)
	Events.choice_requested.connect(func(_e): play("question"))
	_last_money = GameState.money
	_update_music(true)


func _process(delta: float) -> void:
	_check_timer += delta
	if _check_timer >= 1.0:
		_check_timer = 0.0
		_update_music(false)
		# Bir anda büyük para girişi (maaş, satış, piyango): para sesi
		if _last_money >= 0 and GameState.money - _last_money >= 50:
			play("money")
		_last_money = GameState.money
	# Gündüz parçası bitince sıradakine geç
	if _current and not _current.playing and music_on and _current_path != MUSIC_NIGHT:
		_day_index = (_day_index + 1) % MUSIC_DAY.size()
		_switch_to(MUSIC_DAY[_day_index], false)


# ---------------------------------------------------------------
# Efektler
# ---------------------------------------------------------------
func play(name: String) -> void:
	if not sfx_on or not SFX.has(name):
		return
	if Time.get_ticks_msec() / 1000.0 < _quiet_until and name != "click":
		return
	var p := _free_sfx_player()
	p.stream = _stream(SFX[name])
	p.volume_db = -4.0 if name in ["good", "bad"] else -8.0
	p.play()


func _free_sfx_player() -> AudioStreamPlayer:
	for p in _sfx_players:
		if not p.playing:
			return p
	return _sfx_players[0]


func _on_message(text: String) -> void:
	for w in ERROR_WORDS:
		if text.contains(w):
			play("error")
			return
	if text.begins_with("Yeni unvan") or text.begins_with("Tebrikler") or text.begins_with("Yeni ev") or text.begins_with("Yeni işletme"):
		play("levelup")


func _on_event(ev: Dictionary) -> void:
	play("bad" if ev.id in ["cold", "theft", "crisis"] else "good")


# ---------------------------------------------------------------
# Müzik
# ---------------------------------------------------------------
func _is_night() -> bool:
	var hour := fmod(GameState.game_minutes, 1440.0) / 60.0
	return GameState.sleeping or hour >= 22.0 or hour < 6.0


func _update_music(immediate: bool) -> void:
	if not music_on:
		return
	var want: String = MUSIC_NIGHT if _is_night() else MUSIC_DAY[_day_index]
	if want != _current_path:
		_switch_to(want, immediate)


func _switch_to(path: String, immediate: bool) -> void:
	_current_path = path
	var old := _current
	var nxt := _music_b if _current == _music_a else _music_a
	var st := _stream(path)
	if st is AudioStreamOggVorbis:
		(st as AudioStreamOggVorbis).loop = path == MUSIC_NIGHT
	nxt.stream = st
	nxt.volume_db = MUSIC_DB if immediate else -40.0
	nxt.play()
	_current = nxt
	if not immediate:
		var tw := create_tween().set_parallel(true)
		tw.tween_property(nxt, "volume_db", MUSIC_DB, FADE_TIME)
		if old and old.playing:
			tw.tween_property(old, "volume_db", -40.0, FADE_TIME)
			tw.chain().tween_callback(old.stop)
	elif old:
		old.stop()


# ---------------------------------------------------------------
# Ayarlar
# ---------------------------------------------------------------
func set_music(on: bool) -> void:
	music_on = on
	if on:
		_current_path = ""
		_update_music(true)
	else:
		_music_a.stop()
		_music_b.stop()
	_save_settings()


func set_sfx(on: bool) -> void:
	sfx_on = on
	_save_settings()


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)  # Diğer bölümleri (rehber) korumak için önce oku
	cfg.set_value("audio", "music", music_on)
	cfg.set_value("audio", "sfx", sfx_on)
	cfg.save(SETTINGS_PATH)


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		music_on = cfg.get_value("audio", "music", true)
		sfx_on = cfg.get_value("audio", "sfx", true)


# ---------------------------------------------------------------
# Yardımcılar
# ---------------------------------------------------------------
func _setup_buses() -> void:
	for bus in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, "Master")


func _new_player(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	add_child(p)
	return p


func _stream(path: String) -> AudioStream:
	if not _streams.has(path):
		_streams[path] = load(path)
	return _streams[path]
