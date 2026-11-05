extends Node
## Mağaza ve özel para (Elmas) — autoload: Store
## Elmaslar ayrı bir cüzdan dosyasında tutulur: "Yeni oyun" ile silinmez
## (gerçek parayla alınmış olabilirler).
##
## Gerçek ödeme: Android'de Google Play Billing eklentisi bağlanınca
## `_start_real_purchase` doldurulacak. Şimdilik TEST MODU: satın alma anında onaylanır.

signal wallet_changed
signal purchase_finished(pack_id: String, ok: bool)

const WALLET_PATH := "user://wallet.json"
const TEST_MODE := true

## Gerçek parayla alınan elmas paketleri (fiyatlar Play Console'da belirlenecek).
const GEM_PACKS := [
	{"id": "gems_small", "name": "Avuç dolusu elmas", "gems": 50, "price_label": "₺19,99"},
	{"id": "gems_medium", "name": "Kese dolusu elmas", "gems": 150, "price_label": "₺49,99", "badge": "+%25"},
	{"id": "gems_large", "name": "Sandık dolusu elmas", "gems": 500, "price_label": "₺129,99", "badge": "En avantajlı"},
]

## Elmasla alınan ürünler.
const ITEMS := [
	{"id": "meal", "name": "Sıcak yemek", "desc": "Karnını tamamen doyurur", "price": 2},
	{"id": "energy", "name": "Enerji içeceği", "desc": "Enerji +50", "price": 2},
	{"id": "doctor", "name": "Özel doktor", "desc": "Sağlık tamamen dolar", "price": 6},
	{"id": "allowance", "name": "Harçlık", "desc": "+300 para", "price": 5},
	{"id": "cash_bag", "name": "Para çantası", "desc": "+3000 para", "price": 30},
	{"id": "tutor", "name": "Özel ders", "desc": "Eğitim +10", "price": 8},
	{"id": "party", "name": "Şirket kutlaması", "desc": "Tüm işletmelerin morali %100", "price": 5},
	{"id": "vacation", "name": "Tatil", "desc": "Mutluluk ve temizlik tamamen dolar", "price": 4},
]

const DAILY_BASE := 3          # Günlük ödül
const DAILY_STREAK_BONUS := 1  # Ardışık her gün için ek (en fazla +7)

var gems: int = 10             # Başlangıç hediyesi
var last_daily_day: int = -1   # Gerçek takvim günü (unix gün)
var streak: int = 0
var total_purchased: int = 0   # Gerçek parayla alınan toplam elmas


func _ready() -> void:
	_load()


# ---------------------------------------------------------------
# Elmas
# ---------------------------------------------------------------
func add_gems(amount: int, reason: String = "") -> void:
	gems += amount
	_save()
	wallet_changed.emit()
	if reason != "":
		GameState.message.emit("+%d elmas: %s" % [amount, reason])


func spend_gems(amount: int) -> bool:
	if gems < amount:
		return false
	gems -= amount
	_save()
	wallet_changed.emit()
	return true


# ---------------------------------------------------------------
# Elmasla ürün alma
# ---------------------------------------------------------------
func get_item(item_id: String) -> Dictionary:
	for it in ITEMS:
		if it.id == item_id:
			return it
	return {}


func buy_item(item_id: String) -> bool:
	var it := get_item(item_id)
	if it.is_empty() or GameState.is_dead:
		return false
	if item_id == "party" and GameState.businesses.is_empty():
		GameState.message.emit("Kutlama yapılacak bir işletme yok.")
		return false
	if not spend_gems(int(it.price)):
		GameState.message.emit("Yeterli elmas yok (%d gerekli)." % int(it.price))
		return false
	_apply_item(item_id)
	GameState.message.emit("%s alındı! (-%d elmas)" % [it.name, int(it.price)])
	GameState.changed.emit()
	GameState.save_game()
	return true


func _apply_item(item_id: String) -> void:
	var needs: Dictionary = GameState.person.needs
	match item_id:
		"meal":
			needs.hunger = 100.0
		"energy":
			needs.energy = minf(100.0, needs.energy + 50.0)
		"doctor":
			needs.health = 100.0
		"allowance":
			GameState.money += 300
		"cash_bag":
			GameState.money += 3000
		"tutor":
			GameState.person.education = minf(100.0, GameState.person.education + 10.0)
		"party":
			for b in GameState.businesses:
				b.morale = 100.0
		"vacation":
			needs.fun = 100.0
			needs.hygiene = 100.0


# ---------------------------------------------------------------
# Günlük ödül (gerçek takvim gününe göre)
# ---------------------------------------------------------------
func _today() -> int:
	return int(Time.get_unix_time_from_system() / 86400.0)


func can_claim_daily() -> bool:
	return _today() != last_daily_day


func next_daily_amount() -> int:
	var s := streak + 1 if _today() == last_daily_day + 1 else 1
	return DAILY_BASE + mini(s - 1, 7) * DAILY_STREAK_BONUS


func claim_daily() -> void:
	if not can_claim_daily():
		GameState.message.emit("Bugünkü ödül alındı. Yarın tekrar gel!")
		return
	var amount := next_daily_amount()
	streak = streak + 1 if _today() == last_daily_day + 1 else 1
	last_daily_day = _today()
	add_gems(amount, "günlük ödül (%d. gün)" % streak)


# ---------------------------------------------------------------
# Gerçek para ile satın alma
# ---------------------------------------------------------------
func get_pack(pack_id: String) -> Dictionary:
	for p in GEM_PACKS:
		if p.id == pack_id:
			return p
	return {}


func purchase_pack(pack_id: String) -> void:
	var p := get_pack(pack_id)
	if p.is_empty():
		purchase_finished.emit(pack_id, false)
		return
	if TEST_MODE:
		_on_purchase_success(pack_id)
	else:
		_start_real_purchase(pack_id)


func _start_real_purchase(pack_id: String) -> void:
	# TODO: Google Play Billing eklentisi (godot-google-play-billing) bağlanınca
	# burada satın alma akışı başlatılacak; onay gelince _on_purchase_success çağrılacak.
	push_warning("Gerçek ödeme henüz bağlı değil: %s" % pack_id)
	purchase_finished.emit(pack_id, false)


func _on_purchase_success(pack_id: String) -> void:
	var p := get_pack(pack_id)
	total_purchased += int(p.gems)
	add_gems(int(p.gems), "%s%s" % [p.name, " (test)" if TEST_MODE else ""])
	purchase_finished.emit(pack_id, true)


# ---------------------------------------------------------------
# Kayıt
# ---------------------------------------------------------------
func _save() -> void:
	var f := FileAccess.open(WALLET_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({
			"gems": gems,
			"last_daily_day": last_daily_day,
			"streak": streak,
			"total_purchased": total_purchased,
		}))


func _load() -> void:
	if not FileAccess.file_exists(WALLET_PATH):
		_save()
		return
	var f := FileAccess.open(WALLET_PATH, FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY:
		return
	gems = int(d.get("gems", 0))
	last_daily_day = int(d.get("last_daily_day", -1))
	streak = int(d.get("streak", 0))
	total_purchased = int(d.get("total_purchased", 0))


## Sadece testler için: cüzdanı sıfırla.
func reset_wallet_for_tests() -> void:
	gems = 10
	last_daily_day = -1
	streak = 0
	total_purchased = 0
	_save()
	wallet_changed.emit()
