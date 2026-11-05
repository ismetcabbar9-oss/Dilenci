extends SceneTree
## Ekran görüntüsü: xvfb-run godot --rendering-method gl_compatibility -s tools/screenshot.gd -- <çıktı.png> [jobs]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://shot.png"
	var main = load("res://scenes/main.tscn").instantiate()
	# Rehberi ekran görüntülerinde gizle ("intro" verilirse göster)
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	if cfg.has_section("guide"):
		cfg.erase_section("guide")
	if not args.has("intro"):
		for k in ["intro", "hungry", "tired", "dirty", "school", "teen_job", "adult", "love", "morale", "home", "old"]:
			cfg.set_value("guide", k, true)
	cfg.save("user://settings.cfg")
	root.add_child(main)
	for i in 40:
		await process_frame
	if args.has("jobs"):
		var gs = root.get_node("GameState")
		gs.person.age_minutes = 17.0 * gs.DAYS_PER_YEAR * 1440.0
		gs.person.education = 30.0
		gs.changed.emit()
		main._open_jobs()
		for i in 20:
			await process_frame
	if args.has("family"):
		var gs = root.get_node("GameState")
		gs.person.age_minutes = gs.years_to_minutes(34.0)
		gs.person.partner = {"name": "Kerem" if gs.person.gender == "female" else "Ayşe",
			"gender": "male" if gs.person.gender == "female" else "female",
			"age_minutes": gs.years_to_minutes(35.0), "relation": 85.0, "married": true}
		gs.person.children = [
			{"name": "Ece", "gender": "female", "age_minutes": gs.years_to_minutes(8.0)},
			{"name": "Can", "gender": "male", "age_minutes": gs.years_to_minutes(4.0)},
		]
		gs.person.job = "worker"
		gs.money = 240
		gs.changed.emit()
		main._select_tab(2)
		for i in 60:
			await process_frame
	if args.has("business"):
		var gs = root.get_node("GameState")
		gs.person.age_minutes = gs.years_to_minutes(42.0)
		gs.person.education = 60.0
		gs.person.experience = 80.0
		gs.money = 60000
		for t in ["kiosk", "cafe", "market", "restaurant", "factory"]:
			gs.open_business(t)
		gs.upgrade_business(0)
		gs.upgrade_business(0)
		gs.businesses[1].morale = 45.0
		gs.changed.emit()
		main._select_tab(2)
		main._open_business()
		for i in 30:
			await process_frame
	if args.has("store"):
		main._select_tab(5)
		main._open_store()
		for i in 30:
			await process_frame
	for a in args:
		if a.begins_with("home="):
			var gs = root.get_node("GameState")
			gs.home_level = int(a.substr(5))
			gs.changed.emit()
		if a.begins_with("hour="):
			var gs = root.get_node("GameState")
			gs.game_minutes = float(a.substr(5)) * 60.0
		if a.begins_with("act="):
			var gs = root.get_node("GameState")
			gs.acted.emit(a.substr(4))
		if a == "sleep":
			root.get_node("GameState").sleeping = true
			root.get_node("GameState").changed.emit()
		if a.begins_with("event="):
			var gs = root.get_node("GameState")
			gs.person.age_minutes = gs.years_to_minutes(30.0)
			gs.money = 800
			for j in 40:
				await process_frame
			root.get_node("Events").trigger(a.substr(6))
		if a.begins_with("intro="):
			for k in int(a.substr(6)):
				main.guide._next_step()
		if a == "tip":
			main.guide._seen.erase("hungry")
			root.get_node("GameState").person.needs.hunger = 20.0
			for j in 90:
				await process_frame
		if a.begins_with("rich"):
			var gs = root.get_node("GameState")
			var go = root.get_node("Goals")
			gs.person.age_minutes = gs.years_to_minutes(54.0)
			gs.person.education = 100.0
			gs.person.experience = 200.0
			gs.person.job = "gm"
			gs.generation = 2
			gs.family_tree = [{"name": "Ayşe", "age": 78, "generation": 1, "cause": "yaşlılık", "money": 0, "title": "Holding Sahibi"}]
			gs.money = 900000
			for t in ["kiosk", "cafe", "barber", "market", "restaurant", "factory", "hotel"]:
				gs.open_business(t)
			go.buy_luxury("car")
			go.buy_luxury("boat")
			go.buy_luxury("summer_house")
			go.fund_project("park")
			go.fund_project("library")
			go.check_achievements()
			gs.money = 260000
			gs.home_level = 3
			gs.changed.emit()
			main._select_tab(4)
			for j in 30:
				await process_frame
			match a:
				"rich=lux": main._open_luxury()
				"rich=proj": main._open_projects()
				"rich=ach": main._open_achievements()
				"rich=tree": main._open_family_tree()
				"rich=biz": main._open_business()
		if a == "boost":
			main._open_boost()
		if a == "offline":
			var gs = root.get_node("GameState")
			gs._apply_offline(9.0 * 3600.0)
		if a == "settings":
			main._select_tab(5)
			main._open_settings()
		if a.begins_with("room="):
			main._browse_room(int(a.substr(5)))
	for i in 90:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out)
	quit()
