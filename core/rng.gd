extends Node
## 모든 랜덤은 여기를 거친다 (GDD §12.3-5). 시드와 상태를 저장하면 같은 결과를 재현할 수 있다.

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var seed_value: int = 0


func _ready() -> void:
	reseed(int(Time.get_unix_time_from_system()))


func reseed(new_seed: int) -> void:
	seed_value = new_seed
	_rng.seed = new_seed


func randf() -> float:
	return _rng.randf()


func randf_range(from: float, to: float) -> float:
	return _rng.randf_range(from, to)


func randi_range(from: int, to: int) -> int:
	return _rng.randi_range(from, to)


## chance(0.15) → 15% 확률로 true
func chance(probability: float) -> bool:
	return _rng.randf() < probability


func pick(items: Array) -> Variant:
	if items.is_empty():
		return null
	return items[_rng.randi_range(0, items.size() - 1)]


func to_save() -> Dictionary:
	return {"seed": seed_value, "state": _rng.state}


func from_save(data: Dictionary) -> void:
	seed_value = int(data.get("seed", 0))
	_rng.seed = seed_value
	_rng.state = int(data.get("state", 0))
