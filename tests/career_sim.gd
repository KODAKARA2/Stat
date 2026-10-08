extends Node
## 출세 속도 시험: 단순한 봇이 매달 토벌·참전 의뢰를 받아 자동 전투로 싸우고, 남는 행동력은 수행,
## 돈이 모이면 무명 무장을 고용하고, 조건이 되면 지금 도시의 나라에 투신한다.
## 각 신분에 처음 오른 시점(몇 년 몇 월)을 출력한다. 실행: godot --headless --path . res://tests/career_sim.tscn

const RUNS: Array = [
	["knight_bastard", 101], ["mountain_hunter", 102], ["fallen_mage", 103], ["merchant_family", 104],
	["knight_bastard", 105], ["mountain_hunter", 106],
	["knight_bastard", 107, "merc"], ["mountain_hunter", 108, "merc"],
]
const MONTHS: int = 240


func _ready() -> void:
	for run: Array in RUNS:
		RNG.reseed(run[1])
		WorldSetup.new_game({"name": "봇", "race": "human", "origin": "leonhart", "background": run[0], "bonus": {"str": 5, "lead": 5}})
		SaveManager.game_in_progress = false
		var me: String = GameState.player_id
		var reached: Dictionary = {}
		var wins: int = 0
		var fights: int = 0
		for m: int in MONTHS:
			if GameState.flags.has("game_over"):
				reached["game_over"] = "%d년%d월" % [TimeManager.year, TimeManager.month]
				break
			me = GameState.player_id   # 승계했으면 후계자로
			var p: Dictionary = GameState.player()
			var r: Array = _play_month(me, run.size() > 2)
			fights += r[0]
			wins += r[1]
			TimeManager.advance_month()
			var rank: String = p["rank"]
			if not reached.has(rank):
				reached[rank] = "%d년%d월" % [TimeManager.year, TimeManager.month]
			var g: String = "grade_%d" % MercGrade.grade(me)
			if not reached.has(g):
				reached[g] = "%d년%d월" % [TimeManager.year, TimeManager.month]
		var p: Dictionary = GameState.player()
		var order: PackedStringArray = []
		for rank: String in ["merc_veteran", "merc_senior", "merc_vice", "merc_captain", "vassal_knight", "lord", "general", "chancellor", "game_over"]:
			if reached.has(rank):
				order.append("%s %s" % [TranslationServer.translate(DataDB.get_row("ranks", rank).get("name_key", "게임 오버")), reached[rank]])
		var grades: PackedStringArray = []
		for g: int in [7, 5, 3, 1]:
			if reached.has("grade_%d" % g):
				grades.append("%d급 %s" % [g, reached["grade_%d" % g]])
		print("%-16s | 등급: %s" % [run[0], ", ".join(grades)])
		print("%-16s | %s | 전투 %d승/%d · 명성 %d · 공적 %d · 동료 %d · 금 %d" % [run[0], ", ".join(order),
			wins, fights, int(p.get("fame", 0)), int(p.get("merit", 0)), Career.companions(me).size(), int(p["gold"])])
	get_tree().quit()


## 한 달: [싸운 횟수, 이긴 횟수]
func _play_month(me: String, stay_merc: bool = false) -> Array:
	var p: Dictionary = GameState.player()
	var fights: int = 0
	var wins: int = 0
	if not stay_merc and Career.serve_check(me) == "":
		Actions.execute("serve", me)
	if stay_merc and not Career.has_company(me):
		Actions.execute("form_company", me)
	if int(p["gold"]) > 300 and Career.has_free_slot(me):
		Actions.execute("hire_officer", me)
	# 게시판에서 받을 만한 의뢰 (토벌 2단계 이하, 봉신이면 우리 나라 참전)
	for q: Dictionary in Guild.city_quests(p["city"]).duplicate():
		var ok: bool = q.get("type", "monster") == "monster" and int(q["tier"]) <= (3 if stay_merc and Officers.rank_order(me) >= 3 else 2)
		if stay_merc and q.get("type", "") == "war":
			ok = true
		if Career.is_vassal(me) and q.get("type", "") == "war" and q["side"] == p["nation"]:
			ok = true
		if ok:
			Actions.execute("accept_quest", me, {"quest": q["id"]})
	for q: Dictionary in Guild.active_quests(me).duplicate():
		if q["city"] != p["city"] or int(p["ap"]) <= 0:
			continue
		var r: Dictionary = Actions.execute("subjugate", me, {"quest": q["id"]})
		if not r["ok"]:
			continue
		var state: BattleState = BattleSetup.from_war_quest(q, me) if q.get("type", "") == "war" else BattleSetup.from_quest(q, me)
		fights += 1
		if BattleAI.run_to_end(state) == "win":
			wins += 1
		BattleOutcome.apply(state)
	# 남는 행동력: 통치(성주) → 수행 → 휴식
	while int(p["ap"]) > 0:
		if Career.governs(me) == p["city"] and Actions.execute("govern", me, {"kind": "commerce"})["ok"]:
			continue
		var best: String = "str"
		for key: String in ["lead", "str", "cha"]:
			if not Progression.is_capped(me, key) and (Progression.is_capped(me, best) or Officers.stat(me, key) < Officers.stat(me, best)):
				best = key
		if not Actions.execute("train", me, {"stat": best})["ok"]:
			if not Actions.execute("rest", me)["ok"]:
				break   # 죽었거나 행동할 수 없음 (게임 오버)
	return [fights, wins]
