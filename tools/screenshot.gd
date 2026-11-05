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
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out)
	quit()
