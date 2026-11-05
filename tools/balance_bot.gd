extends SceneTree
## Denge botu: makul bir oyuncu gibi bütün bir hayatı oynar ve kilometre taşlarını raporlar.
## Kullanım: godot --headless -s tools/balance_bot.gd -- [tohum] [nesil_sayısı]

var gs
var ev
var st
var log_lines: Array[String] = []
var milestones := {}


func _initialize() -> void:
	await process_frame  # autoload'ların _ready'si çalışsın
	gs = root.get_node("GameState")
	ev = root.get_node("Events")
	st = root.get_node("Store")
	var args := OS.get_cmdline_user_args()
	var seed_val := int(args[0]) if args.size() > 0 else 1
	var gens := int(args[1]) if args.size() > 1 else 1
	seed(seed_val)
	ev.set_seed(seed_val)
	gs.reset_game()
	st.reset_wallet_for_tests()
	var start_ms := Time.get_ticks_msec()
	for g in gens:
		_play_life()
		if gs.get_heirs().is_empty():
			print("Soy sona erdi.")
			break
		gs.continue_with_heir(0)
	print("Süre: %d ms" % (Time.get_ticks_msec() - start_ms))
	gs.reset_game()  # Botun bıraktığı kaydı temizle
	quit()


func _mark(key: String, extra: String = "") -> void:
	if milestones.has(key):
		return
	milestones[key] = gs.get_age_years()
	print("  %5.1f yaş | %-22s | para %7d | %s" % [gs.get_age_years(), key, gs.money, extra])


func _play_life() -> void:
	milestones.clear()
	print("=== Nesil %d: %s %s (ömür %.0f) ===" % [gs.generation, gs.person.name, gs.family_name, gs.person.lifespan])
	var last_year := -1
	var steps := 0
	var low_need_hours := 0.0
	var last_work_day := -1
	var last_school_day := -1
	while not gs.is_dead and steps < 400000:
		steps += 1
		if not ev.pending.is_empty():
			ev.choose(randi() % ev.pending.options.size())
		_decide(last_work_day, last_school_day)
		if gs.person.get("_bot_worked_day", -1) != last_work_day:
			last_work_day = gs.person.get("_bot_worked_day", -1)
		if gs.person.get("_bot_school_day", -1) != last_school_day:
			last_school_day = gs.person.get("_bot_school_day", -1)
		gs.simulate(30.0, false)
		if OS.get_environment("BOT_TRACE") != "" and gs.get_age_years() > float(OS.get_environment("BOT_TRACE")) and steps % 4 == 0:
			var nn: Dictionary = gs.person.needs
			print("    t %.2f yaş %s | aç %d en %d eğ %d tem %d sağ %d | uyku %s | para %d | iş %s" % [gs.get_age_years(), gs.get_clock_text(), nn.hunger, nn.energy, nn.fun, nn.hygiene, nn.health, gs.sleeping, gs.money, gs.person.job])
		for k in ["hunger", "energy", "fun", "hygiene"]:
			if gs.person.needs[k] < 15.0:
				low_need_hours += 0.5
				break
		var y := int(gs.get_age_years())
		if y != last_year and y % 10 == 0:
			last_year = y
			print("  %5d yaş | para %7d | eğitim %3d | tecrübe %4d | iş: %-18s | işletme %d | ev %d | unvan %s" % [
				y, gs.money, int(gs.person.education), int(gs.person.experience),
				gs.get_job().get("name", "-"), gs.businesses.size(), gs.home_level, gs.get_title()])
	print("  Ölüm: %.1f yaş (%s) | para %d | işletme %d | çocuk %d | düşük ihtiyaçta geçen saat: %d" % [
		gs.get_age_years(), gs.family_tree.back().cause if not gs.family_tree.is_empty() else "?",
		gs.money, gs.businesses.size(), gs.person.children.size(), int(low_need_hours)])


func _decide(_lw: int, _ls: int) -> void:
	if gs.sleeping:
		return
	var n: Dictionary = gs.person.needs
	var age: float = gs.get_age_years()
	var hour := fmod(gs.game_minutes, 1440.0) / 60.0
	var day: int = gs.get_day()

	# Temel bakım
	if n.energy < 12.0 or ((hour >= 22.0 or hour < 5.0) and n.energy < 80.0):
		gs.action_sleep()
		return
	if n.hunger < 40.0:
		gs.action_eat()
		if n.hunger >= 40.0:
			return
	if n.hygiene < 35.0:
		gs.action_wash()
		return
	if n.fun < 30.0:
		gs.action_play()
		return
	if n.health < 40.0 and st.gems >= 6:
		st.buy_item("doctor")
	if hour < 7.0:
		return

	# Okul
	if age < 18.0 and gs.person.get("_bot_school_day", -1) != day and hour < 14.0:
		gs.person["_bot_school_day"] = day
		gs.action_school()
		_mark("ilk okul günü")
		return

	# İş: mevcut en iyi işe geç
	var best := {}
	for j in gs.get_available_jobs():
		if best.is_empty() or j.pay > best.pay:
			best = j
	if not best.is_empty() and gs.person.job != best.id:
		gs.take_job(best.id)
		_mark("iş: " + best.name)
	if not gs.get_job().is_empty() and gs.person.get("_bot_worked_day", -1) != day and n.energy > 40.0:
		gs.person["_bot_worked_day"] = day
		gs.action_work()
		return

	if age < 18.0:
		return

	# İşletmeler
	if not gs.businesses.is_empty():
		var low_morale := false
		for b in gs.businesses:
			if b.morale < 60.0:
				low_morale = true
		if low_morale and n.energy > 40.0:
			gs.action_manage()
			return
	var reserve := 100
	var types: Array = gs.BUSINESS_TYPES.duplicate()
	types.reverse()
	for t in types:
		if gs.can_open_business(t.id) and gs.money - int(t.cost) >= reserve:
			gs.open_business(t.id)
			_mark("işletme: " + t.name)
			break
	for i in gs.businesses.size():
		var b: Dictionary = gs.businesses[i]
		if b.level < gs.MAX_BUSINESS_LEVEL and gs.money - gs.business_upgrade_cost(b) > 2000:
			gs.upgrade_business(i)
	if gs.get_title() == "Holding Sahibi":
		_mark("HOLDING")

	# Ev
	for lvl in range(gs.HOMES.size() - 1, gs.home_level, -1):
		if gs.money > int(gs.HOMES[lvl].cost) * 1.5:
			gs.buy_home(lvl)
			_mark("ev: " + gs.HOMES[lvl].name)
			break

	# Aile
	if not gs.has_partner():
		if gs.money > 50 and n.fun < 80.0:
			gs.action_socialize()
			if gs.has_partner():
				_mark("sevgili")
		return
	if not gs.is_married():
		if gs.person.partner.relation < 75.0 and gs.money > 40:
			gs.action_date()
		elif gs.money > gs.WEDDING_COST + 100:
			gs.action_marry()
			if gs.is_married():
				_mark("evlilik")
		return
	if gs.person.partner.relation < 40.0 and gs.money > 40:
		gs.action_date()
		return
	if gs.person.children.size() < 2 and gs.money > gs.BABY_COST + 150:
		var before: int = gs.person.children.size()
		gs.action_have_baby()
		if gs.person.children.size() > before:
			_mark("çocuk %d" % gs.person.children.size())
