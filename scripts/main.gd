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
var actions_grid: GridContainer
var tab_buttons: Array[Button] = []
var current_tab := 0
var family_root: Node3D
var _family_signature := ""

# Eylem sekmeleri: [sekme adı, [[buton, callable], ...]]
var tabs: Array = []


func _ready() -> void:
	_build_world()
	_build_ui()
	GameState.changed.connect(_refresh_ui)
	GameState.changed.connect(_refresh_family)
	GameState.message.connect(_show_message)
	GameState.died.connect(_on_died)
	_refresh_ui()
	_refresh_family()
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
	e.background_color = Color(0.2, 0.22, 0.28)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.8, 0.85)
	e.ambient_light_energy = 0.3
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 40, 0)
	sun.light_energy = 0.75
	sun.shadow_enabled = true
	add_child(sun)

	camera = Camera3D.new()
	camera.position = Vector3(0.3, 3.4, 5.6)
	camera.fov = 50
	camera.look_at_from_position(camera.position, Vector3(0, 0.2, -0.6))
	add_child(camera)

	# Oda: zemin + iki duvar
	_box(Vector3(6, 0.1, 8), Vector3(0, -0.05, 2), Color(0.55, 0.4, 0.28))      # zemin
	_box(Vector3(6, 3, 0.1), Vector3(0, 1.5, -2), Color(0.42, 0.52, 0.47))       # arka duvar
	_box(Vector3(0.1, 3, 8), Vector3(-3, 1.5, 2), Color(0.38, 0.47, 0.43))    # sol duvar
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
	family_root = Node3D.new()
	add_child(family_root)


## Eş ve çocukları odada göster (sadece aile değişince yeniden kurulur).
func _refresh_family() -> void:
	var p: Dictionary = GameState.person
	var members: Array = []
	if not p.get("partner", {}).is_empty():
		members.append(p.partner)
	for c in p.get("children", []):
		members.append(c)
	var sig := ""
	for m in members:
		sig += "%s:%d;" % [m.name, int(GameState.minutes_to_years(m.age_minutes))]
	if sig == _family_signature:
		return
	_family_signature = sig
	for c in family_root.get_children():
		c.queue_free()
	var colors := [Color(0.3, 0.6, 0.9), Color(0.4, 0.8, 0.4), Color(0.9, 0.8, 0.3), Color(0.7, 0.4, 0.9), Color(0.3, 0.8, 0.8)]
	var slots := [Vector3(1.0, 0, 0.4), Vector3(-0.6, 0, 1.4), Vector3(0.6, 0, 1.6), Vector3(-1.4, 0, 1.0), Vector3(1.6, 0, 1.2)]
	for i in mini(members.size(), slots.size()):
		var m: Dictionary = members[i]
		var fig = CharacterScript.new()
		fig.setup(GameState.minutes_to_years(m.age_minutes), m.gender, colors[i])
		fig.position = slots[i]
		fig.rotation.y = -0.4 if slots[i].x > 0 else 0.4
		family_root.add_child(fig)


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

	# --- Alt panel: sekmeli eylemler ---
	tabs = [
		["Bakım", [
			["Ye", GameState.action_eat],
			["Uyu / Uyan", GameState.action_sleep],
			["Oyna", GameState.action_play],
			["Yıkan", GameState.action_wash],
		]],
		["Kariyer", [
			["Okula git", GameState.action_school],
			["İşe git", GameState.action_work],
			["İş bul", _open_jobs],
		]],
		["İşletme", [
			["İşletmelerim", _open_business],
			["İşleri yönet", GameState.action_manage],
		]],
		["Aile", [
			["Dışarı çık", GameState.action_socialize],
			["Buluşma", GameState.action_date],
			["Evlen", GameState.action_marry],
			["Çocuk sahibi ol", GameState.action_have_baby],
		]],
		["Diğer", [
			["Harçlık ver (+10)", GameState.give_money.bind(10)],
			["Yeni oyun", _confirm_reset],
		]],
	]
	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 6)
	col.add_child(tab_row)
	for i in tabs.size():
		var tb := _button(tabs[i][0], 20)
		tb.toggle_mode = true
		tb.custom_minimum_size.y = 56
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tb.pressed.connect(_select_tab.bind(i))
		tab_row.add_child(tb)
		tab_buttons.append(tb)
	actions_grid = GridContainer.new()
	actions_grid.columns = 2
	actions_grid.add_theme_constant_override("h_separation", 10)
	actions_grid.add_theme_constant_override("v_separation", 10)
	actions_grid.custom_minimum_size.y = 170
	col.add_child(actions_grid)
	_select_tab(0)

	_build_death_panel(layer)


func _select_tab(index: int) -> void:
	current_tab = index
	for i in tab_buttons.size():
		tab_buttons[i].set_pressed_no_signal(i == index)
	for c in actions_grid.get_children():
		c.queue_free()
	action_buttons.clear()
	for d in tabs[index][1]:
		var b := _button(d[0], 24)
		b.custom_minimum_size = Vector2(0, 80)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(d[1])
		b.disabled = GameState.is_dead
		actions_grid.add_child(b)
		action_buttons.append(b)


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


func _open_jobs() -> void:
	var w := AcceptDialog.new()
	w.title = "İş ilanları"
	w.ok_button_text = "Kapat"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	w.add_child(box)
	var available: Array = GameState.get_available_jobs()
	for j in GameState.JOBS:
		var row := HBoxContainer.new()
		box.add_child(row)
		var l := _label(20)
		var req: String = GameState.job_requirement_text(j)
		l.text = "%s — %d para / %d saat\n%s" % [j.name, j.pay, int(j.hours), req if req != "" else "Başvurabilir"]
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var b := _button("Mevcut" if GameState.person.job == j.id else "Başvur", 20)
		b.custom_minimum_size = Vector2(120, 60)
		b.disabled = not available.has(j) or GameState.person.job == j.id
		b.pressed.connect(GameState.take_job.bind(j.id))
		b.pressed.connect(w.queue_free)
		row.add_child(b)
	w.confirmed.connect(w.queue_free)
	w.canceled.connect(w.queue_free)
	add_child(w)
	w.popup_centered(Vector2i(520, 0))


# --- İşletme penceresi ---
var _biz_box: VBoxContainer
var _biz_sig := ""


func _open_business() -> void:
	var w := AcceptDialog.new()
	w.title = "İşletmeler"
	w.ok_button_text = "Kapat"
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(600, 760)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	w.add_child(scroll)
	_biz_box = VBoxContainer.new()
	_biz_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_biz_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_biz_box)
	_biz_sig = ""
	_fill_business()
	GameState.changed.connect(_fill_business)
	var close := func():
		if GameState.changed.is_connected(_fill_business):
			GameState.changed.disconnect(_fill_business)
		w.queue_free()
	w.confirmed.connect(close)
	w.canceled.connect(close)
	add_child(w)
	w.popup_centered()


func _fill_business() -> void:
	if not is_instance_valid(_biz_box):
		return
	# Sadece içerik değiştiyse yeniden kur (changed sinyali her karede gelir)
	var sig := "%d|%d|%d|%s" % [GameState.money, int(GameState.get_age_years()), int(GameState.person.education), JSON.stringify(GameState.businesses)]
	if sig == _biz_sig:
		return
	_biz_sig = sig
	for c in _biz_box.get_children():
		c.queue_free()
	var title: String = GameState.get_title()
	var head := _label(22)
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.text = "%s · Unvan: %s\nToplam değer: %d · Para: %d" % [
		GameState.get_holding_name() if title == "Holding Sahibi" else "%s ailesi" % GameState.family_name,
		title if title != "" else "yok", GameState.total_business_value(), GameState.money]
	_biz_box.add_child(head)

	_biz_box.add_child(_section("Sahip olunan işletmeler"))
	if GameState.businesses.is_empty():
		var l := _label(20)
		l.text = "Henüz işletme yok."
		_biz_box.add_child(l)
	for i in GameState.businesses.size():
		var b: Dictionary = GameState.businesses[i]
		var t: Dictionary = GameState.get_business_type(b.type)
		var row := HBoxContainer.new()
		_biz_box.add_child(row)
		var l := _label(20)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.text = "%s (Sv %d)\nGünlük +%d · Moral %d%%" % [t.name, int(b.level), GameState.business_income(b), int(b.morale)]
		row.add_child(l)
		var up := _button("Büyüt\n%d" % GameState.business_upgrade_cost(b) if b.level < GameState.MAX_BUSINESS_LEVEL else "Maks.", 18)
		up.custom_minimum_size = Vector2(110, 64)
		up.disabled = b.level >= GameState.MAX_BUSINESS_LEVEL or GameState.money < GameState.business_upgrade_cost(b)
		up.pressed.connect(GameState.upgrade_business.bind(i))
		row.add_child(up)
		var sell := _button("Sat\n+%d" % int(b.invested * GameState.BUSINESS_SELL_RATIO), 18)
		sell.custom_minimum_size = Vector2(100, 64)
		sell.pressed.connect(GameState.sell_business.bind(i))
		row.add_child(sell)

	_biz_box.add_child(_section("Yeni işletme kur"))
	for t in GameState.BUSINESS_TYPES:
		var row := HBoxContainer.new()
		_biz_box.add_child(row)
		var l := _label(20)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var req: String = GameState.business_requirement_text(t)
		l.text = "%s — %d para\nGünlük ~%d · %s" % [t.name, t.cost, t.income, req if req != "" else "Kurulabilir"]
		row.add_child(l)
		var b := _button("Kur", 20)
		b.custom_minimum_size = Vector2(100, 64)
		b.disabled = not GameState.can_open_business(t.id)
		b.pressed.connect(GameState.open_business.bind(t.id))
		row.add_child(b)


func _section(text: String) -> Label:
	var l := _label(22)
	l.text = text
	l.add_theme_color_override("font_color", Color(1, 0.8, 0.4))
	return l


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
	var biz_line := ""
	if not GameState.businesses.is_empty():
		var title: String = GameState.get_title()
		biz_line = "\n%s · %d işletme · %s" % [
			GameState.get_holding_name() if title == "Holding Sahibi" else "%s ailesi" % GameState.family_name,
			GameState.businesses.size(), title]
	var job: Dictionary = GameState.get_job()
	var fam := "Bekâr"
	if GameState.has_partner():
		fam = "%s: %s (ilişki %d)" % ["Eş" if GameState.is_married() else "Sevgili", p.partner.name, int(p.partner.relation)]
	fam += " · Çocuk: %d" % p.children.size()
	info_label.text = "%s %s, %d yaş · %s%s\nGün %d · %s · Nesil %d\nEğitim %d · Tecrübe %d · İş: %s\n%s" % [
		p.name, GameState.family_name, int(GameState.get_age_years()), stage.name, status,
		GameState.get_day(), GameState.get_clock_text(), GameState.generation,
		int(p.education), int(p.experience), job.get("name", "yok"), fam] + biz_line
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
