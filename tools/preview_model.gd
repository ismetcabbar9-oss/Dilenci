extends SceneTree
## Model önizleme: xvfb-run godot --rendering-method gl_compatibility -s tools/preview_model.gd -- <res://model.glb> <çıktı.png>
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var n: Node3D = load(args[0]).instantiate()
	root.add_child(n)
	await process_frame
	var total := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = mi.global_transform * mi.mesh.get_aabb()
		total = b if first else total.merge(b)
		first = false
	printerr("TOTAL ", total)
	for c in n.find_children("Room*", "Node3D", true, false):
		var t := AABB()
		var f := true
		for mi in c.find_children("*", "MeshInstance3D", true, false):
			var b: AABB = mi.global_transform * mi.mesh.get_aabb()
			t = b if f else t.merge(b)
			f = false
		printerr(c.name, " ", t)
	var cam := Camera3D.new()
	root.add_child(cam)
	var center := total.get_center()
	var r := total.size.length()
	cam.look_at_from_position(center + Vector3(r * 0.7, r * 0.6, r * 0.7), center)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	root.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.6
	root.add_child(env)
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(args[1])
	quit()
