class_name FoundingDialog
extends RefCounted
## 건국 창: 나라 이름과 깃발 색을 정한다. [건국] 버튼을 누르면 on_confirm(이름, 색)을 부르고 창을 닫는다.


static func build(title_key: String, body: String, default_name: String, on_confirm: Callable) -> VBoxContainer:
	var box: VBoxContainer = UiKit.vbox(12)
	box.add_child(UiKit.label(TranslationServer.translate(title_key), 36, UiKit.GOLD))
	box.add_child(UiKit.label(body, 24, UiKit.TEXT, true))
	box.add_child(UiKit.label(TranslationServer.translate("FOUND_NAME_LABEL"), 24, UiKit.MUTED))
	var name_input: NameInput = NameInput.make(default_name, 10, 54)
	box.add_child(name_input)
	box.add_child(UiKit.label(TranslationServer.translate("FOUND_COLOR_LABEL"), 24, UiKit.MUTED))
	var chosen: Array = [Founding.COLORS[0]]
	var swatches: HBoxContainer = HBoxContainer.new()
	swatches.add_theme_constant_override("separation", 8)
	box.add_child(swatches)
	var buttons: Array[Button] = []
	for c: String in Founding.COLORS:
		var b: Button = Button.new()
		b.custom_minimum_size = Vector2(72, 64)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		buttons.append(b)
		swatches.add_child(b)
	var paint: Callable = func() -> void:
		for i: int in buttons.size():
			var st: StyleBoxFlat = UiKit.flat_style(Color.html(Founding.COLORS[i]), 8, 0)
			st.set_border_width_all(4 if Founding.COLORS[i] == chosen[0] else 0)
			st.border_color = Color.WHITE
			for s: String in ["normal", "hover", "pressed", "focus"]:
				buttons[i].add_theme_stylebox_override(s, st)
	for i: int in buttons.size():
		buttons[i].pressed.connect(func() -> void:
			chosen[0] = Founding.COLORS[i]
			paint.call())
	paint.call()
	var ok: Button = UiKit.button(TranslationServer.translate("FOUND_CONFIRM"))
	ok.custom_minimum_size.y = 88
	ok.pressed.connect(func() -> void:
		var n: String = name_input.get_text()
		on_confirm.call(n if n != "" else default_name, chosen[0])
		var node: Node = box
		while node != null and not node is Modal:
			node = node.get_parent()
		if node != null:
			(node as Modal).close())
	box.add_child(ok)
	return box
