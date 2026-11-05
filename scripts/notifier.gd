extends Node
## Yerel bildirimler (autoload: Notifier).
## Uygulama arka plana atılınca karakterin ne zaman ilgiye ihtiyaç duyacağını hesaplar
## ve hatırlatma planlar ("Ali acıktı!"). Geri dönülünce plan iptal edilir.
##
## TODO (APK aşaması): Android yerel bildirim eklentisi bağlanınca _platform_schedule
## gerçek bildirimi kuracak. Şimdilik planlanan bildirimler `scheduled` listesinde tutulur.

var scheduled: Array = []   # [{in_seconds, title, text}]
var enabled := true


func schedule_reminders() -> void:
	cancel_all()
	if not enabled or GameState.is_dead or GameState.person.is_empty():
		return
	var n: Dictionary = GameState.person.needs
	var name: String = GameState.person.name
	# Oyun kapalıyken: 1 gerçek dakika = 2 oyun dakikası → açlık gerçek saatte ~8 puan düşer
	var game_hours_per_real_hour := GameState.OFFLINE_GAME_MIN_PER_SECOND * 3600.0 / 60.0
	var hunger_rate: float = GameState.DECAY_PER_HOUR.hunger * game_hours_per_real_hour
	var fun_rate: float = GameState.DECAY_PER_HOUR.fun * game_hours_per_real_hour
	if n.hunger > 25.0:
		_add((n.hunger - 25.0) / hunger_rate * 3600.0, "%s acıktı!" % name, "Karnı guruldamaya başladı. Ona bir şeyler yedir.")
	if n.fun > 20.0:
		_add((n.fun - 20.0) / fun_rate * 3600.0, "%s canı sıkılıyor" % name, "Biraz ilgiye ihtiyacı var.")
	if Store.can_claim_daily():
		_add(4.0 * 3600.0, "Günlük ödülün hazır!", "Gel ve elmaslarını topla.")
	else:
		_add(20.0 * 3600.0, "Yeni günlük ödül", "Seri bozulmasın, ödülünü almayı unutma!")


func cancel_all() -> void:
	scheduled.clear()
	_platform_cancel()


func _add(in_seconds: float, title: String, text: String) -> void:
	in_seconds = clampf(in_seconds, 15.0 * 60.0, 24.0 * 3600.0)  # En erken 15 dk sonra
	scheduled.append({"in_seconds": in_seconds, "title": title, "text": text})
	_platform_schedule(in_seconds, title, text)


func _platform_schedule(_in_seconds: float, _title: String, _text: String) -> void:
	pass  # TODO: Android yerel bildirim eklentisi


func _platform_cancel() -> void:
	pass
