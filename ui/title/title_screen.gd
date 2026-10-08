extends Control
## 타이틀: 새 게임 / 이어하기 / 데이터 점검


func _ready() -> void:
	SaveManager.game_in_progress = false
	var bg: Panel = Panel.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 48)
	margin.add_theme_constant_override("margin_top", 220)
	margin.add_theme_constant_override("margin_bottom", 96)
	add_child(margin)

	var v: VBoxContainer = UiKit.vbox(16)
	margin.add_child(v)
	var title: Label = UiKit.label(tr("GAME_TITLE"), 48, UiKit.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var sub: Label = UiKit.label(tr("GAME_SUBTITLE"), 24, UiKit.MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)

	var filler: Control = Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(filler)

	v.add_child(UiKit.button(tr("TITLE_NEW_GAME"), func() -> void:
		get_tree().change_scene_to_file("res://ui/create/create_screen.tscn"), 96))
	var cont: Button = UiKit.button(tr("TITLE_CONTINUE"), _continue, 96)
	cont.disabled = not SaveManager.has_save(SaveManager.AUTO_SLOT)
	v.add_child(cont)
	v.add_child(UiKit.button(tr("TITLE_LOAD"), func() -> void:
		var box: VBoxContainer = UiKit.vbox(10)
		box.add_child(UiKit.label(tr("MENU_LOAD"), 36, UiKit.GOLD))
		MenuPanel.add_load_buttons(box, get_tree())
		Modal.open(self, box), 72))
	v.add_child(UiKit.button(tr("TITLE_DATA_CHECK"), func() -> void:
		get_tree().change_scene_to_file("res://ui/boot/boot_screen.tscn"), 72))


func _continue() -> void:
	if SaveManager.load_game(SaveManager.AUTO_SLOT):
		get_tree().change_scene_to_file("res://ui/map/map_screen.tscn")
