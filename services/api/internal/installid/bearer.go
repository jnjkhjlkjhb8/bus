package installid

// Authorization-header parsing, shared by every HTTP surface that authenticates
// a caller. Strict on shape rather than forgiving: a header with stray
// whitespace or a multi-token credential is rejected outright, so a malformed
// value can never be read as a valid one.

import "strings"

func ParseBearerCredential(header string) string {
	if header == "" || header != strings.TrimSpace(header) {
		return ""
	}
	separator := strings.IndexAny(header, " \t")
	if separator <= 0 || !strings.EqualFold(header[:separator], "Bearer") {
		return ""
	}
	credentialStart := separator
	for credentialStart < len(header) && (header[credentialStart] == ' ' || header[credentialStart] == '\t') {
		credentialStart++
	}
	if credentialStart == len(header) {
		return ""
	}
	credential := header[credentialStart:]
	if strings.ContainsAny(credential, " \t\r\n") {
		return ""
	}
	return credential
}

// HTTPPort is the only port the router's HTTP server ever serves on, so a
// self-referential URL (the GBFS discovery document) can name it without a
// config setting.
const HTTPPort = "8080"
