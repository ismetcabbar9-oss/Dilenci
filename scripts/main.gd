extends Node3D
## Ana sahne: 3D oda + karakter + arayüz (kod ile kuruluyor).

const CharacterScript := preload("res://scripts/character.gd")

const HOME_POS := Vector3(0, 0, 0.6)
const BED_POS := Vector3(-1.1, 0.35, -0.2)

var character: Node3D
var camera: Camera3D

# UI
var info_label: Label
var money_label: Label
var msg_label: Label
var bars := {}
var action_buttons: Array[Button] = []
var speed_buttons: Array[Button] = []
var death_panel: PanelContainer
var _msg_timer := 0.0


func _ready() -> void:
	_build_world()
	_build_ui()
	GameState.changed.connect(_refresh_ui)
	GameState.message.connect(_show_message)
	GameState.died.connect(_on_died)
	_refresh_ui()
	if GameState.is_dead:
		_on_died("")


func _process(delta: float) -> void:
	# Uyurken karakter yatağa gider
	var target := BED_POS if GameState.sleeping else HOME_POS
	character.position = character.position.lerp(target, clampf(delta * 4.0, 0.0, 1.0))
	if _msg_timer > 0.0:
		_msg_timer -= delta
		if _msg_timer <= 0.0:
			msg_label.text = ""


# ---------------------------------------------------------------
# 3D dünya
# ---------------------------------------------------------------
func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.75, 0.9)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.8, 0.85)
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)

	camera = Camera3D.new()
	camera.position = Vector3(0, 2.2, 4.2)
	camera.rotation_degrees = Vector3(-15, 0, 0)
	camera.fov = 55
	add_child(camera)

	# Oda: zemin + iki duvar
	_box(Vector3(5, 0.1, 4), Vector3(0, -0.05, 0), Color(0.7, 0.55, 0.4))      # zemin
	_box(Vector3(5, 3, 0.1), Vector3(0, 1.5, -2), Color(0.93, 0.9, 0.82))       # arka duvar
	_box(Vector3(0.1, 3, 4), Vector3(-2.5, 1.5, 0), Color(0.88, 0.85, 0.78))    # sol duvar
	# Yatak
	_box(Vector3(1.0, 0.3, 2.0), Vector3(-1.1, 0.15, -0.9), Color(0.45, 0.3, 0.2))
	_box(Vector3(0.95, 0.12, 1.9), Vector3(-1.1, 0.36, -0.9), Color(0.9, 0.9, 1.0))
	_box(Vector3(0.7, 0.12, 0.35), Vector3(-1.1, 0.46, -1.6), Color(1, 1, 1))  # yastık
	# Masa
	_box(Vector3(1.0, 0.08, 0.7), Vector3(1.3, 0.75, -1.2), Color(0.55, 0.35, 0.2))
	for x in [0.85, 1.75]:
		for z in [-1.5, -0.9]:
			_box(Vector3(0.06, 0.75, 0.06), Vector3(x, 0.375, z), Color(0.5, 0.32, 0.18))
	# Pencere (duvarda açık mavi kare)
	_box(Vector3(1.2, 0.9, 0.02), Vector3(1.0, 1.9, -1.94), Color(0.6, 0.85, 1.0))

	character = CharacterScript.new()
	character.position = HOME_POS
	add_child(character)


func _box(size: Vector3, pos: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	mi.material_override = mat
	mi.position = pos
	add_child(mi)


# ---------------------------------------------------------------
# Arayüz
# ---------------------------------------------------------------
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		root.add_theme_constant_override("margin_" + side, 20)
	layer.add_child(root)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	root.add_child(col)

	# --- Üst panel: bilgi + ihtiyaçlar ---
	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", _panel_style())
	col.add_child(top)
	var top_col := VBoxContainer.new()
	top.add_child(top_col)

	var header := HBoxContainer.new()
	top_col.add_child(header)
	info_label = _label(26)
	info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(info_label)
	money_label = _label(26)
	header.add_child(money_label)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	top_col.add_child(grid)
	for key in GameState.NEED_KEYS:
		var l := _label(22)
		l.text = GameState.NEED_NAMES[key]
		l.custom_minimum_size.x = 140
		grid.add_child(l)
		var bar := ProgressBar.new()
		bar.max_value = 100
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 26)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		grid.add_child(bar)
		bars[key] = bar

	# Hız butonları
	var speed_row := HBoxContainer.new()
	speed_row.alignment = BoxContainer.ALIGNMENT_END
	top_col.add_child(speed_row)
	var speed_texts := ["II", "1x", "5x", "20x", "60x"]
	for i in speed_texts.size():
		var b := _button(speed_texts[i], 22)
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(70, 50)
		b.pressed.connect(GameState.set_speed.bind(i))
		speed_row.add_child(b)
		speed_buttons.append(b)

	# Boşluk (karakter burada görünür)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(spacer)

	msg_label = _label(26)
	msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg_label.add_theme_color_override("font_outline_color", Color.BLACK)
	msg_label.add_theme_constant_override("outline_size", 6)
	col.add_child(msg_label)

	# --- Alt panel: eylemler ---
	var actions := GridContainer.new()
	actions.columns = 3
	actions.add_theme_constant_override("h_separation", 10)
	actions.add_theme_constant_override("v_separation", 10)
	col.add_child(actions)
	var defs := [
		["Ye", GameState.action_eat],
		["Uyu / Uyan", GameState.action_sleep],
		["Oyna", GameState.action_play],
		["Yıkan", GameState.action_wash],
		["Harçlık ver (+10)", GameState.give_money.bind(10)],
		["Yeni oyun", _confirm_reset],
	]
	for d in defs:
		var b := _button(d[0], 24)
		b.custom_minimum_size = Vector2(0, 90)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(d[1])
		actions.add_child(b)
		action_buttons.append(b)

	_build_death_panel(layer)


func _build_death_panel(layer: CanvasLayer) -> void:
	death_panel = PanelContainer.new()
	death_panel.set_anchors_preset(Control.PRESET_CENTER)
	death_panel.add_theme_stylebox_override("panel", _panel_style())
	death_panel.visible = false
	layer.add_child(death_panel)


func _on_died(_cause: String) -> void:
	for c in death_panel.get_children():
		c.queue_free()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	death_panel.add_child(box)
	var last: Dictionary = GameState.family_tree.back() if not GameState.family_tree.is_empty() else {}
	var t := _label(28)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.text = "%s %d yaşında hayatını kaybetti (%s)." % [last.get("name", "?"), last.get("age", 0), last.get("cause", "?")]
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size.x = 560
	box.add_child(t)

	var heirs: Array = GameState.get_heirs()
	if heirs.is_empty():
		var n := _label(24)
		n.text = "Geride çocuk kalmadı. Soy burada sona erdi."
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(n)
	else:
		var n := _label(24)
		n.text = "Mirası kim devralsın?"
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(n)
		for i in heirs.size():
			var h: Dictionary = heirs[i]
			var b := _button("%s (%d yaş)" % [h.name, int(h.age_minutes / (GameState.DAYS_PER_YEAR * 1440.0))], 24)
			b.custom_minimum_size.y = 80
			b.pressed.connect(_continue_heir.bind(i))
			box.add_child(b)
	var nb := _button("Yeni hayat başlat", 24)
	nb.custom_minimum_size.y = 80
	nb.pressed.connect(_new_life)
	box.add_child(nb)

	death_panel.visible = true
	death_panel.reset_size()
	death_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)


func _continue_heir(i: int) -> void:
	death_panel.visible = false
	GameState.continue_with_heir(i)


func _new_life() -> void:
	death_panel.visible = false
	GameState.reset_game()


func _confirm_reset() -> void:
	var d := ConfirmationDialog.new()
	d.dialog_text = "Her şey silinip yeni bir hayat başlasın mı?"
	d.ok_button_text = "Evet"
	d.cancel_button_text = "Vazgeç"
	d.confirmed.connect(GameState.reset_game)
	d.confirmed.connect(d.queue_free)
	d.canceled.connect(d.queue_free)
	add_child(d)
	d.popup_centered()


func _refresh_ui() -> void:
	var p: Dictionary = GameState.person
	var stage: Dictionary = GameState.get_stage()
	var status := " (uyuyor)" if GameState.sleeping else ""
	info_label.text = "%s, %d yaş · %s%s\nGün %d · %s · Nesil %d" % [
		p.name, int(GameState.get_age_years()), stage.name, status,
		GameState.get_day(), GameState.get_clock_text(), GameState.generation]
	money_label.text = "Para: %d" % GameState.money
	for key in bars:
		var v: float = p.needs[key]
		var bar: ProgressBar = bars[key]
		bar.value = v
		bar.modulate = Color(1, 0.35, 0.35) if v < 25.0 else (Color(1, 0.85, 0.3) if v < 50.0 else Color(0.5, 1, 0.5))
	for i in speed_buttons.size():
		speed_buttons[i].set_pressed_no_signal(i == GameState.speed_index)
	for b in action_buttons:
		b.disabled = GameState.is_dead


func _show_message(text: String) -> void:
	msg_label.text = text
	_msg_timer = 3.0


# --- UI yardımcıları ---
func _label(font_size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	return l


func _button(text: String, font_size: int) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", font_size)
	return b


func _panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.1, 0.12, 0.18, 0.85)
	s.set_corner_radius_all(16)
	s.set_content_margin_all(14)
	return s
