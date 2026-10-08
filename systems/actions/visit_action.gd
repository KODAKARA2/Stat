class_name VisitAction
extends GameAction
## 방문: 같은 도시의 인물 1명을 만나 대화한다. 친밀도 소폭 상승. params = {"target": officer_id}
## 교류(InteractAction)도 이 클래스를 물려받아 금을 쓰고 더 크게 오르게 한다.


func _init() -> void:
	id = "visit"


func check(actor: String, params: Dictionary) -> String:
	var target: String = params.get("target", "")
	if target == "" or target == actor or not Officers.is_active(target):
		return "ACT_FAIL_NO_TARGET"
	if Officers.get_state(target).get("city", "") != Officers.get_state(actor).get("city", ""):
		return "ACT_FAIL_NOT_HERE"
	return ""


func affinity_gain(actor: String) -> int:
	var divisor: float = maxf(float(cfg("cha_divisor", 30)), 1.0)
	return RNG.randi_range(int(cfg("affinity_min", 2)), int(cfg("affinity_max", 5))) + int(Officers.stat(actor, "cha") / divisor)


func run(actor: String, params: Dictionary) -> Dictionary:
	var target: String = params["target"]
	var first_meeting: bool = not Relationship.has_met(actor, target)
	# 대사는 친밀도가 오르기 '전' 관계로 고른다
	var speech: String = pick_speech(actor, target, first_meeting)
	Relationship.mark_met(actor, target)
	var gain: int = affinity_gain(actor)
	var after: int = Relationship.add(actor, target, gain)
	return {
		"target": target,
		"speech": speech,
		"affinity_delta": gain,
		"affinity": after,
		"lines": [msg("ACT_AFFINITY_UP", [Officers.display_name(target), gain, after])],
	}


## 상황에 맞는 대사 한 줄. 같은 상황이면 여러 개 중 무작위.
func pick_speech(actor: String, target: String, first_meeting: bool) -> String:
	var a: Dictionary = Officers.get_state(actor)
	var t: Dictionary = Officers.get_state(target)
	var affinity: int = Relationship.affinity(actor, target)
	var key: String
	if first_meeting and t.get("variant", "") == "dark_elf" and a.get("variant", "") != "dark_elf":
		key = "TALK_DARK_ELF_INSIST"          # "우린 그냥 엘프야"
	elif first_meeting and a.get("variant", "") == "dark_elf" and t.get("race", "") != "elf":
		key = "TALK_SEE_DARK_ELF"             # 상대가 주인공을 다른 종족으로 오해
	elif affinity < 20 and Officers.track(actor) in ["free", "merc"] and Officers.track(target) in ["vassal", "ruler"]:
		key = "TALK_LOOK_DOWN"                # 사관은 용병을 얕본다
	elif affinity < -20:
		key = "TALK_COLD"
	elif affinity < 20:
		key = "TALK_NEUTRAL"
	elif affinity < 50:
		key = "TALK_WARM"
	else:
		key = "TALK_CLOSE"
	return speech_variant(key)


## TALK_X_1, TALK_X_2 ... 중 번역이 있는 것 하나
static func speech_variant(base_key: String) -> String:
	var options: Array = []
	for i: int in range(1, 10):
		var k: String = "%s_%d" % [base_key, i]
		if TranslationServer.translate(k) == k:
			break
		options.append(k)
	if options.is_empty():
		return TranslationServer.translate(base_key)
	return TranslationServer.translate(RNG.pick(options))
