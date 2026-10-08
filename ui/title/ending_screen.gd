extends Control
## 엔딩: 대륙 통일 또는 은퇴. 한 사람의 경력을 숫자로 정리하고, 맺음말 몇 줄.


func _ready() -> void:
	var info: Dictionary = GameState.flags.get("ending", {})
	var bg: Panel = Panel.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 48)
	margin.add_theme_constant_override("margin_top", 160)
	margin.add_theme_constant_override("margin_bottom", 96)
	add_child(margin)
	var v: VBoxContainer = UiKit.vbox(18)
	margin.add_child(v)
	var unify: bool = info.get("kind", "") == "unify"
	var title: Label = UiKit.label(tr("ENDING_UNIFY_TITLE" if unify else "ENDING_RETIRE_TITLE"), 48, UiKit.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var who: Label = UiKit.label(tr("ENDING_WHO") % [info.get("name", "?"), TranslationServer.translate(info.get("rank_key", "")),
		int(info.get("year", 1)), int(info.get("month", 1))], 28, UiKit.TEXT, true)
	who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(who)
	# 경력 정리: 숫자로
	var months: int = int(info.get("months", 0))
	var stats: Array = [tr("ENDING_STAT_TIME") % [months / 12, months % 12], tr("ENDING_STAT_FAME") % int(info.get("fame", 0)),
		tr("ENDING_STAT_GOLD") % Fmt.num(int(info.get("gold", 0))), tr("ENDING_STAT_COMPANIONS") % int(info.get("companions", 0)),
		tr("ENDING_STAT_CHILDREN") % int(info.get("children", 0))]
	if String(info.get("nation", "")) != "":
		stats.append(tr("ENDING_STAT_NATION") % [info["nation"], int(info.get("cities", 0))])
	var box: PanelContainer = UiKit.panel(UiKit.PANEL_BG.lightened(0.05), 16)
	var stat_v: VBoxContainer = UiKit.vbox(6)
	box.add_child(stat_v)
	for line: String in stats:
		stat_v.add_child(UiKit.label(line, 24, UiKit.TEXT))
	v.add_child(box)
	for key: String in info.get("epilogue", []):
		v.add_child(UiKit.label(tr(key), 24, UiKit.MUTED, true))
	var filler: Control = Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(filler)
	v.add_child(UiKit.button(tr("MENU_TO_TITLE"), func() -> void: get_tree().change_scene_to_file("res://ui/title/title_screen.tscn"), 96))
