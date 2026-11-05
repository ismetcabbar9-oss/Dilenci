class_name ClayDialog
extends CanvasLayer
## Kil stili pencere (AcceptDialog / ConfirmationDialog yerine).
## Aynı kullanım: title, ok_button_text, cancel_button_text, dialog_text, confirmed, canceled,
## içerik add_child ile eklenir, popup_centered() ile mantar gibi büyüyerek açılır.

signal confirmed
signal canceled

var title := ""
var dialog_text := ""
var ok_button_text := "Tamam"
var cancel_button_text := "Vazgeç"
var confirm := false   # true: iki butonlu onay penceresi

var _dim: ColorRect
var _panel: PanelContainer
var _content: VBoxContainer
var _closing := false


func _init() -> void:
	layer = 20


func popup_centered(_size = null) -> void:
	var user_children := get_children()
	_dim = ColorRect.new()
	_dim.color = Color(0.1, 0.05, 0.02, 0.0)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.gui_input.connect(_on_dim_input)
	add_child(_dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_panel = PanelContainer.new()
	_panel.theme = UiStyle.make_theme()
	_panel.add_theme_stylebox_override("panel", UiStyle.panel_box())
	center.add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_panel.add_child(box)
	if title != "":
		var t := Label.new()
		t.text = title
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		t.add_theme_font_override("font", UiStyle.FONT_BLACK)
		t.add_theme_font_size_override("font_size", 30)
		t.add_theme_color_override("font_color", UiStyle.CORAL.darkened(0.15))
		box.add_child(t)
	if dialog_text != "":
		var l := Label.new()
		l.text = dialog_text
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 520
		l.add_theme_font_size_override("font_size", 24)
		box.add_child(l)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 10)
	box.add_child(_content)
	for c in user_children:
		c.reparent(_content, false)
	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 14)
	box.add_child(footer)
	if confirm:
		var cb := ClayButton.new()
		cb.text = cancel_button_text
		cb.clay_color = UiStyle.CREAM
		cb.custom_minimum_size = Vector2(200, 72)
		cb.pressed.connect(_close.bind(false))
		footer.add_child(cb)
	var ok := ClayButton.new()
	ok.text = ok_button_text
	ok.clay_color = UiStyle.GREEN if confirm else UiStyle.BLUE
	ok.custom_minimum_size = Vector2(200, 72)
	ok.pressed.connect(_close.bind(true))
	ok.pressed.connect(Audio.play.bind("click"))
	footer.add_child(ok)
	_dim.create_tween().tween_property(_dim, "color:a", 0.45, 0.18)
	Audio.play("open")
	UiStyle.pop_in(_panel)


func _on_dim_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and not confirm:
		_close(false)


func _close(ok: bool) -> void:
	if _closing:
		return
	_closing = true
	Audio.play("close")
	if _dim:
		_dim.create_tween().tween_property(_dim, "color:a", 0.0, 0.14)
	UiStyle.pop_out(_panel, func():
		if ok:
			confirmed.emit()
		else:
			canceled.emit()
		if is_instance_valid(self) and not is_queued_for_deletion():
			queue_free())
