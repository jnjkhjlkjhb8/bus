package shared

import "strings"

// ZhuyinToneMarks are the tone keys a 注音 IME leaves in the composing buffer
// while the rider is still typing. search_vector.alias stores toneless
// Bopomofo, so queries are normalised to match rather than the column
// carrying every toned spelling of every name.
const ZhuyinToneMarks = "ˊˇˋ˙"

// StripZhuyinTones removes the tone marks from a search query so toned input
// matches the toneless aliases the loader writes. A no-op for anything
// without them, which is every query that is not Bopomofo.
func StripZhuyinTones(q string) string {
	if !strings.ContainsAny(q, ZhuyinToneMarks) {
		return q
	}
	return strings.Map(func(r rune) rune {
		if strings.ContainsRune(ZhuyinToneMarks, r) {
			return -1
		}
		return r
	}, q)
}
