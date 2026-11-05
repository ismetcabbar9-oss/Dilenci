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

# --- İşler (kariyer basamakları) ---
# min_edu: eğitim puanı, min_exp: tecrübe (çalışılan vardiya), pay: vardiya başı maaş
const JOBS := [
	{"id": "paper", "name": "Gazete dağıtıcısı", "min_age": 13.0, "min_edu": 0.0, "min_exp": 0.0, "pay": 8, "hours": 3.0},
	{"id": "waiter", "name": "Garson", "min_age": 16.0, "min_edu": 10.0, "min_exp": 0.0, "pay": 15, "hours": 6.0},
	{"id": "worker", "name": "İşçi", "min_age": 18.0, "min_edu": 15.0, "min_exp": 5.0, "pay": 25, "hours": 8.0},
	{"id": "master", "name": "Usta", "min_age": 20.0, "min_edu": 25.0, "min_exp": 30.0, "pay": 40, "hours": 8.0},
	{"id": "clerk", "name": "Memur", "min_age": 20.0, "min_edu": 55.0, "min_exp": 0.0, "pay": 45, "hours": 8.0},
	{"id": "manager", "name": "Müdür", "min_age": 25.0, "min_edu": 65.0, "min_exp": 60.0, "pay": 80, "hours": 9.0},
]
const DAILY_RENT := 15        # 18 yaşından sonra her gün ev/fatura gideri
const DAILY_ALLOWANCE := 5    # 18 yaşından önce ailenin verdiği günlük harçlık
# --- Aile ---
const OUTING_COST := 10       # Dışarı çıkıp sosyalleşmek
const DATE_COST := 15         # Partnerle buluşma
const WEDDING_COST := 100
const BABY_COST := 50
const CHILD_DAILY_COST := 5   # 18 yaşına kadar her çocuk için günlük gider
const PARTNER_DAILY_INCOME := 10  # Evliyken eşin eve kattığı katkı
const MAX_CHILDREN := 4
const MIN_RELATION_TO_MARRY := 70.0
const MALE_NAMES := ["Ali", "Mehmet", "Can", "Emre", "Murat", "Kerem", "Burak", "Yusuf"]
const FEMALE_NAMES := ["Ayşe", "Zeynep", "Elif", "Selin", "Deniz", "Ece", "Merve", "Defne"]

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
	var gender := "female" if randf() < 0.5 else "male"
	person = make_person(random_name(gender), gender, START_AGE_YEARS)
	_start_life()
	message.emit.call_deferred("%s hayata başladı. Ona iyi bak!" % person.name)


func make_person(p_name: String, gender: String, age_years: float) -> Dictionary:
	return {
		"name": p_name,
		"gender": gender,
		"education": 0.0,
		"experience": 0.0,
		"job": "",
		"age_minutes": age_years * DAYS_PER_YEAR * 24.0 * 60.0,
		"lifespan": randf_range(68.0, 88.0),
		"needs": {"hunger": 80.0, "energy": 90.0, "fun": 70.0, "hygiene": 80.0, "health": 100.0},
		"partner": {},    # {name, gender, age_minutes, relation, married}
		"children": [],   # Miras için: [{name, gender, age_minutes}]
		"last_baby_minutes": -1.0e9,
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
## Uzun süreleri 30 dakikalık parçalara bölerek işler (bir anda çöküş olmasın).
func simulate(minutes: float, offline: bool) -> void:
	var left := minutes
	while left > 0.0 and not is_dead:
		var step := minf(left, 30.0)
		_simulate_step(step, offline)
		left -= step
	changed.emit()


func _simulate_step(minutes: float, offline: bool) -> void:
	var hours := minutes / 60.0
	var needs: Dictionary = person.needs
	var day_before := get_day()
	game_minutes += minutes
	for _d in get_day() - day_before:
		_new_day()
	person.age_minutes += minutes
	if not person.partner.is_empty():
		person.partner.age_minutes += minutes
	for c in person.children:
		c.age_minutes += minutes

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


# ---------------------------------------------------------------
# Eylemler
# ---------------------------------------------------------------
func _new_day() -> void:
	_relation_decay()
	if get_age_years() < 18.0:
		money += DAILY_ALLOWANCE
		return
	var cost := DAILY_RENT
	for c in person.children:
		if c.age_minutes < years_to_minutes(18.0):
			cost += CHILD_DAILY_COST
	if is_married():
		money += PARTNER_DAILY_INCOME
	if money >= cost:
		money -= cost
		message.emit("Günlük ev ve aile giderleri ödendi (-%d)." % cost)
	else:
		money = 0
		_add_need("fun", -20.0)
		message.emit("Faturalar ödenemedi! %s çok stresli." % person.name)


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


func action_school() -> void:
	if not can_act():
		return
	if get_age_years() >= 18.0:
		message.emit("Okul çağı bitti.")  # Üniversite ileride
		return
	if person.needs.energy < 20.0:
		message.emit("Okula gidemeyecek kadar yorgun.")
		return
	person.education = minf(100.0, person.education + 3.0)
	_add_need("energy", -20.0)
	_add_need("fun", -5.0)
	_pass_time(6.0 * 60.0)
	message.emit("Okuldan döndü. Eğitim: %d" % int(person.education))


func action_work() -> void:
	if not can_act():
		return
	var job := get_job()
	if job.is_empty():
		message.emit("Henüz bir işi yok. 'İş bul' ile iş ara.")
		return
	if person.needs.energy < 25.0:
		message.emit("İşe gidemeyecek kadar yorgun.")
		return
	var hours: float = job.hours
	money += int(job.pay)
	person.experience += 1.0
	_add_need("energy", -3.5 * hours)
	_add_need("fun", -1.0 * hours)
	_add_need("hygiene", -2.0 * hours)
	_pass_time(hours * 60.0)
	message.emit("%s olarak çalıştı (+%d)." % [job.name, int(job.pay)])


# ---------------------------------------------------------------
# Aile
# ---------------------------------------------------------------
func has_partner() -> bool:
	return not person.partner.is_empty()


func is_married() -> bool:
	return has_partner() and bool(person.partner.get("married", false))


## Dışarı çık: eğlenir, bekârsa biriyle tanışabilir (18+).
func action_socialize() -> void:
	if not can_act():
		return
	if get_age_years() < 16.0:
		_add_need("fun", 15.0)
		_pass_time(90.0)
		message.emit("Arkadaşlarıyla parkta oynadı.")
		return
	if money < OUTING_COST:
		message.emit("Dışarı çıkmak için %d para gerekli." % OUTING_COST)
		return
	money -= OUTING_COST
	_add_need("fun", 20.0)
	_add_need("energy", -10.0)
	_pass_time(3.0 * 60.0)
	if not has_partner() and get_age_years() >= 18.0 and randf() < 0.45:
		var g := "male" if person.gender == "female" else "female"
		var age_diff := randf_range(-4.0, 4.0)
		person.partner = {
			"name": random_name(g),
			"gender": g,
			"age_minutes": maxf(years_to_minutes(18.0), person.age_minutes + years_to_minutes(age_diff)),
			"relation": 20.0,
			"married": false,
		}
		message.emit("%s ile tanıştı! Aralarında bir şeyler var." % person.partner.name)
	else:
		message.emit("Arkadaşlarıyla güzel vakit geçirdi (-%d)." % OUTING_COST)


func action_date() -> void:
	if not can_act():
		return
	if not has_partner():
		message.emit("Henüz kimsesi yok. Dışarı çıkıp sosyalleşmeli.")
		return
	if money < DATE_COST:
		message.emit("Buluşma için %d para gerekli." % DATE_COST)
		return
	money -= DATE_COST
	person.partner.relation = minf(100.0, person.partner.relation + 15.0)
	_add_need("fun", 15.0)
	_pass_time(2.0 * 60.0)
	message.emit("%s ile güzel vakit geçirdi. İlişki: %d" % [person.partner.name, int(person.partner.relation)])


func action_marry() -> void:
	if not can_act():
		return
	if not has_partner():
		message.emit("Evlenmek için önce birini bulmalı.")
	elif is_married():
		message.emit("Zaten evli.")
	elif get_age_years() < 20.0:
		message.emit("Evlenmek için en az 20 yaşında olmalı.")
	elif person.partner.relation < MIN_RELATION_TO_MARRY:
		message.emit("İlişki henüz yeterince güçlü değil (%d/%d)." % [int(person.partner.relation), int(MIN_RELATION_TO_MARRY)])
	elif money < WEDDING_COST:
		message.emit("Düğün için %d para gerekli." % WEDDING_COST)
	else:
		money -= WEDDING_COST
		person.partner.married = true
		_add_need("fun", 40.0)
		message.emit("%s ile evlendi! Mutluluklar!" % person.partner.name)
	changed.emit()


func action_have_baby() -> void:
	if not can_act():
		return
	var mother_age := get_age_years() if person.gender == "female" else minutes_to_years(person.partner.get("age_minutes", 0.0))
	if not is_married():
		message.emit("Çocuk için önce evlenmeli.")
	elif person.children.size() >= MAX_CHILDREN:
		message.emit("Aile yeterince kalabalık.")
	elif mother_age > 45.0:
		message.emit("Artık çocuk sahibi olmak için geç.")
	elif person.age_minutes - person.last_baby_minutes < years_to_minutes(1.0):
		message.emit("Yeni bir bebek için biraz beklemeli.")
	elif money < BABY_COST:
		message.emit("Bebek masrafları için %d para gerekli." % BABY_COST)
	else:
		money -= BABY_COST
		person.last_baby_minutes = person.age_minutes
		var g := "female" if randf() < 0.5 else "male"
		var child := {"name": random_name(g), "gender": g, "age_minutes": 0.0}
		person.children.append(child)
		_add_need("fun", 30.0)
		message.emit("Bir bebekleri oldu: %s! (%s)" % [child.name, "kız" if g == "female" else "erkek"])
	changed.emit()


func _relation_decay() -> void:
	if not has_partner():
		return
	var p: Dictionary = person.partner
	p.relation = maxf(0.0, p.relation - (1.0 if p.married else 3.0))
	if p.relation <= 0.0 and not p.married:
		message.emit("%s ile ilişki bitti." % p.name)
		person.partner = {}
	elif p.relation < 20.0:
		message.emit("%s ile araları soğuyor, birlikte vakit geçirmeli." % p.name)


func get_job() -> Dictionary:
	for j in JOBS:
		if j.id == person.get("job", ""):
			return j
	return {}


## Şartları sağlanan işler.
func get_available_jobs() -> Array:
	var out := []
	for j in JOBS:
		if get_age_years() >= j.min_age and person.education >= j.min_edu and person.experience >= j.min_exp:
			out.append(j)
	return out


## Tüm işler + kilitliyse neden kilitli.
func job_requirement_text(j: Dictionary) -> String:
	var miss := []
	if get_age_years() < j.min_age:
		miss.append("%d yaş" % int(j.min_age))
	if person.education < j.min_edu:
		miss.append("eğitim %d" % int(j.min_edu))
	if person.experience < j.min_exp:
		miss.append("tecrübe %d" % int(j.min_exp))
	return "" if miss.is_empty() else "Gerekli: " + ", ".join(miss)


func take_job(job_id: String) -> void:
	for j in get_available_jobs():
		if j.id == job_id:
			person.job = job_id
			message.emit("Yeni iş: %s! Vardiya başı %d para." % [j.name, int(j.pay)])
			changed.emit()
			return


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
	# Çok küçükse akrabalar büyütür; oyun en az 6 yaştan devam eder.
	var next := make_person(heir.name, heir.gender, maxf(6.0, minutes_to_years(heir.age_minutes)))
	person = next
	money = share
	generation += 1
	_start_life()
	message.emit("%s mirası devraldı (%d para). Nesil %d başlıyor." % [person.name, share, generation])


# ---------------------------------------------------------------
# Yardımcılar
# ---------------------------------------------------------------
func get_age_years() -> float:
	return minutes_to_years(person.age_minutes)


func years_to_minutes(years: float) -> float:
	return years * DAYS_PER_YEAR * 24.0 * 60.0


func minutes_to_years(minutes: float) -> float:
	return minutes / (DAYS_PER_YEAR * 24.0 * 60.0)


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


func random_name(gender: String) -> String:
	var names: Array = FEMALE_NAMES if gender == "female" else MALE_NAMES
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
	for k in ["education", "experience"]:
		if not person.has(k):
			person[k] = 0.0
	if not person.has("job"):
		person.job = ""
	if not person.has("partner"):
		person.partner = {}
	if not person.has("last_baby_minutes"):
		person.last_baby_minutes = -1.0e9
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
