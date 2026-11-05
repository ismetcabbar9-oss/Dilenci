class_name UiStyle
extends RefCounted
## "Kil + Şeker" arayüz stili: parlak renkler, kabartmalı (alt kenarı kalın) kutular,
## yuvarlak Nunito yazı tipi, mantar gibi açılma animasyonları.

const FONT_BOLD := preload("res://assets/ui/fonts/Nunito-800.ttf")
const FONT_BLACK := preload("res://assets/ui/fonts/Nunito-900.ttf")

const YELLOW := Color(1.0, 0.79, 0.2)
const GREEN := Color(0.36, 0.8, 0.42)
const BLUE := Color(0.31, 0.7, 1.0)
const CORAL := Color(1.0, 0.48, 0.35)
const PINK := Color(1.0, 0.45, 0.6)
const PURPLE := Color(0.62, 0.5, 1.0)
const TEAL := Color(0.25, 0.8, 0.78)
const CREAM := Color(1.0, 0.965, 0.91)
const CREAM_DARK := Color(0.94, 0.83, 0.68)
const TEXT_DARK := Color(0.42, 0.24, 0.12)
const TEXT_LIGHT := Color(1, 1, 1)

const ICON_DIR := "res://assets/ui/icons/"

static var _theme: Theme


static func icon(name: String) -> Texture2D:
	var path := ICON_DIR + name + ".png"
	return load(path) if ResourceLoader.exists(path) else null


## Kabartmalı kutu: alt kenar koyu ve kalın (yükselti), gölge.
static func clay_box(c: Color, radius: int = 20, depth: int = 7, pressed := false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(radius)
	s.border_color = c.darkened(0.28)
	s.border_width_bottom = 2 if pressed else depth
	s.shadow_color = Color(0, 0, 0, 0.22 if not pressed else 0.12)
	s.shadow_size = 6 if not pressed else 2
	s.shadow_offset = Vector2(0, 4 if not pressed else 1)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 8 + (depth - 2 if pressed else 0)
	s.content_margin_bottom = 8 + (0 if pressed else depth - 2)
	s.anti_aliasing = true
	return s


## Krem kil panel (üst bilgi paneli, pencereler).
static func panel_box(c: Color = CREAM, radius: int = 28) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(radius)
	s.border_color = c.darkened(0.12)
	s.border_width_bottom = 10
	s.shadow_color = Color(0.35, 0.18, 0.05, 0.35)
	s.shadow_size = 14
	s.shadow_offset = Vector2(0, 8)
	s.set_content_margin_all(18)
	s.content_margin_bottom = 24
	return s


static func make_theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = FONT_BOLD
	t.default_font_size = 24
	t.set_color("font_color", "Label", TEXT_DARK)
	t.set_color("font_color", "CheckButton", TEXT_DARK)
	t.set_color("font_pressed_color", "CheckButton", TEXT_DARK)
	t.set_color("font_hover_color", "CheckButton", TEXT_DARK)
	t.set_color("font_hover_pressed_color", "CheckButton", TEXT_DARK)
	# Kaydırma çubuğu: ince ve yuvarlak
	var grab := StyleBoxFlat.new()
	grab.bg_color = CREAM_DARK.darkened(0.2)
	grab.set_corner_radius_all(6)
	grab.content_margin_left = 5
	grab.content_margin_right = 5
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", grab)
	t.set_stylebox("grabber_pressed", "VScrollBar", grab)
	var sb := StyleBoxEmpty.new()
	sb.content_margin_left = 5
	sb.content_margin_right = 5
	t.set_stylebox("scroll", "VScrollBar", sb)
	_theme = t
	return t


## Mantar gibi açılma: küçükten büyüğe, hafif taşıp yerine oturur.
static func pop_in(c: Control, delay: float = 0.0) -> void:
	if not c.is_inside_tree():
		await c.ready
	c.pivot_offset = c.size / 2.0
	c.scale = Vector2.ONE * 0.15
	c.modulate.a = 0.0
	var tw := c.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_callback(func(): c.pivot_offset = c.size / 2.0)
	tw.set_parallel(true)
	tw.tween_property(c, "modulate:a", 1.0, 0.14)
	tw.tween_property(c, "scale", Vector2.ONE * 1.12, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.set_parallel(false)
	tw.tween_property(c, "scale", Vector2.ONE * 0.96, 0.08).set_trans(Tween.TRANS_SINE)
	tw.tween_property(c, "scale", Vector2.ONE, 0.08).set_trans(Tween.TRANS_SINE)


## Küçülerek kaybolma; bitince on_done çağrılır.
static func pop_out(c: Control, on_done: Callable = Callable()) -> void:
	if not is_instance_valid(c):
		if on_done.is_valid():
			on_done.call()
		return
	c.pivot_offset = c.size / 2.0
	var tw := c.create_tween().set_parallel(true)
	tw.tween_property(c, "scale", Vector2.ONE * 0.6, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(c, "modulate:a", 0.0, 0.14)
	if on_done.is_valid():
		tw.chain().tween_callback(on_done)


## Kısa titreşim (sadece telefonda).
static func haptic(ms: int = 12) -> void:
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(ms)
