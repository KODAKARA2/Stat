class_name MenuPanel
extends PanelContainer
## [메뉴] 탭: 저장(슬롯 3개), 불러오기(자동 저장 + 슬롯 3개), 화면 설정(글씨체·크기), 은퇴(엔딩), 데이터 점검, 타이틀로.

signal toast_requested(text: String)

var _content: VBoxContainer


func _ready() -> void:
	add_theme_stylebox_override("panel", UiKit.flat_style(UiKit.PANEL_BG, 0, 16))
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_content = UiKit.vbox(10)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_content)
	refresh()


func refresh() -> void:
	UiKit.clear(_content)
	_content.add_child(UiKit.label(tr("MENU_TITLE"), 36, UiKit.GOLD))
	_content.add_child(UiKit.label("■ " + tr("MENU_SAVE"), 24, UiKit.GOLD))
	for i: int in SaveManager.MANUAL_SLOTS.size():
		var slot: String = SaveManager.MANUAL_SLOTS[i]
		var save_button: Button = UiKit.button(MenuPanel.slot_text(slot, i + 1), _save.bind(slot, i + 1), 80)
		save_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # 긴 저장 정보는 줄을 바꿔 화면 안에
		_content.add_child(save_button)
	_content.add_child(UiKit.label("■ " + tr("MENU_LOAD"), 24, UiKit.GOLD))
	MenuPanel.add_load_buttons(_content, get_tree())
	# 화면 설정: 글씨체·글씨 크기 (바꾸면 지금 화면을 다시 그린다)
	_content.add_child(UiKit.label("■ " + tr("MENU_DISPLAY"), 24, UiKit.GOLD))
	_content.add_child(_choice_row([["clear", "MENU_FONT_CLEAR"], ["pixel", "MENU_FONT_PIXEL"]], Settings.font, func(v: String) -> void:
		Settings.set_font(v)
		get_tree().reload_current_scene()))
	_content.add_child(_choice_row([["normal", "MENU_SIZE_NORMAL"], ["large", "MENU_SIZE_LARGE"], ["xlarge", "MENU_SIZE_XLARGE"]], Settings.text_size, func(v: String) -> void:
		Settings.set_text_size(v)
		get_tree().reload_current_scene()))
	_content.add_child(UiKit.spacer(12))
	# 은퇴 (엔딩): 두 번 눌러야 끝난다
	var retire: Button = UiKit.button(tr("MENU_RETIRE"), Callable(), 72)
	retire.pressed.connect(func() -> void:
		if not retire.has_meta("armed"):
			retire.set_meta("armed", true)
			retire.text = tr("MENU_RETIRE_CONFIRM")
			return
		Ending.retire()
		get_tree().change_scene_to_file("res://ui/title/ending_screen.tscn"))
	_content.add_child(retire)
	_content.add_child(UiKit.button(tr("MENU_DATA_CHECK"), func() -> void: get_tree().change_scene_to_file("res://ui/boot/boot_screen.tscn"), 72))
	_content.add_child(UiKit.button(tr("MENU_TO_TITLE"), func() -> void: get_tree().change_scene_to_file("res://ui/title/title_screen.tscn"), 72))


## 하나만 고르는 버튼 줄. options = [[값, 문자열 키], ...]
func _choice_row(options: Array, current: String, on_pick: Callable) -> HBoxContainer:
	var row: HBoxContainer = UiKit.hbox(8)
	for opt: Array in options:
		var b: Button = UiKit.button(tr(opt[1]), Callable(), 72)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.disabled = opt[0] == current
		b.pressed.connect(on_pick.bind(opt[0]))
		row.add_child(b)
	return row


func _save(slot: String, number: int) -> void:
	if SaveManager.save_game(slot):
		toast_requested.emit(tr("MENU_SAVED") % number)
	refresh()


static func slot_text(slot: String, number: int) -> String:
	var info: Dictionary = SaveManager.peek(slot)
	if info.is_empty():
		return TranslationServer.translate("MENU_SLOT_EMPTY") % number
	var key: String = "MENU_AUTO_INFO" if slot == SaveManager.AUTO_SLOT else "MENU_SLOT_INFO"
	var args: Array = [int(info["year"]), int(info["month"]), info["name"], TranslationServer.translate(info["rank_key"])]
	if slot != SaveManager.AUTO_SLOT:
		args.push_front(number)
	return TranslationServer.translate(key) % args


## 불러오기 버튼들 (자동 저장 + 수동 슬롯). 비어 있으면 꺼진다. 타이틀 화면에서도 쓴다.
static func add_load_buttons(box: Container, tree: SceneTree) -> void:
	var slots: Array = [SaveManager.AUTO_SLOT] + Array(SaveManager.MANUAL_SLOTS)
	for i: int in slots.size():
		var slot: String = slots[i]
		var b: Button = UiKit.button(slot_text(slot, i), func() -> void:
			if SaveManager.load_game(slot):
				tree.change_scene_to_file("res://ui/map/map_screen.tscn"), 80)
		b.disabled = not SaveManager.has_save(slot)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(b)
