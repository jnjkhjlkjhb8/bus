// Package searchalias derives the phonetic spellings a rider might type for a
// Chinese place name — pinyin, zhuyin, initials, and common shorthands — so a
// search matches without an exact character match. It is a pure function of the
// name, computed once at write time.
package searchalias

import (
	"strings"
	"unicode"

	"github.com/mozillazg/go-pinyin"
)

// SearchAlias renders the phonetic and shorthand forms of a stop, station, or
// route name so search matches what a rider types before the IME has turned
// it into Chinese — "beitou", "bt", or "ㄅㄟㄊㄡ" all reach 北投.
//
// The result is one space-separated string, written to search_vector.alias and
// matched by the same trigram predicates as name. Space-separated rather than
// one run-on string so a trigram of one form's tail plus the next form's head
// cannot match anything.
//
// Tone marks are deliberately absent: the router strips them from the query
// (see stripZhuyinTones) rather than this storing every toned spelling, which
// would multiply the column for a difference no rider means.
func SearchAlias(name string) string {
	syllables := pinyinSyllables(name)
	if len(syllables) == 0 {
		return strings.Join(nameShorthands(name), " ")
	}

	var full, initials, zhuyin strings.Builder
	for _, s := range syllables {
		full.WriteString(s)
		initials.WriteString(syllableInitial(s))
		zhuyin.WriteString(syllableZhuyin(s))
	}

	forms := []string{full.String()}
	// Initials are only a useful handle when there is more than one syllable;
	// for a one-syllable name they are a single letter that matches half the
	// corpus.
	if len(syllables) > 1 {
		forms = append(forms, initials.String())
	}
	if z := zhuyin.String(); z != "" {
		forms = append(forms, z)
	}
	forms = append(forms, nameShorthands(name)...)
	return strings.Join(forms, " ")
}

// pinyinSyllables romanises name one rune at a time.
//
// go-pinyin drops everything that is not Han, which would silently glue "紅"
// and "5" of 紅5 into one token; walking the runes keeps digits and Latin
// where the rider typed them. Runes with no reading (punctuation, spaces) are
// dropped so the forms stay one word.
func pinyinSyllables(name string) []string {
	args := pinyin.NewArgs()
	var out []string
	for _, r := range name {
		if readings := pinyin.SinglePinyin(r, args); len(readings) > 0 {
			// The first reading is go-pinyin's most common one. A station
			// whose name uses a rarer reading of a polyphone is mis-spelled
			// here; it is still reachable by its Chinese name, which is what
			// the rider has once the IME commits.
			out = append(out, readings[0])
			continue
		}
		if unicode.IsLetter(r) || unicode.IsDigit(r) {
			out = append(out, strings.ToLower(string(r)))
		}
	}
	return out
}

// syllableInitial is the first letter of a romanised syllable — the handle a
// rider uses when they type "bt" for 北投. Digits and Latin runes carried
// through by pinyinSyllables are their own initial.
func syllableInitial(syllable string) string {
	if syllable == "" {
		return ""
	}
	return syllable[:1]
}

// _nameShorthandTable holds the contractions riders use that no phonetic rule
// produces — 北車 is not an abbreviation of the sounds of 臺北車站, it is a
// separate word. Hand-maintained, and deliberately short: an entry earns its
// place by being what people actually say. Keyed on the exact name, with both
// 臺 and 台 spellings listed because the feeds use both.
var _nameShorthandTable = map[string][]string{
	"臺北車站":  {"北車"},
	"台北車站":  {"北車"},
	"臺北市政府": {"市府"},
	"台北市政府": {"市府"},
	"市政府":   {"市府"},
	"高雄車站":  {"高雄火車站"},
	"臺中車站":  {"台中火車站"},
	"台中車站":  {"台中火車站"},
}

func nameShorthands(name string) []string {
	return _nameShorthandTable[name]
}
