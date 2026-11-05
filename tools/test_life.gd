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
	if gs.businesses.size() != 4 or gs.money != m + int(12000 * 0.6): fails += 1; print("FAIL satış")
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
	# Ev satın alma: kira yerine bakım gideri
	gs.reset_game()
	gs.person.age_minutes = gs.years_to_minutes(25.0)
	gs.money = 3000
	gs.buy_home(1)
	if gs.home_level != 1 or gs.money != 500: fails += 1; print("FAIL ev alınamadı")
	gs.buy_home(3)
	if gs.home_level != 1: fails += 1; print("FAIL parasız villa alındı")
	_fill(gs)
	m = gs.money
	gs.simulate(24.0 * 60.0, false)
	if gs.money != m - gs.HOMES[1].upkeep: fails += 1; print("FAIL ev bakım gideri ", m, "->", gs.money)
	# Rastgele olaylar
	var ev = root.get_node("Events")
	gs.reset_game()
	gs.person.age_minutes = gs.years_to_minutes(30.0)
	gs.money = 1000
	_fill(gs)
	ev.trigger("cold")
	if gs.person.needs.health != 80.0: fails += 1; print("FAIL grip etkisi yok")
	ev.trigger("lottery")
	if gs.money != 6000: fails += 1; print("FAIL piyango ", gs.money)
	gs.set_speed(3)
	ev.trigger("investment")
	if ev.pending.is_empty() or gs.speed_index != 0: fails += 1; print("FAIL seçimli olay oyunu durdurmadı")
	ev.choose(1)  # reddet
	if not ev.pending.is_empty() or gs.speed_index != 3 or gs.money != 6000: fails += 1; print("FAIL seçim sonrası durum")
	ev.trigger("serious_illness")
	gs.person.needs.health = 50.0
	ev.choose(0)  # hastane
	if gs.person.needs.health != 100.0 or gs.money != 5850: fails += 1; print("FAIL hastane seçimi")
	# Tüm olayların şartı ve etkisi hatasız çalışmalı
	gs.open_business("kiosk")
	gs.open_business("cafe")
	gs.person.partner = {"name": "Deniz", "gender": "female", "age_minutes": gs.person.age_minutes, "relation": 50.0, "married": true}
	gs.person.children = [{"name": "Ece", "gender": "female", "age_minutes": gs.years_to_minutes(9.0)}]
	gs.person.job = "worker"
	gs.person.experience = 10.0
	for e in ev.events:
		e.cond.call()
		ev.trigger(e.id)
		if not ev.pending.is_empty():
			ev.choose(0)
	# Doğal oluşum: 200 günde birkaç olay çıkmalı
	ev.set_seed(42)
	ev._last_seen = {}
	var count := 0
	for d in 200:
		gs.game_minutes += 1440.0
		var before: Dictionary = ev._last_seen.duplicate()
		ev._on_day_started(false)
		if ev._last_seen != before: count += 1
		if not ev.pending.is_empty(): ev.choose(1)
	if count < 10 or count > 120: fails += 1; print("FAIL olay sıklığı ", count)
	print("200 günde olay sayısı: ", count)
	# İçerik: üniversite, emeklilik, lüks, hayır işleri, başarımlar
	var go = root.get_node("Goals")
	gs.reset_game()
	gs.person.education = 59.0
	_fill(gs)
	gs.action_school()
	if gs.person.education != 60.0: fails += 1; print("FAIL okul tavanı ", gs.person.education)
	gs.action_school()
	if gs.person.education != 60.0: fails += 1; print("FAIL okul tavanı aşıldı")
	gs.person.age_minutes = gs.years_to_minutes(19.0)
	gs.money = 100
	_fill(gs)
	gs.action_school()
	if gs.person.education != 64.0 or gs.money != 75: fails += 1; print("FAIL üniversite ", gs.person.education, " ", gs.money)
	gs.person.job = "doctor"
	gs.person.age_minutes = gs.years_to_minutes(66.0)
	gs.retire()
	if gs.person.job != "" or gs.person.pension != 65: fails += 1; print("FAIL emeklilik")
	_fill(gs)
	m = gs.money
	gs.simulate(24.0 * 60.0, false)
	if gs.money != m + 65 - gs.DAILY_RENT: fails += 1; print("FAIL emekli maaşı ", m, "->", gs.money)
	gs.money = 30000
	go.buy_luxury("car")
	go.buy_luxury("car")
	if go.owned_luxury() != ["car"] or gs.money != 27000: fails += 1; print("FAIL araba")
	go.fund_project("library")
	if go.completed_projects() != ["library"] or gs.family_bonus("school") != 1: fails += 1; print("FAIL kütüphane")
	go.check_achievements()
	if not go.unlocked().has("philanthropist"): fails += 1; print("FAIL başarım")
	if go.legacy_score() <= 0: fails += 1; print("FAIL miras puanı")
	gs.person.education = 100.0
	gs.person.experience = 300.0
	gs.money = 2000000
	for t in gs.BUSINESS_TYPES:
		gs.open_business(t.id)
	if gs.businesses.size() != 11: fails += 1; print("FAIL yeni işletmeler ", gs.businesses.size())
	if gs.get_title() != "Sanayici": fails += 1; print("FAIL unvan ", gs.get_title(), " ", gs.total_business_value())
	# Mağaza / elmas
	var st = root.get_node("Store")
	st.reset_wallet_for_tests()
	gs.reset_game()
	st.claim_daily()
	if st.gems != 13: fails += 1; print("FAIL günlük ödül ", st.gems)
	st.claim_daily()
	if st.gems != 13: fails += 1; print("FAIL günlük ödül iki kez alındı")
	gs.person.needs.hunger = 10.0
	st.buy_item("meal")
	if gs.person.needs.hunger != 100.0 or st.gems != 11: fails += 1; print("FAIL yemek alınamadı")
	if st.buy_item("cash_bag"): fails += 1; print("FAIL elmas yetmeden alındı")
	st.purchase_pack("gems_medium")
	if st.gems != 161: fails += 1; print("FAIL paket ", st.gems)
	var before: int = gs.money
	st.buy_item("cash_bag")
	if gs.money != before + 3000: fails += 1; print("FAIL para çantası")
	gs.reset_game()
	if st.gems != 131: fails += 1; print("FAIL yeni oyunda elmas silindi ", st.gems)
	st.reset_wallet_for_tests()
	gs.reset_game()
	print("SONUÇ: ", "TÜM TESTLER GEÇTİ" if fails == 0 else "%d HATA" % fails)
	quit(fails)


func _fill(gs) -> void:
	for k in gs.person.needs:
		gs.person.needs[k] = 100.0
