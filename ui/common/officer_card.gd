class_name OfficerCard
extends RefCounted
## 인물 상세 내용물 (Modal 안에 넣어 쓴다). 플레이어는 잠재치·경험치·소지금까지 보여 준다.


static func build(id: String) -> Control:
	var s: Dictionary = Officers.get_state(id)
	var me: bool = Officers.is_player(id)
	var root: VBoxContainer = UiKit.vbox(10)

	var head: HBoxContainer = UiKit.hbox(16)
	root.add_child(head)
	head.add_child(UiKit.portrait(s.get("sprite_id", ""), 120))
	var info: VBoxContainer = UiKit.vbox(4)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(info)
	info.add_child(UiKit.label(Officers.display_name(id), 36, UiKit.GOLD))
	info.add_child(UiKit.label(TranslationServer.translate("CARD_RACE_AGE") % [Officers.race_label(id), int(s.get("age", 0))], 24, UiKit.MUTED))
	var rank_text: String = "%s · %s" % [Officers.nation_label(id), Officers.rank_label(id)]
	if MercGrade.points(id) > 0 or id == GameState.player_id:
		rank_text += " · " + MercGrade.label(id)
	info.add_child(UiKit.label(rank_text, 24, UiKit.MUTED, true))
	info.add_child(UiKit.label(TranslationServer.translate("CARD_LOCATION") % UiKit.city_name(s.get("city", "")), 24, UiKit.MUTED))
	var unit_name: String = TranslationServer.translate(DataDB.get_row("unit_types", s.get("unit_type", "infantry")).get("name_key", ""))
	info.add_child(UiKit.label(TranslationServer.translate("CARD_TROOPS") % [Fmt.num(int(s.get("troops", 0))), Fmt.num(Officers.max_troops(id)), unit_name], 24, UiKit.MUTED))
	# 이력: 결투 전적과 의뢰 처리
	info.add_child(UiKit.label(Record.duel_line(id), 24, UiKit.TEXT))
	if me or Record.count(id, "quest_done") + Record.count(id, "quest_fail") > 0:
		info.add_child(UiKit.label(Record.quest_line(id), 24, UiKit.TEXT))

	if me:
		root.add_child(UiKit.label(TranslationServer.translate("CARD_PLAYER_STATUS") % [
			int(s["ap"]), Officers.max_ap(id), int(s["energy"]), Fmt.num(int(s["gold"])), int(s["fame"])], 24, UiKit.TEXT, true))
	else:
		var player: String = GameState.player_id
		if Relationship.has_met(player, id):
			var aff: int = Relationship.affinity(player, id)
			root.add_child(UiKit.label(TranslationServer.translate("PEOPLE_AFFINITY") % aff, 24, UiKit.affinity_color(aff)))
		else:
			root.add_child(UiKit.label(TranslationServer.translate("PEOPLE_STRANGER"), 24, UiKit.MUTED))

	var grid: GridContainer = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 6)
	root.add_child(grid)
	for key: String in Officers.stat_keys():
		var value: int = Officers.stat(id, key)
		grid.add_child(UiKit.label(Officers.stat_label(key), 24, UiKit.MUTED))
		var bar: ProgressBar = ProgressBar.new()
		bar.max_value = 100
		bar.value = value
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(240, 20)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.add_theme_stylebox_override("fill", UiKit.flat_style(_stat_color(value), 3, 0))
		bar.add_theme_stylebox_override("background", UiKit.flat_style(Color(0.25, 0.23, 0.2), 3, 0))
		grid.add_child(bar)
		var text: String = str(value)
		var bonus: int = Officers.equipment_bonus(id, key)
		if bonus != 0:
			text += " (%+d)" % bonus
		if me:
			if Progression.is_capped(id, key):
				text += " " + TranslationServer.translate("CARD_CAPPED")
			else:
				text += " [%d/%d]" % [int(s["exp"].get(key, 0)), Progression.exp_needed(Officers.base_stat(id, key))]
		grid.add_child(UiKit.label(text, 24))
	if me and not s.get("reputation", {}).is_empty():
		var reps: PackedStringArray = []
		for n: String in s["reputation"]:
			reps.append("%s %+d" % [Diplomacy.nation_name(n), int(s["reputation"][n])])
		root.add_child(UiKit.label(TranslationServer.translate("CARD_REPUTATION") + " " + ", ".join(reps), 24, UiKit.TEXT, true))
	if me:
		var pot: PackedStringArray = []
		for key: String in Officers.stat_keys():
			pot.append("%s %d" % [Officers.stat_label(key), Officers.potential(id, key)])
		root.add_child(UiKit.label(TranslationServer.translate("CARD_POTENTIAL") + " " + ", ".join(pot), 24, UiKit.MUTED, true))
		var gear: PackedStringArray = []
		for slot: String in ["weapon", "armor", "accessory"]:
			var item_id: String = Shop.equipped(id, slot)
			if item_id != "":
				gear.append(TranslationServer.translate(DataDB.get_row("items", item_id).get("name_key", "")))
		if not gear.is_empty():
			root.add_child(UiKit.label(TranslationServer.translate("CARD_EQUIPMENT") + " " + ", ".join(gear), 24, UiKit.TEXT, true))

	var skills: PackedStringArray = []
	for skill_id: String in s.get("skills", []):
		skills.append(SkillLevels.card_line(id, skill_id))
	var skill_text: String = ", ".join(skills) if not skills.is_empty() else TranslationServer.translate("CARD_NO_SKILL")
	root.add_child(UiKit.label(TranslationServer.translate("CARD_SKILLS") + " " + skill_text, 24, UiKit.TEXT, true))
	return root


static func _stat_color(value: int) -> Color:
	if value >= 80:
		return Color(0.95, 0.72, 0.3)
	if value >= 60:
		return Color(0.55, 0.78, 0.45)
	if value >= 40:
		return Color(0.45, 0.65, 0.85)
	return Color(0.55, 0.52, 0.48)
