class_name BattleOutcome
extends RefCounted
## 전투가 끝난 뒤 정산 (GDD §8.5): 보수·명성·경험치, 병력·기력 반영, 길드의 담담한 보고.
## 돌려주는 값: {"won", "lines": [결과 문장], "report": [길드 보고 문장]}


static func apply(state: BattleState) -> Dictionary:
	var won: bool = state.result == "win"
	var quest: Dictionary = state.quest
	var lines: Array = []
	var report: Array = []
	var leader: BattleUnit = state.leader_of("ally")
	var officer_id: String = leader.officer_id
	var s: Dictionary = Officers.get_state(officer_id)

	# 장수 부대: 남은 병력·기력을 돌려준다
	for u: BattleUnit in state.units:
		if u.officer_id == "":
			continue
		var os: Dictionary = Officers.get_state(u.officer_id)
		os["troops"] = u.troops
		os["energy"] = clampi(u.sp, 0, int(DataDB.balance("energy.max", 100)))
		if not u.alive():
			os["troops"] = 0
			# 궤멸한 장수는 판정 (GDD §5): 사망 또는 부상
			var death: float = float(Family.cfg("death", "player_battle_death", 0.1)) if u.officer_id == GameState.player_id \
				else float(DataDB.balance("battle.defeat_death_chance", 0.1))
			if u.officer_id == GameState.player_id and bool(Family.cfg("death", "player_death_requires_heir", true)) and Family.heir_of(u.officer_id) == "":
				death = 0.0   # 후계자가 없으면 전투에서는 죽지 않는다 (안전장치)
			if RNG.chance(death):
				lines.append(msg("BATTLE_DIED", [u.name]))
				Family.die(u.officer_id, "battle")
				continue
			os["injury"] = maxi(int(os.get("injury", 0)), int(DataDB.balance("battle.defeat_injury_months", 2)))
			lines.append(msg("BATTLE_INJURED", [u.name, int(os["injury"])]))

	# 고용 부대: 남은 병력 반영, 궤멸한 부대는 계약 끝
	var hired: Array = Guild.hired(officer_id)
	var lost_hired: Array[int] = []
	for u: BattleUnit in state.units:
		if u.hire_index < 0 or u.hire_index >= hired.size():
			continue
		if u.alive():
			hired[u.hire_index]["troops"] = u.troops
		else:
			lost_hired.append(u.hire_index)
			report.append(msg("BATTLE_REPORT_HIRED_LOST", [u.name]))
	lost_hired.sort()
	lost_hired.reverse()
	for i: int in lost_hired:
		hired.remove_at(i)

	if won:
		var gold: int = MercGrade.pay(officer_id, int(quest.get("gold", 0)))   # 등급이 높을수록 보수가 많다
		s["gold"] = int(s["gold"]) + gold
		var fame: int = int(quest.get("fame", 0))
		var fame_cap: int = int(Guild.cfg("fame_min_rank_order", {}).get(str(int(quest.get("tier", 1))), 999))
		if quest.get("type", "monster") == "monster" and Officers.rank_order(officer_id) >= fame_cap:
			fame = 0   # 이 신분에 이 정도 토벌은 명성이 안 된다
		Career.add_fame(officer_id, fame)
		lines.append(msg("BATTLE_REWARD", [Fmt.num(gold), fame]))
		# 경험치: 통솔 + 이 부대의 공격 능력
		var attack_stat: String = {"melee": "str", "ranged": "str", "magic": "mag"}.get(leader.type_row().get("attack_stat", "melee"), "str")
		for key: String in ["lead", attack_stat]:
			var r: Dictionary = Progression.add_exp(officer_id, key, int(quest.get("exp", 25)))
			lines.append(msg("ACT_TRAIN_EXP", [Officers.stat_label(key), r["exp"], r["progress"], r["need"]]))
			if r["gained"] > 0:
				lines.append(msg("ACT_TRAIN_UP", [Officers.stat_label(key), r["before"], r["after"]]))
		Guild.complete(officer_id, quest.get("id", ""))
	else:
		lines.append(msg("BATTLE_FAILED"))

	# 참전 의뢰: 이 싸움의 결과가 월말 전쟁 판정에 반영된다. 이기든 지든 한 번뿐.
	if quest.get("type", "") == "war":
		var plan: Dictionary = WarSystem.find_plan(quest.get("plan", ""))
		if not plan.is_empty():
			plan["player_side"] = quest["side"]
			plan["player_result"] = "win" if won else "lose"
		if won:
			var rep: Dictionary = s.get_or_add("reputation", {})
			rep[quest["side"]] = int(rep.get(quest["side"], 0)) + int(Guild.war_cfg("rep_gain", 5))
			rep[quest["enemy"]] = int(rep.get(quest["enemy"], 0)) - int(Guild.war_cfg("rep_loss", 3))
			lines.append(msg("BATTLE_WAR_REP", [Diplomacy.nation_name(quest["side"]), int(Guild.war_cfg("rep_gain", 5)),
				Diplomacy.nation_name(quest["enemy"]), int(Guild.war_cfg("rep_loss", 3))]))
		lines.append(msg("BATTLE_WAR_EFFECT_WIN" if won else "BATTLE_WAR_EFFECT_LOSE", [WorldMap.city_name(quest["target"])]))
		Guild.complete(officer_id, quest.get("id", ""))
		# 용병단 계약 중 고용국을 위해 이기면 전과 보너스
		var c: Dictionary = Career.contract(officer_id)
		if won and not c.is_empty() and c["employer"] == quest["side"]:
			s["gold"] = int(s["gold"]) + int(c.get("win_bonus", 0))
			lines.append(msg("CONTRACT_WIN_BONUS", [Fmt.num(int(c.get("win_bonus", 0)))]))

	# 용병단 점령전: 이기면 그 도시로 건국(이름은 지도 화면이 묻는다), 지면 평판·명성 하락
	if quest.get("type", "") == "conquest":
		if won:
			var c: Dictionary = GameState.cities[quest["target"]]
			c["troops"] = int(int(c["troops"]) * float(Founding.cfg("conquest_troops_left", 0.3)))
			GameState.flags["pending_founding"] = {"city": quest["target"], "former": quest["enemy"]}
			lines.append(msg("CONQUEST_WON", [WorldMap.city_name(quest["target"])]))
		else:
			var rep: Dictionary = s.get_or_add("reputation", {})
			rep[quest["enemy"]] = int(rep.get(quest["enemy"], 0)) + int(Founding.cfg("conquest_fail_rep", -20))
			Career.add_fame(officer_id, int(Founding.cfg("conquest_fail_fame", -5)))
			lines.append(msg("CONQUEST_LOST", [Diplomacy.nation_name(quest["enemy"]), -int(Founding.cfg("conquest_fail_rep", -20)), -int(Founding.cfg("conquest_fail_fame", -5))]))

	# 이력: 의뢰 완수 / 실패
	if quest.get("type", "monster") in ["monster", "war", "conquest"]:
		Record.add(officer_id, "quest_done" if won else "quest_fail")

	# 용병 등급: 길드 공적
	var grade_up: String = MercGrade.add_points(officer_id, MercGrade.quest_points(quest, won))
	if grade_up != "":
		lines.append(grade_up)

	# 출세: 공적·임무, 명성으로 승진
	Career.on_battle(state, won)
	var rank_before: String = s.get("rank", "")
	Career.check_promotion(officer_id)
	if s.get("rank", "") != rank_before:
		lines.append(msg("CAREER_PROMOTED", [Officers.display_name(officer_id), Officers.rank_label(officer_id)]))

	# 길드 보고: 숫자로, 담담하게
	var lost: int = 0
	var sent: int = 0
	for u: BattleUnit in state.living("ally") + _fallen(state, "ally"):
		sent += u.start_troops
		lost += u.start_troops - u.troops
	report.append(msg("BATTLE_REPORT_LOSS", [Fmt.num(lost), int(round(100.0 * lost / maxf(sent, 1)))]))
	if state.bonus_spent > 0:
		report.append(msg("BATTLE_BONUS_SPENT", [Fmt.num(state.bonus_spent)]))
	for u: BattleUnit in _fallen(state, "ally"):
		if u.officer_id == "" and u.hire_index < 0:
			report.append(msg("BATTLE_REPORT_HELPER_LOST", [u.name]))
	report.append(msg("BATTLE_REPORT_DONE" if won else "BATTLE_REPORT_FAIL"))
	EventRunner.trigger("after_battle", {"won": won, "quest_type": quest.get("type", "monster")})
	return {"won": won, "lines": lines, "report": report}


static func _fallen(state: BattleState, team: String) -> Array[BattleUnit]:
	var list: Array[BattleUnit] = []
	for u: BattleUnit in state.units:
		if u.team == team and not u.alive():
			list.append(u)
	return list


static func msg(key: String, args: Array = []) -> String:
	return GameAction.msg(key, args)
