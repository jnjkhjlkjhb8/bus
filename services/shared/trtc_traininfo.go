package shared

import (
	"context"
	"encoding/json"
	"encoding/xml"
	"net/http"
	"strings"
	"time"

	"github.com/go-resty/resty/v2"
)

// This file is the GetTrainInfo client for Metro Taipei's mobile-app endpoint,
// shared by both binaries: the router calls it once at session creation to bind
// a carriage to a trip, and the functions tracker calls it per station hop to
// advance a metro alight-reminder session (ADR-0015). It is distinct from the
// api.metro.taipei SOAP feeds the trtcEta live job polls (ADR-0014).

// TRTCTrainInfoURL is the mobile-app GetTrainInfo endpoint. Unlike the
// api.metro.taipei services, this host serves the per-car train position keyed
// by carID.
const TRTCTrainInfoURL = "https://mobileapp.metro.taipei/TRTCTraininfo/TrainTimeControl.asmx"

// TRTCTrainInfo is one GetTrainInfo reading: the train's next station and
// countdown, keyed by carID. TripId equals the congestion feed's TrainNumber
// (and getTrackInfo train number); it is the trip identity a session follows.
// StnName is the next station in Chinese with a 「站」suffix, and may be empty
// mid-run. DestName is an internal code that does not match public TDX station
// IDs and is intentionally ignored.
type TRTCTrainInfo struct {
	TrainID       string `json:"TrainId"`
	TripID        string `json:"TripId"`
	StnName       string `json:"StnName"`
	CountdownTime string `json:"CountdownTime"`
	DestName      string `json:"DestName"`
	UpdateTime    string `json:"UpdateTime"`
}

// TRTCTrainInfoClient calls GetTrainInfo with a reused HTTP client. Credentials
// come from TRTC_USERNAME / TRTC_PASSWORD (the same account trtcEta uses); an
// empty user or pass makes GetTrainInfo a no-op returning (nil, false, nil), so
// credential-less environments issue zero requests.
type TRTCTrainInfoClient struct {
	http *resty.Client
	url  string
	user string
	pass string
}

// NewTRTCTrainInfoClient builds the production client. The Content-Type is SOAP
// 1.2; the request body is built per call (see GetTrainInfo). A finite timeout
// bounds every call so a stuck endpoint cannot hang a tracker tick.
func NewTRTCTrainInfoClient(user, pass string) *TRTCTrainInfoClient {
	return &TRTCTrainInfoClient{
		http: resty.New().SetTimeout(15 * time.Second),
		url:  TRTCTrainInfoURL,
		user: user,
		pass: pass,
	}
}

// newTRTCTrainInfoClientWithHTTP is the test seam: it injects a resty client
// (e.g. one wired to an httptest server or a stub RoundTripper) and an override
// URL. Production uses NewTRTCTrainInfoClient.
func newTRTCTrainInfoClientWithHTTP(httpClient *resty.Client, url, user, pass string) *TRTCTrainInfoClient {
	return &TRTCTrainInfoClient{http: httpClient, url: url, user: user, pass: pass}
}

// trtcTrainInfoBody builds the SOAP 1.2 request body. CRITICAL: the GetTrainInfo
// element carries NO xmlns — the service's WSDL targetNamespace is empty, and
// adding xmlns="http://tempuri.org/" yields a 302 redirect with an empty result
// (ADR-0015). The body children are carID/username/password (lowercase, unlike
// the api.metro.taipei services' userName/passWord).
func trtcTrainInfoBody(carID, user, pass string) string {
	esc := func(s string) string {
		var b strings.Builder
		_ = xml.EscapeText(&b, []byte(s))
		return b.String()
	}
	return `<?xml version="1.0" encoding="utf-8"?>` +
		`<soap12:Envelope xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:soap12="http://www.w3.org/2003/05/soap-envelope">` +
		`<soap12:Body><GetTrainInfo>` +
		`<carID>` + esc(carID) + `</carID>` +
		`<username>` + esc(user) + `</username>` +
		`<password>` + esc(pass) + `</password>` +
		`</GetTrainInfo></soap12:Body></soap12:Envelope>`
}

// GetTrainInfo returns one train's reading for a full carID. The bool reports
// whether a reading was found: an empty or invalid carID returns no JSON, which
// is (nil, false, nil) rather than an error, because "查無此車" is an expected
// caller-facing outcome, not a transport failure. Empty credentials likewise
// return (nil, false, nil) without issuing a request.
func (c *TRTCTrainInfoClient) GetTrainInfo(ctx context.Context, carID string) (*TRTCTrainInfo, bool, error) {
	if c.user == "" || c.pass == "" {
		return nil, false, nil
	}
	resp, err := c.http.R().
		SetContext(ctx).
		SetHeader("Content-Type", "application/soap+xml; charset=utf-8").
		SetBody(trtcTrainInfoBody(carID, c.user, c.pass)).
		Post(c.url)
	if err != nil {
		return nil, false, err
	}
	if resp.StatusCode() != http.StatusOK {
		return nil, false, _oops.With("status_code", resp.StatusCode()).Errorf("GetTrainInfo: status")
	}
	raw, ok := extractJSONObject(resp.Body())
	if !ok {
		// No JSON object in the response is the empty-result signal (unknown or
		// invalid carID), not a parse failure.
		return nil, false, nil
	}
	var info TRTCTrainInfo
	if err := json.Unmarshal(raw, &info); err != nil {
		return nil, false, _oops.Wrapf(err, "GetTrainInfo: decode")
	}
	if info.TripID == "" {
		return nil, false, nil
	}
	return &info, true, nil
}

// extractJSONObject pulls the JSON object embedded in a GetTrainInfo response.
// The service returns the object before/inside the SOAP envelope (the same
// inconsistency trtcEta's array extraction handles), so extraction is simply
// first-'{'..last-'}'.
func extractJSONObject(raw []byte) ([]byte, bool) {
	s := string(raw)
	start := strings.IndexByte(s, '{')
	end := strings.LastIndexByte(s, '}')
	if start < 0 || end <= start {
		return nil, false
	}
	return raw[start : end+1], true
}
