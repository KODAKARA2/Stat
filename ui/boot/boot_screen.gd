extends Control
## 데이터 점검 화면 (메뉴 탭): 데이터 로드 결과, 한글 표시, 임시 그림.

@onready var _title: Label = %Title
@onready var _subtitle: Label = %Subtitle
@onready var _date: Label = %Date
@onready var _log: VBoxContainer = %Log
@onready var _next_button: Button = %NextMonth


func _ready() -> void:
	_title.text = tr("GAME_TITLE")
	_subtitle.text = tr("GAME_SUBTITLE")
	_next_button.text = tr("BOOT_BACK_TO_MAP" if SaveManager.game_in_progress else "BOOT_BACK")
	_next_button.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://ui/map/map_screen.tscn" if SaveManager.game_in_progress else "res://ui/title/title_screen.tscn"))
	EventBus.month_started.connect(_on_month_started)
	_build_log()
	_on_month_started(TimeManager.year, TimeManager.month)


func _build_log() -> void:
	_add_line(tr("BOOT_FONT_TEST"))
	_add_line(tr("BOOT_TABLES") % DataDB.table_names().size())
	_add_line("  " + ", ".join(DataDB.table_names()))
	if DataDB.errors.is_empty():
		_add_line(tr("BOOT_NO_ERRORS"))
	else:
		_add_line(tr("BOOT_ERRORS") % DataDB.errors.size(), Color.SALMON)
		for err: String in DataDB.errors:
			_add_line("  " + err, Color.SALMON)

	_add_header(tr("BOOT_NATIONS"))
	for nation: Dictionary in DataDB.get_rows("nations"):
		_add_icon_line(nation["sprite_id"], tr(nation["name_key"]), Color.html(nation["color"]))

	_add_header(tr("BOOT_RANKS"))
	var ranks: Array = DataDB.get_rows("ranks").duplicate()
	ranks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["order"] < b["order"])
	var rank_names: PackedStringArray = []
	for rank: Dictionary in ranks:
		rank_names.append(tr(rank["name_key"]))
	_add_line(" < ".join(rank_names))

	_add_header(tr("BOOT_MONSTERS"))
	var by_tier: Dictionary = {}
	for mon: Dictionary in DataDB.get_rows("monsters"):
		var tier: int = int(mon["tier"])
		if not by_tier.has(tier):
			by_tier[tier] = PackedStringArray()
		by_tier[tier].append(tr(mon["name_key"]))
	for tier: int in [1, 2, 3, 4]:
		_add_line("%d단계: %s" % [tier, ", ".join(by_tier.get(tier, PackedStringArray()))])

	for line: String in [tr("BOOT_TABLES") % DataDB.table_names().size()] + Array(DataDB.errors):
		print(line)


func _on_month_started(year: int, month: int) -> void:
	_date.text = tr("BOOT_DATE") % [year, month, TimeManager.season_name()]
	print(_date.text)


func _add_header(text: String) -> void:
	var spacer: Control = Control.new()
	spacer.custom_minimum_size.y = 12
	_log.add_child(spacer)
	_add_line("■ " + text, Color(0.92, 0.77, 0.36))


func _add_line(text: String, color: Color = Color.TRANSPARENT) -> void:
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", Settings.fs(24))
	if color != Color.TRANSPARENT:
		label.add_theme_color_override("font_color", color)
	_log.add_child(label)


func _add_icon_line(sprite_id: String, text: String, color: Color) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	var icon: TextureRect = TextureRect.new()
	icon.texture = AssetRegistry.get_texture(sprite_id)
	icon.custom_minimum_size = Vector2(32, 32)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	row.add_child(icon)
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", Settings.fs(24))
	label.add_theme_color_override("font_color", color)
	row.add_child(label)
	_log.add_child(row)
