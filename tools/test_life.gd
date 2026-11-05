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
	_fill(gs)
	gs.simulate(24.0 * 60.0, false)
	if gs.money != m - gs.DAILY_RENT: fails += 1; print("FAIL kira düşmedi ", m, " ", gs.money)
	# Aile: tanışma → buluşma → evlilik → çocuk
	gs.money = 1000
	_fill(gs)
	if gs.is_dead: fails += 1; print("FAIL 24 saat aç kalınca öldü (çok sert)")
	for i in 30:
		if gs.has_partner(): break
		_fill(gs)
		gs.action_socialize()
	if not gs.has_partner(): fails += 1; print("FAIL partner bulunamadı")
	for i in 5:
		_fill(gs)
		gs.action_date()
	gs.action_marry()
	if not gs.is_married(): fails += 1; print("FAIL evlenilemedi")
	gs.action_have_baby()
	gs.action_have_baby()  # bekleme süresi nedeniyle olmamalı
	if gs.person.children.size() != 1: fails += 1; print("FAIL çocuk sayısı ", gs.person.children.size())
	for i in 10:
		_fill(gs)
		gs.simulate(gs.years_to_minutes(0.11), false)
	_fill(gs)
	gs.action_have_baby()
	if gs.person.children.size() != 2: fails += 1; print("FAIL ikinci çocuk")
	if gs.person.children.is_empty() or gs.person.children[0].age_minutes < gs.years_to_minutes(1.0): fails += 1; print("FAIL çocuk büyümedi")
	# İşletmeler
	gs.person.age_minutes = gs.years_to_minutes(35.0)
	gs.person.education = 50.0
	gs.person.experience = 60.0
	gs.money = 400
	gs.open_business("factory")
	if gs.businesses.size() != 0: fails += 1; print("FAIL parasız fabrika açıldı")
	gs.open_business("kiosk")
	if gs.businesses.size() != 1 or gs.money != 100: fails += 1; print("FAIL büfe açılamadı")
	if gs.get_title() != "Esnaf": fails += 1; print("FAIL unvan Esnaf değil: ", gs.get_title())
	_fill(gs)
	m = gs.money
	gs.simulate(24.0 * 60.0, false)
	var expected_min: int = m + 15 - 15 - 25  # büfe ~20 (moral düşebilir), kira+çocuk giderleri
	if gs.money < expected_min - 20: fails += 1; print("FAIL işletme geliri gelmedi ", m, "->", gs.money)
	gs.money = 100000
	gs.upgrade_business(0)
	if gs.businesses[0].level != 2: fails += 1; print("FAIL büyütülemedi")
	for t in ["cafe", "market", "restaurant", "factory"]:
		gs.open_business(t)
	if gs.get_title() != "Holding Sahibi": fails += 1; print("FAIL holding olunamadı: ", gs.get_title(), " ", gs.total_business_value())
	m = gs.money
	gs.sell_business(4)
	if gs.businesses.size() != 4 or gs.money != m + int(18000 * 0.6): fails += 1; print("FAIL satış")
	# Ölüm + miras
	gs.person.children = [{"name": "Ece", "gender": "female", "age_minutes": 20.0 * gs.DAYS_PER_YEAR * 1440.0}]
	gs.money = 100
	gs.person.age_minutes = gs.years_to_minutes(gs.person.lifespan)
	gs.simulate(1.0, false)
	if not gs.is_dead: fails += 1; print("FAIL ölmedi")
	gs.continue_with_heir(0)
	if gs.businesses.size() != 4: fails += 1; print("FAIL işletmeler mirasa geçmedi")
	if gs.is_dead or gs.person.name != "Ece" or gs.generation != 2 or gs.money != 100:
		fails += 1; print("FAIL miras")
	gs.reset_game()
	print("SONUÇ: ", "TÜM TESTLER GEÇTİ" if fails == 0 else "%d HATA" % fails)
	quit(fails)


func _fill(gs) -> void:
	for k in gs.person.needs:
		gs.person.needs[k] = 100.0
