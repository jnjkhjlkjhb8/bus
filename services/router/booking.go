package main

import (
	"context"
	"fmt"
	"net/http"
	"regexp"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/go-resty/resty/v2"

	"github.com/jnjkhjlkjhb8/wheres_the_car/services/shared"
)

// bookingProxy exchanges rail booking parameters for a short-lived TDX deeplink
// redirect URL. It is the router's second deliberate TDX carve-out alongside
// MaaS (ADR-0005 amendment, ADR-0012): a request/response proxy, not a
// cacheable read, so it cannot be pre-materialised into Redis. The returned URL
// is HMAC-signed by TDX and expires in minutes, so it must be minted per click.
type bookingProxy struct {
	tra  *resty.Client
	thsr *resty.Client
}

func newBookingProxy(tdx *shared.TDXClient) *bookingProxy {
	return &bookingProxy{
		tra:  tdx.NewAuthedClient("https://tdx.transportdata.tw/api/maas-tra"),
		thsr: tdx.NewAuthedClient("https://tdx.transportdata.tw/api/maas-thsr"),
	}
}

// tdxBookingResponse is the TDX deeplink exchange envelope. On success `data`
// holds the redirect URL; on failure `data` is absent and `error` is set.
type tdxBookingResponse struct {
	Result string `json:"result"`
	Data   struct {
		Deeplink string `json:"deeplink"`
		Expired  string `json:"expired"`
	} `json:"data"`
}

// bookingDetailLimit caps how much of an upstream error body reaches the log.
// TDX failure envelopes are short; a cap keeps a surprise HTML error page from
// flooding the line.
const bookingDetailLimit = 240

// bookingDetail renders an upstream failure as a single log-safe token: status,
// the envelope's `result`, and a truncated body. Without it a failed exchange
// logged nothing at all and 502 could not be told apart from a rejected station
// name, an unsubscribed API, or an expired token.
func bookingDetail(res *resty.Response, body tdxBookingResponse) string {
	raw := strings.TrimSpace(string(res.Body()))
	raw = strings.Join(strings.Fields(raw), " ")
	if len(raw) > bookingDetailLimit {
		raw = raw[:bookingDetailLimit] + "…"
	}
	return fmt.Sprintf("status=%d result=%q body=%q", res.StatusCode(), body.Result, raw)
}

var (
	trainDatePattern = regexp.MustCompile(`^\d{4}-\d{2}-\d{2}$`)
	trainTimePattern = regexp.MustCompile(`^\d{2}:\d{2}$`)
)

// maxTicketsPerCategory is TDX's documented per-category ceiling.
const maxTicketsPerCategory = 10

// parseTicketCounts reads the passenger-category counts, defaulting a missing
// category to 0. It rejects out-of-range values here rather than letting TDX
// reject the whole exchange, and requires at least one passenger so a booking
// for nobody never reaches upstream.
func parseTicketCounts(c *gin.Context) (map[string]int, error) {
	counts := make(map[string]int, len(thsrTicketParams))
	total := 0
	for category := range thsrTicketParams {
		raw := strings.TrimSpace(c.Query(category + "_ticket"))
		if raw == "" {
			continue
		}
		n, err := strconv.Atoi(raw)
		if err != nil || n < 0 || n > maxTicketsPerCategory {
			return nil, fmt.Errorf("%s_ticket must be an integer between 0 and %d", category, maxTicketsPerCategory)
		}
		counts[category] = n
		total += n
	}
	if total == 0 {
		// No counts at all is the TRA/direct case, where the variant takes none;
		// an explicit all-zero set would book nothing.
		if len(counts) == 0 {
			return counts, nil
		}
		return nil, fmt.Errorf("at least one ticket is required")
	}
	return counts, nil
}

// route selects the upstream client and resource path for an (agency, kind)
// pair. kind is the deeplink variant: "direct" (App Link → opens the operator
// app if installed) or "web" (→ pre-filled booking web page).
func (b *bookingProxy) route(agency, kind string) (*resty.Client, string, bool) {
	if kind != "web" && kind != "direct" {
		return nil, "", false
	}
	switch agency {
	case "tra":
		return b.tra, "/booking/deeplink/" + kind + "/tra", true
	case "hsr":
		return b.thsr, "/booking/deeplink/" + kind + "/hsr", true
	default:
		return nil, "", false
	}
}

// bookingRequest is one booking exchange in our own vocabulary. The upstream
// spelling of every field differs per (agency, kind), so that mapping lives in
// bookingParams instead of being baked into the caller.
type bookingRequest struct {
	agency   string
	kind     string
	start    string
	end      string
	date     string // yyyy-mm-dd
	time     string // hh:mm
	train    string
	carriage string         // "Y" standard, "J" business — THSR web only
	tickets  map[string]int // passenger category → count — THSR web only
}

// thsrTicketParams maps a passenger category to its TDX parameter. THSR takes
// one count parameter per category rather than a single quantity, and only the
// /web/hsr variant accepts them at all.
var thsrTicketParams = map[string]string{
	"adult":    "adult_ticket",
	"child":    "children_ticket",
	"disabled": "disabled_ticket",
	"senior":   "senior_ticket",
	"student":  "student_ticket",
}

// bookingParams renders a request into its variant's upstream query string. The
// variants genuinely disagree, which is why one shared parameter set kept
// failing:
//
//   - /web/hsr: departure_date as yyyymmdd, a 4-digit zero-padded
//     departure_number, ticket_type (trip type, S = one-way), carriage_type,
//     and one count parameter per passenger category.
//   - /direct/hsr: train_date (yyyy-mm-dd) plus a required train_time.
//   - /web/tra: departure_date — a live 500 named it.
//   - /direct/tra: train_date, and no train_time.
//
// train_time is a THSR-only field: TRA takes none, so sending it there is at
// best ignored and at worst another rejected exchange.
func bookingParams(r bookingRequest) map[string]string {
	q := map[string]string{"start_station": r.start, "end_station": r.end}
	if r.agency == "hsr" && r.kind == "web" {
		q["departure_date"] = strings.ReplaceAll(r.date, "-", "")
		// A 3-digit train number must be zero-padded to 4.
		q["departure_number"] = fmt.Sprintf("%04s", r.train)
		q["ticket_type"] = "S"
		carriage := r.carriage
		if carriage != "J" {
			carriage = "Y"
		}
		q["carriage_type"] = carriage
		for category, param := range thsrTicketParams {
			q[param] = strconv.Itoa(r.tickets[category])
		}
		return q
	}
	if r.agency == "tra" && r.kind == "web" {
		q["departure_date"] = r.date
	} else {
		q["train_date"] = r.date
	}
	if r.agency == "hsr" {
		q["train_time"] = r.time
	}
	q["train_number"] = r.train
	return q
}

func (b *bookingProxy) exchange(ctx context.Context, client *resty.Client, resource string, r bookingRequest) (string, string, error) {
	var body tdxBookingResponse
	res, err := client.R().
		SetContext(ctx).
		SetQueryParams(bookingParams(r)).
		SetResult(&body).
		Get(resource)
	if err != nil {
		return "", "", err
	}
	if res.IsError() || body.Result != "success" || body.Data.Deeplink == "" {
		return "", "", fmt.Errorf("tdx booking exchange failed: %s", bookingDetail(res, body))
	}
	return body.Data.Deeplink, body.Data.Expired, nil
}

// handleBookingDeeplink proxies a rail booking exchange to TDX. The app picks
// `kind` from a client-side install probe (ADR-0012); a missing-credentials
// upstream (non-prod) surfaces as 503 so the app falls back to a plain booking
// site link.
func handleBookingDeeplink(booking *bookingProxy) gin.HandlerFunc {
	return func(c *gin.Context) {
		if booking == nil {
			c.JSON(http.StatusServiceUnavailable, gin.H{"error": "booking unavailable"})
			return
		}
		agency := strings.ToLower(strings.TrimSpace(c.Query("agency")))
		kind := strings.ToLower(strings.TrimSpace(c.Query("kind")))
		client, resource, ok := booking.route(agency, kind)
		if !ok {
			c.JSON(http.StatusBadRequest, gin.H{"error": "agency must be tra|hsr and kind must be web|direct"})
			return
		}
		req := bookingRequest{
			agency:   agency,
			kind:     kind,
			start:    strings.TrimSpace(c.Query("start_station")),
			end:      strings.TrimSpace(c.Query("end_station")),
			date:     strings.TrimSpace(c.Query("train_date")),
			time:     strings.TrimSpace(c.Query("train_time")),
			train:    strings.TrimSpace(c.Query("train_number")),
			carriage: strings.ToUpper(strings.TrimSpace(c.Query("carriage_type"))),
		}
		if req.start == "" || req.end == "" || !trainDatePattern.MatchString(req.date) {
			c.JSON(http.StatusBadRequest, gin.H{"error": "missing or malformed start_station/end_station/train_date"})
			return
		}
		// THSR requires train_time and TRA takes none, so it is required exactly
		// where it is used — failing here beats an upstream rejection whose
		// message the app can do nothing with.
		if req.agency == "hsr" && !trainTimePattern.MatchString(req.time) {
			c.JSON(http.StatusBadRequest, gin.H{"error": "train_time must be hh:mm for hsr"})
			return
		}
		if n, err := strconv.Atoi(req.train); err != nil || n <= 0 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "train_number must be a positive integer"})
			return
		}
		tickets, err := parseTicketCounts(c)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		req.tickets = tickets
		url, expired, err := booking.exchange(c.Request.Context(), client, resource, req)
		if err != nil {
			log.Errorf("[BOOKING] action=exchange event=failed agency=%s kind=%s start=%q end=%q date=%s time=%s train=%s error=%v",
				agency, kind, req.start, req.end, req.date, req.time, req.train, err)
			if shared.IsTDXAuthError(err) {
				c.JSON(http.StatusServiceUnavailable, gin.H{"error": "booking unavailable", "reason": "auth"})
				return
			}
			c.JSON(http.StatusBadGateway, gin.H{"error": "booking upstream failed", "reason": "upstream"})
			return
		}
		c.JSON(http.StatusOK, gin.H{"url": url, "expired": expired})
	}
}
