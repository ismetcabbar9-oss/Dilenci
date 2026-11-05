extends SceneTree
## Hızlı mantık testi:  godot --headless -s tools/test_life.gd

func _initialize() -> void:
	var gs = root.get_node("GameState")
	gs.reset_game()
	var fails := 0
	gs.person.needs.energy = 100.0
	gs.action_school()
	if gs.person.education <= 0.0: fails += 1; print("FAIL okul eğitimi artırmadı")
	gs.action_work()
	if gs.money != 20: fails += 1; print("FAIL işsizken para değişti")
	# 13 yaşa getir, gazete işi al
	gs.person.age_minutes = 13.0 * gs.DAYS_PER_YEAR * 1440.0
	gs.take_job("paper")
	if gs.person.job != "paper": fails += 1; print("FAIL iş alınamadı")
	gs.take_job("manager")
	if gs.person.job != "paper": fails += 1; print("FAIL şartsız müdür olundu")
	var m: int = gs.money
	gs.person.needs.energy = 100.0
	gs.action_work()
	if gs.money <= m: fails += 1; print("FAIL çalışınca para artmadı")
	# 20 yaş, günlük kira
	gs.person.age_minutes = 20.0 * gs.DAYS_PER_YEAR * 1440.0
	m = gs.money
	gs.simulate(24.0 * 60.0, false)
	if gs.money != m - gs.DAILY_RENT: fails += 1; print("FAIL kira düşmedi ", m, " ", gs.money)
	# Ölüm + miras
	gs.person.children = [{"name": "Ece", "gender": "female", "age_minutes": 20.0 * gs.DAYS_PER_YEAR * 1440.0}]
	gs.money = 100
	gs.person.needs.health = 0.0
	gs.simulate(1.0, false)
	if not gs.is_dead: fails += 1; print("FAIL ölmedi")
	gs.continue_with_heir(0)
	if gs.is_dead or gs.person.name != "Ece" or gs.generation != 2 or gs.money != 100:
		fails += 1; print("FAIL miras")
	gs.reset_game()
	print("SONUÇ: ", "TÜM TESTLER GEÇTİ" if fails == 0 else "%d HATA" % fails)
	quit(fails)
