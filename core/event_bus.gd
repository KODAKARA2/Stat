extends Node
## 로직(systems)과 화면(ui)이 서로를 모른 채 소통하는 통로 (GDD §12.3-1).

signal data_loaded(table_count: int)
signal month_started(year: int, month: int)
signal month_ended(year: int, month: int)
signal game_saved(slot: String)
signal game_loaded(slot: String)
signal action_executed(actor_id: String, action_id: String, result: Dictionary)
