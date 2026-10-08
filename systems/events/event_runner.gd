class_name EventRunner
extends RefCounted
## 이벤트 덱 (GDD §10): data/events/*.json의 이벤트 중 조건이 맞는 것을 골라 한 장면씩 보여 준다.
## 메인 스토리가 없으므로 이벤트가 곧 콘텐츠. 조건·효과 타입은 아래 표(_check_condition / _apply_effect)에 하나씩 추가하면 늘어난다.
##
## 이벤트 = {"id", "trigger": "on_action"|"month_start"|"after_battle"|"rank_change", "action": (on_action일 때 행동 id),
##           "conditions": [...], "once": bool, "weight": 숫자, "scenes": [{"speaker", "text_key"} | {"choice": [{"text_key", "effects": [...]}]}]}
## 화자(speaker): "player" / "narrator" / 무장 id / "here" (지금 도시의 아무 인물) / "random_free" (아무 재야) / "new_wanderer" (새 떠돌이)

## 지금 보여 줄 이벤트 (UI가 꺼내 간다)
static func pending() -> Dictionary:
	return GameState.flags.get("pending_event", {})


static func clear_pending() -> void:
	GameState.flags.erase("pending_event")


static func all_events() -> Array:
	var list: Array = []
	for table: String in DataDB.table_names():
		if table.begins_with("events/"):
			list.append_array(DataDB.get_rows(table))
	return list


## 트리거가 생기면 부른다. 조건이 맞는 이벤트를 가중치로 하나 골라 pending에 둔다. 골랐으면 true.
static func trigger(kind: String, context: Dictionary = {}) -> bool:
	if not pending().is_empty() or GameState.player_id == "":
		return false
	var candidates: Array = []
	var total: float = 0.0
	for ev: Dictionary in all_events():
		if ev.get("trigger", "") != kind:
			continue
		if kind == "on_action" and ev.get("action", "") != context.get("action", ""):
			continue
		if ev.get("once", false) and GameState.flags.get("events_done", {}).has(ev["id"]):
			continue
		if not conditions_met(ev.get("conditions", []), context):
			continue
		candidates.append(ev)
		total += float(ev.get("weight", 1.0))
	if candidates.is_empty():
		return false
	var roll: float = RNG.randf() * total
	var chosen: Dictionary = candidates.back()
	for ev: Dictionary in candidates:
		roll -= float(ev.get("weight", 1.0))
		if roll <= 0.0:
			chosen = ev
			break
	GameState.flags["pending_event"] = {"id": chosen["id"], "speakers": _resolve_speakers(chosen), "context": context}
	if chosen.get("once", false):
		GameState.flags.get_or_add("events_done", {})[chosen["id"]] = TimeManager.month_index()
	return true


static func find_event(event_id: String) -> Dictionary:
	for ev: Dictionary in all_events():
		if ev["id"] == event_id:
			return ev
	return {}


## 화자를 실제 무장 id로 정해 둔다 (장면을 넘겨도 같은 사람이 말하도록)
static func _resolve_speakers(ev: Dictionary) -> Dictionary:
	var map: Dictionary = {}
	var city: String = GameState.player().get("city", "")
	for scene: Dictionary in ev.get("scenes", []):
		var sp: String = scene.get("speaker", "")
		if sp == "" or map.has(sp):
			continue
		match sp:
			"player":
				map[sp] = GameState.player_id
			"narrator":
				map[sp] = ""
			"here":
				var here: PackedStringArray = Officers.in_city(city, GameState.player_id)
				map[sp] = RNG.pick(Array(here)) if not here.is_empty() else ""
			"random_free":
				var free: Array = []
				for id: String in GameState.officers:
					if Career.is_free_agent(id):
						free.append(id)
				map[sp] = RNG.pick(free) if not free.is_empty() else ""
			"new_wanderer":
				map[sp] = OfficerGen.generate("", city, "none")
			_:
				map[sp] = sp if GameState.officers.has(sp) else ""
	return map


static func speaker_id(sp: String) -> String:
	return pending().get("speakers", {}).get(sp, "")


# ── 조건 ────────────────────────────────────────

static func conditions_met(conditions: Array, context: Dictionary) -> bool:
	for c: Dictionary in conditions:
		if not _check_condition(c, context):
			return false
	return true


static func _compare(a: float, op: String, b: float) -> bool:
	match op:
		">=":
			return a >= b
		"<=":
			return a <= b
		">":
			return a > b
		"<":
			return a < b
		"==":
			return is_equal_approx(a, b)
		"!=":
			return not is_equal_approx(a, b)
	return false


static func _check_condition(c: Dictionary, context: Dictionary) -> bool:
	var p: Dictionary = GameState.player()
	var me: String = GameState.player_id
	var op: String = c.get("op", ">=")
	match c.get("type", ""):
		"random":
			return RNG.chance(float(c.get("chance", 0.5)))
		"gold":
			return _compare(int(p.get("gold", 0)), op, float(c["value"]))
		"fame":
			return _compare(int(p.get("fame", 0)), op, float(c["value"]))
		"merit":
			return _compare(int(p.get("merit", 0)), op, float(c["value"]))
		"rank_order":
			return _compare(Officers.rank_order(me), op, float(c["value"]))
		"track":
			return Officers.track(me) == c["value"]
		"is_vassal":
			return Career.is_vassal(me) == bool(c.get("value", true))
		"has_company":
			return Career.has_company(me) == bool(c.get("value", true))
		"companions":
			return _compare(Career.companions(me).size(), op, float(c["value"]))
		"race":
			return p.get("race", "") == c["value"]
		"variant":
			return p.get("variant", "") == c["value"]
		"background":
			return p.get("background", "") == c["value"]
		"season":
			return TimeManager.season() == int(c["value"])
		"month":
			return _compare(TimeManager.month, op, float(c["value"]))
		"year":
			return _compare(TimeManager.year, op, float(c["value"]))
		"flag":
			return GameState.flags.get("story", {}).has(c["value"]) == bool(c.get("set", true))
		"city_owner":
			return GameState.city_owner(p.get("city", "")) == c["value"]
		"city_terrain":
			return DataDB.get_row("cities", p.get("city", "")).get("terrain", "") == c["value"]
		"at_war_here":
			var owner: String = GameState.city_owner(p.get("city", ""))
			var any: bool = false
			for n: String in Diplomacy.alive_nations():
				any = any or Diplomacy.at_war(owner, n)
			return any == bool(c.get("value", true))
		"injured":
			return (int(p.get("injury", 0)) > 0) == bool(c.get("value", true))
		"affinity":
			return GameState.officers.has(c["officer"]) and _compare(Relationship.affinity(me, c["officer"]), op, float(c["value"]))
		"officer_alive":
			return Officers.is_active(c["officer"]) == bool(c.get("value", true))
		"officer_here":
			return Officers.is_active(c["officer"]) and Officers.get_state(c["officer"]).get("city", "") == p.get("city", "")
		"battle_won":
			return bool(context.get("won", false)) == bool(c.get("value", true))
		"context":
			return str(context.get(c["key"], "")) == str(c["value"])
	push_warning("이벤트: 모르는 조건 '%s'" % c.get("type", ""))
	return false


# ── 효과 ────────────────────────────────────────

## 선택지 하나의 효과들을 적용하고, 결과 문장 목록을 돌려준다
static func apply_effects(effects: Array) -> Array:
	var lines: Array = []
	for e: Dictionary in effects:
		var line: String = _apply_effect(e)
		if line != "":
			lines.append(line)
	return lines


static func _target(e: Dictionary) -> String:
	var t: String = e.get("target", "")
	var resolved: String = speaker_id(t)
	return resolved if resolved != "" else t


static func _apply_effect(e: Dictionary) -> String:
	var p: Dictionary = GameState.player()
	var me: String = GameState.player_id
	match e.get("type", ""):
		"gold":
			var delta: int = int(e["delta"])
			if delta < 0:
				delta = -mini(-delta, int(p["gold"]))
			p["gold"] = int(p["gold"]) + delta
			return GameAction.msg("EFFECT_GOLD_UP" if delta >= 0 else "EFFECT_GOLD_DOWN", [absi(delta)])
		"fame":
			Career.add_fame(me, int(e["delta"]))
			return GameAction.msg("EFFECT_FAME", [int(e["delta"])])
		"merit":
			Career.add_merit(me, int(e["delta"]))
			return GameAction.msg("EFFECT_MERIT", [int(e["delta"])])
		"energy":
			p["energy"] = clampi(int(p["energy"]) + int(e["delta"]), 0, int(DataDB.balance("energy.max", 100)))
			return GameAction.msg("EFFECT_ENERGY", [int(e["delta"])])
		"affinity":
			var t: String = _target(e)
			if t == "" or not GameState.officers.has(t):
				return ""
			Relationship.mark_met(me, t)
			var after: int = Relationship.add(me, t, int(e["delta"]))
			return GameAction.msg("EFFECT_AFFINITY", [Officers.display_name(t), int(e["delta"]), after])
		"reputation":
			var n: String = e.get("nation", "")
			if n == "here":
				n = GameState.city_owner(p.get("city", ""))
			if n == "":
				return ""
			var rep: Dictionary = p.get_or_add("reputation", {})
			rep[n] = int(rep.get(n, 0)) + int(e["delta"])
			return GameAction.msg("EFFECT_REPUTATION", [Diplomacy.nation_name(n), int(e["delta"])])
		"exp":
			var r: Dictionary = Progression.add_exp(me, e["stat"], int(e["amount"]))
			return GameAction.msg("ACT_TRAIN_EXP", [Officers.stat_label(e["stat"]), r["exp"], r["progress"], r["need"]])
		"flag":
			GameState.flags.get_or_add("story", {})[e["value"]] = TimeManager.month_index()
			return ""
		"add_companion":
			var t: String = _target(e)
			if t == "" or not Career.is_free_agent(t) or not Career.has_free_slot(me):
				return GameAction.msg("EFFECT_COMPANION_FAIL")
			Career.add_companion(me, t)
			return GameAction.msg("RECRUIT_JOINED", [Officers.display_name(t)])
		"start_duel":
			GameState.flags["pending_duel"] = _target(e)   # UI가 결투 창을 띄운다
			return ""
		"injury":
			p["injury"] = maxi(int(p.get("injury", 0)), int(e["months"]))
			return GameAction.msg("EFFECT_INJURY", [int(e["months"])])
		"troops":
			p["troops"] = clampi(int(p.get("troops", 0)) + int(e["delta"]), 0, Officers.max_troops(me))
			return GameAction.msg("EFFECT_TROOPS", [int(e["delta"])])
		"chance":
			# 확률로 win 또는 lose 효과 묶음 (도박 등)
			var won: bool = RNG.chance(float(e.get("chance", 0.5)))
			var sub: Array = apply_effects(e.get("win" if won else "lose", []))
			sub.push_front(TranslationServer.translate(e.get("win_key" if won else "lose_key", "")))
			return "\n".join(sub.filter(func(s: String) -> bool: return s != ""))
		"text":
			return TranslationServer.translate(e["key"])
	push_warning("이벤트: 모르는 효과 '%s'" % e.get("type", ""))
	return ""


## 선택지 중 보여 줄 것 (선택지에도 conditions를 달 수 있다: 예) 금이 있어야 고를 수 있음)
static func available_choices(scene: Dictionary) -> Array:
	var list: Array = []
	for ch: Dictionary in scene.get("choice", []):
		list.append({"choice": ch, "enabled": conditions_met(ch.get("conditions", []), pending().get("context", {}))})
	return list
