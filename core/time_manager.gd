extends Node
## 1턴 = 1개월 (GDD §3.1). 월말 처리 순서는 M1 이후 여기에 연결한다.

enum Season { SPRING, SUMMER, AUTUMN, WINTER }

const SEASON_KEYS: PackedStringArray = ["SEASON_SPRING", "SEASON_SUMMER", "SEASON_AUTUMN", "SEASON_WINTER"]

var year: int = 1
var month: int = 1


func start_new(start_year: int, start_month: int) -> void:
	year = start_year
	month = start_month
	EventBus.month_started.emit(year, month)


## 3~5월 봄, 6~8월 여름, 9~11월 가을, 12~2월 겨울
func season() -> Season:
	return (((month + 9) % 12) / 3) as Season


func season_name() -> String:
	return tr(SEASON_KEYS[season()])


func advance_month() -> void:
	EventBus.month_ended.emit(year, month)
	month += 1
	if month > 12:
		month = 1
		year += 1
	EventBus.month_started.emit(year, month)
	EventBus.month_ready.emit(year, month)


func to_save() -> Dictionary:
	return {"year": year, "month": month}


func from_save(data: Dictionary) -> void:
	year = int(data.get("year", 1))
	month = int(data.get("month", 1))


## 게임 시작부터 센 달 번호 (마감일 비교용). 1년 1월 = 1
func month_index() -> int:
	return (year - 1) * 12 + month
