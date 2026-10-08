class_name MonthlyUpdate
extends RefCounted
## 매월 초 공통 처리: 행동력·기력 회복, 병력 보충, 부상 회복, (1월) 나이 +1·노환·출산·성인식, 길드 의뢰 갱신, 전쟁 계획, 출세, 이벤트.
## 매월 말: 고용 계약, 출세(월급·임무·승진), 전쟁 정산.


static func start_month(_year: int, month: int) -> void:
	var regen: int = DataDB.balance("energy.monthly_regen", 20)
	var energy_max: int = DataDB.balance("energy.max", 100)
	var troop_regen: float = DataDB.balance("battle.troop_regen", 0.25)
	for id: String in GameState.officers:
		var s: Dictionary = GameState.officers[id]
		if not bool(s.get("alive", false)):
			continue
		if month == 1:
			s["age"] = int(s["age"]) + 1   # 미성년 자녀도 나이를 먹는다
		if not Officers.is_active(id):
			continue
		s["ap"] = Officers.max_ap(id)
		s["energy"] = mini(int(s["energy"]) + regen, energy_max)
		var max_troops: int = Officers.max_troops(id)
		s["troops"] = mini(int(s.get("troops", 0)) + int(ceil(max_troops * troop_regen)), max_troops)
		s["injury"] = maxi(0, int(s.get("injury", 0)) - 1)
	if month == 1 and GameState.player_id != "" and int(GameState.flags.get("months_played", 0)) > 0:
		Family.new_year()   # 노환·성인식·출산 (게임 시작 직후의 1월은 건너뜀)
	if GameState.player_id != "":
		Guild.expire(GameState.player_id)
	Guild.refresh_all()
	if not GameState.nations.is_empty():
		WarSystem.start_month(month)
		Career.start_month()
		SkillLevels.start_month()   # 그 전법을 더 잘 쓰는 친한 사람에게서 배운다
		if int(GameState.flags.get("months_played", 0)) > 0:   # 첫 달은 조용히 (게임에 익숙해지도록)
			EventRunner.trigger("month_start")


static func end_month(_year: int, _month: int) -> void:
	if GameState.player_id != "":
		var left: Array = Guild.tick_contracts(GameState.player_id)
		for entry: Dictionary in left:
			var unit_key: String = DataDB.get_row("unit_types", Guild.helper_type(entry["type"]).get("unit_type", "")).get("name_key", "")
			GameState.flags.get_or_add("month_log", []).append(GameAction.msg("LOG_HIRE_ENDED", [TranslationServer.translate(unit_key)]))
	if not GameState.nations.is_empty():
		GameState.flags["months_played"] = int(GameState.flags.get("months_played", 0)) + 1
		Career.end_month()   # 월급·임무·승진 (보고서에 들어가도록 전쟁 정산보다 먼저)
		WarSystem.end_month(_year, _month)
		Ending.check_unification()
