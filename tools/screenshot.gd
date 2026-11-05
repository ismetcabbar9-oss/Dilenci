extends SceneTree
## Ekran görüntüsü: xvfb-run godot --rendering-method gl_compatibility -s tools/screenshot.gd -- <çıktı.png> [jobs]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://shot.png"
	var main = load("res://scenes/main.tscn").instantiate()
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
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out)
	quit()
