extends Node
## 화면 설정 (기기마다 저장, user://settings.cfg): 글씨체와 글씨 크기.
## 작은 창(1080p·배율 125% 모니터에서 세로 창)에서는 도트 글씨가 어중간한 크기로 줄어 획이 들쭉날쭉해지고 눈이 피로하다
## → 기본은 매끈한 본고딕(Noto Sans KR) + 1.25배. [메뉴]에서 도트 글씨·크기를 바꿀 수 있다.

const PATH: String = "user://settings.cfg"
const FONTS: Dictionary = {
	"clear": "res://assets/fonts/NotoSansKR-Medium.otf",
	"pixel": "res://assets/fonts/Galmuri11.ttf",
}
const SIZES: Dictionary = {"normal": 1.0, "large": 1.25, "xlarge": 1.5}
const BASE_FONT_SIZE: int = 24

var font: String = "clear"
var text_size: String = "large"


func _ready() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(PATH) == OK:
		font = String(cfg.get_value("display", "font", font))
		text_size = String(cfg.get_value("display", "text_size", text_size))
	if not FONTS.has(font):
		font = "clear"
	if not SIZES.has(text_size):
		text_size = "large"
	apply()


func save() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("display", "font", font)
	cfg.set_value("display", "text_size", text_size)
	cfg.save(PATH)


## 프로젝트 테마(모든 화면의 기본 글씨)에 반영한다
func apply() -> void:
	var theme: Theme = ThemeDB.get_project_theme()
	if theme == null:
		return
	theme.default_font = load(FONTS[font]) as Font
	theme.default_font_size = fs(BASE_FONT_SIZE)


func scale() -> float:
	return float(SIZES.get(text_size, 1.0))


## 화면 설계 기준 글씨 크기(24/36/48) → 지금 설정의 실제 크기
func fs(size: int) -> int:
	return int(round(size * scale()))


func set_font(value: String) -> void:
	font = value
	save()
	apply()


func set_text_size(value: String) -> void:
	text_size = value
	save()
	apply()
