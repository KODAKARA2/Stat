class_name Career
extends RefCounted
## 출세 (GDD §4.2): 용병 신분 승진, 동료, 투신(봉신), 평정 임무, 공적, 사관 승진, 영지, 용병단 전쟁 계약.
## 주인공 상태에 쓰는 값: fame(명성), merit(공적), companions[], company{}, contract{}, mission{}, governs(다스리는 도시)


static func cfg(section: String, key: String, default_value: Variant = null) -> Variant:
	return DataDB.get_table("career").get(section, {}).get(key, default_value)


static func msg(key: String, args: Array = []) -> String:
	return GameAction.msg(key, args)


static func log_line(text: String) -> void:
	GameState.flags.get_or_add("month_log", []).append(text)


# ── 동료 ────────────────────────────────────────

static func companions(leader: String) -> Array:
	var list: Array = []
	for id: String in Officers.get_state(leader).get("companions", []):
		if Officers.is_active(id):
			list.append(id)
	return list


static func companion_slots(leader: String) -> int:
	return int(Officers.rank_row(leader).get("companion_slots", 0))


static func has_free_slot(leader: String) -> bool:
	return companions(leader).size() < companion_slots(leader)


## 영입할 수 있는 재야: 나라도 없고 다른 사람 동료도 아닌 사람
static func is_free_agent(id: String) -> bool:
	var s: Dictionary = Officers.get_state(id)
	return id != GameState.player_id and Officers.is_active(id) and s.get("nation", "") == "" and s.get("leader", "") == ""


static func recruit_chance(leader: String, target: String) -> float:
	var c: float = float(cfg("companion", "base", 0.3))
	c += (Relationship.affinity(leader, target) - int(cfg("companion", "affinity_floor", 20))) * float(cfg("companion", "per_affinity", 0.01))
	c += Officers.stat(leader, "cha") * float(cfg("companion", "per_cha", 0.003))
	c += int(Officers.get_state(leader).get("fame", 0)) * float(cfg("companion", "per_fame", 0.002))
	c += MercGrade.steps(leader) * float(MercGrade.cfg("recruit_per_step", 0.015))   # 이름난 용병이면 따라오고 싶어진다
	return clampf(c, cfg("companion", "min", 0.05), cfg("companion", "max", 0.95))


static func add_companion(leader: String, id: String) -> void:
	var s: Dictionary = Officers.get_state(leader)
	if not s.has("companions"):
		s["companions"] = []
	if not s["companions"].has(id):
		s["companions"].append(id)
	var c: Dictionary = Officers.get_state(id)
	c["leader"] = leader
	c["city"] = s.get("city", c.get("city", ""))
	Relationship.mark_met(leader, id)
	Relationship.add(leader, id, int(cfg("companion", "join_affinity", 10)))


static func remove_companion(leader: String, id: String) -> void:
	Officers.get_state(leader).get("companions", []).erase(id)
	Officers.get_state(id)["leader"] = ""


## 동료는 주인공을 따라다닌다
static func follow(leader: String) -> void:
	var city: String = Officers.get_state(leader).get("city", "")
	for id: String in companions(leader):
		Officers.get_state(id)["city"] = city


static func wage(id: String) -> int:
	var total: int = 0
	for key: String in Officers.stat_keys():
		total += Officers.stat(id, key)
	return int(cfg("companion", "wage_base", 5)) + int(total / float(cfg("companion", "wage_divisor", 25)))


## 매월 말 동료 월급. 못 주면 친밀도가 떨어지고, 0 아래면 떠난다.
static func pay_wages(leader: String) -> void:
	var s: Dictionary = Officers.get_state(leader)
	for id: String in companions(leader):
		var w: int = wage(id)
		if int(s["gold"]) >= w:
			s["gold"] = int(s["gold"]) - w
		else:
			var aff: int = Relationship.add(leader, id, int(cfg("companion", "unpaid_affinity", -10)))
			log_line(msg("CAREER_UNPAID", [Officers.display_name(id), aff]))
			if aff < 0:
				remove_companion(leader, id)
				log_line(msg("CAREER_COMPANION_LEFT", [Officers.display_name(id)]))


# ── 승진 ────────────────────────────────────────

## 같은 길(track)의 바로 위 신분
static func next_rank(id: String) -> Dictionary:
	var cur: Dictionary = Officers.rank_row(id)
	var best: Dictionary = {}
	for row: Dictionary in DataDB.get_rows("ranks"):
		if row["track"] == cur.get("track", "") and int(row["order"]) > int(cur.get("order", 0)):
			if best.is_empty() or int(row["order"]) < int(best["order"]):
				best = row
	return best


## 승진 조건을 채웠으면 올린다. 바뀌면 true.
static func check_promotion(id: String) -> bool:
	var nxt: Dictionary = next_rank(id)
	if nxt.is_empty():
		return false
	var s: Dictionary = Officers.get_state(id)
	if int(s.get("fame", 0)) < int(nxt.get("req_fame", 0)):
		return false
	if companions(id).size() < int(nxt.get("req_companions", 0)):
		return false
	if int(s.get("merit", 0)) < int(nxt.get("req_merit", 0)):
		return false
	if nxt["id"] == "lord" and assign_city(id) == "":
		return false   # 다스릴 도시가 없으면 성주가 될 수 없다
	s["rank"] = nxt["id"]
	log_line(msg("CAREER_PROMOTED", [Officers.display_name(id), TranslationServer.translate(nxt["name_key"])]))
	EventRunner.trigger("rank_change", {"rank": nxt["id"]})
	return true


## 승진 조건 안내 문장
static func next_rank_text(id: String) -> String:
	var nxt: Dictionary = next_rank(id)
	if nxt.is_empty():
		return TranslationServer.translate("CAREER_TOP")
	var parts: PackedStringArray = []
	var s: Dictionary = Officers.get_state(id)
	if nxt.has("req_fame"):
		parts.append(msg("CAREER_REQ_FAME", [int(s.get("fame", 0)), int(nxt["req_fame"])]))
	if nxt.has("req_companions"):
		parts.append(msg("CAREER_REQ_COMPANIONS", [companions(id).size(), int(nxt["req_companions"])]))
	if nxt.has("req_merit"):
		parts.append(msg("CAREER_REQ_MERIT", [int(s.get("merit", 0)), int(nxt["req_merit"])]))
	return msg("CAREER_NEXT", [TranslationServer.translate(nxt["name_key"]), " · ".join(parts)])


static func add_fame(id: String, amount: int) -> void:
	var s: Dictionary = Officers.get_state(id)
	s["fame"] = maxi(0, int(s.get("fame", 0)) + amount)


static func add_merit(id: String, amount: int) -> void:
	var s: Dictionary = Officers.get_state(id)
	s["merit"] = maxi(0, int(s.get("merit", 0)) + amount)


# ── 투신 (봉신) ─────────────────────────────────

static func is_vassal(id: String) -> bool:
	return Officers.track(id) in ["vassal", "ruler"]


## 투신할 수 없으면 사유 키
static func serve_check(id: String) -> String:
	var s: Dictionary = Officers.get_state(id)
	var n: String = GameState.city_owner(s.get("city", ""))
	if is_vassal(id):
		return "SERVE_FAIL_ALREADY"
	if n == "":
		return "SERVE_FAIL_NO_NATION"
	if Officers.rank_order(id) < int(cfg("serve", "min_rank_order", 2)):
		return "SERVE_FAIL_RANK"
	var rep: int = int(s.get("reputation", {}).get(n, 0))
	if rep < 0:
		return "SERVE_FAIL_HATED"
	if rep < int(cfg("serve", "min_reputation", 5)) and int(s.get("fame", 0)) < int(cfg("serve", "min_fame", 20)):
		return "SERVE_FAIL_UNKNOWN"
	return ""


static func serve_chance(id: String, n: String) -> float:
	var s: Dictionary = Officers.get_state(id)
	return clampf(float(cfg("serve", "base", 0.5)) + int(s.get("reputation", {}).get(n, 0)) * float(cfg("serve", "per_rep", 0.02))
		+ int(s.get("fame", 0)) * float(cfg("serve", "per_fame", 0.005)), 0.05, 0.95)


static func become_vassal(id: String, n: String) -> void:
	var s: Dictionary = Officers.get_state(id)
	s["nation"] = n
	s["rank"] = "vassal_knight"
	s["merit"] = 0
	s["governs"] = ""
	s["contract"] = {}


## 성주가 다스릴 도시: 지금 다스리는 도시가 아직 우리 나라면 그대로, 아니면 지금 있는 도시(우리 나라라면), 아니면 우리 나라 아무 도시
static func assign_city(id: String) -> String:
	var s: Dictionary = Officers.get_state(id)
	var n: String = s.get("nation", "")
	var cur: String = s.get("governs", "")
	if cur != "" and GameState.city_owner(cur) == n:
		return cur
	var pick: String = ""
	if GameState.city_owner(s.get("city", "")) == n:
		pick = s["city"]
	else:
		var cities: Array = Economy.cities_of(n)
		if not cities.is_empty():
			pick = cities[0]
	s["governs"] = pick
	return pick


static func governs(id: String) -> String:
	var s: Dictionary = Officers.get_state(id)
	# 군주는 자기 나라 도시라면 어디서든 다스린다
	if s.get("rank", "") == "ruler":
		var here: String = s.get("city", "")
		return here if GameState.city_owner(here) == s.get("nation", "") and s.get("nation", "") != "" else ""
	var city: String = s.get("governs", "")
	if city != "" and GameState.city_owner(city) != s.get("nation", ""):
		s["governs"] = ""   # 빼앗겼다
		return ""
	return city


static func pay_salary(id: String) -> void:
	if not is_vassal(id):
		return
	var s: Dictionary = Officers.get_state(id)
	var n: String = s.get("nation", "")
	var salary: int = int(Officers.rank_row(id).get("salary", 0))
	if salary <= 0 or not GameState.nations.has(n):
		return
	var paid: int = mini(salary, maxi(0, int(GameState.nations[n]["gold"])))
	GameState.nations[n]["gold"] = int(GameState.nations[n]["gold"]) - paid
	s["gold"] = int(s["gold"]) + paid
	log_line(msg("CAREER_SALARY", [Fmt.num(paid)]))


# ── 평정 임무 ───────────────────────────────────

## 매월 초 평정: 임무 하나. 우리 나라 출정이 있으면 참전 명령이 우선.
static func assign_mission(id: String) -> void:
	var s: Dictionary = Officers.get_state(id)
	if not is_vassal(id) or s.get("rank", "") == "ruler":   # 군주는 평정 임무를 받지 않는다
		s["mission"] = {}
		return
	var n: String = s["nation"]
	var mission: Dictionary = {}
	for p: Dictionary in WarSystem.plans():
		if p["attacker"] == n or p["defender"] == n:
			mission = {"type": "war", "plan": p["id"], "target": p["to"], "need": 1, "done": 0, "merit": int(cfg("missions", "war_merit", 15))}
			_give_war_order(id, p, p["attacker"] == n)
			break
	if mission.is_empty():
		var options: Array = ["subjugate", "train"]
		if governs(id) != "":
			options.append("develop")
		var kind: String = RNG.pick(options)
		var need: int = int(cfg("missions", kind + "_need", 1))
		mission = {"type": kind, "need": need, "done": 0, "merit": int(cfg("missions", kind + "_merit", 5))}
	s["mission"] = mission


## 참전 명령: 그 출정의 우리 편 참전 의뢰를 (한도와 상관없이) 받은 것으로 만든다
static func _give_war_order(id: String, plan: Dictionary, attack: bool) -> void:
	var city: String = plan["from"] if attack else plan["to"]
	var q: Dictionary = Guild.find(Guild.city_quests(city), "%s_%s" % [plan["id"], "a" if attack else "d"])
	if q.is_empty():
		return
	Guild.city_quests(city).erase(q)
	q["order"] = true   # 명령이라 의뢰 한도에 안 걸린다
	Officers.get_state(id).get_or_add("quests", []).append(q)
	log_line(msg("CAREER_WAR_ORDER", [WorldMap.city_name(plan["to"])]))


## 행동 결과로 임무 진행 (GameState가 EventBus.action_executed로 불러 준다)
static func on_action(actor: String, action_id: String, _result: Dictionary) -> void:
	if actor != GameState.player_id:
		return
	var m: Dictionary = Officers.get_state(actor).get("mission", {})
	if m.is_empty():
		return
	if (m["type"] == "train" and action_id == "train") or (m["type"] == "develop" and action_id == "govern"):
		m["done"] = int(m["done"]) + 1


## 전투가 끝나면 (BattleOutcome이 불러 준다): 공적·임무
static func on_battle(state: BattleState, won: bool) -> void:
	var id: String = GameState.player_id
	if not is_vassal(id) or not won:
		return
	var s: Dictionary = Officers.get_state(id)
	var q: Dictionary = state.quest
	var m: Dictionary = s.get("mission", {})
	if q.get("type", "") == "war" and q.get("side", "") == s["nation"]:
		add_merit(id, int(cfg("merit", "war_win", 12)))
		if m.get("type", "") == "war" and m.get("plan", "") == q.get("plan", ""):
			m["done"] = 1
	elif q.get("type", "monster") == "monster" and GameState.city_owner(q.get("city", "")) == s["nation"]:
		add_merit(id, int(cfg("merit", "own_subjugate", 4)))
		if m.get("type", "") == "subjugate":
			m["done"] = int(m["done"]) + 1


## 매월 말: 임무 판정
static func resolve_mission(id: String) -> void:
	var s: Dictionary = Officers.get_state(id)
	var m: Dictionary = s.get("mission", {})
	if m.is_empty():
		return
	if int(m["done"]) >= int(m["need"]):
		add_merit(id, int(m["merit"]))
		log_line(msg("CAREER_MISSION_DONE", [mission_text(m), int(m["merit"])]))
	else:
		add_merit(id, int(cfg("merit", "mission_fail", -2)))
		log_line(msg("CAREER_MISSION_FAILED", [mission_text(m)]))
	s["mission"] = {}


static func mission_text(m: Dictionary) -> String:
	match m.get("type", ""):
		"war":
			return msg("MISSION_WAR", [WorldMap.city_name(m.get("target", ""))])
		"subjugate":
			return msg("MISSION_SUBJUGATE")
		"train":
			return msg("MISSION_TRAIN", [int(m["need"])])
		"develop":
			return msg("MISSION_DEVELOP", [int(m["need"])])
	return ""


# ── 용병단과 전쟁 계약 ──────────────────────────

static func has_company(id: String) -> bool:
	return not Officers.get_state(id).get("company", {}).is_empty()


static func contract(id: String) -> Dictionary:
	return Officers.get_state(id).get("contract", {})


## 매월 초: 전쟁 중인 나라가 길드에 용병단 계약을 건다. 계약 = {"id", "type": "contract", "employer", "months", "pay", "penalty", "city"}
static func post_contracts() -> void:
	var fame: int = int(GameState.player().get("fame", 0))
	for n: String in Diplomacy.alive_nations():
		var at_war: bool = false
		for other: String in Diplomacy.alive_nations():
			at_war = at_war or Diplomacy.at_war(n, other)
		if not at_war:
			continue
		var chance: float = float(cfg("contract", "offer_chance", 0.5)) * float(Nations.row(n).get("hire_rate", 0.5))
		if not RNG.chance(chance):
			continue
		var cities: Array = Economy.cities_of(n)
		if cities.is_empty():
			continue
		var months: int = RNG.randi_range(int(cfg("contract", "months_min", 1)), int(cfg("contract", "months_max", 3)))
		var pay: int = int(float(cfg("contract", "pay_base", 150)) * (1.0 + fame * float(cfg("contract", "pay_per_fame", 0.005))))
		var city: String = RNG.pick(cities)
		GameState.cities[city].get_or_add("quests", []).append({
			"id": "c%d_%s" % [TimeManager.month_index(), n], "type": "contract", "employer": n, "city": city,
			"months": months, "pay": pay, "win_bonus": int(cfg("contract", "win_bonus", 80)),
			"gold": pay, "fame": 0, "tier": 2, "deadline": TimeManager.month_index(),
		})


static func accept_contract(id: String, offer: Dictionary) -> void:
	var c: Dictionary = offer.duplicate()
	c["months_left"] = int(c["months"])
	Officers.get_state(id)["contract"] = c


## 계약 중인데 고용국의 적 편에 서면 배신: 위약금, 평판·명성 하락, 계약 파기
static func betray_if_needed(id: String, side: String) -> String:
	var c: Dictionary = contract(id)
	if c.is_empty() or side == c["employer"] or not Diplomacy.at_war(side, c["employer"]):
		return ""
	var s: Dictionary = Officers.get_state(id)
	var penalty: int = int(c["pay"]) * int(c["months_left"])
	s["gold"] = maxi(0, int(s["gold"]) - penalty)
	var rep: Dictionary = s.get_or_add("reputation", {})
	rep[c["employer"]] = int(rep.get(c["employer"], 0)) + int(cfg("contract", "betray_rep", -25))
	add_fame(id, int(cfg("contract", "betray_fame", -10)))
	s["betrayals"] = int(s.get("betrayals", 0)) + 1
	s["contract"] = {}
	var text: String = msg("CONTRACT_BETRAYED", [Diplomacy.nation_name(c["employer"]), Fmt.num(penalty)])
	log_line(text)
	return text


## 매월 초: 계약 중이면 고용국 출정에 참전 명령
static func contract_orders(id: String) -> void:
	var c: Dictionary = contract(id)
	if c.is_empty():
		return
	for p: Dictionary in WarSystem.plans():
		if p["attacker"] == c["employer"]:
			_give_war_order(id, p, true)
		elif p["defender"] == c["employer"]:
			_give_war_order(id, p, false)


## 매월 말: 계약 보수, 남은 기간, 만료
static func tick_contract(id: String) -> void:
	var c: Dictionary = contract(id)
	if c.is_empty():
		return
	var s: Dictionary = Officers.get_state(id)
	var paid: int = MercGrade.pay(id, int(c["pay"]))   # 등급이 높을수록 월급이 많다
	s["gold"] = int(s["gold"]) + paid
	c["months_left"] = int(c["months_left"]) - 1
	log_line(msg("CONTRACT_PAID", [Diplomacy.nation_name(c["employer"]), Fmt.num(paid)]))
	var grade_up: String = MercGrade.add_points(id, int(MercGrade.cfg("points", {}).get("contract_month", 3)))
	if grade_up != "":
		log_line(grade_up)
	if int(c["months_left"]) <= 0:
		var rep: Dictionary = s.get_or_add("reputation", {})
		rep[c["employer"]] = int(rep.get(c["employer"], 0)) + int(cfg("contract", "complete_rep", 10))
		s["contract"] = {}
		log_line(msg("CONTRACT_DONE", [Diplomacy.nation_name(c["employer"])]))


# ── 월초·월말 묶음 (MonthlyUpdate가 부른다) ───────

static func start_month() -> void:
	var id: String = GameState.player_id
	if id == "" or not Officers.is_active(id):
		return
	if is_vassal(id):
		assign_mission(id)
	elif has_company(id):
		post_contracts()
		contract_orders(id)


static func end_month() -> void:
	var id: String = GameState.player_id
	if id == "" or not Officers.is_active(id):
		return
	pay_wages(id)
	pay_salary(id)
	tick_contract(id)
	resolve_mission(id)
	check_promotion(id)
