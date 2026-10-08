class_name Progression
extends RefCounted
## 능력치 성장 (GDD §4.3). 능력별 경험치가 쌓이면 +1, 개인 잠재치에서 멈춘다.


static func exp_needed(stat_value: int) -> int:
	return int(DataDB.balance("progression.exp_base", 40) + stat_value * DataDB.balance("progression.exp_per_stat", 1.0))


static func is_capped(id: String, key: String) -> bool:
	return Officers.base_stat(id, key) >= mini(Officers.potential(id, key), DataDB.balance("stats.max", 100))


## 경험치를 더한다.
## 돌려주는 값: {"exp": 실제로 더한 양, "gained": 오른 수치, "before", "after", "progress": 지금 경험치, "need": 다음까지 필요량, "capped"}
static func add_exp(id: String, key: String, amount: int) -> Dictionary:
	var s: Dictionary = Officers.get_state(id)
	if Officers.has_trait(id, "exp_bonus_10"):
		amount = int(round(amount * 1.1))
	var before: int = Officers.base_stat(id, key)
	var exp: int = int(s["exp"].get(key, 0)) + amount
	var value: int = before
	while not is_capped(id, key) and exp >= exp_needed(value):
		exp -= exp_needed(value)
		value += 1
		s["stats"][key] = value
	if is_capped(id, key):
		exp = 0
	s["exp"][key] = exp
	return {
		"exp": amount, "gained": value - before, "before": before, "after": value,
		"progress": exp, "need": exp_needed(value), "capped": is_capped(id, key),
	}
