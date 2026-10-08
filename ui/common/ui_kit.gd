class_name UiKit
extends RefCounted
## 화면 조각을 코드로 만들 때 쓰는 공통 부품. 글자 크기는 설계 기준(24/36/48)으로 적고, 실제 크기는 Settings.fs가 정한다(글씨 크기 설정).

const GOLD: Color = Color(0.92, 0.77, 0.36)
const TEXT: Color = Color(0.93, 0.9, 0.84)
const MUTED: Color = Color(0.7, 0.66, 0.58)
const GOOD: Color = Color(0.55, 0.85, 0.5)
const BAD: Color = Color(0.95, 0.5, 0.42)
const PANEL_BG: Color = Color(0.12, 0.11, 0.1, 1.0)
const ROW_BG: Color = Color(0.18, 0.165, 0.14)


static func label(text: String, size: int = 24, color: Color = TEXT, wrap: bool = false) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", Settings.fs(size))
	l.add_theme_color_override("font_color", color)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


static func button(text: String, on_pressed: Callable = Callable(), min_height: int = 72) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.custom_minimum_size.y = min_height
	if on_pressed.is_valid():
		b.pressed.connect(on_pressed)
	return b


static func hbox(separation: int = 8) -> HBoxContainer:
	var box: HBoxContainer = HBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	return box


static func vbox(separation: int = 8) -> VBoxContainer:
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	return box


static func flat_style(color: Color, radius: int = 6, margin: int = 12) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(margin)
	return style


static func panel(color: Color = ROW_BG, margin: int = 12) -> PanelContainer:
	var p: PanelContainer = PanelContainer.new()
	p.add_theme_stylebox_override("panel", flat_style(color, 6, margin))
	return p


static func portrait(sprite_id: String, size: int) -> TextureRect:
	var rect: TextureRect = TextureRect.new()
	rect.texture = AssetRegistry.get_texture(sprite_id)
	rect.custom_minimum_size = Vector2(size, size)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return rect


static func spacer(height: int) -> Control:
	var c: Control = Control.new()
	c.custom_minimum_size.y = height
	return c


static func clear(node: Node) -> void:
	for child: Node in node.get_children():
		node.remove_child(child)
		child.queue_free()


static func city_name(city_id: String) -> String:
	return TranslationServer.translate(DataDB.get_row("cities", city_id).get("name_key", city_id))


## 친밀도 숫자 → 색
static func affinity_color(value: int) -> Color:
	if value >= 20:
		return GOOD
	if value <= -20:
		return BAD
	return TEXT


## 인물 한 줄: [얼굴] 이름 / 신분·소속 / (오른쪽) 친밀도 + 추가 버튼들. 줄을 누르면 on_tap(id)
static func officer_row(id: String, buttons: Array = [], on_tap: Callable = Callable()) -> PanelContainer:
	var row: PanelContainer = panel(ROW_BG, 10)
	var h: HBoxContainer = hbox(12)
	row.add_child(h)
	h.add_child(portrait(Officers.get_state(id).get("sprite_id", ""), 72))
	var info: VBoxContainer = vbox(2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(info)
	var name_line: String = Officers.display_name(id)
	if Officers.is_player(id):
		name_line += " " + TranslationServer.translate("PEOPLE_YOU")
	elif Officers.get_state(id).get("leader", "") == GameState.player_id:
		name_line += " · " + TranslationServer.translate("PEOPLE_COMPANION")
	info.add_child(label(name_line, 24, GOLD if Officers.is_player(id) else TEXT))
	info.add_child(label("%s · %s · %s" % [Officers.nation_label(id), Officers.rank_label(id), Officers.race_label(id)], 24, MUTED))
	if not Officers.is_player(id):
		var player: String = GameState.player_id
		var text: String
		var color: Color = MUTED
		if Relationship.has_met(player, id):
			var aff: int = Relationship.affinity(player, id)
			text = TranslationServer.translate("PEOPLE_AFFINITY") % aff
			color = affinity_color(aff)
		else:
			text = TranslationServer.translate("PEOPLE_STRANGER")
		info.add_child(label(text + " · " + city_name(Officers.get_state(id).get("city", "")), 24, color))
	for b: Button in buttons:
		b.custom_minimum_size = Vector2(120 if buttons.size() < 3 else 92, 64)
		h.add_child(b)
	if on_tap.is_valid():
		row.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				on_tap.call(id))
	return row
