class_name Modal
extends Control
## 화면 위에 뜨는 창. 바깥 어두운 곳을 누르거나 닫기 버튼을 누르면 닫힌다.
## 사용: Modal.open(부모, 내용물) → 내용물은 아무 Control이나.

signal closed

var _box: PanelContainer


static func open(parent: Node, content: Control, close_text_key: String = "UI_CLOSE") -> Modal:
	var modal: Modal = Modal.new()
	modal._build(content, close_text_key)
	parent.add_child(modal)
	return modal


func _build(content: Control, close_text_key: String) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			close())
	add_child(dim)

	var center: MarginContainer = MarginContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right"]:
		center.add_theme_constant_override("margin_" + side, 24)
	for side: String in ["top", "bottom"]:
		center.add_theme_constant_override("margin_" + side, 96)
	add_child(center)

	_box = UiKit.panel(UiKit.PANEL_BG, 20)
	_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var style: StyleBoxFlat = _box.get_theme_stylebox("panel") as StyleBoxFlat
	style.border_color = UiKit.GOLD
	style.set_border_width_all(2)
	center.add_child(_box)

	var v: VBoxContainer = UiKit.vbox(16)
	_box.add_child(v)
	v.add_child(content)
	v.add_child(UiKit.button(tr(close_text_key), close))

	# 살짝 커지며 나타나기
	_box.pivot_offset = Vector2(336, 200)
	_box.scale = Vector2(0.92, 0.92)
	modulate.a = 0.0
	var tween: Tween = create_tween().set_parallel()
	tween.tween_property(self, "modulate:a", 1.0, 0.12)
	tween.tween_property(_box, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func close() -> void:
	closed.emit()
	queue_free()
