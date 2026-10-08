extends Node

func _ready() -> void:
	for seed_value: int in [11, 22, 33, 44, 55]:
		RNG.reseed(seed_value)
		WorldSetup.new_game({"name": "Probe", "race": "human", "origin": "merka", "background": "knight_bastard", "bonus": {}})
		SaveManager.game_in_progress = false
		var max_gold: int = 0
		var max_food: int = 0
		var max_troops: int = 0
		var negatives: int = 0
		for month: int in 240:
			TimeManager.advance_month()
			for n: String in GameState.nations:
				var s: Dictionary = GameState.nations[n]
				max_gold = maxi(max_gold, int(s["gold"]))
				max_food = maxi(max_food, int(s["food"]))
				if int(s["gold"]) < 0 or int(s["food"]) < 0:
					negatives += 1
			for c: String in GameState.cities:
				max_troops = maxi(max_troops, int(GameState.cities[c]["troops"]))
				if int(GameState.cities[c]["troops"]) < 0:
					negatives += 1
		print("seed=%d months=240 max_nation_gold=%d max_nation_food=%d max_city_troops=%d negative_states=%d" % [seed_value,max_gold,max_food,max_troops,negatives])
	get_tree().quit()
