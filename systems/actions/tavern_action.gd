class_name TavernAction
extends GameAction
## 술집 (행동력 1, 술값): 소문 / 재야 발견 / 시비(결투) / 그냥 한잔.
## 결투는 화면이 띄우고, 결과는 Duel이 정산한다. 여기서는 무슨 일이 일어났는지만 정한다.


func _init() -> void:
	id = "tavern"


func check(actor: String, _params: Dictionary) -> String:
	if int(Officers.get_state(actor).get("gold", 0)) < int(Career.cfg("tavern", "drink_cost", 5)):
		return "ACT_FAIL_NO_GOLD"
	return ""


func run(actor: String, _params: Dictionary) -> Dictionary:
	var s: Dictionary = Officers.get_state(actor)
	s["gold"] = int(s["gold"]) - int(Career.cfg("tavern", "drink_cost", 5))
	var roll: float = RNG.randf()
	var rumor: float = float(Career.cfg("tavern", "rumor", 0.4))
	var discover: float = rumor + float(Career.cfg("tavern", "discover", 0.3))
	var brawl: float = discover + float(Career.cfg("tavern", "brawl", 0.15))
	if roll < rumor:
		return {"event": "rumor", "lines": [_rumor()]}
	if roll < discover:
		var id_new: String = OfficerGen.generate("", s["city"], "none")
		return {"event": "discover", "target": id_new, "speech": VisitAction.speech_variant("TALK_TAVERN_MEET"),
			"lines": [msg("TAVERN_DISCOVER", [Officers.display_name(id_new), Officers.race_label(id_new)])]}
	if roll < brawl:
		# 시비 거는 술꾼: 결투가 끝나면 사라지는 임시 인물
		var thug: String = OfficerGen.generate("", s["city"], "none")
		Officers.get_state(thug)["temporary"] = true
		return {"event": "brawl", "target": thug, "speech": VisitAction.speech_variant("TALK_TAVERN_BRAWL"),
			"lines": [msg("TAVERN_BRAWL", [Officers.display_name(thug)])]}
	return {"event": "drink", "lines": [VisitAction.speech_variant("TAVERN_DRINK")]}


## 소문: 대륙 정세 한 토막 (전쟁, 국고, 재야)
func _rumor() -> String:
	var kind: int = RNG.randi_range(0, 2)
	var nations: Array = Diplomacy.alive_nations()
	var n: String = RNG.pick(nations)
	match kind:
		0:
			var foes: PackedStringArray = []
			for other: String in nations:
				if Diplomacy.at_war(n, other):
					foes.append(Diplomacy.nation_name(other))
			if not foes.is_empty():
				return msg("RUMOR_WAR", [Diplomacy.nation_name(n), ", ".join(foes)])
		1:
			var gold: int = int(GameState.nations[n].get("gold", 0))
			return msg("RUMOR_RICH" if gold > 3000 else "RUMOR_POOR", [Diplomacy.nation_name(n)])
	var free: Array = []
	for oid: String in GameState.officers:
		if Career.is_free_agent(oid):
			free.append(oid)
	if not free.is_empty():
		var who: String = RNG.pick(free)
		return msg("RUMOR_WANDERER", [Officers.display_name(who), WorldMap.city_name(Officers.get_state(who)["city"])])
	return msg("RUMOR_NOTHING")
