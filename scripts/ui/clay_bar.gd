class_name ClayBar
extends ProgressBar
## 3B görünümlü ihtiyaç çubuğu: içe gömük oluk, kabartmalı dolgu, parlak şerit.
## Değer yumuşakça akar; kritik seviyede kırmızı yanıp söner.

var _target := 0.0
var _time := 0.0
var _last_band := -1


func _init() -> void:
	max_value = 100
	show_percentage = false
	custom_minimum_size = Vector2(0, 28)
	var bg := StyleBoxFlat.new()
	bg.bg_color = UiStyle.CREAM_DARK.lightened(0.25)
	bg.set_corner_radius_all(14)
	bg.border_color = UiStyle.CREAM_DARK.darkened(0.15)
	bg.border_width_top = 4   # içe gömük oluk hissi
	add_theme_stylebox_override("background", bg)
	_set_fill(UiStyle.GREEN)


func _set_fill(c: Color) -> void:
	var f := StyleBoxFlat.new()
	f.bg_color = c
	f.set_corner_radius_all(14)
	f.border_color = c.darkened(0.25)
	f.border_width_bottom = 6
	add_theme_stylebox_override("fill", f)


func set_target(v: float) -> void:
	_target = clampf(v, 0.0, 100.0)
	var band := 0 if _target < 25.0 else (1 if _target < 50.0 else 2)
	if band != _last_band:
		_last_band = band
		_set_fill([UiStyle.CORAL.lerp(Color(0.95, 0.25, 0.25), 0.5), UiStyle.YELLOW, UiStyle.GREEN][band])


func _process(delta: float) -> void:
	_time += delta
	if absf(value - _target) > 0.05:
		value = lerpf(value, _target, clampf(delta * 6.0, 0.0, 1.0))
	# Kritik seviyede nabız gibi yanıp sönme
	if _target < 25.0:
		self_modulate = Color(1, 1, 1).lerp(Color(1, 0.6, 0.6), (sin(_time * 7.0) + 1.0) * 0.5)
	else:
		self_modulate = Color.WHITE
	queue_redraw()


func _draw() -> void:
	# Dolgu üzerinde parlak şerit
	var w := size.x * (value / max_value)
	if w > 16.0:
		var hl := StyleBoxFlat.new()
		hl.bg_color = Color(1, 1, 1, 0.45)
		hl.set_corner_radius_all(4)
		draw_style_box(hl, Rect2(Vector2(8, 5), Vector2(w - 16, 5)))
