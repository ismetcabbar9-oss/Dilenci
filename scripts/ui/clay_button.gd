class_name ClayButton
extends Button
## Kil buton: kabartmalı görünüm, üstte parlak şerit, basınca çöküp yaylanır,
## dokunulan yerde ışık halkası yayılır ve telefon kısa titrer.

var clay_color := UiStyle.YELLOW:
	set(v):
		clay_color = v
		_apply_style()
var depth := 7
var radius := 20
var toggle_off_color := UiStyle.CREAM   # toggle butonlarda seçili değilken

var _ripple := 1.0    # 0 → 1: halka büyür ve söner
var _press_tween: Tween


func _init() -> void:
	focus_mode = Control.FOCUS_NONE
	add_theme_constant_override("icon_max_width", 40)
	add_theme_constant_override("h_separation", 8)
	add_theme_font_override("font", UiStyle.FONT_BLACK)


func _ready() -> void:
	_apply_style()
	button_down.connect(_on_down)
	button_up.connect(_on_up)
	toggled.connect(func(_on): _apply_style())
	resized.connect(func(): pivot_offset = size / 2.0)
	pivot_offset = size / 2.0


func _apply_style() -> void:
	var on := clay_color if (not toggle_mode or button_pressed) else toggle_off_color
	var text_c := UiStyle.TEXT_LIGHT if on.get_luminance() < 0.72 else UiStyle.TEXT_DARK
	add_theme_stylebox_override("normal", UiStyle.clay_box(on, radius, depth))
	add_theme_stylebox_override("hover", UiStyle.clay_box(on.lightened(0.06), radius, depth))
	# Seçili toggle (sekme, hız) kabarık ve renkli kalır; normal buton basılıyken çöker
	add_theme_stylebox_override("pressed", UiStyle.clay_box(on.darkened(0.05), radius, depth, not toggle_mode))
	add_theme_stylebox_override("hover_pressed", UiStyle.clay_box(on.darkened(0.05), radius, depth, not toggle_mode))
	add_theme_stylebox_override("disabled", UiStyle.clay_box(on.lerp(Color(0.75, 0.75, 0.75), 0.6), radius, depth))
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		add_theme_color_override(k, text_c)
	add_theme_color_override("font_disabled_color", text_c.lerp(Color(0.5, 0.5, 0.5), 0.6))
	add_theme_color_override("font_outline_color", on.darkened(0.45))
	add_theme_constant_override("outline_size", 6 if text_c == UiStyle.TEXT_LIGHT else 0)
	queue_redraw()


## Sinyal göndermeden seçili yap ve görünümü güncelle (sekme/hız butonları için).
func set_pressed_quiet(v: bool) -> void:
	set_pressed_no_signal(v)
	_apply_style()


func _on_down() -> void:
	if disabled:
		return
	UiStyle.haptic()
	if _press_tween:
		_press_tween.kill()
	_press_tween = create_tween()
	_press_tween.tween_property(self, "scale", Vector2(0.92, 0.9), 0.07).set_trans(Tween.TRANS_QUAD)
	_ripple = 0.0
	var rt := create_tween()
	rt.tween_method(_set_ripple, 0.0, 1.0, 0.45).set_ease(Tween.EASE_OUT)


func _set_ripple(v: float) -> void:
	_ripple = v
	queue_redraw()


func _on_up() -> void:
	if _press_tween:
		_press_tween.kill()
	_press_tween = create_tween()
	_press_tween.tween_property(self, "scale", Vector2(1.06, 1.05), 0.09).set_trans(Tween.TRANS_QUAD)
	_press_tween.tween_property(self, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _draw() -> void:
	# Üstte parlak "şeker" şeridi
	var hl := StyleBoxFlat.new()
	hl.bg_color = Color(1, 1, 1, 0.28 if not disabled else 0.1)
	hl.set_corner_radius_all(radius - 6)
	var top := 6.0 if not (button_pressed or is_pressed()) else 10.0
	draw_style_box(hl, Rect2(Vector2(10, top), Vector2(size.x - 20, minf(size.y * 0.22, 14))))
	# Basınca yayılan ışık halkası
	if _ripple < 1.0:
		var g := StyleBoxFlat.new()
		g.bg_color = Color(1, 1, 1, 0)
		g.draw_center = false
		g.border_color = Color(1, 1, 0.85, 0.75 * (1.0 - _ripple))
		g.set_border_width_all(5)
		g.set_corner_radius_all(radius + 6)
		var grow := 4.0 + _ripple * 18.0
		draw_style_box(g, Rect2(Vector2(-grow, -grow), size + Vector2(grow, grow) * 2.0))
		var flash := StyleBoxFlat.new()
		flash.bg_color = Color(1, 1, 1, 0.35 * (1.0 - _ripple))
		flash.set_corner_radius_all(radius)
		draw_style_box(flash, Rect2(Vector2.ZERO, size))
