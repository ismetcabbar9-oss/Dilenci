extends Node3D
## Ana sahne: 3D oda + karakter + arayüz (kod ile kuruluyor).

const CharacterScript := preload("res://scripts/character.gd")
const HomeScript := preload("res://scripts/home.gd")

# Kamera, odanın merkezine göre bu ofsetten bakar
const CAM_OFFSET := Vector3(2.2, 5.6, 8.6)
const CAM_LOOK := Vector3(0.0, 1.4, 0.5)

var character: Node3D
var camera: Camera3D
var home: Node3D
var sun: DirectionalLight3D
var env: Environment
var lamp: OmniLight3D

# UI
var info_label: Label
var money_label: Label
var msg_label: Label
var room_label: Label
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

var _focus_room := 0          # Kameranın baktığı oda
var _char_room := 0           # Karakterin bulunduğu oda
var _char_target := Vector3.ZERO
var _manual_focus := false
var _ui_layer: CanvasLayer
var _event_card: PanelContainer
var _event_card_timer := 0.0
var _event_modal: Control
var guide: Node
var _guide_targets := {}    # Oyuncu oklarla gezerken kamerayı karaktere bağlama
var _was_sleeping := false

# Eylem sekmeleri: [sekme adı, [[buton, callable], ...]]
var tabs: Array = []


func _ready() -> void:
	_build_world()
	_build_ui()
	GameState.changed.connect(_refresh_ui)
	GameState.changed.connect(_on_state_changed)
	GameState.message.connect(_show_message)
	GameState.died.connect(_on_died)
	GameState.acted.connect(_on_acted)
	Store.wallet_changed.connect(_refresh_ui)
	Events.event_happened.connect(_show_event_card)
	Events.choice_requested.connect(_show_event_choice)
	Goals.achievement_unlocked.connect(func(a): _show_event_card({"id": "achievement", "title": "Başarım: " + a.name, "text": a.desc, "result": "+%d elmas" % a.gems}))
	_rebuild_home()
	_refresh_ui()
	guide.start_intro_if_needed.call_deferred()
	if GameState.is_dead:
		_on_died("")


func _process(delta: float) -> void:
	# Karakter hedefe yürür
	var to := _char_target - character.position
	to.y = 0.0
	var dist := to.length()
	if dist > 0.05:
		var step := minf(dist, delta * (6.0 if dist > 2.0 else 2.5))
		character.position += to.normalized() * step
		character.rotation.y = lerp_angle(character.rotation.y, atan2(to.x, to.z), clampf(delta * 8.0, 0.0, 1.0))
		character.set_moving(true)
	else:
		character.set_moving(false)
		# Uyurken yatak boyunca (baş arka duvara), uyanıkken kameraya dönük
		var face: float = home.room_for_action("sleep").get("bed_yaw", 0.0) if GameState.sleeping else 0.35
		character.rotation.y = lerp_angle(character.rotation.y, face, clampf(delta * 6.0, 0.0, 1.0))
	character.position.y = lerpf(character.position.y, _char_target.y, clampf(delta * 5.0, 0.0, 1.0))

	# Kamera odayı takip eder
	if not _manual_focus:
		_focus_room = _char_room
	if not home.rooms.is_empty():
		var c: Vector3 = home.rooms[clampi(_focus_room, 0, home.rooms.size() - 1)].center
		var desired := c + CAM_OFFSET
		camera.position = camera.position.lerp(desired, clampf(delta * 3.0, 0.0, 1.0))
		camera.look_at(camera.position - CAM_OFFSET + CAM_LOOK)

	_update_daylight()
	if _event_card_timer > 0.0:
		_event_card_timer -= delta
		if _event_card_timer <= 0.0 and is_instance_valid(_event_card):
			_event_card.queue_free()
	if _msg_timer > 0.0:
		_msg_timer -= delta
		if _msg_timer <= 0.0:
			msg_label.text = ""


# ---------------------------------------------------------------
# 3D dünya
# ---------------------------------------------------------------
func _build_world() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.2, 0.22, 0.28)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.8, 0.85)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 40, 0)
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	add_child(sun)

	camera = Camera3D.new()
	camera.fov = 45
	add_child(camera)

	home = HomeScript.new()
	add_child(home)

	lamp = OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.8, 0.55)
	lamp.omni_range = 5.0
	lamp.light_energy = 0.0
	add_child(lamp)

	character = CharacterScript.new()
	add_child(character)
	family_root = Node3D.new()
	add_child(family_root)


func _rebuild_home() -> void:
	home.build(GameState.home_level)
	_family_signature = ""
	_refresh_family()
	var r: Dictionary = home.room_for_action("sleep" if GameState.sleeping else "idle")
	_char_room = home.room_index(r.id)
	_char_target = _spot_for_current_state()
	character.position = _char_target
	_manual_focus = false
	if not home.rooms.is_empty():
		camera.position = home.rooms[_char_room].center + CAM_OFFSET
		camera.look_at(home.rooms[_char_room].center + CAM_LOOK)
	_update_room_label()


func _spot_for_current_state() -> Vector3:
	if GameState.sleeping:
		var r: Dictionary = home.room_for_action("sleep")
		if r.bed != Vector3.INF:
			return r.bed
		return home.stand_spot(r)
	return home.stand_spot(home.rooms[_char_room])


func _on_state_changed() -> void:
	if home.built_level != GameState.home_level:
		_rebuild_home()
		return
	_refresh_family()
	if GameState.sleeping != _was_sleeping:
		_was_sleeping = GameState.sleeping
		var r: Dictionary = home.room_for_action("sleep" if GameState.sleeping else "idle")
		_char_room = home.room_index(r.id)
		_char_target = _spot_for_current_state()
		_manual_focus = false
		_update_room_label()


func _on_acted(kind: String) -> void:
	var r: Dictionary = home.room_for_action(kind)
	_char_room = home.room_index(r.id)
	_char_target = home.stand_spot(r)
	_manual_focus = false
	character.play_action(kind)
	_update_room_label()


func _browse_room(step: int) -> void:
	if home.rooms.is_empty():
		return
	_manual_focus = true
	_focus_room = wrapi(_focus_room + step, 0, home.rooms.size())
	_update_room_label()


func _update_room_label() -> void:
	if room_label == null or home.rooms.is_empty():
		return
	var r: Dictionary = home.rooms[clampi(_focus_room if _manual_focus else _char_room, 0, home.rooms.size() - 1)]
	room_label.text = "%s · %s" % [GameState.get_home().name, home.ROOM_NAMES.get(r.id, "")]


## Gece-gündüz: güneş açısı, ışık rengi ve gece lambası oyun saatine göre.
func _update_daylight() -> void:
	var minute_of_day := fmod(GameState.game_minutes, 1440.0)
	var hour := minute_of_day / 60.0
	# 6:00 doğuş, 18:00 batış; gün ışığı 0..1
	var day := clampf(sin((hour - 6.0) / 12.0 * PI), 0.0, 1.0)
	var dusk := clampf(1.0 - absf(hour - 18.5) / 1.5, 0.0, 1.0) + clampf(1.0 - absf(hour - 6.5) / 1.5, 0.0, 1.0)
	sun.light_energy = 0.12 + day * 0.6
	sun.light_color = Color(1, 1, 1).lerp(Color(1.0, 0.6, 0.35), clampf(dusk, 0.0, 1.0))
	sun.rotation_degrees.x = -20.0 - day * 45.0
	env.ambient_light_color = Color(0.35, 0.4, 0.6).lerp(Color(0.85, 0.85, 0.9), day)
	env.ambient_light_energy = 0.3 + day * 0.15
	env.background_color = Color(0.05, 0.06, 0.12).lerp(Color(0.45, 0.65, 0.85), day)
	# Lamba karakterin odasında, karanlıkta yanar
	lamp.light_energy = (1.0 - day) * 1.4
	if not home.rooms.is_empty():
		lamp.position = home.rooms[clampi(_focus_room, 0, home.rooms.size() - 1)].center + Vector3(0, 2.2, 0.6)


## Eş ve çocukları oturma odasında göster (sadece aile değişince yeniden kurulur).
func _refresh_family() -> void:
	var p: Dictionary = GameState.person
	var members: Array = []
	if not p.get("partner", {}).is_empty():
		members.append(p.partner)
	for c in p.get("children", []):
		members.append(c)
	var sig := "%d|" % GameState.home_level
	for m in members:
		sig += "%s:%d;" % [m.name, int(GameState.minutes_to_years(m.age_minutes))]
	if sig == _family_signature:
		return
	_family_signature = sig
	for c in family_root.get_children():
		c.queue_free()
	if home.rooms.is_empty():
		return
	var room: Dictionary = home.room_for_action("idle")
	for i in mini(members.size(), 5):
		var m: Dictionary = members[i]
		var fig = CharacterScript.new()
		fig.setup(GameState.minutes_to_years(m.age_minutes), m.gender, Color.WHITE)
		fig.position = home.stand_spot(room, i + 1)
		fig.rotation.y = randf_range(-0.6, 0.6)
		family_root.add_child(fig)


# ---------------------------------------------------------------
# Arayüz
# ---------------------------------------------------------------
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_ui_layer = layer

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
	_guide_targets["top"] = top
	top.add_theme_stylebox_override("panel", _panel_style())
	col.add_child(top)
	var top_col := VBoxContainer.new()
	top.add_child(top_col)

	var header := HBoxContainer.new()
	top_col.add_child(header)
	info_label = _label(24)
	info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # Uzun satırlar para yazısına binmesin
	header.add_child(info_label)
	money_label = _label(24)
	money_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
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
	_guide_targets["speed"] = speed_row
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

	# Oda gezinme: < Oda adı >
	var nav := HBoxContainer.new()
	_guide_targets["nav"] = nav
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(nav)
	var prev := _button("<", 26)
	prev.custom_minimum_size = Vector2(70, 56)
	prev.pressed.connect(_browse_room.bind(-1))
	nav.add_child(prev)
	room_label = _label(22)
	room_label.custom_minimum_size.x = 380
	room_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	room_label.add_theme_color_override("font_outline_color", Color.BLACK)
	room_label.add_theme_constant_override("outline_size", 6)
	nav.add_child(room_label)
	var nxt := _button(">", 26)
	nxt.custom_minimum_size = Vector2(70, 56)
	nxt.pressed.connect(_browse_room.bind(1))
	nav.add_child(nxt)

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
			["Okul / Üniversite", GameState.action_school],
			["İşe git", GameState.action_work],
			["İş bul", _open_jobs],
			["Emekli ol", _confirm_retire],
		]],
		["İşletme", [
			["İşletmelerim", _open_business],
			["İşleri yönet", GameState.action_manage],
			["Ev satın al", _open_homes],
		]],
		["Aile", [
			["Dışarı çık", GameState.action_socialize],
			["Buluşma", GameState.action_date],
			["Evlen", GameState.action_marry],
			["Çocuk sahibi ol", GameState.action_have_baby],
		]],
		["Hedefler", [
			["Lüks varlıklar", _open_luxury],
			["Hayır işleri", _open_projects],
			["Başarımlar", _open_achievements],
			["Aile ağacı", _open_family_tree],
		]],
		["Mağaza", [
			["Mağaza", _open_store],
			["Günlük ödül", Store.claim_daily],
			["Ayarlar", _open_settings],
			["Yeni oyun", _confirm_reset],
		]],
	]
	var bottom := VBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	col.add_child(bottom)
	_guide_targets["actions"] = bottom
	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 6)
	bottom.add_child(tab_row)
	for i in tabs.size():
		var tb := _button(tabs[i][0], 17)
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
	bottom.add_child(actions_grid)
	_select_tab(0)

	_build_death_panel(layer)

	guide = preload("res://scripts/guide.gd").new()
	guide.layer = layer
	guide.targets = _guide_targets
	guide.make_label = _label
	guide.make_button = _button
	add_child(guide)


func _open_settings() -> void:
	var w := AcceptDialog.new()
	w.title = "Ayarlar"
	w.ok_button_text = "Kapat"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	w.add_child(box)
	for item in [["Müzik", Audio.music_on, Audio.set_music], ["Ses efektleri", Audio.sfx_on, Audio.set_sfx]]:
		var c := CheckButton.new()
		c.text = item[0]
		c.button_pressed = item[1]
		c.add_theme_font_size_override("font_size", 26)
		c.custom_minimum_size = Vector2(420, 70)
		c.toggled.connect(item[2])
		box.add_child(c)
	var cr := _label(18)
	cr.text = "Müzik: Kistol · Ses: Kenney, MintoDog (CC0)\n3D: Agor_, Stas_SayHallo, IsaacTheMaverick, Brynnnnn (CC BY 4.0)"
	cr.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cr.custom_minimum_size.x = 420
	box.add_child(cr)
	w.confirmed.connect(w.queue_free)
	w.canceled.connect(w.queue_free)
	add_child(w)
	w.popup_centered()


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
		GameState.get_holding_name() if GameState.is_holding() else "%s ailesi" % GameState.family_name,
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
		if GameState.owns_business(t.id):
			b.text = "Sahip"
		b.pressed.connect(GameState.open_business.bind(t.id))
		row.add_child(b)


# --- Olaylar ---
func _event_panel(title: String, text: String, accent: Color) -> Array:
	var panel := PanelContainer.new()
	var st := _panel_style()
	st.bg_color = Color(0.12, 0.14, 0.22, 0.97)
	st.border_color = accent
	st.set_border_width_all(4)
	panel.add_theme_stylebox_override("panel", st)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var t := _label(30)
	t.text = title
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_color_override("font_color", accent)
	box.add_child(t)
	var body := _label(24)
	body.text = text
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.custom_minimum_size.x = 560
	box.add_child(body)
	return [panel, box]


## Anlık olay: birkaç saniye görünen kart (dokununca kapanır).
func _show_event_card(ev: Dictionary) -> void:
	if is_instance_valid(_event_card):
		_event_card.queue_free()
	var good: bool = not (ev.id in ["cold", "theft", "crisis"])
	var parts := _event_panel(ev.title, "%s\n%s" % [ev.text, ev.get("result", "")], Color(0.5, 1.0, 0.6) if good else Color(1.0, 0.5, 0.45))
	_event_card = parts[0]
	_ui_layer.add_child(_event_card)
	_event_card.reset_size()
	_event_card.position = Vector2((get_viewport().get_visible_rect().size.x - _event_card.size.x) / 2.0, 460)
	_event_card.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and is_instance_valid(_event_card):
			_event_card.queue_free())
	_event_card_timer = 4.5


## Seçimli olay: ekran kararır, oyuncu seçer (oyun bu sırada durur).
func _show_event_choice(ev: Dictionary) -> void:
	if is_instance_valid(_event_modal):
		_event_modal.queue_free()
	_event_modal = ColorRect.new()
	(_event_modal as ColorRect).color = Color(0, 0, 0, 0.55)
	_event_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui_layer.add_child(_event_modal)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_event_modal.add_child(center)
	var parts := _event_panel(ev.title, ev.text, Color(1.0, 0.8, 0.35))
	center.add_child(parts[0])
	var opts: Array = ev.options
	for i in opts.size():
		var b := _button(opts[i].label, 24)
		b.custom_minimum_size.y = 80
		b.pressed.connect(_on_event_choice.bind(i))
		parts[1].add_child(b)


func _on_event_choice(i: int) -> void:
	if is_instance_valid(_event_modal):
		_event_modal.queue_free()
	Events.choose(i)


# --- Hedefler ---
## Kaydırılabilir liste penceresi; rows: [[metin, buton yazısı, etkin mi, callable]]
func _list_dialog(title: String, header: String, rows: Array) -> void:
	var w := AcceptDialog.new()
	w.title = title
	w.ok_button_text = "Kapat"
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(600, mini(820, 140 + rows.size() * 84))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	w.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)
	if header != "":
		var h := _label(20)
		h.text = header
		h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		h.add_theme_color_override("font_color", Color(1, 0.8, 0.4))
		box.add_child(h)
	for r in rows:
		var row := HBoxContainer.new()
		box.add_child(row)
		var l := _label(19)
		l.text = r[0]
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		if r[1] != "":
			var b := _button(r[1], 18)
			b.custom_minimum_size = Vector2(130, 64)
			b.disabled = not r[2]
			if r[3] is Callable:
				b.pressed.connect(r[3])
				b.pressed.connect(w.queue_free)
			row.add_child(b)
	w.confirmed.connect(w.queue_free)
	w.canceled.connect(w.queue_free)
	add_child(w)
	w.popup_centered()


func _fmt_money(v: int) -> String:
	var s := str(v)
	var out := ""
	while s.length() > 3:
		out = "." + s.right(3) + out
		s = s.left(s.length() - 3)
	return s + out


func _open_luxury() -> void:
	var rows := []
	for it in Goals.LUXURY:
		var owned: bool = Goals.owned_luxury().has(it.id)
		rows.append(["%s — %s para\nPrestij +%d · her gün mutluluk +%d" % [it.name, _fmt_money(it.cost), it.prestige, int(it.fun)],
			"Sahip" if owned else "Satın al", not owned and GameState.money >= it.cost and GameState.get_age_years() >= 18.0,
			Goals.buy_luxury.bind(it.id)])
	_list_dialog("Lüks varlıklar", "Para: %s · Varlıklar aileye miras kalır." % _fmt_money(GameState.money), rows)


func _open_projects() -> void:
	var rows := []
	for p in Goals.PROJECTS:
		var done: bool = Goals.completed_projects().has(p.id)
		rows.append(["%s — %s para\n%s (+%d miras puanı, +%d elmas)" % [p.name, _fmt_money(p.cost), p.desc, p.legacy, p.gems],
			"Tamamlandı" if done else "Bağışla", not done and GameState.money >= p.cost, Goals.fund_project.bind(p.id)])
	_list_dialog("Hayır işleri", "Topluma katkı, aile adını nesiller boyu yaşatır. Para: %s" % _fmt_money(GameState.money), rows)


func _open_achievements() -> void:
	var rows := []
	var got: Array = Goals.unlocked()
	for a in Goals.ACHIEVEMENTS:
		var ok: bool = got.has(a.id)
		rows.append(["%s %s\n%s (+%d elmas)" % ["✔" if ok else "○", a.name, a.desc, a.gems], "", false, null])
	_list_dialog("Başarımlar", "%d / %d başarım" % [got.size(), Goals.ACHIEVEMENTS.size()], rows)


func _open_family_tree() -> void:
	var rows := []
	for f in GameState.family_tree:
		rows.append(["Nesil %d · %s · %d yaş · %s%s" % [int(f.generation), f.name, int(f.age), f.cause,
			(" · " + f.title) if f.get("title", "") != "" else ""], "", false, null])
	rows.append(["Nesil %d · %s · %d yaş · yaşıyor%s" % [GameState.generation, GameState.person.name,
		int(GameState.get_age_years()), (" · " + GameState.get_title()) if GameState.get_title() != "" else ""], "", false, null])
	_list_dialog("%s ailesi" % GameState.family_name, "Aile mirası puanı: %d" % Goals.legacy_score(), rows)


func _confirm_retire() -> void:
	if GameState.get_job().is_empty():
		GameState.message.emit("Emekli olacak bir işi yok.")
		return
	if GameState.get_age_years() < 60.0:
		GameState.message.emit("Emekli olmak için en az 60 yaşında olmalı.")
		return
	var d := ConfirmationDialog.new()
	d.dialog_text = "İşi bırakıp emekli olsun mu?\nHer gün %d emekli maaşı alır." % int(int(GameState.get_job().pay) * GameState.PENSION_RATIO)
	d.ok_button_text = "Emekli ol"
	d.cancel_button_text = "Vazgeç"
	d.confirmed.connect(GameState.retire)
	d.confirmed.connect(d.queue_free)
	d.canceled.connect(d.queue_free)
	add_child(d)
	d.popup_centered()


# --- Ev penceresi ---
func _open_homes() -> void:
	var w := AcceptDialog.new()
	w.title = "Evler"
	w.ok_button_text = "Kapat"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	w.add_child(box)
	var head := _label(20)
	head.text = "Ev sahibi olunca kira yerine daha düşük bakım gideri ödenir. Büyük evde daha hızlı dinlenilir ve mutluluk daha yavaş azalır. Ev aileye miras kalır."
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.custom_minimum_size.x = 560
	box.add_child(head)
	for i in GameState.HOMES.size():
		var h: Dictionary = GameState.HOMES[i]
		var row := HBoxContainer.new()
		box.add_child(row)
		var l := _label(20)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.text = "%s — %d oda\n%s · günlük gider %d" % [h.name, h.rooms.size(), ("%d para" % h.cost) if h.cost > 0 else "başlangıç", h.upkeep]
		row.add_child(l)
		var b := _button("Mevcut" if i == GameState.home_level else ("Sahip" if i < GameState.home_level else "Satın al"), 20)
		b.custom_minimum_size = Vector2(130, 64)
		b.disabled = i <= GameState.home_level or GameState.money < int(h.cost) or GameState.get_age_years() < 18.0
		b.pressed.connect(GameState.buy_home.bind(i))
		b.pressed.connect(w.queue_free)
		row.add_child(b)
	w.confirmed.connect(w.queue_free)
	w.canceled.connect(w.queue_free)
	add_child(w)
	w.popup_centered()


# --- Mağaza penceresi ---
var _store_box: VBoxContainer


func _open_store() -> void:
	var w := AcceptDialog.new()
	w.title = "Mağaza"
	w.ok_button_text = "Kapat"
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(600, 820)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	w.add_child(scroll)
	_store_box = VBoxContainer.new()
	_store_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_store_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_store_box)
	_fill_store()
	Store.wallet_changed.connect(_fill_store)
	var close := func():
		if Store.wallet_changed.is_connected(_fill_store):
			Store.wallet_changed.disconnect(_fill_store)
		w.queue_free()
	w.confirmed.connect(close)
	w.canceled.connect(close)
	add_child(w)
	w.popup_centered()


func _fill_store() -> void:
	if not is_instance_valid(_store_box):
		return
	for c in _store_box.get_children():
		c.queue_free()
	var head := _label(26)
	head.text = "Elmas: %d" % Store.gems
	head.add_theme_color_override("font_color", Color(0.5, 0.9, 1.0))
	_store_box.add_child(head)

	# Günlük ödül
	var daily := HBoxContainer.new()
	_store_box.add_child(daily)
	var dl := _label(20)
	dl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dl.text = "Günlük ödül: +%d elmas" % Store.next_daily_amount() if Store.can_claim_daily() else "Günlük ödül alındı · seri: %d gün" % Store.streak
	daily.add_child(dl)
	var db := _button("Al", 20)
	db.custom_minimum_size = Vector2(110, 60)
	db.disabled = not Store.can_claim_daily()
	db.pressed.connect(Store.claim_daily)
	daily.add_child(db)

	_store_box.add_child(_section("%s için" % GameState.person.name))
	for it in Store.ITEMS:
		var row := HBoxContainer.new()
		_store_box.add_child(row)
		var l := _label(20)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.text = "%s\n%s" % [it.name, it.desc]
		row.add_child(l)
		var b := _button("%d elmas" % it.price, 20)
		b.custom_minimum_size = Vector2(130, 64)
		b.disabled = Store.gems < it.price or GameState.is_dead
		b.pressed.connect(Store.buy_item.bind(it.id))
		row.add_child(b)

	_store_box.add_child(_section("Elmas paketleri" + (" (TEST MODU – ücretsiz)" if Store.TEST_MODE else "")))
	for p in Store.GEM_PACKS:
		var row := HBoxContainer.new()
		_store_box.add_child(row)
		var l := _label(20)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.text = "%s · %d elmas%s" % [p.name, p.gems, ("\n" + p.badge) if p.has("badge") else ""]
		row.add_child(l)
		var b := _button(p.price_label, 20)
		b.custom_minimum_size = Vector2(130, 64)
		b.pressed.connect(Store.purchase_pack.bind(p.id))
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
			GameState.get_holding_name() if GameState.is_holding() else "%s ailesi" % GameState.family_name,
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
	money_label.text = "Para: %d\nElmas: %d" % [GameState.money, Store.gems]
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
	b.pressed.connect(Audio.play.bind("click"))
	return b


func _panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.1, 0.12, 0.18, 0.85)
	s.set_corner_radius_all(16)
	s.set_content_margin_all(14)
	return s
