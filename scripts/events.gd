extends Node
## Rastgele hayat olayları (autoload: Events)
## Her yeni oyun gününde belli bir ihtimalle, şartları uyan bir olay seçilir.
## - Anlık olaylar hemen etki eder ve mesaj gösterir.
## - Seçimli olaylarda oyun durur, oyuncu bir seçenek seçer (main.gd pencereyi gösterir).

signal event_happened(ev: Dictionary)   # Anlık olay oldu (bilgi kartı için)
signal choice_requested(ev: Dictionary) # Seçimli olay: UI seçenekleri göstermeli
signal choice_resolved(result_text: String)

const DAILY_CHANCE := 0.3       # Bir günde olay çıkma ihtimali
const COOLDOWN_DAYS := 6        # Aynı olay en erken kaç gün sonra tekrar
const MIN_DAYS_BETWEEN := 1     # İki olay arası en az gün

var rng := RandomNumberGenerator.new()
var events: Array = []
var pending: Dictionary = {}    # Cevap bekleyen seçimli olay
var _last_seen := {}            # olay id -> oyun günü
var _last_event_day := -100
var _speed_before := 1


func _init() -> void:
	rng.randomize()
	_define_events()


func _ready() -> void:
	GameState.day_started.connect(_on_day_started)


func _on_day_started(offline: bool) -> void:
	if not pending.is_empty() or GameState.is_dead:
		return
	var day := GameState.get_day()
	if day - _last_event_day < MIN_DAYS_BETWEEN + 1:
		return
	if rng.randf() > DAILY_CHANCE:
		return
	var ev := _pick(offline)
	if not ev.is_empty():
		trigger(ev.id, offline)


## Şartları uyan olaylardan ağırlıklı rastgele seçim.
func _pick(offline: bool) -> Dictionary:
	var day := GameState.get_day()
	var pool: Array = []
	var total := 0.0
	for ev in events:
		if offline and ev.has("options"):
			continue  # Oyuncu yokken seçim gerektiren olay olmaz
		if day - int(_last_seen.get(ev.id, -100)) < COOLDOWN_DAYS:
			continue
		if not ev.cond.call():
			continue
		pool.append(ev)
		total += float(ev.weight)
	if pool.is_empty():
		return {}
	var r := rng.randf() * total
	for ev in pool:
		r -= float(ev.weight)
		if r <= 0.0:
			return ev
	return pool.back()


func get_event(id: String) -> Dictionary:
	for ev in events:
		if ev.id == id:
			return ev
	return {}


## Olayı başlat (testler ve ekran görüntüleri için doğrudan da çağrılabilir).
func trigger(id: String, offline: bool = false) -> void:
	var ev := get_event(id)
	if ev.is_empty() or not ev.cond.call():
		return
	_last_seen[id] = GameState.get_day()
	_last_event_day = GameState.get_day()
	var shown := ev.duplicate()
	shown.text = _fmt(ev.text)
	if ev.has("options"):
		pending = shown
		_speed_before = GameState.speed_index if GameState.speed_index > 0 else 1
		GameState.set_speed(0)  # Karar verilene kadar zaman dursun
		choice_requested.emit(shown)
	else:
		var result: String = ev.effect.call()
		shown.result = result
		GameState.message.emit("%s: %s" % [ev.title, result])
		GameState.changed.emit()
		if not offline:
			event_happened.emit(shown)


func choose(option_index: int) -> void:
	if pending.is_empty():
		return
	var ev := get_event(pending.id)
	var opts: Array = ev.options
	option_index = clampi(option_index, 0, opts.size() - 1)
	var result: String = opts[option_index].effect.call()
	pending = {}
	GameState.set_speed(_speed_before)
	GameState.message.emit(result)
	GameState.changed.emit()
	GameState.save_game()
	choice_resolved.emit(result)


func _fmt(text: String) -> String:
	var p: Dictionary = GameState.person
	var partner_name: String = p.partner.get("name", "") if p.has("partner") else ""
	var child_name: String = p.children[0].name if not p.get("children", []).is_empty() else ""
	return text.format({"name": p.name, "partner": partner_name, "child": child_name})


# ---------------------------------------------------------------
# Yardımcılar (olay tanımlarında kullanılır)
# ---------------------------------------------------------------
func _age() -> float:
	return GameState.get_age_years()


func _needs() -> Dictionary:
	return GameState.person.needs


func _add(key: String, amount: float) -> void:
	GameState.person.needs[key] = clampf(GameState.person.needs[key] + amount, 0.0, 100.0)


func _money(amount: int) -> void:
	GameState.money = maxi(0, GameState.money + amount)


func _has_school_child() -> bool:
	for c in GameState.person.get("children", []):
		var a := GameState.minutes_to_years(c.age_minutes)
		if a >= 7.0 and a < 18.0:
			return true
	return false


# ---------------------------------------------------------------
# Olay tanımları
# ---------------------------------------------------------------
func _define_events() -> void:
	events = [
		# ---------- Anlık olaylar ----------
		{
			"id": "cold", "title": "Grip", "weight": 3.0,
			"text": "{name} gribe yakalandı.",
			"cond": func(): return true,
			"effect": func():
				_add("health", -20.0)
				_add("energy", -15.0)
				return "Sağlık -20, enerji -15. Dinlenmeli.",
		},
		{
			"id": "found_money", "title": "Şanslı gün", "weight": 2.0,
			"text": "{name} yerde para buldu!",
			"cond": func(): return true,
			"effect": func():
				var amount := rng.randi_range(20, 60)
				_money(amount)
				return "+%d para." % amount,
		},
		{
			"id": "good_friend", "title": "Güzel bir gün", "weight": 2.0,
			"text": "Eski bir arkadaşı {name}'i ziyarete geldi.",
			"cond": func(): return true,
			"effect": func():
				_add("fun", 20.0)
				return "Mutluluk +20.",
		},
		{
			"id": "report_card", "title": "Karne günü", "weight": 2.0,
			"text": "{name} karnesini aldı.",
			"cond": func(): return _age() >= 7.0 and _age() < 18.0,
			"effect": func():
				var edu: float = GameState.person.education
				if edu >= _age() * 2.0:
					_add("fun", 20.0)
					Store.add_gems(1)
					return "Takdir belgesi! Mutluluk +20, +1 elmas."
				_add("fun", -10.0)
				return "Notlar pek iyi değil. Daha çok okula gitmeli.",
		},
		{
			"id": "promotion", "title": "Terfi", "weight": 2.0,
			"text": "{name} işindeki başarısıyla dikkat çekti.",
			"cond": func(): return not GameState.get_job().is_empty() and GameState.person.experience >= 5.0,
			"effect": func():
				var bonus := int(GameState.get_job().pay) * 3
				_money(bonus)
				GameState.person.experience += 5.0
				_add("fun", 15.0)
				return "Prim +%d, tecrübe +5." % bonus,
		},
		{
			"id": "theft", "title": "Hırsızlık", "weight": 1.0,
			"text": "{name}'in cüzdanı çalındı!",
			"cond": func(): return _age() >= 16.0 and GameState.money >= 200,
			"effect": func():
				var loss := int(GameState.money * 0.1)
				_money(-loss)
				_add("fun", -15.0)
				return "-%d para." % loss,
		},
		{
			"id": "crisis", "title": "Ekonomik kriz", "weight": 1.5,
			"text": "Piyasalarda kriz var, müşteriler azaldı.",
			"cond": func(): return not GameState.businesses.is_empty(),
			"effect": func():
				for b in GameState.businesses:
					b.morale = maxf(0.0, b.morale - 35.0)
				return "Tüm işletmelerin morali -35. İşlerle ilgilenmeli.",
		},
		{
			"id": "good_season", "title": "Bereketli sezon", "weight": 1.5,
			"text": "İşler çok iyi gidiyor!",
			"cond": func(): return not GameState.businesses.is_empty(),
			"effect": func():
				var gain := 0
				for b in GameState.businesses:
					gain += GameState.business_income(b) * 2
				_money(gain)
				return "Ekstra kazanç +%d." % gain,
		},
		{
			"id": "child_success", "title": "Gurur günü", "weight": 1.5,
			"text": "{child} okulda ödül kazandı!",
			"cond": func(): return _has_school_child(),
			"effect": func():
				_add("fun", 25.0)
				return "Aile çok mutlu. Mutluluk +25.",
		},
		{
			"id": "lottery", "title": "PİYANGO!", "weight": 0.15,
			"text": "{name}'in aldığı bilet büyük ikramiyeyi kazandı!",
			"cond": func(): return _age() >= 18.0,
			"effect": func():
				_money(5000)
				_add("fun", 50.0)
				return "+5000 para!",
		},
		{
			"id": "inheritance_far", "title": "Uzak akraba mirası", "weight": 0.6,
			"text": "Hiç tanımadığı uzak bir akrabası {name}'e miras bıraktı!",
			"cond": func(): return _age() >= 18.0,
			"effect": func():
				var amount := rng.randi_range(5, 30) * 100
				_money(amount)
				return "+%d para." % amount,
		},
		{
			"id": "car_accident", "title": "Kaza", "weight": 0.8,
			"text": "{name} küçük bir trafik kazası geçirdi.",
			"cond": func(): return _age() >= 18.0,
			"effect": func():
				_add("health", -25.0)
				_money(-100)
				return "Sağlık -25, tamir masrafı -100.",
		},
		{
			"id": "scholarship", "title": "Burs", "weight": 1.5,
			"text": "{name} başarısı sayesinde burs kazandı!",
			"cond": func(): return _age() >= 14.0 and _age() < 25.0 and GameState.person.education >= 45.0,
			"effect": func():
				_money(200)
				GameState.person.education = minf(100.0, GameState.person.education + 5.0)
				Store.add_gems(2)
				return "+200 para, eğitim +5, +2 elmas.",
		},
		{
			"id": "famous_review", "title": "Ünlü bir yorum", "weight": 1.2,
			"text": "Ünlü bir eleştirmen {name}'in işletmesini övdü!",
			"cond": func(): return not GameState.businesses.is_empty(),
			"effect": func():
				var gain := 0
				for b in GameState.businesses:
					b.morale = 100.0
					gain += GameState.business_income(b)
				_money(gain)
				return "Tüm işletmelerin morali %%100, ekstra +%d." % gain,
		},
		{
			"id": "anniversary", "title": "Yıldönümü", "weight": 1.2,
			"text": "{name} ve {partner} evlilik yıldönümlerini kutluyor.",
			"cond": func(): return GameState.is_married(),
			"effect": func():
				_add("fun", 25.0)
				GameState.person.partner.relation = minf(100.0, GameState.person.partner.relation + 10.0)
				return "Mutluluk +25, ilişki +10.",
		},
		{
			"id": "graduation", "title": "Mezuniyet", "weight": 3.0,
			"text": "{name} liseden mezun oldu! Aile çok gururlu.",
			"cond": func(): return _age() >= 18.0 and _age() < 19.5 and GameState.person.education >= 50.0,
			"effect": func():
				_add("fun", 30.0)
				Store.add_gems(3)
				return "Mutluluk +30, +3 elmas.",
		},
		# ---------- Seçimli olaylar ----------
		{
			"id": "investment", "title": "Yatırım teklifi", "weight": 1.5,
			"text": "Bir arkadaşı {name}'e yeni bir girişim için 500 para yatırmasını teklif ediyor. Riskli ama kazançlı olabilir.",
			"cond": func(): return _age() >= 20.0 and GameState.money >= 500,
			"options": [
				{"label": "Yatır (500)", "effect": func():
					_money(-500)
					if rng.randf() < 0.5:
						_money(1500)
						_add("fun", 20.0)
						return "Girişim başarılı oldu! +1500 para geri döndü."
					_add("fun", -20.0)
					return "Girişim battı, 500 para gitti."},
				{"label": "Reddet", "effect": func():
					return "Teklifi kibarca reddetti."},
			],
		},
		{
			"id": "serious_illness", "title": "Hastalık", "weight": 1.5,
			"text": "{name} kendini çok kötü hissediyor. Doktora gitmesi gerekebilir.",
			"cond": func(): return _age() >= 18.0,
			"options": [
				{"label": "Hastaneye git (150)", "effect": func():
					if GameState.money >= 150:
						_money(-150)
						_add("health", 100.0)
						return "Tedavi oldu, sağlığı yerinde."
					_add("health", -25.0)
					return "Parası yetmedi! Sağlık -25."},
				{"label": "Evde dinlen", "effect": func():
					if rng.randf() < 0.5:
						_add("health", -10.0)
						return "Dinlenerek atlattı. Sağlık -10."
					_add("health", -40.0)
					return "Hastalık ağırlaştı! Sağlık -40."},
			],
		},
		{
			"id": "charity", "title": "Komşu yardımı", "weight": 1.5,
			"text": "Zor durumdaki bir komşu {name}'den 100 para yardım istiyor.",
			"cond": func(): return _age() >= 18.0 and GameState.money >= 100,
			"options": [
				{"label": "Yardım et (100)", "effect": func():
					_money(-100)
					_add("fun", 25.0)
					Store.add_gems(2)
					return "Komşu çok minnettar. Mutluluk +25, +2 elmas."},
				{"label": "Reddet", "effect": func():
					_add("fun", -5.0)
					return "Yardım edemedi, biraz içi burkuldu."},
			],
		},
		{
			"id": "school_trip", "title": "Okul gezisi", "weight": 2.0,
			"text": "Okul müzeye gezi düzenliyor. Katılım 20 para.",
			"cond": func(): return _age() >= 7.0 and _age() < 18.0,
			"options": [
				{"label": "Katıl (20)", "effect": func():
					if GameState.money < 20:
						return "Parası yetmedi, geziye katılamadı."
					_money(-20)
					_add("fun", 25.0)
					GameState.person.education = minf(100.0, GameState.person.education + 4.0)
					return "Harika bir geziydi! Mutluluk +25, eğitim +4."},
				{"label": "Katılma", "effect": func():
					return "Evde kaldı."},
			],
		},
		{
			"id": "partner_gift", "title": "Özel gün", "weight": 1.5,
			"text": "Bugün {partner} için özel bir gün. Bir hediye almak ister misin?",
			"cond": func(): return GameState.has_partner(),
			"options": [
				{"label": "Hediye al (60)", "effect": func():
					if GameState.money < 60:
						GameState.person.partner.relation = maxf(0.0, GameState.person.partner.relation - 10.0)
						return "Parası yetmedi... İlişki -10."
					_money(-60)
					GameState.person.partner.relation = minf(100.0, GameState.person.partner.relation + 20.0)
					return "%s çok mutlu oldu! İlişki +20." % GameState.person.partner.name},
				{"label": "Unut gitsin", "effect": func():
					GameState.person.partner.relation = maxf(0.0, GameState.person.partner.relation - 15.0)
					return "%s kırıldı. İlişki -15." % GameState.person.partner.name},
			],
		},
		{
			"id": "buyout", "title": "Satın alma teklifi", "weight": 1.0,
			"text": "Büyük bir şirket {name}'in bir işletmesini piyasa değerinin 1,5 katına almak istiyor.",
			"cond": func(): return GameState.businesses.size() >= 2,
			"options": [
				{"label": "Sat (x1,5)", "effect": func():
					var i := rng.randi_range(0, GameState.businesses.size() - 1)
					var b: Dictionary = GameState.businesses[i]
					var price := int(b.invested * 1.5)
					var bname: String = GameState.get_business_type(b.type).name
					GameState.businesses.remove_at(i)
					_money(price)
					return "%s satıldı: +%d para." % [bname, price]},
				{"label": "Reddet", "effect": func():
					return "Aile şirketi satılık değil!"},
			],
		},
		{
			"id": "tax_audit", "title": "Vergi denetimi", "weight": 1.0,
			"text": "Maliye {name}'in işletmelerini denetliyor. Bazı belgeler eksik çıktı.",
			"cond": func(): return GameState.businesses.size() >= 2,
			"options": [
				{"label": "Avukat tut (300)", "effect": func():
					if GameState.money < 300:
						_money(-int(GameState.total_business_value() * 0.05))
						return "Avukata para yetmedi, ceza ödendi."
					_money(-300)
					return "Avukat her şeyi yoluna koydu."},
				{"label": "Cezayı öde (%5)", "effect": func():
					var fine := int(GameState.total_business_value() * 0.05)
					_money(-fine)
					return "Ceza ödendi: -%d para." % fine},
			],
		},
		{
			"id": "fire", "title": "Yangın!", "weight": 0.7,
			"text": "{name}'in işletmelerinden birinde yangın çıktı! Hasarı hemen onarmak masraflı.",
			"cond": func(): return not GameState.businesses.is_empty(),
			"options": [
				{"label": "Hemen onar", "effect": func():
					var b: Dictionary = GameState.businesses[rng.randi_range(0, GameState.businesses.size() - 1)]
					var cost := int(GameState.business_upgrade_cost(b) * 0.4)
					_money(-cost)
					return "%s onarıldı: -%d para." % [GameState.get_business_type(b.type).name, cost]},
				{"label": "Sigortaya bırak", "effect": func():
					var b: Dictionary = GameState.businesses[rng.randi_range(0, GameState.businesses.size() - 1)]
					if b.level > 1 and rng.randf() < 0.6:
						b.level -= 1
						return "Sigorta yetmedi, %s bir seviye geriledi." % GameState.get_business_type(b.type).name
					b.morale = maxf(0.0, b.morale - 30.0)
					return "Sigorta zararı karşıladı ama çalışanlar huzursuz."},
			],
		},
		{
			"id": "child_sick", "title": "Çocuk hastalandı", "weight": 1.2,
			"text": "{child} ateşlendi. Doktora götürmek gerekebilir.",
			"cond": func(): return not GameState.person.get("children", []).is_empty() and _age() >= 20.0,
			"options": [
				{"label": "Doktora götür (80)", "effect": func():
					_money(-80)
					_add("fun", 5.0)
					return "%s çabucak iyileşti." % GameState.person.children[0].name},
				{"label": "Evde bak", "effect": func():
					_add("energy", -30.0)
					_add("fun", -15.0)
					return "Bütün gece başında bekledi. Enerji -30, mutluluk -15."},
			],
		},
		{
			"id": "retirement", "title": "Emeklilik", "weight": 2.0,
			"text": "{name} artık emeklilik yaşına geldi. İşi bırakıp emekli maaşıyla dinlenmek ister mi?",
			"cond": func(): return _age() >= 65.0 and not GameState.get_job().is_empty(),
			"options": [
				{"label": "Emekli ol", "effect": func():
					GameState.retire()
					_add("fun", 30.0)
					return "Hayırlı emeklilikler! Emekli maaşı: %d/gün." % int(GameState.person.get("pension", 0))},
				{"label": "Çalışmaya devam", "effect": func():
					return "Biraz daha çalışacak."},
			],
		},
		{
			"id": "startup_offer", "title": "Ortaklık teklifi", "weight": 0.8,
			"text": "Genç bir girişimci {name}'den 5000 para yatırım istiyor. Başarılı olursa kazanç büyük olabilir.",
			"cond": func(): return _age() >= 25.0 and GameState.money >= 5000,
			"options": [
				{"label": "Yatır (5000)", "effect": func():
					_money(-5000)
					var r := rng.randf()
					if r < 0.35:
						_money(20000)
						return "Girişim büyük başarı! +20000 para."
					if r < 0.7:
						_money(6000)
						return "Makul bir kazanç: +6000 para."
					return "Girişim battı, 5000 para gitti."},
				{"label": "Reddet", "effect": func():
					return "Riske girmedi."},
			],
		},
	]


## Testler için: rastgeleliği sabitle.
func set_seed(s: int) -> void:
	rng.seed = s
