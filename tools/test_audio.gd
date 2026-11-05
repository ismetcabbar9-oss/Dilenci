extends SceneTree
## Ses testi: godot --headless -s tools/test_audio.gd
func _initialize() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 30:
		await process_frame
	var au = root.get_node("Audio")
	var gs = root.get_node("GameState")
	var fails := 0
	gs.game_minutes = 12.0 * 60.0
	gs.sleeping = false
	au._update_music(true)
	if not au._current_path.contains("day_"): fails += 1; print("FAIL gündüz müziği yok: ", au._current_path)
	gs.game_minutes = 23.0 * 60.0
	au._update_music(true)
	if not au._current_path.contains("night_"): fails += 1; print("FAIL gece müziği yok: ", au._current_path)
	if not au._current.playing: fails += 1; print("FAIL müzik çalmıyor")
	au._quiet_until = 0.0
	for s in au.SFX:
		au.play(s)
	au.set_music(false)
	if au._music_a.playing or au._music_b.playing: fails += 1; print("FAIL müzik kapanmadı")
	au.set_music(true)
	print("SES SONUÇ: ", "GEÇTİ" if fails == 0 else "%d HATA" % fails)
	quit(fails)
