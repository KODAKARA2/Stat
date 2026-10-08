class_name UnitInfo
extends RefCounted
## 전투 중 부대 상세 (우클릭 / 길게 누르기): 초상화, 병력, 사기, 기력, 능력치, 이동·사거리, 지형, 전법.


static func build(state: BattleState, u: BattleUnit) -> Control:
	var root: VBoxContainer = UiKit.vbox(8)
	var head: HBoxContainer = UiKit.hbox(16)
	root.add_child(head)
	head.add_child(UiKit.portrait(u.sprite_id, 112))
	var info: VBoxContainer = UiKit.vbox(2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(info)
	info.add_child(UiKit.label(u.name, 36, UiKit.GOLD))
	var tags: PackedStringArray = [TranslationServer.translate("UNIT_TEAM_ALLY" if u.team == "ally" else "UNIT_TEAM_ENEMY"),
		TranslationServer.translate(u.type_row().get("name_key", ""))]
	if u.leader:
		tags.append(TranslationServer.translate("BATTLE_LEADER"))
	info.add_child(UiKit.label(" · ".join(tags), 24, UiKit.MUTED))
	var terrain: Dictionary = state.terrain_row(u.cell)
	info.add_child(UiKit.label(TranslationServer.translate("UNIT_TERRAIN") % [TranslationServer.translate(terrain.get("name_key", "")),
		int(round((1.0 - float(terrain.get("defense", 1.0))) * 100))], 24, UiKit.MUTED))

	var grid: GridContainer = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 6)
	root.add_child(grid)
	_bar_row(grid, "UNIT_TROOPS", u.troops, u.max_troops, "%s/%s" % [Fmt.num(u.troops), Fmt.num(u.max_troops)], Color(0.45, 0.7, 1.0))
	_bar_row(grid, "UNIT_MORALE", u.morale, 100, str(u.morale), _morale_color(u.morale))
	_bar_row(grid, "UNIT_SP", u.sp, u.max_sp, str(u.sp), Color(0.95, 0.8, 0.35))
	for pair: Array in [["STAT_STR", u.str_], ["STAT_LEAD", u.lead], ["STAT_MAG", u.mag]]:
		_bar_row(grid, pair[0], int(pair[1]), 100, str(pair[1]), Color(0.6, 0.6, 0.55))

	var r: Vector2i = BattleRules.attack_range(state, u, u.cell)
	root.add_child(UiKit.label(TranslationServer.translate("UNIT_MOVE_RANGE") % [u.move_points(), r.x, r.y,
		u.attack_power(), int(round(BattleRules.morale_mult(u) * 100)), int(round(BattleRules.taken_mult(u) * 100))], 24, UiKit.TEXT, true))
	var skills: PackedStringArray = []
	for skill: Dictionary in u.battle_skills():
		skills.append(TranslationServer.translate("BATTLE_SKILL_LINE") % [SkillLevels.title(skill), int(skill["battle"].get("sp", 0))])
	root.add_child(UiKit.label(TranslationServer.translate("CARD_SKILLS") + " " +
		(", ".join(skills) if not skills.is_empty() else TranslationServer.translate("CARD_NO_SKILL")), 24, UiKit.TEXT, true))
	return root


static func _bar_row(grid: GridContainer, key: String, value: int, max_value: int, text: String, color: Color) -> void:
	grid.add_child(UiKit.label(TranslationServer.translate(key), 24, UiKit.MUTED))
	var bar: ProgressBar = ProgressBar.new()
	bar.max_value = maxi(max_value, 1)
	bar.value = value
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(220, 20)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_theme_stylebox_override("fill", UiKit.flat_style(color, 3, 0))
	bar.add_theme_stylebox_override("background", UiKit.flat_style(Color(0.25, 0.23, 0.2), 3, 0))
	grid.add_child(bar)
	grid.add_child(UiKit.label(text, 24))


static func _morale_color(m: int) -> Color:
	if m >= 70:
		return Color(0.55, 0.85, 0.5)
	if m >= 40:
		return Color(0.95, 0.8, 0.35)
	return Color(0.95, 0.45, 0.4)
