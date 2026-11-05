extends Node
## İlk açılış rehberi ve bağlamsal ipuçları.
## - İlk açılışta adım adım tanıtım (ilgili arayüz parçası sarı çerçeveyle vurgulanır).
## - Oyun sırasında doğru anda bir kez gösterilen ipuçları.
## Görülenler user://settings.cfg [guide] bölümünde saklanır (Yeni oyun ile sıfırlanmaz).

const SETTINGS_PATH := "user://settings.cfg"

var layer: CanvasLayer
var targets := {}            # "top", "speed", "actions", "nav" -> Control
var make_label: Callable     # main._label
var make_button: Callable    # main._button

var _seen := {}
var _step := -1
var _overlay: Control
var _check_timer := 0.0
var _speed_before := -1   # Kart açıkken zaman durur

const INTRO := [
	{"title": "Hoş geldin!", "target": "",
		"text": "Bu küçük çocuğun bütün hayatı senin elinde. Onu besle, okula gönder, iş bulmasına yardım et. Bir gün kendi holdingini kurabilir!"},
	{"title": "İhtiyaçlar", "target": "top",
		"text": "Üstteki çubuklar ihtiyaçlarını gösterir. Kırmızıya dönerse hemen ilgilen; uzun süre ihmal edilirse sağlığı bozulur."},
	{"title": "Zaman", "target": "speed",
		"text": "1x hızda bir gün 6 dakika sürer; 3x ücretsizdir, uyurken zaman kendiliğinden hızlanır. 10x Hızlı mod reklamla açılır. Oyunu kapatsan da zaman yavaşça işler!"},
	{"title": "Eylemler", "target": "actions",
		"text": "Ne yapacağını alttaki sekmelerden seç: Bakım, Kariyer, İşletme, Aile ve Mağaza."},
	{"title": "Evini gez", "target": "nav",
		"text": "Karakter yaptığı işe göre evde dolaşır. Okları kullanarak odalara göz atabilirsin. Her gün uğrayıp günlük ödülünü almayı unutma!"},
]

# [id, koşul, başlık, metin]
var _tips: Array = []


func _ready() -> void:
	_load()
	_tips = [
		["hungry", func(): return GameState.person.needs.hunger < 30.0,
			"Karnı acıktı!", "Bakım sekmesinden 'Ye' ile karnını doyur."],
		["tired", func(): return GameState.person.needs.energy < 20.0 and not GameState.sleeping,
			"Çok yorgun", "Bakım sekmesinden 'Uyu' ile dinlenmesini sağla. Uyurken zaman hızlı geçirilebilir."],
		["dirty", func(): return GameState.person.needs.hygiene < 25.0,
			"Temizlik", "Biraz kirlenmiş. Bakım sekmesinden 'Yıkan'."],
		["school", func(): return GameState.get_age_years() >= 6.5 and GameState.person.education < 3.0,
			"Okul zamanı", "Kariyer sekmesinden 'Okul / Üniversite'. Eğitim, ileride daha iyi işlerin ve işletmelerin kapısını açar."],
		["teen_job", func(): return GameState.get_age_years() >= 13.0 and GameState.person.job == "",
			"İlk iş!", "13 yaşına girdi. Kariyer → 'İş bul' ile harçlığını kendisi kazanabilir."],
		["adult", func(): return GameState.get_age_years() >= 18.0,
			"Artık yetişkin", "Bundan sonra yemek ve ev giderleri onun cebinden çıkar. Çalış, para biriktir ve İşletme → 'İşletmelerim' ile ilk işini kur!"],
		["love", func(): return GameState.get_age_years() >= 20.0 and not GameState.has_partner(),
			"Aşk kapıda", "Aile → 'Dışarı çık' ile yeni insanlarla tanışabilir. İlişki güçlenince evlenip çocuk sahibi olabilir."],
		["morale", func():
			for b in GameState.businesses:
				if b.morale < 50.0:
					return true
			return false,
			"Çalışanlar mutsuz", "İşletmelerin morali düşünce kâr azalır. İşletme → 'İşleri yönet'."],
		["home", func(): return GameState.home_level == 0 and GameState.money >= 2500 and GameState.get_age_years() >= 18.0,
			"Kendi evin", "Artık bir daire alabilirsin! İşletme → 'Ev satın al'. Kira biter, daha iyi dinlenir."],
		["old", func(): return GameState.get_age_years() >= 60.0,
			"Yaşlılık", "Hayat sonsuz değil. Öldüğünde çocuklarından biri mirası devralır ve hikâye devam eder."],
	]


func start_intro_if_needed() -> void:
	if not _seen.get("intro", false):
		_step = 0
		_show_step()


func _process(delta: float) -> void:
	if _step >= 0 or is_instance_valid(_overlay):
		return
	_check_timer += delta
	if _check_timer < 1.0:
		return
	_check_timer = 0.0
	if GameState.is_dead or not Events.pending.is_empty():
		return
	for t in _tips:
		if _seen.get(t[0], false):
			continue
		if t[1].call():
			_seen[t[0]] = true
			_save()
			_show_card(t[2], t[3], "", func(): pass)
			return


func _show_step() -> void:
	var s: Dictionary = INTRO[_step]
	var last := _step == INTRO.size() - 1
	_show_card(s.title, s.text, s.target, _next_step, "Başla!" if last else "İleri", "%d/%d" % [_step + 1, INTRO.size()])


func _next_step() -> void:
	_step += 1
	if _step >= INTRO.size():
		_step = -1
		_seen["intro"] = true
		_save()
		return
	_show_step()


## Kart: karartılmış arka plan, isteğe bağlı vurgulanan arayüz parçası, metin ve buton.
func _show_card(title: String, text: String, target: String, on_ok: Callable, ok_text: String = "Tamam", counter: String = "") -> void:
	if is_instance_valid(_overlay):
		_overlay.queue_free()
	if _speed_before < 0 and GameState.speed_index > 0:
		_speed_before = GameState.speed_index
		GameState.set_speed(0)
	_overlay = Control.new()
	_overlay.theme = UiStyle.make_theme()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(dim)

	var card_y := 470.0
	if target != "" and targets.has(target) and is_instance_valid(targets[target]):
		var c: Control = targets[target]
		var r := c.get_global_rect().grow(6)
		var frame := Panel.new()
		var st := StyleBoxFlat.new()
		st.bg_color = Color(0, 0, 0, 0)
		st.border_color = Color(1.0, 0.85, 0.3)
		st.set_border_width_all(5)
		st.set_corner_radius_all(14)
		frame.add_theme_stylebox_override("panel", st)
		frame.position = r.position
		frame.size = r.size
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_overlay.add_child(frame)
		# Kartı vurgulanan alanın üstüne binmeyecek yere koy
		card_y = r.end.y + 20.0 if r.get_center().y < 640.0 else maxf(120.0, r.position.y - 380.0)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.panel_box())
	_overlay.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var tip_icon := TextureRect.new()
	tip_icon.texture = UiStyle.icon("tip")
	tip_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tip_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tip_icon.custom_minimum_size = Vector2(42, 42)
	head.add_child(tip_icon)
	var t: Label = make_label.call(30)
	t.text = title
	t.add_theme_font_override("font", UiStyle.FONT_BLACK)
	t.add_theme_color_override("font_color", UiStyle.BLUE.darkened(0.35))
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	if counter != "":
		var cl: Label = make_label.call(20)
		cl.text = counter
		head.add_child(cl)
	var body: Label = make_label.call(24)
	body.text = text
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size.x = 600
	box.add_child(body)
	var b: Button = make_button.call(ok_text, 24)
	b.clay_color = UiStyle.GREEN
	b.custom_minimum_size.y = 76
	box.add_child(b)
	b.pressed.connect(func():
		if is_instance_valid(_overlay):
			var ov := _overlay
			UiStyle.pop_out(panel, ov.queue_free)
		if _speed_before >= 0 and Events.pending.is_empty():
			GameState.set_speed(_speed_before)
		_speed_before = -1
		on_ok.call())
	panel.reset_size()
	var vw := layer.get_viewport().get_visible_rect().size.x
	panel.position = Vector2((vw - panel.size.x) / 2.0, card_y)
	UiStyle.pop_in(panel)


func reset_for_tests() -> void:
	_seen = {}
	_save()


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)  # Ses ayarlarını korumak için önce oku
	for k in _seen:
		cfg.set_value("guide", k, _seen[k])
	if _seen.is_empty() and cfg.has_section("guide"):
		cfg.erase_section("guide")
	cfg.save(SETTINGS_PATH)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK and cfg.has_section("guide"):
		for k in cfg.get_section_keys("guide"):
			_seen[k] = cfg.get_value("guide", k)
