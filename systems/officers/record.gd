class_name Record
extends RefCounted
## 장수 이력 (인물 카드에 보여 준다): 결투 승·패·무, 의뢰 완수·실패.
## 상태: record = {"duel_win", "duel_lose", "duel_draw", "quest_done", "quest_fail"}
## 의뢰 = 토벌·참전·점령전·용병단 계약. 완수 = 이김 / 계약 만료까지 복무. 실패 = 짐·후퇴 / 기한 넘김 / 계약 파기(배신).

const KEYS: Array[String] = ["duel_win", "duel_lose", "duel_draw", "quest_done", "quest_fail"]


static func add(id: String, key: String, amount: int = 1) -> void:
	if id == "" or not GameState.officers.has(id) or Officers.get_state(id).get("temporary", false):
		return
	var r: Dictionary = Officers.get_state(id).get_or_add("record", {})
	r[key] = int(r.get(key, 0)) + amount


static func count(id: String, key: String) -> int:
	return int(Officers.get_state(id).get("record", {}).get(key, 0))


## 결투 한 판 기록 (양쪽 모두)
static func duel(d: DuelState) -> void:
	var w: String = d.winner()
	for id: String in [d.a_id, d.b_id]:
		add(id, "duel_draw" if w == "" else ("duel_win" if w == id else "duel_lose"))


## 카드 한 줄: "결투 3승 1패 (무 1)"
static func duel_line(id: String) -> String:
	var text: String = TranslationServer.translate("RECORD_DUEL") % [count(id, "duel_win"), count(id, "duel_lose")]
	if count(id, "duel_draw") > 0:
		text += " " + TranslationServer.translate("RECORD_DRAW") % count(id, "duel_draw")
	return text


## 카드 한 줄: "의뢰 12건 완수 / 2건 실패"
static func quest_line(id: String) -> String:
	return TranslationServer.translate("RECORD_QUEST") % [count(id, "quest_done"), count(id, "quest_fail")]


static func has_any(id: String) -> bool:
	for key: String in KEYS:
		if count(id, key) > 0:
			return true
	return false
