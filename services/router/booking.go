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

var trainDatePattern = regexp.MustCompile(`^\d{4}-\d{2}-\d{2}$`)

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

func (b *bookingProxy) exchange(ctx context.Context, client *resty.Client, resource, start, end, date, train string) (string, string, error) {
	var body tdxBookingResponse
	res, err := client.R().
		SetContext(ctx).
		SetQueryParams(map[string]string{
			"start_station": start,
			"end_station":   end,
			"train_date":    date,
			"train_number":  train,
		}).
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
		start := strings.TrimSpace(c.Query("start_station"))
		end := strings.TrimSpace(c.Query("end_station"))
		date := strings.TrimSpace(c.Query("train_date"))
		train := strings.TrimSpace(c.Query("train_number"))
		if start == "" || end == "" || !trainDatePattern.MatchString(date) {
			c.JSON(http.StatusBadRequest, gin.H{"error": "missing or malformed start_station/end_station/train_date"})
			return
		}
		if n, err := strconv.Atoi(train); err != nil || n <= 0 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "train_number must be a positive integer"})
			return
		}
		url, expired, err := booking.exchange(c.Request.Context(), client, resource, start, end, date, train)
		if err != nil {
			log.Errorf("[BOOKING] action=exchange event=failed agency=%s kind=%s start=%q end=%q date=%s train=%s error=%v",
				agency, kind, start, end, date, train, err)
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
