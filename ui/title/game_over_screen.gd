extends Control
## 게임 오버: 후계자 없이 주인공이 세상을 떠났다. 담담하게.


func _ready() -> void:
	var info: Dictionary = GameState.flags.get("game_over", {})
	var bg: Panel = Panel.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 48)
	margin.add_theme_constant_override("margin_top", 260)
	margin.add_theme_constant_override("margin_bottom", 120)
	add_child(margin)
	var v: VBoxContainer = UiKit.vbox(20)
	margin.add_child(v)
	var title: Label = UiKit.label(tr("GAMEOVER_TITLE"), 48, UiKit.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var body: Label = UiKit.label(tr("GAMEOVER_BODY") % [info.get("name", "?"), TranslationServer.translate(info.get("rank_key", "")),
		int(info.get("year", 1)), int(info.get("month", 1)), int(info.get("fame", 0))], 24, UiKit.TEXT, true)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(body)
	var report: Label = UiKit.label(tr("GAMEOVER_REPORT"), 24, UiKit.MUTED, true)
	report.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(report)
	var filler: Control = Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(filler)
	v.add_child(UiKit.button(tr("MENU_TO_TITLE"), func() -> void: get_tree().change_scene_to_file("res://ui/title/title_screen.tscn"), 96))
