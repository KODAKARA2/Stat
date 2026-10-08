class_name Duel
extends RefCounted
## 결투 규칙 (2026-10-08 개편: 3수 예약형. 삼국지10 일기토의 '3수 예약·사용 횟수·충돌 축적·회피'를 참고한 이 게임 전용 규칙).
##
## 명령
##  찌르기 thrust / 베기 slash / 치기 bash : 공격. 찌르기 > 베기 > 치기 > 찌르기.
##      같은 계통끼리는 '충돌' — 피해 없이 충돌 누적이 쌓이고, 다음에 맞는 쪽이 한꺼번에 받는다.
##  회피 dodge : 찌르기·베기를 흘리고 상대에게 '빈틈'(다음 수 무효)을 만든다. 치기에는 더 세게 맞는다.
##  방어 guard : 언제나 쓸 수 있다(횟수 무한). 받는 피해 크게 감소, 치기는 덜 막힌다.
##  필살기 (능력·특기로 해금, 기력 소모, 한 턴에 같은 것 한 번):
##      일섬 flash  — 모든 공격을 이기는 큰 베기
##      간파 read   — 상대가 물리 공격을 하면 무효로 하고 받아친다 (안 하면 헛수)
##      기합 focus  — 체력·기력 회복, 빈틈 해소 (그 사이 맞으면 더 아프다)
##      마검 spell  — 방어·회피를 무시하는 마법 일격 (공격과 맞부딪히면 둘 다 맞는다)
##  빈틈 none : 빈틈으로 무효가 된 수. 맞으면 더 아프다.
## 수치는 career.json duel.

const ATTACKS: Array[String] = ["thrust", "slash", "bash"]
const BASICS: Array[String] = ["thrust", "slash", "bash", "dodge", "guard"]
const SPECIALS: Array[String] = ["flash", "read", "focus", "spell"]
const BEATS: Dictionary = {"thrust": "slash", "slash": "bash", "bash": "thrust"}   # 이기는 상대
const SLOTS: int = 3


static func cfg(key: String, default_value: Variant = null) -> Variant:
	return DataDB.get_table("career").get("duel", {}).get(key, default_value)


# ── 시작 ────────────────────────────────────────

static func start(a_id: String, b_id: String) -> DuelState:
	var d: DuelState = DuelState.new()
	d.a_id = a_id
	d.b_id = b_id
	for id: String in [a_id, b_id]:
		d.max_hp[id] = int(float(cfg("hp_base", 60)) + Officers.stat(id, "str") * float(cfg("hp_per_str", 0.6)))
		d.hp[id] = d.max_hp[id]
		d.sp[id] = int(cfg("sp_start", 30))
		d.hand[id] = (cfg("hand_start", {"thrust": 2, "slash": 2, "bash": 2, "dodge": 1}) as Dictionary).duplicate()
		d.specials[id] = specials_of(id)
		d.plan[id] = []
		d.stunned[id] = false
	_begin_turn(d)
	return d


## 그 장수가 쓸 수 있는 필살기: 능력치 또는 특기로 해금
static func specials_of(id: String) -> Array:
	var out: Array = []
	var skills: Array = Officers.get_state(id).get("skills", [])
	var unlock: Dictionary = cfg("special_unlock", {})
	for sp_id: String in SPECIALS:
		var u: Dictionary = unlock.get(sp_id, {})
		var ok: bool = Officers.stat(id, u.get("stat", "str")) >= int(u.get("min", 999))
		for sk: String in u.get("skills", []):
			ok = ok or skills.has(sk)
		if ok:
			out.append(sp_id)
	return out


static func sp_cost(cmd: String) -> int:
	return int(cfg("special_cost", {}).get(cmd, 0))


static func is_attack(cmd: String) -> bool:
	return ATTACKS.has(cmd) or cmd == "flash"


## 명령의 계통 (일섬은 베기 계통)
static func family(cmd: String) -> String:
	return "slash" if cmd == "flash" else cmd


# ── 예약 ────────────────────────────────────────

## 지금 예약에 cmd를 더할 수 있으면 "", 아니면 사유 키
static func can_add(d: DuelState, id: String, cmd: String) -> String:
	var plan: Array = d.plan[id]
	if plan.size() >= SLOTS:
		return "DUEL_FAIL_FULL"
	if cmd == "guard":
		return ""
	if SPECIALS.has(cmd):
		if not (d.specials[id] as Array).has(cmd):
			return "DUEL_FAIL_LOCKED"
		if plan.has(cmd):
			return "DUEL_FAIL_ONCE"
		var spent: int = 0
		for c: String in plan:
			spent += sp_cost(c)
		return "" if int(d.sp[id]) >= spent + sp_cost(cmd) else "DUEL_FAIL_SP"
	var used: int = plan.count(cmd)
	return "" if int(d.hand[id].get(cmd, 0)) > used else "DUEL_FAIL_HAND"


static func add(d: DuelState, id: String, cmd: String) -> bool:
	if can_add(d, id, cmd) != "":
		return false
	(d.plan[id] as Array).append(cmd)
	return true


static func remove_last(d: DuelState, id: String) -> void:
	var plan: Array = d.plan[id]
	if not plan.is_empty():
		plan.pop_back()


## 남은 횟수 (예약한 만큼 뺀 것). 방어는 -1 = 무한
static func remaining(d: DuelState, id: String, cmd: String) -> int:
	if cmd == "guard":
		return -1
	return int(d.hand[id].get(cmd, 0)) - (d.plan[id] as Array).count(cmd)


# ── 턴 ──────────────────────────────────────────

static func _begin_turn(d: DuelState) -> void:
	d.plan[d.b_id] = ai_plan(d, d.b_id)
	d.plan[d.a_id] = []
	d.log = []
	# 상대 기색: 지력 차이로 정확도가 정해진다. 턴 시작에 한 번만 뽑는다 (화면을 다시 그려도 그대로)
	var acc: float = clampf(float(cfg("hint_base", 0.5)) + (Officers.stat(d.a_id, "int") - Officers.stat(d.b_id, "int")) * float(cfg("hint_per_int", 0.01)),
		float(cfg("hint_min", 0.25)), float(cfg("hint_max", 0.85)))
	var slot: int = RNG.randi_range(0, SLOTS - 1)
	var real: String = _hint_kind(d.plan[d.b_id][slot])
	var shown: String = real
	if not RNG.chance(acc):
		var others: Array = ["attack", "guard", "special"]
		others.erase(real)
		shown = RNG.pick(others)
	d.hint = {"slot": slot, "kind": shown}


static func _hint_kind(cmd: String) -> String:
	if SPECIALS.has(cmd):
		return "special"
	return "attack" if is_attack(cmd) else "guard"


## 플레이어 예약 확정 → 3수를 차례로 해결. 결과는 d.log. 예약이 3수가 아니면 남은 칸은 방어로 채운다.
static func resolve_turn(d: DuelState) -> Array:
	while (d.plan[d.a_id] as Array).size() < SLOTS:
		(d.plan[d.a_id] as Array).append("guard")
	var steps: Array = []
	for i: int in SLOTS:
		if d.finished():
			break
		steps.append(_resolve_slot(d, i))
		_check_end(d, false)
	if not d.finished():
		_end_turn(d)   # (다음 턴 준비가 d.log를 비우므로 결과는 따로 들고 있다가 돌려준다)
	d.log = steps
	return steps


static func _end_turn(d: DuelState) -> void:
	for id: String in [d.a_id, d.b_id]:
		# 쓴 만큼 무작위 보충 (계통마다 상한)
		var used: int = 0
		for c: String in d.plan[id]:
			if c != "guard" and not SPECIALS.has(c) and c != "none":
				d.hand[id][c] = int(d.hand[id].get(c, 0)) - 1
				used += 1
		var caps: Dictionary = cfg("hand_cap", {"thrust": 3, "slash": 3, "bash": 3, "dodge": 2})
		for k: int in used:
			var room: Array = []
			for c: String in caps:
				if int(d.hand[id].get(c, 0)) < int(caps[c]):
					room.append(c)
			if room.is_empty():
				break
			var pick: String = RNG.pick(room)
			d.hand[id][pick] = int(d.hand[id].get(pick, 0)) + 1
		d.sp[id] = mini(int(d.sp[id]) + int(cfg("sp_regen_turn", 10)), int(cfg("sp_max", 100)))
	d.turn += 1
	_check_end(d, true)
	if not d.finished():
		_begin_turn(d)


## 끝났는지: 쓰러짐(동시에 쓰러지면 무승부), 마지막 턴이 끝나면 체력 비율 (차이가 작으면 무승부)
static func _check_end(d: DuelState, turn_over: bool) -> void:
	var a_down: bool = int(d.hp[d.a_id]) <= 0
	var b_down: bool = int(d.hp[d.b_id]) <= 0
	if a_down and b_down:
		d.result = "draw"
	elif b_down:
		d.result = "a"
	elif a_down:
		d.result = "b"
	elif turn_over and d.turn > int(cfg("turns", 5)):
		var ra: float = float(d.hp[d.a_id]) / maxf(d.max_hp[d.a_id], 1)
		var rb: float = float(d.hp[d.b_id]) / maxf(d.max_hp[d.b_id], 1)
		if absf(ra - rb) < float(cfg("draw_margin", 0.05)):
			d.result = "draw"
		else:
			d.result = "a" if ra > rb else "b"


# ── 한 수 해결 ──────────────────────────────────

static func _resolve_slot(d: DuelState, i: int) -> Dictionary:
	var a: String = d.a_id
	var b: String = d.b_id
	var cmd: Dictionary = {}
	for id: String in [a, b]:
		cmd[id] = String(d.plan[id][i]) if i < (d.plan[id] as Array).size() else "guard"
		if d.stunned[id]:
			cmd[id] = "none"   # 빈틈: 이 수는 무효
			d.stunned[id] = false
	var out: Dictionary = {"slot": i, "a_cmd": cmd[a], "b_cmd": cmd[b], "a_dmg": 0, "b_dmg": 0, "events": []}
	# 필살기 기력: 실제로 나간 수만 소모
	for id: String in [a, b]:
		d.sp[id] = maxi(0, int(d.sp[id]) - sp_cost(cmd[id]))
	var r: Dictionary = clash(cmd[a], cmd[b])   # {"a_mult", "b_mult", "clash", "a_stun", "b_stun", "a_focus", "b_focus", "a_counter", "b_counter"}
	if r.get("clash", false):
		d.pool = mini(d.pool + int(cfg("clash_add", 8)), int(cfg("clash_cap", 40)))
		out["events"].append("clash")
	for id: String in [a, b]:
		var side: String = "a" if id == a else "b"
		var mult: float = float(r.get(side + "_mult", 0.0))   # 이 사람이 '주는' 피해 배율
		if mult > 0.0:
			var dmg: int = damage(id, mult) + d.pool
			if d.pool > 0:
				out["events"].append("pool")
			d.pool = 0
			var foe: String = d.other(id)
			d.hp[foe] = maxi(0, int(d.hp[foe]) - dmg)
			out[("b" if side == "a" else "a") + "_dmg"] = dmg
		if r.get(side + "_stun", false):
			d.stunned[d.other(id)] = true   # 이 사람이 상대에게 빈틈을 만들었다
			out["events"].append(side + "_stun")
		if r.get(side + "_focus", false):
			d.hp[id] = mini(int(d.max_hp[id]), int(d.hp[id]) + int(int(d.max_hp[id]) * float(cfg("focus_heal", 0.1))))
			d.sp[id] = mini(int(cfg("sp_max", 100)), int(d.sp[id]) + int(cfg("focus_sp", 25)))
			d.stunned[id] = false
			out["events"].append(side + "_focus")
		if r.get(side + "_counter", false):
			out["events"].append(side + "_counter")
	out["text"] = _text(d, out)
	# 화면이 한 수씩 보여 줄 수 있게 이 수가 끝난 뒤 상태를 함께 적는다
	out["hp"] = {a: int(d.hp[a]), b: int(d.hp[b])}
	out["sp"] = {a: int(d.sp[a]), b: int(d.sp[b])}
	out["pool"] = d.pool
	out["stunned"] = {a: bool(d.stunned[a]), b: bool(d.stunned[b])}
	return out


## 두 명령의 맞부딪힘 (a 쪽 기준). *_mult = 그쪽이 주는 피해 배율 (0이면 안 줌)
static func clash(x: String, y: String) -> Dictionary:
	var r: Dictionary = _one_way(x, y)
	var back: Dictionary = _one_way(y, x)
	var out: Dictionary = {"a_mult": r["mult"], "b_mult": back["mult"], "clash": r["clash"] or back["clash"],
		"a_stun": r["stun"], "b_stun": back["stun"], "a_focus": r["focus"], "b_focus": back["focus"],
		"a_counter": r["counter"], "b_counter": back["counter"]}
	return out


## x를 낸 쪽이 y를 낸 상대에게: {"mult": 주는 피해 배율, "clash", "stun": 상대에게 빈틈, "focus": 기합 성공, "counter": 간파 성공}
static func _one_way(x: String, y: String) -> Dictionary:
	var m: Dictionary = cfg("mult", {})
	var r: Dictionary = {"mult": 0.0, "clash": false, "stun": false, "focus": false, "counter": false}
	match x:
		"thrust", "slash", "bash", "flash":
			var base: float = float(m.get("flash", 2.0)) if x == "flash" else 1.0
			if is_attack(y):
				if family(x) == family(y) and (x == "flash") == (y == "flash"):
					r["clash"] = true            # 같은 계통: 충돌
				elif x == "flash" or (y != "flash" and BEATS[family(x)] == family(y)):
					r["mult"] = base             # 이겼다
			else:
				match y:
					"guard":
						r["mult"] = base * float(m.get("bash_vs_guard", 0.6) if x == "bash" else m.get("vs_guard", 0.35))
					"dodge":
						if x == "bash":
							r["mult"] = base * float(m.get("bash_vs_dodge", 1.2))   # 피하려다 걸렸다
						# 찌르기·베기·일섬은 빗나간다 (빈틈은 회피한 쪽이 만든다)
					"read":
						pass                         # 간파당했다 (받아치기는 read 쪽에서)
					"focus":
						r["mult"] = base * float(m.get("vs_focus", 1.3))
					"spell":
						r["mult"] = base             # 맞부딪히면 둘 다 맞는다
					"none":
						r["mult"] = base * float(m.get("vs_none", 1.25))
		"dodge":
			if y in ["thrust", "slash", "flash"]:
				r["stun"] = true                 # 흘려 내고 상대에게 빈틈
		"read":
			if is_attack(y):
				r["mult"] = float(m.get("read_counter", 1.3))
				r["counter"] = true
		"focus":
			if not is_attack(y) and y != "spell":
				r["focus"] = true
		"spell":
			var sm: float = float(m.get("spell", 1.4))
			r["mult"] = sm * (float(m.get("vs_focus", 1.3)) if y == "focus" else 1.0) * (float(m.get("vs_none", 1.25)) if y == "none" else 1.0)
	return r


## 한 번의 피해: (dmg_base + 무력 × dmg_per_str) × 배율 × 무작위
static func damage(id: String, mult: float, randomize: bool = true) -> int:
	var base: float = float(cfg("dmg_base", 10)) + Officers.stat(id, "str") * float(cfg("dmg_per_str", 0.25))
	var r: float = float(cfg("dmg_random", 0.12)) if randomize else 0.0
	return maxi(1, int(round(base * mult * (RNG.randf_range(1.0 - r, 1.0 + r) if randomize else 1.0))))


static func _text(d: DuelState, out: Dictionary) -> String:
	var an: String = Officers.display_name(d.a_id)
	var bn: String = Officers.display_name(d.b_id)
	var ev: Array = out["events"]
	var parts: PackedStringArray = []
	if ev.has("clash"):
		parts.append(TranslationServer.translate("DUEL_EV_CLASH") % d.pool)
	if ev.has("a_counter"):
		parts.append(TranslationServer.translate("DUEL_EV_COUNTER") % an)
	if ev.has("b_counter"):
		parts.append(TranslationServer.translate("DUEL_EV_COUNTER") % bn)
	if ev.has("a_stun"):
		parts.append(TranslationServer.translate("DUEL_EV_OPENING") % [an, bn])
	if ev.has("b_stun"):
		parts.append(TranslationServer.translate("DUEL_EV_OPENING") % [bn, an])
	if ev.has("a_focus"):
		parts.append(TranslationServer.translate("DUEL_EV_FOCUS") % an)
	if ev.has("b_focus"):
		parts.append(TranslationServer.translate("DUEL_EV_FOCUS") % bn)
	if ev.has("pool"):
		parts.append(TranslationServer.translate("DUEL_EV_POOL"))
	if int(out["b_dmg"]) > 0 and int(out["a_dmg"]) > 0:
		parts.append(TranslationServer.translate("DUEL_EV_TRADE"))
	elif int(out["b_dmg"]) > 0:
		parts.append(TranslationServer.translate("DUEL_EV_HIT") % [an, bn])
	elif int(out["a_dmg"]) > 0:
		parts.append(TranslationServer.translate("DUEL_EV_HIT") % [bn, an])
	elif parts.is_empty():
		parts.append(TranslationServer.translate("DUEL_EV_NOTHING"))
	return " ".join(parts)


# ── AI ──────────────────────────────────────────

## 상대 예약: 가능한 3수 조합을 모두 만들고, 상대(플레이어)의 남은 패에서 뽑은 표본과 겨뤄 본 점수로 고른다.
## 플레이어의 이번 예약은 보지 않는다. 지력이 높을수록 좋은 수를, 야망이 클수록 공격을 고른다.
static func ai_plan(d: DuelState, id: String) -> Array:
	var foe: String = d.other(id)
	var mine: Array = _sequences(d, id)
	var all_theirs: Array = _sequences(d, foe)
	var theirs: Array = []
	for k: int in int(cfg("ai_samples", 16)):
		theirs.append(RNG.pick(all_theirs))
	# 미리 계산: 한 수 대결표, 기본 피해량 (모의 해결을 수천 번 돌리므로 매번 설정·능력치를 읽지 않는다)
	var table: Dictionary = {}
	for x: String in BASICS + (d.specials[id] as Array) + ["none"]:
		for y: String in BASICS + (d.specials[foe] as Array) + ["none"]:
			var r: Dictionary = clash(x, y)
			table[x + "|" + y] = [float(r["a_mult"]), float(r["b_mult"]), bool(r["clash"]), bool(r["a_stun"]), bool(r["b_stun"])]
	var ctx: Dictionary = {"table": table, "dm": float(damage(id, 1.0, false)), "df": float(damage(foe, 1.0, false)),
		"add": int(cfg("clash_add", 8)), "cap": int(cfg("clash_cap", 40)), "pool": d.pool, "st_me": bool(d.stunned[id]), "st_foe": bool(d.stunned[foe])}
	var p: Dictionary = Officers.get_state(id).get("personality", {})
	var aggression: float = 0.7 + int(p.get("ambition", 50)) / 100.0       # 주는 피해 가중
	var caution: float = 0.7 + (1.0 - float(d.hp[id]) / maxf(d.max_hp[id], 1)) * 1.2   # 받는 피해 가중 (체력이 적을수록 조심)
	var scored: Array = []
	for seq: Array in mine:
		var total: float = 0.0
		for other_seq: Array in theirs:
			var r: Vector2 = _simulate(ctx, seq, other_seq)
			total += r.x * aggression - r.y * caution
		scored.append([total / theirs.size(), seq])
	scored.sort_custom(func(x: Array, y: Array) -> bool: return x[0] > y[0])
	# 지력이 낮을수록 상위 몇 개 중에서 대충 고른다
	var spread: int = clampi(int(round((100 - Officers.stat(id, "int")) / 12.0)), 1, scored.size())
	return (scored[RNG.randi_range(0, spread - 1)][1] as Array).duplicate()


## 그 사람이 지금 낼 수 있는 3수 조합 전부 (횟수·기력·한 턴 한 번 규칙 반영)
static func _sequences(d: DuelState, id: String) -> Array:
	var options: Array = BASICS + (d.specials[id] as Array)
	var out: Array = []
	var saved: Array = (d.plan[id] as Array).duplicate()
	d.plan[id] = []
	_grow(d, id, options, out)
	d.plan[id] = saved
	return out


static func _grow(d: DuelState, id: String, options: Array, out: Array) -> void:
	if (d.plan[id] as Array).size() == SLOTS:
		out.append((d.plan[id] as Array).duplicate())
		return
	for c: String in options:
		if can_add(d, id, c) == "":
			(d.plan[id] as Array).append(c)
			_grow(d, id, options, out)
			(d.plan[id] as Array).pop_back()


## AI 검토용 모의 해결 (무작위 없음, 미리 계산한 대결표 사용): Vector2(준 피해, 받은 피해)
static func _simulate(ctx: Dictionary, seq: Array, other_seq: Array) -> Vector2:
	var table: Dictionary = ctx["table"]
	var st_me: bool = ctx["st_me"]
	var st_foe: bool = ctx["st_foe"]
	var pool: int = ctx["pool"]
	var add: int = ctx["add"]
	var cap: int = ctx["cap"]
	var dealt: float = 0.0
	var taken: float = 0.0
	for i: int in SLOTS:
		var x: String = "none" if st_me else String(seq[i])
		var y: String = "none" if st_foe else String(other_seq[i])
		var r: Array = table[x + "|" + y]
		st_me = bool(r[4])
		st_foe = bool(r[3])
		if r[2]:
			pool = mini(pool + add, cap)
		if r[0] > 0.0:
			dealt += float(ctx["dm"]) * r[0] + pool
			pool = 0
		if r[1] > 0.0:
			taken += float(ctx["df"]) * r[1] + pool
			pool = 0
	return Vector2(dealt, taken)


# ── 받아들일지 / 결과 ───────────────────────────

## 상대가 결투를 받아들일지: 자기가 더 세거나 야망이 크면 받는다
static func accepts(challenger: String, target: String) -> bool:
	if Officers.stat(target, "str") >= Officers.stat(challenger, "str") * 0.8:
		return true
	return RNG.chance(0.3 + int(Officers.get_state(target).get("personality", {}).get("ambition", 50)) / 200.0)


## 적 장수가 먼저 결투를 걸어올지 (전투 중 AI): 야망과 무력 우위가 클수록
static func wants_to_challenge(challenger: String, target: String) -> bool:
	var ambition: int = int(Officers.get_state(challenger).get("personality", {}).get("ambition", 50))
	var edge: int = Officers.stat(challenger, "str") - Officers.stat(target, "str")
	return RNG.chance(clampf(float(cfg("ai_challenge_base", 0.08)) + ambition / 500.0 + edge * 0.01, 0.0, 0.6))


## 결투 성장: 겨룬 것만으로도 무력 경험치 (이기면 더)
static func _grow_stats(d: DuelState) -> Array:
	var lines: Array = []
	for id: String in [d.a_id, d.b_id]:
		if Officers.get_state(id).get("temporary", false):
			continue
		var gain: int = int(cfg("exp_win", 20)) if d.winner() == id else int(cfg("exp_lose", 8))
		var r: Dictionary = Progression.add_exp(id, "str", gain)
		if id == GameState.player_id and int(r["gained"]) > 0:
			lines.append(GameAction.msg("ACT_TRAIN_UP", [Officers.stat_label("str"), r["before"], r["after"]]))
	return lines


## 전투 중 결투 결과: 진 부대 사기 크게 하락, 이긴 부대 사기 상승. 진 NPC 장수는 낮은 확률로 전사(부대 붕괴). 무승부는 둘 다 조금.
static func apply_battle(state: BattleState, a_unit: BattleUnit, b_unit: BattleUnit, d: DuelState) -> Array:
	var lines: Array = []
	Record.duel(d)
	var winner_id: String = d.winner()
	if winner_id == "":
		for u: BattleUnit in [a_unit, b_unit]:
			u.morale = clampi(u.morale + int(cfg("draw_morale", -5)), 0, 100)
		lines.append(GameAction.msg("DUEL_RESULT_DRAW", [a_unit.name, b_unit.name]))
	else:
		var win_unit: BattleUnit = a_unit if winner_id == a_unit.officer_id else b_unit
		var lose_unit: BattleUnit = b_unit if win_unit == a_unit else a_unit
		win_unit.morale = clampi(win_unit.morale + int(cfg("winner_morale", 20)), 0, 100)
		lose_unit.morale = clampi(lose_unit.morale + int(cfg("loser_morale", -40)), 0, 100)
		lines.append(GameAction.msg("DUEL_RESULT_BATTLE", [win_unit.name, lose_unit.name]))
		if winner_id == GameState.player_id:
			Career.add_fame(winner_id, int(cfg("battle_win_fame", 2)))
		var loser_id: String = lose_unit.officer_id
		if loser_id != GameState.player_id and RNG.chance(float(cfg("loser_death_chance", 0.05))):
			Officers.get_state(loser_id)["alive"] = false
			lose_unit.troops = 0
			lines.append(GameAction.msg("DUEL_DIED", [Officers.display_name(loser_id)]))
	lines.append_array(_grow_stats(d))
	return lines


## 술집 시비 결과: 이기면 명성, 지면 술값 덤터기, 비기면 서로 술 한 잔. 시비 건 임시 인물은 사라진다.
static func apply_tavern(d: DuelState) -> Array:
	var lines: Array = []
	Record.duel(d)
	var me: String = d.a_id
	match d.winner():
		me:
			Career.add_fame(me, int(cfg("tavern_win_fame", 3)))
			lines.append(GameAction.msg("DUEL_TAVERN_WIN", [int(cfg("tavern_win_fame", 3))]))
		"":
			lines.append(GameAction.msg("DUEL_TAVERN_DRAW"))
		_:
			var s: Dictionary = Officers.get_state(me)
			var lost: int = mini(int(s["gold"]), int(cfg("tavern_lose_gold", 10)))
			s["gold"] = int(s["gold"]) - lost
			lines.append(GameAction.msg("DUEL_TAVERN_LOSE", [lost]))
	lines.append_array(_grow_stats(d))
	remove_temporary(d.b_id)
	return lines


static func remove_temporary(id: String) -> void:
	if Officers.get_state(id).get("temporary", false):
		GameState.officers.erase(id)
