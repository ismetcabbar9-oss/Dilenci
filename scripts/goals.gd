extends Node
## Uzun vadeli hedefler (autoload: Goals). Veri GameState.goals içinde tutulur (kayıt ve miras orada).
## - Lüks varlıklar: prestij ve her gün biraz mutluluk.
## - Hayır projeleri: aile mirası puanı, elmas ve aileye kalıcı fayda.
## - Başarımlar: bir kez kazanılır, elmas ödülü verir.
## - Aile mirası puanı: nesiller boyu biriken toplam skor.

signal achievement_unlocked(a: Dictionary)

const LUXURY := [
	{"id": "car", "name": "Araba", "cost": 3000, "prestige": 5, "fun": 3.0},
	{"id": "boat", "name": "Tekne", "cost": 20000, "prestige": 15, "fun": 4.0},
	{"id": "summer_house", "name": "Yazlık", "cost": 60000, "prestige": 30, "fun": 5.0},
	{"id": "yacht", "name": "Yat", "cost": 150000, "prestige": 60, "fun": 6.0},
	{"id": "jet", "name": "Özel jet", "cost": 500000, "prestige": 120, "fun": 7.0},
	{"id": "island", "name": "Özel ada", "cost": 2000000, "prestige": 300, "fun": 10.0},
]

## bonus: aileye kalıcı katkı (GameState.family_bonus ile okunur)
const PROJECTS := [
	{"id": "park", "name": "Mahalleye park", "cost": 5000, "legacy": 20, "gems": 5, "bonus": "",
		"desc": "Çocuklar için yeşil bir alan."},
	{"id": "library", "name": "Halk kütüphanesi", "cost": 20000, "legacy": 50, "gems": 10, "bonus": "school",
		"desc": "Ailenin çocukları okulda %25 daha hızlı öğrenir."},
	{"id": "school", "name": "Okul binası", "cost": 80000, "legacy": 120, "gems": 20, "bonus": "school",
		"desc": "Eğitim desteği artar (+%25 daha)."},
	{"id": "hospital", "name": "Hastane", "cost": 250000, "legacy": 250, "gems": 40, "bonus": "hospital",
		"desc": "Aile bireylerinin sağlığı daha hızlı toparlanır."},
	{"id": "university", "name": "Üniversite kampüsü", "cost": 1000000, "legacy": 600, "gems": 80, "bonus": "school",
		"desc": "Adın tarihe geçer; eğitim desteği daha da artar."},
]

## check: koşul (Callable). Ödüller elmas.
var ACHIEVEMENTS: Array = []


func _init() -> void:
	ACHIEVEMENTS = [
		{"id": "first_job", "name": "İlk maaş", "desc": "İlk işine başla.", "gems": 3,
			"check": func(): return GameState.person.get("job", "") != "" or float(GameState.person.get("experience", 0)) > 0.0},
		{"id": "graduate", "name": "Mezun", "desc": "Eğitimi 100'e çıkar.", "gems": 10,
			"check": func(): return float(GameState.person.get("education", 0)) >= 100.0},
		{"id": "married", "name": "Mutlu yuva", "desc": "Evlen.", "gems": 5,
			"check": func(): return GameState.is_married()},
		{"id": "big_family", "name": "Kalabalık aile", "desc": "3 çocuk sahibi ol.", "gems": 10,
			"check": func(): return GameState.person.get("children", []).size() >= 3},
		{"id": "first_business", "name": "Patron", "desc": "İlk işletmeni kur.", "gems": 5,
			"check": func(): return not GameState.businesses.is_empty()},
		{"id": "holding", "name": "Holding", "desc": "Holding sahibi ol.", "gems": 15,
			"check": func(): return GameState.is_holding()},
		{"id": "villa", "name": "Villa hayatı", "desc": "Villaya taşın.", "gems": 15,
			"check": func(): return GameState.home_level >= 3},
		{"id": "doctor", "name": "Beyaz önlük", "desc": "Doktor ol.", "gems": 10,
			"check": func(): return GameState.person.get("job", "") == "doctor"},
		{"id": "ceo", "name": "Zirve", "desc": "CEO ol.", "gems": 20,
			"check": func(): return GameState.person.get("job", "") == "ceo"},
		{"id": "millionaire", "name": "Milyoner", "desc": "1.000.000 paraya ulaş.", "gems": 30,
			"check": func(): return GameState.money >= 1000000},
		{"id": "luxury3", "name": "Lüks tutkunu", "desc": "3 lüks varlığa sahip ol.", "gems": 10,
			"check": func(): return owned_luxury().size() >= 3},
		{"id": "philanthropist", "name": "Hayırsever", "desc": "İlk hayır projeni tamamla.", "gems": 10,
			"check": func(): return not completed_projects().is_empty()},
		{"id": "all_projects", "name": "Şehrin kurucusu", "desc": "Tüm hayır projelerini tamamla.", "gems": 100,
			"check": func(): return completed_projects().size() >= PROJECTS.size()},
		{"id": "gen3", "name": "Hanedan", "desc": "3. nesle ulaş.", "gems": 20,
			"check": func(): return GameState.generation >= 3},
		{"id": "world_giant", "name": "Dünya Devi", "desc": "En yüksek unvana ulaş.", "gems": 100,
			"check": func(): return GameState.get_title() == "Dünya Devi"},
	]


var _timer := 0.0


func _process(delta: float) -> void:
	_timer += delta
	if _timer >= 1.0:
		_timer = 0.0
		check_achievements()


func _ready() -> void:
	GameState.day_started.connect(_on_day)


# ---------------------------------------------------------------
# Veri yardımcıları
# ---------------------------------------------------------------
func _data() -> Dictionary:
	var g: Dictionary = GameState.goals
	for k in ["luxury", "projects", "achievements"]:
		if not g.has(k):
			g[k] = []
	if not g.has("bonus"):
		g["bonus"] = {}
	if not g.has("legacy"):
		g["legacy"] = 0
	return g


func owned_luxury() -> Array:
	return _data().luxury


func completed_projects() -> Array:
	return _data().projects


func unlocked() -> Array:
	return _data().achievements


func _find(list: Array, id: String) -> Dictionary:
	for x in list:
		if x.id == id:
			return x
	return {}


# ---------------------------------------------------------------
# Lüks
# ---------------------------------------------------------------
func buy_luxury(id: String) -> void:
	var it := _find(LUXURY, id)
	if it.is_empty() or owned_luxury().has(id) or GameState.is_dead:
		return
	if GameState.get_age_years() < 18.0:
		GameState.message.emit("Lüks harcamalar için 18 yaşında olmalı.")
		return
	if GameState.money < int(it.cost):
		GameState.message.emit("%s için %d para gerekli." % [it.name, int(it.cost)])
		return
	GameState.money -= int(it.cost)
	owned_luxury().append(id)
	GameState.person.needs.fun = 100.0
	GameState.message.emit("Yeni varlık: %s! Prestij +%d" % [it.name, int(it.prestige)])
	GameState.changed.emit()
	GameState.save_game()


func _on_day(_offline: bool) -> void:
	# Lüks varlıklar her gün biraz mutluluk verir
	var fun := 0.0
	for id in owned_luxury():
		fun += float(_find(LUXURY, id).get("fun", 0.0))
	if fun > 0.0 and not GameState.is_dead:
		GameState.person.needs.fun = minf(100.0, GameState.person.needs.fun + fun)


# ---------------------------------------------------------------
# Hayır projeleri
# ---------------------------------------------------------------
func fund_project(id: String) -> void:
	var p := _find(PROJECTS, id)
	if p.is_empty() or completed_projects().has(id) or GameState.is_dead:
		return
	if GameState.money < int(p.cost):
		GameState.message.emit("%s için %d para gerekli." % [p.name, int(p.cost)])
		return
	GameState.money -= int(p.cost)
	completed_projects().append(id)
	var d := _data()
	d.legacy = int(d.legacy) + int(p.legacy)
	if p.bonus != "":
		d.bonus[p.bonus] = int(d.bonus.get(p.bonus, 0)) + 1
	GameState.person.needs.fun = 100.0
	GameState.message.emit("%s açıldı! %s ailesi minnetle anılacak." % [p.name, GameState.family_name])
	Store.add_gems(int(p.gems), p.name)
	GameState.changed.emit()
	GameState.save_game()


# ---------------------------------------------------------------
# Başarımlar
# ---------------------------------------------------------------
func check_achievements() -> void:
	if GameState.person.is_empty():
		return
	for a in ACHIEVEMENTS:
		if unlocked().has(a.id):
			continue
		if a.check.call():
			unlocked().append(a.id)
			Store.add_gems(int(a.gems), "Başarım: %s" % a.name)
			achievement_unlocked.emit(a)


# ---------------------------------------------------------------
# Aile mirası puanı
# ---------------------------------------------------------------
func legacy_score() -> int:
	var score := int(_data().legacy)
	for id in owned_luxury():
		score += int(_find(LUXURY, id).prestige)
	score += GameState.total_business_value() / 1000
	score += (GameState.generation - 1) * 25
	score += unlocked().size() * 5
	score += GameState.home_level * 10
	return score
