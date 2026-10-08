extends Control
## 캐릭터 생성 (GDD §4.1): 이름, 종족(엘프는 갈래), 성별, 출신 국가, 출신 배경, 보너스 포인트.
## 외형 파츠 조합은 아트가 준비되면 붙인다(지금은 임시 초상).

var _name_input: NameInput
var _race: String = "human"
var _variant: String = ""
var _gender: String = "m"
var _origin: String = "leonhart"
var _background: String = "knight_bastard"
var _bonus: Dictionary = {}
var _portrait_index: int = 0
var _portrait_rect: TextureRect

var _variant_row: HBoxContainer
var _race_desc: Label
var _bg_desc: Label
var _points_label: Label
var _stat_values: Dictionary = {}   # stat → Label
var _start_button: Button


func _ready() -> void:
	for key: String in Officers.stat_keys():
		_bonus[key] = 0
	var bg: Panel = Panel.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var layout: VBoxContainer = UiKit.vbox(0)
	layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(layout)

	var header: Label = UiKit.label(tr("CREATE_TITLE"), 36, UiKit.GOLD)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.custom_minimum_size.y = 72
	header.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	layout.add_child(header)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)
	var margin: MarginContainer = MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	scroll.add_child(margin)
	var form: VBoxContainer = UiKit.vbox(10)
	margin.add_child(form)

	# 이름
	form.add_child(_section("CREATE_NAME"))
	# 게임 안 한글 자판 (Windows 한글 입력기 문제 우회, 근성영애와 같은 방식)
	_name_input = NameInput.make("", 8)
	_name_input.edit.placeholder_text = tr("CREATE_NAME_HINT")
	_name_input.changed.connect(func(_t: String) -> void: _update())
	form.add_child(_name_input)

	# 종족 (엘프는 갈래 선택이 하나 더)
	form.add_child(_section("CREATE_RACE"))
	var races: Array = []
	for row: Dictionary in DataDB.get_rows("races"):
		races.append([row["id"], tr(row["name_key"])])
	form.add_child(_choice_grid(races, 3, _race, func(v: String) -> void:
		_race = v
		_variant = ""
		_portrait_index = 0
		_rebuild_variants()
		_update()))
	_variant_row = UiKit.hbox(8)
	form.add_child(_variant_row)
	_race_desc = UiKit.label("", 24, UiKit.MUTED, true)
	form.add_child(_race_desc)

	# 성별
	form.add_child(_section("CREATE_GENDER"))
	form.add_child(_choice_grid([["m", tr("GENDER_M")], ["f", tr("GENDER_F")]], 2, _gender, func(v: String) -> void:
		_gender = v
		_portrait_index = 0
		_update()))

	# 초상화 (임시 그림: 종족·성별에 맞는 것 중에서 고른다)
	form.add_child(_section("CREATE_PORTRAIT"))
	var prow: HBoxContainer = UiKit.hbox(16)
	prow.alignment = BoxContainer.ALIGNMENT_CENTER
	prow.add_child(_small_button("◀", _cycle_portrait.bind(-1)))
	_portrait_rect = UiKit.portrait("", 128)
	prow.add_child(_portrait_rect)
	prow.add_child(_small_button("▶", _cycle_portrait.bind(1)))
	form.add_child(prow)

	# 출신 국가
	form.add_child(_section("CREATE_ORIGIN"))
	var nations: Array = []
	for row: Dictionary in DataDB.get_rows("nations"):
		nations.append([row["id"], tr(row["name_key"])])
	form.add_child(_choice_grid(nations, 2, _origin, func(v: String) -> void:
		_origin = v
		_update()))

	# 출신 배경
	form.add_child(_section("CREATE_BACKGROUND"))
	var bgs: Array = []
	for row: Dictionary in DataDB.get_rows("backgrounds"):
		bgs.append([row["id"], tr(row["name_key"])])
	form.add_child(_choice_grid(bgs, 2, _background, func(v: String) -> void:
		_background = v
		_update()))
	_bg_desc = UiKit.label("", 24, UiKit.MUTED, true)
	form.add_child(_bg_desc)

	# 능력치 + 보너스 포인트
	form.add_child(_section("CREATE_STATS"))
	_points_label = UiKit.label("", 24, UiKit.GOLD)
	form.add_child(_points_label)
	for key: String in Officers.stat_keys():
		var row: HBoxContainer = UiKit.hbox(12)
		var name_label: Label = UiKit.label(Officers.stat_label(key), 24)
		name_label.custom_minimum_size.x = 96
		row.add_child(name_label)
		var value: Label = UiKit.label("", 24)
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(value)
		_stat_values[key] = value
		row.add_child(_small_button("−", _change_bonus.bind(key, -1)))
		row.add_child(_small_button("+", _change_bonus.bind(key, 1)))
		form.add_child(row)
	form.add_child(UiKit.spacer(24))

	# 아래 고정: 시작 버튼
	var foot: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		foot.add_theme_constant_override("margin_" + side, 12)
	layout.add_child(foot)
	_start_button = UiKit.button(tr("CREATE_START"), _start, 96)
	_start_button.add_theme_font_size_override("font_size", Settings.fs(36))
	foot.add_child(_start_button)

	_rebuild_variants()
	_update()


func _section(key: String) -> Label:
	var l: Label = UiKit.label("■ " + tr(key), 24, UiKit.GOLD)
	l.custom_minimum_size.y = 48
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	return l


func _small_button(text: String, on_pressed: Callable) -> Button:
	var b: Button = UiKit.button(text, on_pressed, 56)
	b.custom_minimum_size.x = 72
	b.focus_mode = Control.FOCUS_NONE   # 이름 입력칸의 포커스(조합 중인 글자)를 뺏지 않게
	return b


## 하나만 고르는 버튼 묶음. options = [[값, 표시글], ...]
func _choice_grid(options: Array, columns: int, initial: String, on_pick: Callable) -> GridContainer:
	var grid: GridContainer = GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	var group: ButtonGroup = ButtonGroup.new()
	for opt: Array in options:
		var b: Button = UiKit.button(opt[1], Callable(), 64)
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = opt[0] == initial
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE   # 이름 입력칸의 포커스(조합 중인 글자)를 뺏지 않게
		b.pressed.connect(on_pick.bind(opt[0]))
		grid.add_child(b)
	return grid


func _rebuild_variants() -> void:
	UiKit.clear(_variant_row)
	var variants: Array = DataDB.get_row("races", _race).get("variants", [])
	if variants.is_empty():
		_variant_row.visible = false
		return
	_variant_row.visible = true
	var options: Array = [["", tr(DataDB.get_row("races", _race)["name_key"])]]
	for v: Dictionary in variants:
		options.append([v["id"], tr(v["name_key"])])
	var grid: GridContainer = _choice_grid(options, options.size(), _variant, func(v: String) -> void:
		_variant = v
		_portrait_index = 0
		_update())
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_variant_row.add_child(grid)


func _points_left() -> int:
	var used: int = 0
	for key: String in _bonus:
		used += int(_bonus[key])
	return int(DataDB.balance("create.bonus_points", 10)) - used


func _change_bonus(key: String, delta: int) -> void:
	var limit: int = DataDB.balance("create.max_per_stat_bonus", 10)
	var next: int = int(_bonus[key]) + delta
	if next < 0 or next > limit or (delta > 0 and _points_left() <= 0):
		return
	_bonus[key] = next
	_update()


func _update() -> void:
	if _portrait_rect:
		_portrait_rect.texture = AssetRegistry.get_texture(_portrait_id())
	var race: Dictionary = DataDB.get_row("races", _race)
	var traits: PackedStringArray = []
	for t: String in race.get("traits", []):
		traits.append(tr("TRAIT_" + t.to_upper()))
	_race_desc.text = tr("CREATE_RACE_DESC") % [int(race["lifespan"]), int(race["adult_age"]), int(race["start_age"]), ", ".join(traits)]
	if _variant == "dark_elf":
		_race_desc.text += "\n" + tr("CREATE_DARK_ELF_NOTE")

	var bg: Dictionary = DataDB.get_row("backgrounds", _background)
	_bg_desc.text = tr(bg["desc_key"]) + "\n" + tr("CREATE_BG_START") % [Fmt.num(int(bg["gold"])), UiKit.city_name(WorldSetup.start_city(_origin))]

	var stats: Dictionary = WorldSetup.compute_stats(_race, _background, _bonus)
	var mods: Dictionary = race.get("stat_mod", {})
	for key: String in _stat_values:
		var text: String = str(stats[key])
		var extra: PackedStringArray = []
		if int(_bonus[key]) > 0:
			extra.append("+%d" % int(_bonus[key]))
		if int(mods.get(key, 0)) != 0:
			extra.append(tr("CREATE_RACE_MOD") % int(mods[key]))
		if not extra.is_empty():
			text += "  (" + ", ".join(extra) + ")"
		(_stat_values[key] as Label).text = text
	_points_label.text = tr("CREATE_POINTS_LEFT") % _points_left()



func _start() -> void:
	var player_name: String = _name_input.get_text()
	if player_name == "":
		_name_input.show_error(tr("CREATE_NAME_HINT"))
		return
	WorldSetup.new_game({
		"name": player_name,
		"race": _race,
		"variant": _variant,
		"gender": _gender,
		"origin": _origin,
		"background": _background,
		"bonus": _bonus.duplicate(),
		"portrait": _portrait_id(),
	})
	get_tree().change_scene_to_file("res://ui/map/map_screen.tscn")


func _portrait_pool() -> Array:
	return Portraits.pool(_race, _variant, _gender)


func _portrait_id() -> String:
	var pool: Array = _portrait_pool()
	if pool.is_empty():
		return ""
	return Portraits.sprite_id(pool[posmod(_portrait_index, pool.size())])


func _cycle_portrait(step: int) -> void:
	_portrait_index += step
	_update()
