extends Node
## 자동 점검. 실행: godot --headless --path . res://tests/run_tests.tscn
## 실패가 하나라도 있으면 종료 코드 1.

var _fails: int = 0
var _passes: int = 0


func _ready() -> void:
	RNG.reseed(12345)
	_test_data()
	_test_m2_month()
	_test_m3_battle()
	_test_hire()
	_test_m4_war()
	_test_ui_smoke()
	_test_officer_gen()
	_test_bonus()
	_test_m5_career()
	_test_duel()
	_test_events()
	_test_shop()
	_test_family()
	_test_founding()
	_test_ending()
	_test_negotiation()
	_test_name_input()
	_test_skill_levels()
	_test_grade_and_morale()
	_test_save_load()
	print("== 결과: 통과 %d, 실패 %d ==" % [_passes, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func check(cond: bool, what: String) -> void:
	if cond:
		_passes += 1
	else:
		_fails += 1
		print("  [실패] " + what)


func _test_data() -> void:
	print("- 데이터")
	check(DataDB.errors.is_empty(), "데이터 오류 없음: %s" % ", ".join(DataDB.errors))
	check(DataDB.get_rows("cities").size() == 25, "도시 25개")
	check(WorldMap.shared().validate().is_empty(), "지도 연결 정상")
	for row: Dictionary in DataDB.get_rows("officers"):
		check(DataDB.get_row("cities", row["city"]).size() > 0, "%s의 도시 존재" % row["id"])
		check(DataDB.get_row("races", row["race"]).size() > 0, "%s의 종족 존재" % row["id"])
		check(DataDB.get_row("ranks", row["rank"]).size() > 0, "%s의 신분 존재" % row["id"])
		check(tr(row["name_key"]) != row["name_key"], "%s 이름 번역 있음" % row["id"])
	for row: Dictionary in DataDB.get_rows("ranks"):
		if row["track"] == "vassal":
			check(int(row["order"]) > int(DataDB.get_row("ranks", "merc_captain")["order"]), "%s는 용병대장보다 위" % row["id"])


func _test_m2_month() -> void:
	print("- M2: 한 달 행동")
	# 시험 중에 사용자의 자동 저장을 덮어쓰지 않도록 자동 저장을 끈다
	WorldSetup.new_game({"name": "시험", "race": "human", "origin": "leonhart", "background": "knight_bastard", "bonus": {"str": 5}})
	SaveManager.game_in_progress = false
	var me: String = GameState.player_id
	var p: Dictionary = GameState.player()
	check(p["city"] == "leongarde", "레온하트 출신은 레온가르드에서 시작")
	check(int(p["ap"]) == 3, "신입 용병 행동력 3 (실제 %d)" % int(p["ap"]))
	check(Officers.stat(me, "str") == 60, "무력 = 배경55 + 보너스5 (실제 %d)" % Officers.stat(me, "str"))
	check(Relationship.affinity(me, "gabriel") == 15, "출신 배경 인맥: 가브리엘 친밀도 15")

	# 엘프 × 드워프 종족 보정
	GameState.officers["tmp_elf"] = Officers.state_from_data({"id": "tmp_elf", "race": "elf", "city": "arden"})
	check(Relationship.affinity("tmp_elf", "torvi") == -10, "엘프-드워프 기본 친밀도 -10")
	GameState.officers.erase("tmp_elf")

	var before: int = Officers.stat(me, "str")
	var r: Dictionary = Actions.execute("train", me, {"stat": "str"})
	check(r["ok"], "수행 성공")
	r = Actions.execute("visit", me, {"target": "leopold"})
	check(r["ok"] and r.has("speech"), "방문 성공 + 대사")
	r = Actions.execute("interact", me, {"target": "leopold"})
	check(r["ok"] and int(p["gold"]) == 70, "교류로 금 30 소모 (남은 금 %d)" % int(p["gold"]))
	r = Actions.execute("rest", me)
	check(not r["ok"], "행동력 0이면 실패")

	# 이웃이 아닌 도시로 이동 불가
	TimeManager.advance_month()
	check(int(p["ap"]) == 3, "다음 달 행동력 회복")
	check(not Actions.execute("move", me, {"to": "portamerka"})["ok"], "멀리 있는 도시로는 이동 불가")
	check(Actions.execute("move", me, {"to": "arden"})["ok"] and p["city"] == "arden", "이웃 도시 아르덴으로 이동")
	check(not Actions.execute("visit", me, {"target": "leopold"})["ok"], "다른 도시 사람은 방문 불가")

	# 여러 달 수행하면 능력치가 오른다
	for i: int in 6:
		TimeManager.advance_month()
		for j: int in 3:
			if Actions.execute("train", me, {"stat": "str"})["ok"] == false:
				Actions.execute("rest", me)
	check(Officers.stat(me, "str") > before, "몇 달 수행 후 무력 상승 (%d → %d)" % [before, Officers.stat(me, "str")])
	check(Officers.stat(me, "str") <= Officers.potential(me, "str"), "잠재치를 넘지 않음")


func _test_save_load() -> void:
	print("- 저장/불러오기")
	var me: String = GameState.player_id
	var str_before: int = Officers.stat(me, "str")
	var month_before: int = TimeManager.month
	check(SaveManager.save_game("test"), "저장 성공")
	TimeManager.advance_month()
	GameState.player()["stats"]["str"] = 1
	check(SaveManager.load_game("test"), "불러오기 성공")
	check(Officers.stat(me, "str") == str_before, "능력치 복원")
	check(TimeManager.month == month_before, "날짜 복원")
	DirAccess.remove_absolute(SaveManager.slot_path("test"))


func _test_m3_battle() -> void:
	print("- M3: 토벌 의뢰와 전투")
	WorldSetup.new_game({"name": "시험", "race": "human", "origin": "leonhart", "background": "mountain_hunter", "bonus": {}})
	SaveManager.game_in_progress = false
	var me: String = GameState.player_id
	var p: Dictionary = GameState.player()
	check(Guild.city_quests("leongarde").size() == 3, "도시마다 의뢰 3개")
	for q: Dictionary in Guild.city_quests("leongarde"):
		check(int(q["tier"]) <= 3, "4단계 몬스터는 의뢰에 안 나옴")
	check(p["troops"] == Officers.max_troops(me), "시작 병력 = 최대 병력")

	var quest_id: String = Guild.city_quests("leongarde")[0]["id"]
	check(Actions.execute("accept_quest", me, {"quest": quest_id})["ok"], "의뢰 수주")
	check(int(p["ap"]) == 3, "수주는 행동력 0")
	check(Guild.city_quests("leongarde").size() == 2, "게시판에서 사라짐")
	var r: Dictionary = Actions.execute("subjugate", me, {"quest": quest_id})
	check(r["ok"] and r.get("battle", false) and int(p["ap"]) == 2, "토벌 출발: 행동력 1")

	var state: BattleState = BattleSetup.from_quest(r["quest"], me)
	check(state.living("ally").size() >= 2 and state.living("enemy").size() >= 2, "아군·적 배치")
	check(state.leader_of("ally").officer_id == me, "주인공이 총대장")
	# 강 칸은 이동력 3, 숲은 2
	var u: BattleUnit = state.leader_of("ally")
	state.set_terrain(u.cell + Vector2i(0, -1), "river")
	check(BattleRules.move_cost(state, u, u.cell + Vector2i(0, -1)) == 3, "강 이동력 3")
	# 피해 공식: 병력 400 × 0.15 × (55+50)/(50+50) = 63 (평지·상성 1)
	var a: BattleUnit = BattleSetup.helper_unit(Guild.cfg("helper_types")[0], 1)
	var d: BattleUnit = BattleSetup.helper_unit(Guild.cfg("helper_types")[0], 2)
	a.troops = 400
	a.str_ = 55
	d.lead = 50
	state.set_terrain(d.cell, "plains")
	check(BattleRules.damage(state, a, d, 1.0, "", false) == 63, "피해 공식 (실제 %d)" % BattleRules.damage(state, a, d, 1.0, "", false))

	var gold_before: int = int(p["gold"])
	var result: String = BattleAI.run_to_end(state)
	check(result in ["win", "lose"], "전투가 끝까지 진행됨 (%s, %d턴)" % [result, state.turn])
	var outcome: Dictionary = BattleOutcome.apply(state)
	if result == "win":
		check(int(p["gold"]) > gold_before, "승리 보수 지급")
		check(Guild.active_quests(me).is_empty(), "완료한 의뢰는 목록에서 빠짐")
	check(not outcome["report"].is_empty(), "길드 보고 작성")
	check(int(p["troops"]) == state.leader_of("ally").troops, "남은 병력이 장수에게 돌아감")

	# 다음 달: 병력 보충, 의뢰 갱신
	var troops_before: int = int(p["troops"])
	TimeManager.advance_month()
	check(int(p["troops"]) >= troops_before, "매월 병력 보충")
	check(Guild.city_quests("leongarde").size() == 3, "매월 의뢰 갱신")


func _test_hire() -> void:
	print("- 용병 고용 / 상인 집안")
	WorldSetup.new_game({"name": "시험", "race": "human", "origin": "merka", "background": "merchant_family", "bonus": {}})
	SaveManager.game_in_progress = false
	var me: String = GameState.player_id
	var p: Dictionary = GameState.player()
	check(Guild.hired(me).size() == 1, "상인 집안은 창병대 1부대를 계약한 채 시작")
	check(Guild.max_hired(me) == 3, "상인 집안 고용 한도 3")
	check(Guild.hire_cost(me, "helper_spear") == 45, "상재 할인: 창병대 60 → 45 (실제 %d)" % Guild.hire_cost(me, "helper_spear"))
	check(Actions.execute("hire", me, {"type": "helper_archer"})["ok"], "궁병대 고용")
	check(int(p["ap"]) == 3, "고용은 행동력 0")
	check(int(p["gold"]) == 300 - Guild.hire_cost(me, "helper_archer"), "고용비 지불")
	var q: Dictionary = Guild.make_quest(p["city"])
	var state: BattleState = BattleSetup.from_quest(q, me)
	var hired_units: int = 0
	for u: BattleUnit in state.units:
		if u.hire_index >= 0:
			hired_units += 1
	check(hired_units == 2, "고용 부대 2개가 전투에 참가")
	# 계약 2개월: 두 번 월말을 지나면 떠난다
	TimeManager.advance_month()
	check(Guild.hired(me).size() == 2, "1개월 뒤 아직 계약 중")
	TimeManager.advance_month()
	check(Guild.hired(me).is_empty(), "2개월 뒤 계약 종료")

	WorldSetup.new_game({"name": "시험", "race": "human", "origin": "merka", "background": "knight_bastard", "bonus": {}})
	SaveManager.game_in_progress = false
	check(Guild.hired(GameState.player_id).is_empty() and Guild.max_hired(GameState.player_id) == 2, "다른 배경은 고용 없음, 한도 2")
	check(Guild.hire_cost(GameState.player_id, "helper_spear") == 60, "할인 없음")


## 시험용 공격 계획 하나를 직접 만든다 (레온하트 로셀 → 아스트라 칼릭스)
func make_test_plan() -> Dictionary:
	Diplomacy.set_war("leonhart", "astra")
	var plan: Dictionary = {"id": "test_plan", "attacker": "leonhart", "defender": "astra", "from": "rocelle", "to": "calyx",
		"sent": 3000, "mercs": 0, "merc_cost": 0, "commander": "gabriel", "def_commander": "marcus", "player_side": "", "player_result": ""}
	GameState.flags["planned_attacks"] = [plan]
	Guild.post_war_quests(plan)
	return plan


func _test_m4_war() -> void:
	print("- M4: 전쟁")
	WorldSetup.new_game({"name": "시험", "race": "human", "origin": "leonhart", "background": "mountain_hunter", "bonus": {}})
	SaveManager.game_in_progress = false
	var me: String = GameState.player_id
	var p: Dictionary = GameState.player()
	check(GameState.nations["merka"]["gold"] > GameState.nations["bargum"]["gold"], "메르카 국고가 바르굼보다 많다")
	check(Diplomacy.at_war("leonhart", "astra") and not Diplomacy.at_war("leonhart", "merka"), "시작 외교 관계")
	check(Economy.city_income("portamerka") > Economy.city_income("rivar"), "세수: 수도 항구가 더 많다")

	var plan: Dictionary = make_test_plan()
	var a_quest: Dictionary = {}
	var d_quest: Dictionary = {}
	for q: Dictionary in Guild.city_quests("rocelle"):
		if q.get("plan", "") == "test_plan":
			a_quest = q
	for q: Dictionary in Guild.city_quests("calyx"):
		if q.get("plan", "") == "test_plan":
			d_quest = q
	check(not a_quest.is_empty() and not d_quest.is_empty(), "공격·방어 양쪽 도시에 참전 의뢰")
	check(Guild.quest_title(a_quest).contains("공격"), "참전 의뢰 제목")

	# 공격 참전: 공성전
	p["city"] = "rocelle"
	check(Actions.execute("accept_quest", me, {"quest": a_quest["id"]})["ok"], "공격 참전 수주")
	p["city"] = "calyx"
	check(Actions.execute("accept_quest", me, {"quest": d_quest["id"]})["reason"].contains("양쪽"), "같은 전투 양쪽 수주 금지")
	p["city"] = "rocelle"
	var state: BattleState = BattleSetup.from_war_quest(a_quest, me)
	check(state.mode == "siege_attack" and state.keep_cell == Vector2i(3, 0), "공성전: 성 안 거점")
	check(state.terrain_at(Vector2i(3, 1)) == "gate" and state.terrain_at(Vector2i(0, 1)) == "wall", "성벽과 성문")
	var has_siege: bool = false
	var has_cmd: bool = false
	for u: BattleUnit in state.living("ally"):
		has_siege = has_siege or u.unit_type == "siege"
		has_cmd = has_cmd or u.officer_id == "gabriel"
	check(has_siege and has_cmd, "아군에 공성병과 아군 지휘관(가브리엘)")
	var siege_unit: BattleUnit = BattleSetup.regular_unit("leonhart", "ally", 0, true)
	check(BattleRules.gate_damage(siege_unit, false) > BattleRules.gate_damage(BattleSetup.regular_unit("leonhart", "ally", 1, true), false) * 2, "공성병은 성문에 3배")
	var result: String = BattleAI.run_to_end(state)
	check(result in ["win", "lose"], "공성전 끝까지 진행 (%s, %d턴, 성문 %s)" % [result, state.turn, str(state.gate_hp.values())])
	BattleOutcome.apply(state)
	check(plan["player_result"] == result and plan["player_side"] == "leonhart", "참전 결과가 공격 계획에 기록됨")
	check(Guild.active_quests(me).is_empty(), "참전 의뢰는 한 번으로 끝")

	# 방어 공성전도 끝까지 돈다
	var dstate: BattleState = BattleSetup.from_war_quest(d_quest, me)
	check(dstate.mode == "siege_defend" and dstate.keep_cell.y == dstate.height - 1, "방어 공성전: 거점은 아래쪽")
	check(BattleAI.run_to_end(dstate) in ["win", "lose"], "방어 공성전 끝까지 진행")

	# 월말 판정: 점령되면 주인이 바뀐다
	plan["player_result"] = "win"
	GameState.cities["calyx"]["troops"] = 100
	var r: Dictionary = WarResolver.resolve(plan, 5)
	check(r["captured"] and GameState.city_owner("calyx") == "leonhart", "약한 도시는 점령된다")
	check(Officers.get_state("marcus").get("city", "") != "calyx" or not Officers.is_active("marcus"), "빼앗긴 도시의 무장은 퇴각")
	check(not r["lines"].is_empty() and r["lines"][0].contains("예산"), "국가 보고: 예산 문구")

	# 한 달 진행하면 보고서가 남는다
	TimeManager.advance_month()
	check(GameState.flags.has("report"), "월말 보고 생성")
	check(GameState.nations["leonhart"]["gold"] != null, "국고 유지")


## 화면 조각이 참전 의뢰·고용 부대를 그려도 오류가 없는지
func _test_ui_smoke() -> void:
	print("- 화면 조각")
	WorldSetup.new_game({"name": "시험", "race": "elf", "variant": "dark_elf", "origin": "merka", "background": "merchant_family", "bonus": {}})
	SaveManager.game_in_progress = false
	GameState.player()["city"] = "rocelle"
	make_test_plan()
	var panel: CityPanel = CityPanel.new()
	add_child(panel)
	check(panel.get_child_count() > 0, "도시 패널 생성 (참전 의뢰 포함)")
	panel.queue_free()
	var card: Control = OfficerCard.build(GameState.player_id)
	check(card.get_child_count() > 0, "인물 카드 생성")
	card.free()


func _test_officer_gen() -> void:
	print("- 범용 장수 / 등용")
	WorldSetup.new_game({"name": "시험", "race": "human", "origin": "merka", "background": "knight_bastard", "bonus": {}})
	SaveManager.game_in_progress = false
	var total: int = 0
	var count: int = 40
	var spiked: int = 0
	for i: int in count:
		var id: String = OfficerGen.generate("", "rivar", "none")
		var s: Dictionary = Officers.get_state(id)
		check(Officers.display_name(id) != "" and Officers.display_name(id) != "?", "이름 있음")
		for key: String in Officers.stat_keys():
			total += Officers.stat(id, key)
			check(Officers.potential(id, key) >= Officers.stat(id, key), "잠재치 ≥ 능력")
		if Officers.stat_keys().any(func(k: String) -> bool: return Officers.stat(id, k) >= 60):
			spiked += 1
		check(int(s["age"]) >= int(DataDB.get_row("races", s["race"])["adult_age"]), "성인")
	var avg: float = float(total) / (count * 6)
	check(avg > 25 and avg < 45, "평균 능력치는 낮다 (%.1f)" % avg)
	check(spiked > 0, "가끔 쓸 만한 인재 (%d/%d명이 60 이상 능력 보유)" % [spiked, count])
	# 군주가 죽으면 다음 사람이 즉위
	Officers.get_state("leopold")["alive"] = false
	Personnel.run_month("leonhart")
	check(Personnel.ruler_of("leonhart") != "", "새 군주 즉위 (%s)" % Officers.display_name(Personnel.ruler_of("leonhart")))
	# 몇 달 지나면 나라 무장이 늘어난다
	var before: int = Personnel.officers_of("bargum").size()
	for m: int in 12:
		TimeManager.advance_month()
	check(Personnel.officers_of("bargum").size() > before, "1년 뒤 바르굼 무장 증가 (%d → %d)" % [before, Personnel.officers_of("bargum").size()])


func _test_bonus() -> void:
	print("- 사기와 포상")
	WorldSetup.new_game({"name": "시험", "race": "human", "origin": "leonhart", "background": "merchant_family", "bonus": {}})
	SaveManager.game_in_progress = false
	var state: BattleState = BattleSetup.from_quest(Guild.make_quest("leongarde"), GameState.player_id)
	var a: BattleUnit = state.living("ally")[0]
	var d: BattleUnit = state.living("enemy")[0]
	var full: int = BattleRules.damage(state, a, d, 1.0, "", false)
	d.morale = 50
	check(abs(BattleRules.damage(state, a, d, 1.0, "", false) - full * 1.5) <= 1, "사기 50인 부대는 받는 피해 1.5배")
	d.morale = 100
	a.morale = 50
	check(abs(BattleRules.damage(state, a, d, 1.0, "", false) - full * 0.5) <= 1, "사기 50인 부대는 주는 피해 절반")
	a.morale = 0
	check(BattleRules.damage(state, a, d, 1.0, "", false) == 0, "사기 0이면 피해 0")
	a.morale = 40
	var gold: int = int(GameState.player()["gold"])
	var cost: int = BattleRules.bonus_cost(a)
	check(BattleRules.bonus_check(state, a) == "", "포상 가능")
	check(BattleRules.give_bonus(state, a) == 20 and a.morale == 60, "첫 포상 사기 +20")
	check(int(GameState.player()["gold"]) == gold - cost and state.bonus_spent == cost, "포상금은 주인공 금에서")
	check(BattleRules.give_bonus(state, a) == 10 and a.morale == 70, "두 번째 포상 +10")
	var gold3: int = int(GameState.player()["gold"])
	check(BattleRules.give_bonus(state, a) == 0 and a.morale == 70 and int(GameState.player()["gold"]) < gold3, "세 번째 포상: 돈만 받고 사기는 그대로")
	check(not a.acted, "포상은 행동을 쓰지 않는다")
	check(BattleRules.bonus_check(state, d) == "BONUS_FAIL_TARGET", "적에게는 못 준다")


## 행동력을 채워 주며 행동을 될 때까지 (확률 행동용)
func try_until(action_id: String, params: Dictionary, success_key: String, tries: int = 40) -> Dictionary:
	var r: Dictionary = {}
	for i: int in tries:
		GameState.player()["ap"] = 9
		r = Actions.execute(action_id, GameState.player_id, params)
		if r.get("ok", false) and r.get(success_key, false):
			return r
	return r


func _test_m5_career() -> void:
	print("- M5: 출세 (떠돌이 → 성주)")
	WorldSetup.new_game({"name": "시험", "race": "human", "origin": "leonhart", "background": "knight_bastard", "bonus": {"cha": 10}})
	SaveManager.game_in_progress = false
	var me: String = GameState.player_id
	var p: Dictionary = GameState.player()
	check(Career.companion_slots(me) == 1, "신입 용병 동료 한도 1")

	# 무명 무장 고용
	p["gold"] = 1000
	var r: Dictionary = Actions.execute("hire_officer", me, {})
	check(r["ok"] and Career.companions(me).size() == 1, "무명 무장 고용")
	var comp: String = Career.companions(me)[0]
	check(Officers.get_state(comp).get("generic", false), "범용 장수가 동료로")
	check(not Actions.execute("hire_officer", me, {})["ok"], "동료 한도 초과 불가")

	# 명성으로 승진
	p["fame"] = 16
	TimeManager.advance_month()
	check(p["rank"] == "merc_veteran", "명성 15 → 베테랑 용병 (%s)" % p["rank"])
	check(Career.companion_slots(me) == 2, "베테랑 동료 한도 2")
	check(int(p["gold"]) < 1000 - 120, "동료 월급 지급")

	# 재야 영입
	var free: String = OfficerGen.generate("", p["city"], "none")
	Relationship.mark_met(me, free)
	Relationship.add(me, free, 60)
	r = try_until("recruit", {"target": free}, "joined")
	check(r.get("joined", false) and Career.companions(me).has(free), "재야 영입 성공")
	# 동료는 따라온다, 전투에도 나간다
	p["ap"] = 3
	Actions.execute("move", me, {"to": "valois"})
	check(Officers.get_state(free)["city"] == "valois", "동료가 따라 이동")
	var st: BattleState = BattleSetup.from_quest(Guild.make_quest("valois"), me)
	var comp_units: int = 0
	for u: BattleUnit in st.living("ally"):
		if Career.companions(me).has(u.officer_id):
			comp_units += 1
	check(comp_units == 2, "동료 2명이 전투에 참가")

	# 투신: 평판이 있어야
	p["reputation"] = {"leonhart": 8}
	check(Career.serve_check(me) == "", "투신 조건 충족 (베테랑 + 평판 8)")
	r = try_until("serve", {}, "accepted")
	check(Career.is_vassal(me) and p["nation"] == "leonhart" and p["rank"] == "vassal_knight", "레온하트 봉신이 됨")
	check(Actions.execute("accept_quest", me, {"quest": Guild.city_quests("valois")[0]["id"]})["ok"], "봉신도 길드 의뢰를 받을 수 있다")

	# 평정 임무와 녹봉
	TimeManager.advance_month()
	check(not p.get("mission", {}).is_empty(), "평정 임무 받음: %s" % Career.mission_text(p.get("mission", {})))
	var gold_before: int = int(p["gold"])
	p["mission"] = {"type": "train", "need": 1, "done": 0, "merit": 5}
	p["ap"] = 3
	p["energy"] = 100
	Actions.execute("train", me, {"stat": "str"})
	check(int(p["mission"]["done"]) == 1, "수행 임무 진행")
	var merit_before: int = int(p.get("merit", 0))
	TimeManager.advance_month()
	check(int(p.get("merit", 0)) >= merit_before + 5, "임무 완수 → 공적 (%d)" % int(p.get("merit", 0)))
	var log_lines: Array = GameState.flags.get("report", {}).get("log", [])
	check(log_lines.any(func(l: String) -> bool: return l.contains("녹봉")), "녹봉 지급 (금 %d → %d)" % [gold_before, int(p["gold"])])

	# 공적 60 → 성주, 도시를 다스린다
	p["merit"] = 110
	p["city"] = "valois"
	Career.follow(me)
	TimeManager.advance_month()
	check(p["rank"] == "lord" and Career.governs(me) != "", "공적 100 → 성주 (%s, %s)" % [p["rank"], WorldMap.city_name(Career.governs(me))])

	# 통치
	var city: String = Career.governs(me)
	p["city"] = city
	p["ap"] = 5
	GameState.nations["leonhart"]["gold"] = 5000
	var com_before: int = int(GameState.cities[city]["commerce"])
	check(Actions.execute("govern", me, {"kind": "commerce"})["ok"] and int(GameState.cities[city]["commerce"]) > com_before, "상업 개발")
	check(Actions.execute("govern", me, {"kind": "defense"})["ok"], "방어 강화")

	# 출진: 전쟁 중인 이웃 도시
	var target: String = ""
	for other: String in WorldMap.shared().neighbors(city):
		if Diplomacy.at_war("leonhart", GameState.city_owner(other)):
			target = other
	if target == "":
		for other: String in WorldMap.shared().neighbors(city):
			if GameState.city_owner(other) != "leonhart":
				Diplomacy.set_war("leonhart", GameState.city_owner(other))
				target = other
				break
	GameState.flags["planned_attacks"] = []
	GameState.cities[city]["troops"] = 3000
	p["ap"] = 5
	r = Actions.execute("launch_war", me, {"target": target})
	check(r["ok"] and r.get("battle", false), "성주가 직접 출진 (%s → %s) %s" % [WorldMap.city_name(city), WorldMap.city_name(target), r.get("reason", "")])
	if r["ok"]:
		var siege: BattleState = BattleSetup.from_war_quest(r["quest"], me)
		check(siege.mode == "siege_attack" and siege.leader_of("ally").officer_id == me, "출진 공성전: 주인공이 총대장")
		check(BattleAI.run_to_end(siege) in ["win", "lose"], "출진 공성전 끝까지")
		BattleOutcome.apply(siege)
		check(WarSystem.find_plan(r["quest"]["plan"])["player_result"] != "", "출진 결과가 월말 판정에 반영")

	# 용병단과 전쟁 계약 (다른 판)
	WorldSetup.new_game({"name": "시험2", "race": "human", "origin": "merka", "background": "merchant_family", "bonus": {}})
	SaveManager.game_in_progress = false
	me = GameState.player_id
	p = GameState.player()
	p["rank"] = "merc_captain"
	p["fame"] = 120
	check(Actions.execute("form_company", me, {})["ok"] and Career.has_company(me), "용병단 결성")
	var offer: Dictionary = {"id": "c_test", "type": "contract", "employer": "astra", "city": p["city"], "months": 2, "pay": 200, "win_bonus": 80, "gold": 200, "fame": 0, "tier": 2, "deadline": TimeManager.month_index()}
	Guild.city_quests(p["city"]).append(offer)
	check(Actions.execute("accept_quest", me, {"quest": "c_test"})["ok"] and Career.contract(me)["employer"] == "astra", "아스트라와 계약")
	var gold: int = int(p["gold"])
	Career.tick_contract(me)
	check(int(p["gold"]) == gold + 200 and int(Career.contract(me)["months_left"]) == 1, "월 보수 지급")
	# 배신: 아스트라의 적 편에 선다
	Diplomacy.set_war("astra", "merka")
	var betray: String = Career.betray_if_needed(me, "merka")
	check(betray != "" and Career.contract(me).is_empty() and int(p["reputation"]["astra"]) < 0 and int(p["betrayals"]) == 1, "배신: 계약 파기·평판 하락")


func _test_duel() -> void:
	print("- 결투 (3수 예약형)")
	WorldSetup.new_game({"name": "시험", "race": "human", "origin": "leonhart", "background": "knight_bastard", "bonus": {}})
	SaveManager.game_in_progress = false
	var me: String = GameState.player_id
	var foe: String = "gabriel"
	GameState.player()["skills"] = []   # 필살기 해금 시험용 (기사의 서자는 돌격 → 일섬이 열려 있다)
	var d: DuelState = Duel.start(me, foe)
	check(int(d.max_hp[foe]) > int(d.max_hp[me]), "무력 높은 쪽이 체력도 높다")
	check(int(d.hand[me]["thrust"]) == 2 and int(d.hand[me]["dodge"]) == 1, "시작 손패: 공격 계통 2번씩, 회피 1번")
	check((d.specials[foe] as Array).has("flash") and not (d.specials[me] as Array).has("flash"), "무력 82 가브리엘은 일섬, 주인공은 아직")
	check((d.plan[foe] as Array).size() == 3, "상대는 3수를 미리 정해 둔다")
	check(d.hint.has("slot") and d.hint.has("kind"), "기색 힌트는 턴 시작에 한 번 정해진다")
	# 상성
	var r: Dictionary = Duel.clash("thrust", "slash")
	check(float(r["a_mult"]) == 1.0 and float(r["b_mult"]) == 0.0, "찌르기 > 베기")
	r = Duel.clash("bash", "thrust")
	check(float(r["a_mult"]) == 1.0 and float(r["b_mult"]) == 0.0, "치기 > 찌르기")
	r = Duel.clash("slash", "slash")
	check(r["clash"] and float(r["a_mult"]) == 0.0 and float(r["b_mult"]) == 0.0, "같은 계통은 충돌")
	r = Duel.clash("thrust", "dodge")
	check(float(r["a_mult"]) == 0.0 and r["b_stun"], "회피는 찌르기를 흘리고 빈틈을 만든다")
	r = Duel.clash("bash", "dodge")
	check(float(r["a_mult"]) > 1.0 and not r["b_stun"], "치기는 회피를 잡는다")
	r = Duel.clash("slash", "guard")
	check(float(r["a_mult"]) < 0.5 and float(r["b_mult"]) == 0.0, "방어는 피해를 크게 줄인다")
	r = Duel.clash("flash", "thrust")
	check(float(r["a_mult"]) > 1.5 and float(r["b_mult"]) == 0.0, "일섬은 상성과 관계없이 이긴다")
	r = Duel.clash("read", "bash")
	check(float(r["a_mult"]) > 0.0 and float(r["b_mult"]) == 0.0 and r["a_counter"], "간파는 공격을 받아친다")
	# 예약 규칙
	check(Duel.add(d, me, "thrust") and Duel.add(d, me, "thrust"), "찌르기 두 번 예약")
	check(Duel.can_add(d, me, "thrust") == "DUEL_FAIL_FULL" or Duel.can_add(d, me, "thrust") == "DUEL_FAIL_HAND", "손에 없는 수는 못 고른다")
	Duel.remove_last(d, me)
	check((d.plan[me] as Array).size() == 1 and Duel.remaining(d, me, "thrust") == 1, "하나 지우기")
	check(Duel.can_add(d, me, "flash") == "DUEL_FAIL_LOCKED", "익히지 못한 필살기는 잠김")
	# 한 턴 해결: 충돌 → 누적이 다음 피해에 붙는다 → 회피로 빈틈 (다음 턴 첫 수 무효)
	d.plan[me] = ["slash", "slash", "slash"]
	d.plan[foe] = ["slash", "thrust", "dodge"]
	var hp_before: int = int(d.hp[me])
	var log: Array = Duel.resolve_turn(d)
	check((log[0]["events"] as Array).has("clash"), "1수: 베기끼리 충돌")
	check(int(log[1]["a_dmg"]) > Duel.damage(foe, 1.0, false), "2수: 찌르기에 맞으며 충돌 누적까지 받았다")
	check((log[2]["events"] as Array).has("b_stun") and d.stunned[me], "3수: 회피당해 빈틈, 다음 턴으로 넘어간다")
	check(int(d.hp[me]) < hp_before and d.turn == 2, "턴이 넘어갔다")
	var total: int = 0
	for c: String in ["thrust", "slash", "bash", "dodge"]:
		total += int(d.hand[me][c])
	check(total == 7, "쓴 만큼 보충: 손패 수는 그대로 (%d)" % total)
	# 끝까지 (AI끼리 대충): 5턴 안에 결판 또는 판정
	var d2: DuelState = Duel.start(me, foe)
	var guard: int = 0
	while not d2.finished() and guard < 10:
		d2.plan[me] = Duel.ai_plan(d2, me)
		Duel.resolve_turn(d2)
		guard += 1
	check(d2.finished() and d2.turn <= 6, "5턴 안에 끝난다 (%d턴)" % d2.turn)
	check(d2.result in ["a", "b", "draw"], "결과: 승/패/무")
	# AI가 상황을 읽는다: 상대에게 회피가 없고 내 쪽 체력이 많으면, 보통 공격을 섞는다
	var d3: DuelState = Duel.start(foe, me)
	var plan: Array = Duel.ai_plan(d3, foe)
	check(plan.any(func(c: String) -> bool: return Duel.is_attack(c)), "AI 예약에 공격이 들어 있다 %s" % str(plan))
	# 전투 결과
	var st: BattleState = BattleSetup.from_quest(Guild.make_quest("leongarde"), me)
	var mine: BattleUnit = st.leader_of("ally")
	var theirs: BattleUnit = BattleSetup.officer_unit(foe, "enemy")
	st.add_unit(theirs)
	var won: DuelState = Duel.start(me, foe)
	won.hp[foe] = 0
	won.result = "a"
	Duel.apply_battle(st, mine, theirs, won)
	check(theirs.morale <= 60 and mine.morale == 100, "결투에서 진 부대 사기 -40")
	var drawn: DuelState = Duel.start(me, foe)
	drawn.result = "draw"
	var m_before: int = theirs.morale
	Duel.apply_battle(st, mine, theirs, drawn)
	check(theirs.morale == maxi(0, m_before - 5) and mine.morale == 95, "무승부: 양쪽 사기 -5")
	var thug: String = OfficerGen.generate("", "leongarde", "none")
	Officers.get_state(thug)["temporary"] = true
	var td: DuelState = Duel.start(me, thug)
	td.hp[thug] = 0
	td.result = "a"
	var fame_before: int = int(GameState.player()["fame"])
	Duel.apply_tavern(td)
	check(not GameState.officers.has(thug) and int(GameState.player()["fame"]) == fame_before + 3, "술집 결투 승리: 명성 +3, 시비꾼 퇴장")
	# 화면
	var panel: DuelPanel = DuelPanel.open(self, me, foe)
	for c: String in ["guard", "guard", "guard"]:
		panel._pick(c)
	check((panel.duel.plan[me] as Array).size() == 3, "결투 창: 버튼으로 3수 예약")
	panel.queue_free()


const KNOWN_CONDITIONS: Array = ["random", "gold", "fame", "merit", "rank_order", "track", "is_vassal", "has_company", "companions",
	"race", "variant", "background", "season", "month", "year", "flag", "city_owner", "city_terrain", "at_war_here", "injured",
	"affinity", "officer_alive", "officer_here", "battle_won", "context"]
const KNOWN_EFFECTS: Array = ["gold", "fame", "merit", "energy", "affinity", "reputation", "exp", "flag", "add_companion",
	"start_duel", "injury", "troops", "text", "chance"]
const KNOWN_TRIGGERS: Array = ["on_action", "month_start", "after_battle", "rank_change"]


func _test_events() -> void:
	print("- M6: 이벤트")
	var events: Array = EventRunner.all_events()
	check(events.size() >= 15, "이벤트 %d개" % events.size())
	var ids: Dictionary = {}
	for ev: Dictionary in events:
		var id: String = ev.get("id", "?")
		check(not ids.has(id), "%s: id 중복 없음" % id)
		ids[id] = true
		check(ev.get("trigger", "") in KNOWN_TRIGGERS, "%s: 트리거" % id)
		for c: Dictionary in ev.get("conditions", []):
			check(c.get("type", "") in KNOWN_CONDITIONS, "%s: 조건 %s" % [id, c.get("type", "")])
		var has_choice: bool = false
		for scene: Dictionary in ev.get("scenes", []):
			if scene.has("text_key"):
				check(tr(scene["text_key"]) != scene["text_key"], "%s: 문장 %s" % [id, scene["text_key"]])
			for ch: Dictionary in scene.get("choice", []):
				has_choice = true
				check(tr(ch["text_key"]) != ch["text_key"], "%s: 선택지 %s" % [id, ch["text_key"]])
				for c: Dictionary in ch.get("conditions", []):
					check(c.get("type", "") in KNOWN_CONDITIONS, "%s: 선택지 조건 %s" % [id, c.get("type", "")])
				for e: Dictionary in ch.get("effects", []):
					check(e.get("type", "") in KNOWN_EFFECTS, "%s: 효과 %s" % [id, e.get("type", "")])
					for k: String in ["key", "win_key", "lose_key"]:
						if e.has(k):
							check(tr(e[k]) != e[k], "%s: 효과 문장 %s" % [id, e[k]])
		check(has_choice, "%s: 선택지가 있다" % id)

	# 모든 이벤트의 모든 선택지를 실제로 적용해 본다 (오류 없이)
	for ev: Dictionary in events:
		for scene: Dictionary in ev.get("scenes", []):
			for ch: Dictionary in scene.get("choice", []):
				WorldSetup.new_game({"name": "시험", "race": "elf", "variant": "dark_elf", "origin": "leonhart", "background": "knight_bastard", "bonus": {}})
				SaveManager.game_in_progress = false
				GameState.player()["gold"] = 500
				EventRunner.clear_pending()
				GameState.flags["pending_event"] = {"id": ev["id"], "speakers": EventRunner._resolve_speakers(ev), "context": {}}
				EventRunner.apply_effects(ch.get("effects", []))
				EventRunner.clear_pending()
	check(true, "모든 선택지 적용 완료")

	# 트리거: 조건이 맞으면 이벤트가 걸린다
	WorldSetup.new_game({"name": "시험", "race": "elf", "variant": "dark_elf", "origin": "leonhart", "background": "knight_bastard", "bonus": {}})
	SaveManager.game_in_progress = false
	EventRunner.clear_pending()
	var hit: bool = false
	for i: int in 60:
		EventRunner.clear_pending()
		if EventRunner.trigger("on_action", {"action": "visit"}):
			hit = EventRunner.pending()["id"] == "ev_dark_elf_misread"
			if hit:
				break
	check(hit, "다크엘프 주인공이 방문하면 오해 이벤트가 걸린다")
	EventRunner.clear_pending()
	check(EventRunner.trigger("rank_change", {"rank": "merc_veteran"}) and EventRunner.pending()["id"] == "ev_rank_veteran", "승진 이벤트")
	EventRunner.clear_pending()
	check(not EventRunner.trigger("rank_change", {"rank": "merc_veteran"}), "한 번만 나오는 이벤트는 다시 안 나온다")


func _test_shop() -> void:
	print("- 상점 / 장비")
	WorldSetup.new_game({"name": "시험", "race": "human", "origin": "leonhart", "background": "knight_bastard", "bonus": {}})
	SaveManager.game_in_progress = false
	var me: String = GameState.player_id
	var p: Dictionary = GameState.player()
	p["gold"] = 1000
	check(not Shop.available("leongarde").is_empty(), "수도 상점에 물건이 있다")
	check(Shop.available("leongarde").any(func(i: Dictionary) -> bool: return i["id"] == "w_master_blade"), "수도 전용 물건")
	check(not Shop.available("arden").any(func(i: Dictionary) -> bool: return i["id"] == "w_master_blade"), "수도가 아니면 없음")
	check(not Shop.available("leongarde").any(func(i: Dictionary) -> bool: return i["id"] == "w_archmage_rod"), "아스트라 전용 물건은 레온하트에 없음")
	var base: int = Officers.stat(me, "str")
	check(Actions.execute("buy", me, {"item": "w_knight_sword"})["ok"], "장검 구입")
	check(Officers.stat(me, "str") == base + 6 and Officers.base_stat(me, "str") == base, "장비 보너스 +6 (기본치는 그대로)")
	var gold: int = int(p["gold"])
	check(Actions.execute("buy", me, {"item": "w_master_blade"})["ok"], "대검으로 교체")
	check(int(p["gold"]) == gold - 450 + 80 and Officers.stat(me, "str") == base + 10, "원래 장검은 반값에 팔림")
	check(not Actions.execute("buy", me, {"item": "w_master_blade"})["ok"], "같은 장비 중복 구입 불가")
	p["injury"] = 2
	Actions.execute("buy", me, {"item": "c_salve"})
	check(int(p["injury"]) == 1, "상처약: 부상 1개월 회복")
	WorldSetup.new_game({"name": "시험", "race": "halfling", "origin": "merka", "background": "merchant_family", "bonus": {}})
	SaveManager.game_in_progress = false
	check(Shop.price(GameState.player_id, DataDB.get_row("items", "x_silver_ring")) == 96, "하플링 20% 할인 (120 → 96)")


func _test_family() -> void:
	print("- M7: 가족·노화·승계")
	WorldSetup.new_game({"name": "시험", "race": "human", "gender": "m", "origin": "leonhart", "background": "knight_bastard", "bonus": {}})
	SaveManager.game_in_progress = false
	var me: String = GameState.player_id
	var p: Dictionary = GameState.player()

	# 노화: 수명 근처부터 확률
	p["age"] = 30
	check(Family.death_chance(me) == 0.0, "30세 인간은 노환 사망 확률 0")
	p["age"] = 70
	check(Family.death_chance(me) >= 0.3, "70세 인간은 높다 (%.2f)" % Family.death_chance(me))
	p["age"] = 18
	GameState.officers["tmp_elf"] = Officers.state_from_data({"id": "tmp_elf", "race": "elf", "age": 300, "city": "arden"})
	check(Family.death_chance("tmp_elf") == 0.0, "300세 엘프는 아직 멀었다")
	GameState.officers.erase("tmp_elf")

	# 연애와 결혼: 같은 도시의 미혼 성인 (이자벨: 로셀 성주)
	var partner: String = "isabelle"
	p["city"] = Officers.get_state(partner)["city"]
	p["gold"] = 500
	check(Family.can_confess(me, partner) == "ROMANCE_FAIL_AFFINITY", "친밀도가 낮으면 고백 불가")
	Relationship.mark_met(me, partner)
	Relationship.add(me, partner, 95)
	var r: Dictionary = try_until("confess", {"target": partner}, "accepted")
	check(Relationship.has_tag(me, partner, "lover"), "연인이 됨")
	p["ap"] = 3
	r = Actions.execute("propose", me, {"target": partner})
	check(r["ok"] and Family.spouse(me) == partner and Family.spouse(partner) == me, "결혼")
	check(int(p["gold"]) == 400, "혼례 비용 100")

	# 자녀: 출산 판정이 될 때까지 해를 넘긴다 (인간 × 인간 출산율 0.3)
	var child: String = ""
	for i: int in 20:
		Family._births()
		if not Family.children(me).is_empty():
			child = Family.children(me)[0]
			break
	check(child != "", "아이가 태어났다")
	if child != "":
		var c: Dictionary = Officers.get_state(child)
		check(c["minor"] and not Officers.is_active(child), "미성년은 활동하지 않는다")
		check(c["race"] == "human", "인간 부부의 아이는 인간")
		check(GameState.flags.get("pending_naming", "") == child, "주인공의 아이는 이름을 묻는다")
		c["age"] = 16
		Family.new_year()
		check(not c["minor"] and Officers.is_active(child), "16세 성인식")
		check(Career.companions(me).has(child), "주인공의 자녀는 동료로 합류")

	# 혼혈 없음: 종족은 부모 한쪽 50:50
	var elf_mom: String = OfficerGen.generate("", "arden", "none", "elf", "f")
	var races: Dictionary = {}
	for i: int in 40:
		var kid: String = Family.make_child(me, elf_mom)
		races[Officers.get_state(kid)["race"]] = true
		GameState.officers.erase(kid)
	check(races.size() == 2 and races.has("human") and races.has("elf"), "인간 × 엘프 자녀는 인간 또는 엘프 (하프 없음)")

	# 맹세
	Relationship.mark_met(me, "gabriel")
	Relationship.add(me, "gabriel", 100)
	p["city"] = Officers.get_state("gabriel")["city"]
	p["ap"] = 3
	check(Actions.execute("swear", me, {"target": "gabriel"})["ok"] and Relationship.has_tag(me, "gabriel", "sworn"), "가브리엘과 맹우")

	# 승계 순서: 성인 자녀 → 배우자 → 맹우
	check(Family.heir_of(me) == child, "후계자 1순위: 성인 자녀")
	var gold_before: int = int(p["gold"])
	Family.die(me, "battle")
	check(GameState.player_id == child, "자녀가 뒤를 잇는다")
	check(int(GameState.player()["gold"]) >= gold_before, "금을 물려받는다")
	check(GameState.flags.has("succession"), "승계 알림")

	# 후계자가 없으면 게임 오버
	WorldSetup.new_game({"name": "외톨이", "race": "human", "origin": "leonhart", "background": "knight_bastard", "bonus": {}})
	SaveManager.game_in_progress = false
	Family.die(GameState.player_id, "old_age")
	check(GameState.flags.has("game_over"), "후계자 없으면 게임 오버")


func _test_founding() -> void:
	print("- M7: 건국 (독립 선언 / 용병단 점령전)")
	WorldSetup.new_game({"name": "시험", "race": "human", "origin": "leonhart", "background": "knight_bastard", "bonus": {}})
	SaveManager.game_in_progress = false
	var me: String = GameState.player_id
	var p: Dictionary = GameState.player()
	var city: String = ""
	for c: String in Economy.cities_of("leonhart"):
		if not DataDB.get_row("cities", c).get("capital", false):
			city = c
			break
	p["nation"] = "leonhart"
	p["rank"] = "vassal_knight"
	p["city"] = city
	check(Founding.independence_check(me) == "FOUND_FAIL_RANK", "기사는 독립 불가")
	p["rank"] = "lord"
	p["governs"] = city
	p["gold"] = 1000
	p["ap"] = 9
	check(Founding.independence_check(me) == "", "성주는 다스리는 도시에서 독립 가능")
	var r: Dictionary = Actions.execute("declare_independence", me, {"name": "시험국", "color": Founding.COLORS[2]})
	check(r["ok"], "독립 선언 실행: %s" % r.get("reason", ""))
	var n: String = p.get("nation", "")
	check(Nations.is_player_nation(n) and Founding.player_nation() == n, "주인공 나라가 생겼다")
	check(GameState.city_owner(city) == n, "도시가 새 나라 소속")
	check(Nations.display_name(n) == "시험국" and Diplomacy.nation_name(n) == "시험국", "나라 이름")
	check(Nations.color(n) == Color.html(Founding.COLORS[2]), "깃발 색")
	check(p["rank"] == "ruler" and Officers.track(me) == "ruler", "주인공은 군주")
	check(Personnel.ruler_of(n) == me, "새 나라 군주 = 주인공 (NPC 즉위 없음)")
	check(Career.governs(me) == city, "군주는 자기 나라 도시를 다스린다")
	check(Diplomacy.at_war(n, "leonhart"), "원 소속국과 전쟁")
	var others_truce: bool = true
	for other: String in Diplomacy.alive_nations():
		if other != n and other != "leonhart":
			others_truce = others_truce and Diplomacy.status(n, other) == "truce"
	check(others_truce, "다른 나라와는 휴전")
	check(int(GameState.nations[n]["gold"]) == 1000 and int(p["gold"]) == 500, "금 절반이 국고로 (500 + 500)")
	check(Founding.independence_check(me) == "FOUND_FAIL_ALREADY_RULER", "이미 군주면 다시 독립 불가")
	# 몇 달 흘려도 문제 없다 (NPC가 주인공 나라 군주 자리를 뺏지 않는다)
	for i: int in 3:
		MonthlyUpdate.start_month(TimeManager.year, TimeManager.month)
		MonthlyUpdate.end_month(TimeManager.year, TimeManager.month)
	check(Personnel.ruler_of(n) == me or not GameState.nations[n]["alive"], "몇 달 뒤에도 군주는 주인공")
	# 저장/불러오기: 나라 이름이 남는다
	check(SaveManager.save_game("test_found"), "건국 후 저장")
	GameState.nations[n]["custom"]["name"] = "바뀜"
	check(SaveManager.load_game("test_found") and Nations.display_name(n) == "시험국", "불러오면 나라 이름 복원")
	DirAccess.remove_absolute(SaveManager.slot_path("test_found"))

	# 용병단 점령전
	WorldSetup.new_game({"name": "시험", "race": "human", "origin": "leonhart", "background": "knight_bastard", "bonus": {}})
	SaveManager.game_in_progress = false
	me = GameState.player_id
	p = GameState.player()
	var here: String = p["city"]
	var target: String = ""
	for other: String in WorldMap.shared().neighbors(here):
		if GameState.city_owner(other) != "":
			target = other
			break
	check(Founding.conquest_check(me, target) == "CONQUEST_FAIL_COMPANY", "용병단 없으면 점령전 불가")
	p["rank"] = "merc_captain"
	p["company"] = {"name": "시험단"}
	p["ap"] = 9
	check(Founding.conquest_check(me, target) == "", "용병대장 + 용병단이면 이웃 도시 점령전 가능")
	r = Actions.execute("conquest", me, {"target": target})
	check(r["ok"] and r["quest"]["type"] == "conquest", "점령전 시작")
	var enemy: String = GameState.city_owner(target)
	var state: BattleState = BattleSetup.from_war_quest(r["quest"], me)
	var only_company: bool = true
	for u: BattleUnit in state.living("ally"):
		only_company = only_company and (u.officer_id != "" or u.hire_index >= 0)
	check(only_company, "우리 편은 용병단뿐 (정규군 없음)")
	check(state.living("enemy").size() >= 3 and state.mode == "siege_attack", "공성전, 적 정규군 있음")
	state.result = "win"
	BattleOutcome.apply(state)
	check(GameState.flags.get("pending_founding", {}).get("city", "") == target, "이기면 건국 대기")
	Founding.found_nation(me, target, "점령국", Founding.COLORS[0], enemy)
	GameState.flags.erase("pending_founding")
	check(GameState.city_owner(target) == p["nation"] and p["city"] == target, "빼앗은 도시로 건국, 주인공은 그 도시로")
	check(Diplomacy.at_war(p["nation"], enemy), "빼앗긴 나라와 전쟁")
	check(Founding.conquest_check(me, here) == "FOUND_FAIL_VASSAL", "군주는 점령전 대신 출진")
	# 지면 원한
	WorldSetup.new_game({"name": "시험", "race": "human", "origin": "leonhart", "background": "knight_bastard", "bonus": {}})
	SaveManager.game_in_progress = false
	me = GameState.player_id
	p = GameState.player()
	p["rank"] = "merc_captain"
	p["company"] = {"name": "시험단"}
	p["fame"] = 300
	p["ap"] = 9
	r = Actions.execute("conquest", me, {"target": target})
	state = BattleSetup.from_war_quest(r["quest"], me)
	state.result = "lose"
	BattleOutcome.apply(state)
	check(int(p.get("reputation", {}).get(enemy, 0)) <= -20 and int(p["fame"]) <= 295, "지면 그 나라 평판 -20, 명성 -5")
	check(not GameState.flags.has("pending_founding"), "지면 건국 없음")


func _test_ending() -> void:
	print("- 엔딩 (통일 / 은퇴)")
	WorldSetup.new_game({"name": "시험", "race": "human", "origin": "leonhart", "background": "knight_bastard", "bonus": {}})
	SaveManager.game_in_progress = false
	var me: String = GameState.player_id
	var p: Dictionary = GameState.player()
	Ending.check_unification()
	check(not GameState.flags.has("ending"), "나라가 없으면 통일 아님")
	var city: String = Economy.cities_of("leonhart")[1]
	p["nation"] = "leonhart"
	p["rank"] = "lord"
	p["governs"] = city
	p["city"] = city
	Founding.found_nation(me, city, "통일국", Founding.COLORS[1], "leonhart")
	var n: String = p["nation"]
	for c: String in GameState.cities:
		GameState.cities[c]["nation"] = n
	MonthlyUpdate.end_month(TimeManager.year, TimeManager.month)
	check(GameState.flags.get("ending", {}).get("kind", "") == "unify", "모든 도시를 가지면 월말에 통일 엔딩")
	var info: Dictionary = GameState.flags.get("ending", {})
	check(int(info.get("cities", 0)) == 25 and info.get("nation", "") == "통일국", "엔딩 요약: 나라·도시")
	for key: String in info.get("epilogue", []):
		check(tr(key) != key, "맺음말 문자열 있음: " + key)
	GameState.flags.erase("ending")
	Ending.retire()
	info = GameState.flags["ending"]
	check(info["kind"] == "retire" and info["epilogue"].size() >= 3, "은퇴 엔딩 + 맺음말 3줄 이상")
	for key: String in info["epilogue"]:
		check(tr(key) != key, "맺음말 문자열 있음: " + key)
	check(not SaveManager.game_in_progress, "엔딩 뒤에는 자동 저장 안 함")
	var screen: Control = load("res://ui/title/ending_screen.tscn").instantiate()
	add_child(screen)
	check(screen.get_child_count() > 0, "엔딩 화면 생성")
	screen.queue_free()
	GameState.flags.erase("ending")


func _test_negotiation() -> void:
	print("- 설전 (논리/감정/위세)")
	WorldSetup.new_game({"name": "시험", "race": "human", "origin": "leonhart", "background": "knight_bastard", "bonus": {}})
	SaveManager.game_in_progress = false
	var me: String = GameState.player_id
	var p: Dictionary = GameState.player()
	var target: String = OfficerGen.generate("", p["city"], "none")
	var n: Dictionary = Negotiation.start("recruit", me, {"target": target})
	check(n["target"] == target and int(n["rounds"]) >= 3 and int(n["rounds"]) <= 5, "설전 3~5라운드")
	var mults: Array = n["posture"].values()
	mults.sort()
	check(mults == [0.3, 1.0, 1.5], "한 쪽은 열리고(×1.5) 한 쪽은 질색(×0.3)")
	check(Negotiation.APPROACHES.has(n["hint"]), "눈치 힌트")
	# 늘 열린 쪽을 고르면 거의 성공, 늘 질색하는 쪽이면 실패
	var best_ok: int = 0
	var worst_ok: int = 0
	for i: int in 40:
		var a: Dictionary = Negotiation.start("recruit", me, {"target": target})
		while not Negotiation.finished(a):
			Negotiation.play(a, _posture_pick(a, true))
		best_ok += 1 if Negotiation.succeeded(a) else 0
		var b: Dictionary = Negotiation.start("recruit", me, {"target": target})
		while not Negotiation.finished(b):
			Negotiation.play(b, _posture_pick(b, false))
		worst_ok += 1 if Negotiation.succeeded(b) else 0
	check(best_ok >= 30, "눈치대로 고르면 대부분 성공 (%d/40)" % best_ok)
	check(worst_ok <= 2, "질색하는 쪽만 고르면 실패 (%d/40)" % worst_ok)
	# 지력이 높을수록 힌트가 정확하다
	var hits: Dictionary = {}
	for stat: int in [10, 95]:
		p["stats"]["int"] = stat
		var hit: int = 0
		for i: int in 200:
			var h: Dictionary = Negotiation.start("recruit", me, {"target": target})
			hit += 1 if float(h["posture"][h["hint"]]) > 1.0 else 0
		hits[stat] = hit
	check(int(hits[95]) > int(hits[10]) + 40, "지력 95의 눈치가 지력 10보다 정확 (%d vs %d)" % [hits[95], hits[10]])
	# 설득 성공 → 동료
	p["ap"] = 9
	var r: Dictionary = Actions.execute("negotiate", me, {"kind": "recruit", "target": target})
	check(r["ok"], "설득 시작: %s" % r.get("reason", ""))
	check(Actions.can_execute("negotiate", me, {"kind": "recruit", "target": target}) == "NEGO_FAIL_TRIED", "같은 사람은 한 달에 한 번")
	var nego: Dictionary = r.get("negotiation", n)
	nego["gauge"] = nego["goal"]
	Negotiation.apply(nego)
	check(Career.companions(me).has(target), "설득 성공하면 동료")
	# 계약 보수 배율
	nego["gauge"] = 0
	check(is_equal_approx(Negotiation.pay_mult(nego), 0.75), "계약 보수 최저 75%")
	nego["gauge"] = int(nego["goal"]) + 30
	check(is_equal_approx(Negotiation.pay_mult(nego), 1.5), "계약 보수 최고 150%")
	var offer: Dictionary = {"id": "c_test", "type": "contract", "employer": "merka", "city": p["city"], "months": 2, "pay": 200, "win_bonus": 80,
		"gold": 200, "fame": 0, "tier": 2, "deadline": TimeManager.month_index()}
	GameState.cities[p["city"]].get_or_add("quests", []).append(offer)
	check(Actions.can_execute("negotiate", me, {"kind": "contract", "quest": "c_test"}) == "CONTRACT_FAIL_NO_COMPANY", "용병단 없으면 계약 교섭 불가")
	p["rank"] = "merc_captain"
	p["company"] = {"name": "시험단"}
	r = Actions.execute("negotiate", me, {"kind": "contract", "quest": "c_test"})
	check(r["ok"], "계약 교섭 시작: %s" % r.get("reason", ""))
	if r["ok"]:
		r["negotiation"]["gauge"] = r["negotiation"]["goal"]
		Negotiation.apply(r["negotiation"])
	check(int(offer["pay"]) == 300 and offer.get("negotiated", false), "교섭 성공 → 보수 150%, 한 번뿐")
	# 군주의 휴전 교섭
	var city: String = Economy.cities_of("leonhart")[1]
	p.erase("company")
	p["nation"] = "leonhart"
	p["rank"] = "lord"
	p["governs"] = city
	p["city"] = city
	Founding.found_nation(me, city, "교섭국", Founding.COLORS[3], "leonhart")
	p["ap"] = 9
	r = Actions.execute("negotiate", me, {"kind": "truce", "nation": "leonhart"})
	check(r["ok"], "휴전 교섭 시작: %s" % r.get("reason", ""))
	if r["ok"]:
		r["negotiation"]["gauge"] = r["negotiation"]["goal"]
		Negotiation.apply(r["negotiation"])
	check(Diplomacy.status(p["nation"], "leonhart") == "truce", "휴전 교섭 성공 → 휴전")
	check(Actions.can_execute("negotiate", me, {"kind": "truce", "nation": "leonhart"}) == "NEGO_FAIL_NOT_AT_WAR", "휴전 중이면 교섭할 게 없다")
	# 화면
	var panel: NegotiationPanel = NegotiationPanel.open(self, Negotiation.start("recruit", me, {"target": OfficerGen.generate("", p["city"], "none")}))
	for i: int in 6:
		if not Negotiation.finished(panel.nego):
			panel._play("logic")
	check(Negotiation.finished(panel.nego) and not panel._result.is_empty(), "설전 창: 끝까지 진행하고 결과 반영")
	panel.queue_free()
	var dialog: VBoxContainer = FoundingDialog.build("FOUND_TITLE", "본문", "기본", func(_a: String, _b: String) -> void: pass)
	check(dialog.get_child_count() > 0, "건국 창 생성")
	dialog.free()
	var cp: CityPanel = CityPanel.new()
	add_child(cp)
	check(cp.get_child_count() > 0, "군주의 도시 패널 생성 (휴전 교섭·통치)")
	cp.queue_free()
	var menu: MenuPanel = MenuPanel.new()
	add_child(menu)
	check(menu.get_child_count() > 0, "메뉴 패널 (은퇴 버튼)")
	menu.queue_free()
	check(load("res://ui/map/map_screen.gd") != null, "지도 화면 스크립트 컴파일")


func _posture_pick(n: Dictionary, best: bool) -> String:
	for k: String in n["posture"]:
		if (best and float(n["posture"][k]) > 1.0) or (not best and float(n["posture"][k]) < 1.0):
			return k
	return "logic"


func _test_name_input() -> void:
	print("- 이름 입력 (게임 안 한글 자판)")
	check(Hangul.compose(["ㅇ", "ㅛ", "ㅇ", "ㅂ", "ㅕ", "ㅇ"]) == "용병", "자모 조합: 용병")
	check(Hangul.compose(["ㄷ", "ㅏ", "ㄹ", "ㄱ", "ㅣ"]) == "달기", "받침 넘김: 닭+ㅣ → 달기")
	check(Hangul.compose(["ㄱ", "ㅗ", "ㅏ", "ㄴ"]) == "관", "겹모음: 관")
	var n: NameInput = NameInput.make("", 8)
	add_child(n)
	for k: String in ["ㅇ", "ㅛ", "ㅇ", "ㅂ", "ㅕ", "ㅇ", "ㄷ", "ㅏ", "ㄴ"]:
		n._key(k)
	check(n.get_text() == "용병단", "자판으로 여러 글자 입력: %s" % n.get_text())
	n._key("←")
	check(n.get_text() == "용병다", "지우기는 자모 하나씩")
	n._key("⇧")
	n._key("ㄱ")
	check(n.get_text() == "용병닦", "⇧ 된소리 받침")
	for i: int in 12:
		n._key("ㅏ")
	check(n.get_text().length() <= 8, "8글자 넘게는 안 들어간다")
	n.set_text("")
	n.edit.text = "Leon"   # 영문 직접 입력 뒤 자판 이어 쓰기
	n._key("ㄱ")
	check(n.get_text() == "Leonㄱ", "직접 입력한 글자 뒤에 이어 쓴다")
	n.queue_free()
	# 주인공 만들기: 이름을 넣고 다른 버튼(종족)을 눌러도 이름이 남는다
	var screen: Control = load("res://ui/create/create_screen.tscn").instantiate()
	add_child(screen)
	var input: NameInput = screen._name_input
	for k: String in ["ㄹ", "ㅔ", "ㅇ", "ㅗ", "ㄴ"]:
		input._key(k)
	for b: Node in screen.find_children("*", "Button", true, false):
		if (b as Button).text == tr("RACE_ELF"):
			(b as Button).pressed.emit()
	check(screen._race == "elf" and input.get_text() == "레온", "종족을 바꿔도 이름 유지 (%s)" % input.get_text())
	screen.queue_free()



func _test_skill_levels() -> void:
	print("- 전법 레벨 (1~3)")
	WorldSetup.new_game({"name": "시험", "race": "human", "origin": "leonhart", "background": "knight_bastard", "bonus": {}})
	SaveManager.game_in_progress = false
	var me: String = GameState.player_id
	var p: Dictionary = GameState.player()
	p["skills"] = ["volley", "charge"]
	p.erase("skill_levels")
	check(SkillLevels.level(me, "volley") == 1, "주인공 전법은 1레벨에서 시작")
	var r1: Dictionary = SkillLevels.row_for(me, "volley")
	check(int(r1["level"]) == 1 and int(r1["battle"]["radius"]) == 1 and is_equal_approx(float(r1["battle"]["power"]), 0.7), "1레벨 일제사격: 범위 1, 배율 0.7")
	# 많이 쓰면 오른다
	var ups: Array = []
	for i: int in 18:
		var lv: int = SkillLevels.add_use(me, "volley")
		if lv > 0:
			ups.append([i + 1, lv])
	check(ups == [[6, 2], [18, 3]], "6번째에 2레벨, 18번째에 3레벨 (%s)" % str(ups))
	var r3: Dictionary = SkillLevels.row_for(me, "volley")
	check(int(r3["battle"]["radius"]) == 2 and int(r3["battle"]["range_max"]) == 5, "3레벨 일제사격: 범위 2, 사거리 5")
	check(SkillLevels.add_use(me, "volley") == 0 and SkillLevels.level(me, "volley") == 3, "3레벨이 끝")
	# NPC는 주 능력치로: 가브리엘 무력 82 → 돌격 2레벨
	check(SkillLevels.level("gabriel", "charge") == 2, "가브리엘 돌격 2레벨 (무력 82)")
	# 친한 사람에게서 배운다 (스승 레벨까지, 한 달에 한 단계)
	check(SkillLevels.level(me, "charge") == 1, "주인공 돌격 1레벨")
	SkillLevels.start_month()
	check(SkillLevels.level(me, "charge") == 1, "안 친하면 못 배운다")
	Relationship.mark_met(me, "gabriel")
	Relationship.add(me, "gabriel", 100)
	SkillLevels.start_month()
	check(SkillLevels.level(me, "charge") == 2, "친밀도 70↑ 가브리엘에게서 2레벨로")
	SkillLevels.start_month()
	check(SkillLevels.level(me, "charge") == 2, "스승 레벨(2)보다 높게는 못 배운다")
	check(str(GameState.flags.get("month_log", [])).contains("가브리엘"), "배운 내용이 월말 보고에 남는다")
	# 전투: 레벨 반영 + 사용 횟수
	var quest: Dictionary = Guild.make_quest(p["city"])
	var state: BattleState = BattleSetup.from_quest(quest, me)
	var leader: BattleUnit = state.leader_of("ally")
	var skill: Dictionary = {}
	for sk: Dictionary in leader.battle_skills():
		if sk["id"] == "volley":
			skill = sk
	check(int(skill.get("level", 0)) == 3 and int(skill["battle"]["radius"]) == 2, "전투 부대의 전법도 3레벨 값")
	check(SkillLevels.title(skill) == tr("SKILL_VOLLEY") + " Lv3", "화면 이름: 일제사격 Lv3")
	var before: int = SkillLevels.uses(me, "charge")
	var foe: BattleUnit = state.living("enemy")[0]
	leader.sp = 100
	var charge: Dictionary = SkillLevels.row_for(me, "charge")
	BattleRules.use_skill(state, leader, charge, foe.cell)
	check(SkillLevels.uses(me, "charge") == before + 1, "전투에서 쓰면 사용 횟수 +1")
	# 3레벨 축성·치료는 이웃 아군까지
	var fort3: Dictionary = DataDB.get_row("skills", "fortify").duplicate(true)
	fort3["battle"].merge(fort3["levels"][2], true)
	var allies: Array[BattleUnit] = state.living("ally")
	if allies.size() >= 2:
		allies[1].cell = allies[0].cell + Vector2i(1, 0)
		allies[0].sp = 100
		allies[0].acted = false
		var out: Dictionary = BattleRules.use_skill(state, allies[0], fort3, allies[0].cell)
		check(out["guarded"].size() >= 2 and is_equal_approx(allies[1].guard, 0.4), "3레벨 축성: 옆 아군도 받는 피해 40%")
	check(SkillLevels.card_line(me, "volley").contains("Lv3"), "장수 카드에 전법 레벨")


func _test_grade_and_morale() -> void:
	print("- 용병 등급 (9급 → 1급) / 사기 차이")
	WorldSetup.new_game({"name": "시험", "race": "human", "origin": "leonhart", "background": "knight_bastard", "bonus": {}})
	SaveManager.game_in_progress = false
	var me: String = GameState.player_id
	var p: Dictionary = GameState.player()
	check(MercGrade.grade(me) == 9 and MercGrade.label(me) == "9급 용병", "9급 용병으로 시작")
	check(MercGrade.add_points(me, 5) == "" and MercGrade.grade(me) == 9, "공적 5: 아직 9급")
	check(MercGrade.add_points(me, 1) != "" and MercGrade.grade(me) == 8, "공적 6: 8급 승급 알림")
	MercGrade.add_points(me, 300)
	check(MercGrade.grade(me) == 1 and MercGrade.next_need(me) == 0, "공적이 많으면 1급 (더 오를 곳 없음)")
	check(p["rank"] == "merc_rookie" or p["rank"] == "none", "등급은 신분과 따로 (신분은 그대로)")
	check(MercGrade.pay(me, 100) == 140, "1급: 보수 +40%")
	check(MercGrade.quest_points({"type": "monster", "tier": 3}, true) == 8 and MercGrade.quest_points({"type": "war"}, false) == 2, "의뢰 단계·종류별 공적")
	var target: String = OfficerGen.generate("", p["city"], "none")
	var hi: float = Career.recruit_chance(me, target)
	p["merc_points"] = 0
	check(Career.recruit_chance(me, target) < hi, "등급이 높으면 영입이 잘 된다")
	# 토벌 정산: 공적과 보수 배율
	p["merc_points"] = 0
	var quest: Dictionary = Guild.make_quest(p["city"])
	quest["tier"] = 2
	var state: BattleState = BattleSetup.from_quest(quest, me)
	state.result = "win"
	var gold_before: int = int(p["gold"])
	BattleOutcome.apply(state)
	check(MercGrade.points(me) == 4 and int(p["gold"]) - gold_before == int(quest["gold"]), "2단계 토벌 승리: 공적 +4, 9급 보수는 그대로")

	# 사기: 맞은 쪽 하락 = 1 + (때린 쪽 사기 - 맞은 쪽 사기)
	var a: BattleUnit = BattleUnit.new()
	var d: BattleUnit = BattleUnit.new()
	a.morale = 100
	d.morale = 99
	check(BattleRules.morale_loss(a, d) == 2, "사기 100이 99를 치면 2 하락 (→ 97)")
	d.morale = 90
	check(BattleRules.morale_loss(a, d) == 11, "사기 100이 90을 치면 11 하락 (기본 1 + 차이 10)")
	a.morale = 50
	check(BattleRules.morale_loss(a, d) == 1, "사기 낮은 쪽이 높은 쪽을 치면 기본 1만")
