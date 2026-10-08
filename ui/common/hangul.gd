class_name Hangul
extends RefCounted
## 게임 안 한글 자판용 조합기 (근성영애에서 가져옴). 입력한 자모 목록(ㅇ,ㅔ,ㄹ,ㄹ,ㅣ,ㅈ,ㅔ)을 받아 글자(엘리제)로 조합한다.
## 매번 자모 목록 전체를 처음부터 다시 조합하므로, 받침이 다음 글자로 넘어가는 것(간+ㅏ→가나)도 자연스럽게 처리된다.

const CHO: Array = ["ㄱ", "ㄲ", "ㄴ", "ㄷ", "ㄸ", "ㄹ", "ㅁ", "ㅂ", "ㅃ", "ㅅ", "ㅆ", "ㅇ", "ㅈ", "ㅉ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ"]
const JUNG: Array = ["ㅏ", "ㅐ", "ㅑ", "ㅒ", "ㅓ", "ㅔ", "ㅕ", "ㅖ", "ㅗ", "ㅘ", "ㅙ", "ㅚ", "ㅛ", "ㅜ", "ㅝ", "ㅞ", "ㅟ", "ㅠ", "ㅡ", "ㅢ", "ㅣ"]
const JONG: Array = ["", "ㄱ", "ㄲ", "ㄳ", "ㄴ", "ㄵ", "ㄶ", "ㄷ", "ㄹ", "ㄺ", "ㄻ", "ㄼ", "ㄽ", "ㄾ", "ㄿ", "ㅀ", "ㅁ", "ㅂ", "ㅄ", "ㅅ", "ㅆ", "ㅇ", "ㅈ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ"]

const VOWEL_PAIRS: Dictionary = {"ㅗㅏ": "ㅘ", "ㅗㅐ": "ㅙ", "ㅗㅣ": "ㅚ", "ㅜㅓ": "ㅝ", "ㅜㅔ": "ㅞ", "ㅜㅣ": "ㅟ", "ㅡㅣ": "ㅢ"}
const JONG_PAIRS: Dictionary = {"ㄱㅅ": "ㄳ", "ㄴㅈ": "ㄵ", "ㄴㅎ": "ㄶ", "ㄹㄱ": "ㄺ", "ㄹㅁ": "ㄻ", "ㄹㅂ": "ㄼ", "ㄹㅅ": "ㄽ", "ㄹㅌ": "ㄾ", "ㄹㅍ": "ㄿ", "ㄹㅎ": "ㅀ", "ㅂㅅ": "ㅄ"}


static func is_vowel(j: String) -> bool:
	return JUNG.has(j)


## 자모 목록 → 완성된 글자열
static func compose(seq: Array) -> String:
	var out: String = ""
	var cho: String = ""
	var jung: String = ""
	var jong: String = ""
	for j: String in seq:
		if not is_vowel(j):   # 자음
			if jung == "":
				if cho != "":
					out += cho   # 자음만 두 개 연속 → 앞 자음은 따로
				cho = j
			elif jong == "":
				if cho != "" and JONG.has(j):
					jong = j   # 받침으로
				else:
					out += _flush(cho, jung, "")
					cho = j
					jung = ""
			else:
				var pair: String = JONG_PAIRS.get(jong + j, "")
				if pair != "":
					jong = pair   # 겹받침
				else:
					out += _flush(cho, jung, jong)
					cho = j
					jung = ""
					jong = ""
		else:   # 모음
			if jong != "":
				# 받침의 (마지막) 자음을 다음 글자의 초성으로 넘긴다: 간+ㅏ → 가나, 닭+ㅣ → 달기
				var first: String = ""
				var last: String = jong
				for k: String in JONG_PAIRS:
					if JONG_PAIRS[k] == jong:
						first = k[0]
						last = k[1]
				out += _flush(cho, jung, first)
				cho = last
				jung = j
				jong = ""
			elif jung != "":
				var v: String = VOWEL_PAIRS.get(jung + j, "")
				if v != "":
					jung = v   # 겹모음
				else:
					out += _flush(cho, jung, "")
					cho = ""
					jung = j
			else:
				jung = j
	out += _flush(cho, jung, jong)
	return out


static func _flush(cho: String, jung: String, jong: String) -> String:
	if cho != "" and jung != "":
		var code: int = 0xAC00 + (CHO.find(cho) * 21 + JUNG.find(jung)) * 28 + JONG.find(jong)
		return char(code)
	return cho + jung + jong
