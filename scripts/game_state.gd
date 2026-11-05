extends Node
## Oyunun tüm durumunu tutan merkez (autoload: GameState).
## Zaman akışı, ihtiyaçlar, yaş, para, kayıt/yükleme ve miras burada.

signal changed            # Herhangi bir değer değişti (UI yenilensin)
signal stage_changed(stage: String)
signal message(text: String)
signal died(cause: String)

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 1

# --- Zaman ayarları ---
# 1x hızda 1 gerçek saniye = 1 oyun dakikası.
const GAME_MINUTES_PER_SECOND := 1.0
# Bir oyun yılı kaç oyun günü sürer (sıkıştırılmış takvim).
const DAYS_PER_YEAR := 4
const START_AGE_YEARS := 6.0
const SPEEDS: Array[float] = [0.0, 1.0, 5.0, 20.0, 60.0]
# Oyun kapalıyken en fazla bu kadar gerçek saniye işlenir (8 saat).
const OFFLINE_CAP_SECONDS := 8.0 * 3600.0

# --- İhtiyaçlar: saatte ne kadar düşer ---
const NEED_KEYS: Array[String] = ["hunger", "energy", "fun", "hygiene", "health"]
const NEED_NAMES := {
	"hunger": "Tokluk",
	"energy": "Enerji",
	"fun": "Mutluluk",
	"hygiene": "Temizlik",
	"health": "Sağlık",
}
const DECAY_PER_HOUR := {
	"hunger": 4.0,
	"energy": 3.0,
	"fun": 2.5,
	"hygiene": 2.0,
}
const SLEEP_ENERGY_PER_HOUR := 12.0

# --- Hayat evreleri (başlangıç yaşı) ---
const STAGES := [
	{"id": "child", "name": "Çocukluk", "from": 0.0},
	{"id": "teen", "name": "Gençlik", "from": 13.0},
	{"id": "adult", "name": "Yetişkinlik", "from": 18.0},
	{"id": "middle", "name": "Orta Yaş", "from": 40.0},
	{"id": "elder", "name": "Yaşlılık", "from": 60.0},
]

# --- Durum ---
var person: Dictionary = {}      # Şu an oynanan karakter
var money: int = 0               # Oyun içi para
var gems: int = 0                # Özel para (ileride mağaza)
var game_minutes: float = 0.0    # Oyun başından beri geçen toplam oyun dakikası
var speed_index: int = 1
var generation: int = 1
var family_tree: Array = []      # Önceki nesillerin özeti
var sleeping: bool = false
var is_dead: bool = false

var _autosave_timer := 0.0
var _last_stage := ""


func _ready() -> void:
	if not load_game():
		new_game()


func _process(delta: float) -> void:
	if is_dead:
		return
	var minutes := delta * GAME_MINUTES_PER_SECOND * SPEEDS[speed_index]
	if minutes > 0.0:
		simulate(minutes, false)
	_autosave_timer += delta
	if _autosave_timer >= 10.0:
		_autosave_timer = 0.0
		save_game()


func _notification(what: int) -> void:
	# Android'de uygulama arka plana atılınca / kapanınca kaydet.
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game()


# ---------------------------------------------------------------
# Yeni oyun / karakter
# ---------------------------------------------------------------
func new_game() -> void:
	money = 20
	gems = 0
	generation = 1
	family_tree = []
	game_minutes = 0.0
	speed_index = 1
	person = make_person(_random_name(), START_AGE_YEARS)
	_start_life()
	message.emit.call_deferred("%s hayata başladı. Ona iyi bak!" % person.name)


func make_person(p_name: String, age_years: float) -> Dictionary:
	return {
		"name": p_name,
		"gender": "female" if randf() < 0.5 else "male",
		"age_minutes": age_years * DAYS_PER_YEAR * 24.0 * 60.0,
		"lifespan": randf_range(68.0, 88.0),
		"needs": {"hunger": 80.0, "energy": 90.0, "fun": 70.0, "hygiene": 80.0, "health": 100.0},
		"children": [],   # Miras için: [{name, gender, age_minutes}]
	}


func _start_life() -> void:
	sleeping = false
	is_dead = false
	_last_stage = get_stage().id
	stage_changed.emit(_last_stage)
	changed.emit()
	save_game()


# ---------------------------------------------------------------
# Simülasyon
# ---------------------------------------------------------------
func simulate(minutes: float, offline: bool) -> void:
	var hours := minutes / 60.0
	var needs: Dictionary = person.needs
	game_minutes += minutes
	person.age_minutes += minutes

	for key in DECAY_PER_HOUR:
		var rate: float = DECAY_PER_HOUR[key]
		if sleeping:
			rate *= 0.4  # Uyurken ihtiyaçlar yavaş düşer
		needs[key] = maxf(0.0, needs[key] - rate * hours)

	if sleeping:
		needs.energy = minf(100.0, needs.energy + SLEEP_ENERGY_PER_HOUR * hours)
		if needs.energy >= 100.0:
			sleeping = false
			message.emit("%s uyandı, dinlenmiş görünüyor." % person.name)

	# Sağlık: temel ihtiyaçlar çok düşükse azalır, iyiyse yavaşça toparlanır.
	var low := 0
	for key in DECAY_PER_HOUR:
		if needs[key] < 15.0:
			low += 1
	if low > 0:
		needs.health = maxf(0.0, needs.health - 3.0 * low * hours)
	elif needs.hunger > 50.0 and needs.energy > 40.0:
		needs.health = minf(100.0, needs.health + 1.0 * hours)
	# Yaşlılıkta sağlık yavaşça düşer.
	if get_age_years() > 60.0:
		needs.health = maxf(0.0, needs.health - 0.05 * (get_age_years() - 60.0) * hours)

	if offline:
		needs.health = maxf(needs.health, 10.0)  # Oyuncu yokken ölmesin

	var stage: String = get_stage().id
	if stage != _last_stage:
		_last_stage = stage
		stage_changed.emit(stage)
		message.emit("%s artık %s evresinde!" % [person.name, get_stage().name])

	if not offline:
		if needs.health <= 0.0:
			_die("hastalık")
		elif get_age_years() >= person.lifespan:
			_die("yaşlılık")
	changed.emit()


# ---------------------------------------------------------------
# Eylemler
# ---------------------------------------------------------------
func can_act() -> bool:
	return not is_dead and not sleeping


func action_eat() -> void:
	if not can_act():
		return
	var cost := 0 if get_age_years() < 18.0 else 10  # Çocukken aile besler
	if money < cost:
		message.emit("Yemek için yeterli para yok! (%d gerekli)" % cost)
		return
	money -= cost
	_add_need("hunger", 35.0)
	_pass_time(30.0)
	message.emit("Karnını doyurdu." if cost == 0 else "Karnını doyurdu (-%d)." % cost)


func action_sleep() -> void:
	if is_dead:
		return
	sleeping = not sleeping
	message.emit("Uyumaya gitti." if sleeping else "Uyandırıldı.")
	changed.emit()


func action_play() -> void:
	if not can_act():
		return
	if person.needs.energy < 10.0:
		message.emit("Oynamak için çok yorgun.")
		return
	_add_need("fun", 25.0)
	_add_need("energy", -10.0)
	_add_need("hygiene", -5.0)
	_pass_time(60.0)
	message.emit("Eğlendi!")


func action_wash() -> void:
	if not can_act():
		return
	_add_need("hygiene", 40.0)
	_pass_time(20.0)
	message.emit("Yıkandı, tertemiz.")


## Oyuncunun doğrudan "harçlık / yemek parası" vermesi (ileride mağazaya bağlanacak).
func give_money(amount: int) -> void:
	money += amount
	message.emit("%d para verdin." % amount)
	changed.emit()


func set_speed(index: int) -> void:
	speed_index = clampi(index, 0, SPEEDS.size() - 1)
	changed.emit()


func _add_need(key: String, amount: float) -> void:
	person.needs[key] = clampf(person.needs[key] + amount, 0.0, 100.0)


func _pass_time(minutes: float) -> void:
	simulate(minutes, false)


# ---------------------------------------------------------------
# Ölüm ve miras
# ---------------------------------------------------------------
func _die(cause: String) -> void:
	is_dead = true
	sleeping = false
	family_tree.append({
		"name": person.name,
		"age": int(get_age_years()),
		"generation": generation,
		"cause": cause,
		"money": money,
	})
	died.emit(cause)
	save_game()


## Varisler (yetişkin olmasa da çocuklar devam edebilir).
func get_heirs() -> Array:
	return person.children


## Seçilen çocukla oyuna devam. Para miras kalır (kardeşlerle paylaşılır).
func continue_with_heir(index: int) -> void:
	var heirs := get_heirs()
	if index < 0 or index >= heirs.size():
		return
	var heir: Dictionary = heirs[index]
	var share := int(money / float(heirs.size()))
	var next := make_person(heir.name, heir.age_minutes / (DAYS_PER_YEAR * 24.0 * 60.0))
	next.gender = heir.gender
	person = next
	money = share
	generation += 1
	_start_life()
	message.emit("%s mirası devraldı (%d para). Nesil %d başlıyor." % [person.name, share, generation])


# ---------------------------------------------------------------
# Yardımcılar
# ---------------------------------------------------------------
func get_age_years() -> float:
	return person.age_minutes / (DAYS_PER_YEAR * 24.0 * 60.0)


func get_stage() -> Dictionary:
	var age := get_age_years()
	var current: Dictionary = STAGES[0]
	for s in STAGES:
		if age >= s.from:
			current = s
	return current


func get_day() -> int:
	return int(game_minutes / (24.0 * 60.0)) + 1


func get_clock_text() -> String:
	var minute_of_day := int(game_minutes) % (24 * 60)
	return "%02d:%02d" % [minute_of_day / 60, minute_of_day % 60]


func _random_name() -> String:
	var names := ["Ali", "Ayşe", "Mehmet", "Zeynep", "Can", "Elif", "Emre", "Selin", "Murat", "Deniz"]
	return names[randi() % names.size()]


# ---------------------------------------------------------------
# Kayıt / yükleme
# ---------------------------------------------------------------
func save_game() -> void:
	if person.is_empty():
		return
	var data := {
		"version": SAVE_VERSION,
		"saved_at": Time.get_unix_time_from_system(),
		"person": person,
		"money": money,
		"gems": gems,
		"game_minutes": game_minutes,
		"speed_index": speed_index,
		"generation": generation,
		"family_tree": family_tree,
		"sleeping": sleeping,
		"is_dead": is_dead,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))


func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY or not data.has("person"):
		return false
	person = data.person
	money = int(data.get("money", 0))
	gems = int(data.get("gems", 0))
	game_minutes = float(data.get("game_minutes", 0.0))
	speed_index = int(data.get("speed_index", 1))
	generation = int(data.get("generation", 1))
	family_tree = data.get("family_tree", [])
	sleeping = bool(data.get("sleeping", false))
	is_dead = bool(data.get("is_dead", false))
	_last_stage = get_stage().id

	# Oyun kapalıyken geçen zaman (Tamagotchi hissi).
	if not is_dead:
		var away := Time.get_unix_time_from_system() - float(data.get("saved_at", 0.0))
		away = clampf(away, 0.0, OFFLINE_CAP_SECONDS)
		if away > 60.0:
			simulate(away * GAME_MINUTES_PER_SECOND, true)
			message.emit.call_deferred("Sen yokken %d dakika geçti." % int(away / 60.0))
	changed.emit()
	return true


func reset_game() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	new_game()
