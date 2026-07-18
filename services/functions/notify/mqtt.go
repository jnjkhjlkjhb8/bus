package notify

import (
	"context"
	"crypto/sha256"
	"crypto/tls"
	"encoding/json"
	"fmt"
	"os"
	"strings"
	"time"

	mqtt "github.com/eclipse/paho.mqtt.golang"
	"github.com/go-redis/redis"
	"github.com/jnjkhjlkjhb8/wheres_the_car/services/shared"
)

// mqttTopicCfg is a subscription: an MQTT topic pattern and the Redis TTL applied
// to messages cached from it.
type mqttTopicCfg struct {
	pattern string
	ttl     time.Duration
}

// mqttTopics is the set of TDX MQTT subscriptions and their cache TTLs. TDX
// publishes only news and alert topics — there is no vehicle-position or
// near-stop stream — so every subscription here is advisory text on a 5-minute
// TTL. Bus alerts stay on v2: routeAlerts reads the v2 field names.
var mqttTopics = []mqttTopicCfg{
	{"v2/Bus/News/City/+", 5 * time.Minute},
	{"v2/Bus/News/InterCity", 5 * time.Minute},
	{"v2/Bus/Alert/City/+", 5 * time.Minute},
	{"v2/Bus/Alert/InterCity", 5 * time.Minute},
	{"v2/Rail/Metro/Alert/#", 5 * time.Minute},
	{"v3/Rail/TRA/Alert", 5 * time.Minute},
	{"v2/Rail/THSR/AlertInfo", 5 * time.Minute},
}

// StartMQTT connects to the TDX MQTT broker over TLS and (re)subscribes to all
// topics on every connect. It returns nil when MQTT_CLIENT_ID / MQTT_USERNAME /
// MQTT_PASSWORD are unset, so MQTT is simply skipped in environments without
// credentials. Auto-reconnect is on; the initial connect failing is logged but
// not fatal — the client keeps retrying. Broker: mqtts://mqtt.transportdata.tw:8883
func StartMQTT(rc *redis.Client, dispatcher *Dispatcher) mqtt.Client {
	clientID := os.Getenv("MQTT_CLIENT_ID")
	username := os.Getenv("MQTT_USERNAME")
	password := os.Getenv("MQTT_PASSWORD")
	if clientID == "" || username == "" || password == "" {
		log.Warn("[MQTT] credentials not set — skipping MQTT subscriber")
		return nil
	}
	opts := mqtt.NewClientOptions().
		AddBroker("mqtts://mqtt.transportdata.tw:8883").
		SetClientID(clientID).
		SetUsername(username).
		SetPassword(password).
		SetCleanSession(true).
		SetAutoReconnect(true).
		SetConnectRetry(true).
		SetConnectRetryInterval(10 * time.Second).
		SetTLSConfig(&tls.Config{}).
		SetOnConnectHandler(func(c mqtt.Client) {
			log.Infoln("[MQTT] connected")
			mqttsubscribeall(c, rc, dispatcher)
		}).
		SetConnectionLostHandler(func(_ mqtt.Client, err error) {
			log.Warnf("[MQTT] connection lost: %v", err)
		})
	c := mqtt.NewClient(opts)
	tok := c.Connect()
	tok.Wait()
	if err := tok.Error(); err != nil {
		log.Errorf("[MQTT] initial connect failed: %v — will auto-retry", err)
	}
	return c
}

// mqttsubscribeall subscribes to every mqttTopics entry at QoS 1, routing each
// message to mqtthandle with that topic's TTL. It runs on every (re)connect, so
// subscriptions are restored after a dropped connection. Per-topic subscribe
// failures are logged.
func mqttsubscribeall(c mqtt.Client, rc *redis.Client, dispatcher *Dispatcher) {
	for _, t := range mqttTopics {
		pattern, ttl := t.pattern, t.ttl
		tok := c.Subscribe(pattern, 1, func(_ mqtt.Client, msg mqtt.Message) {
			mqtthandle(rc, msg, ttl, dispatcher)
		})
		tok.Wait()
		if err := tok.Error(); err != nil {
			log.Errorf("[MQTT] subscribe failed topic=%s err=%v", pattern, err)
		} else {
			log.Infof("[MQTT] subscribed topic=%s", pattern)
		}
	}
}

// mqtthandle caches one MQTT message in Redis (key derived from the topic, with
// slashes turned into colons) and republishes it on that key for live streaming.
// It then dispatches route alerts, using SetNX on an "fcm:alert:" key as a
// cross-run dedupe claim so the same alert is not pushed twice within its window.
// Alert dispatch needs the SetNX claim, so a Redis failure skips it: without the
// claim the same alert would push on every retry.
func mqtthandle(rc *redis.Client, msg mqtt.Message, ttl time.Duration, dispatcher *Dispatcher) {
	key := shared.MQTTChannel(msg.Topic())
	payload := canonicalInterCityBusPayload(msg.Topic(), msg.Payload())
	if err := rc.Set(key, payload, ttl).Err(); err != nil {
		log.Errorf("[MQTT] redis set failed key=%s err=%v", key, err)
		return
	}
	if err := rc.Publish(key, payload).Err(); err != nil {
		log.Errorf("[MQTT] redis publish failed key=%s err=%v", key, err)
	}
	dispatchRouteAlerts(context.Background(), routeAlerts(msg.Topic(), msg.Payload()), func(key string, ttl time.Duration) bool {
		ok, err := rc.SetNX("fcm:alert:"+key, "1", ttl).Result()
		return err == nil && ok
	}, dispatcher)
}

// canonicalInterCityBusPayload puts MQTT vehicle snapshots in the same
// canonical subroute+direction identity space as the REST realtime path.
func canonicalInterCityBusPayload(topic string, payload []byte) []byte {
	if !strings.Contains(topic, "/Bus/") || !strings.Contains(topic, "/InterCity") {
		return payload
	}
	var decoded any
	if err := json.Unmarshal(payload, &decoded); err != nil {
		return payload
	}
	canonicalize := func(item any) {
		entry, ok := item.(map[string]any)
		if !ok {
			return
		}
		uid, ok := entry["SubRouteUID"].(string)
		if !ok || strings.TrimSpace(uid) == "" {
			return
		}
		direction := uint8(0)
		if rawDirection, ok := entry["Direction"].(float64); ok && rawDirection >= 0 && rawDirection <= 255 {
			direction = uint8(rawDirection)
		}
		canonicalUID, canonicalDirection := shared.CanonicalSubroute("InterCity", strings.TrimSpace(uid), direction)
		entry["SubRouteUID"] = canonicalUID
		entry["Direction"] = canonicalDirection
	}
	if items, ok := decoded.([]any); ok {
		for _, item := range items {
			canonicalize(item)
		}
	} else {
		canonicalize(decoded)
	}
	canonical, err := json.Marshal(decoded)
	if err != nil {
		return payload
	}
	return canonical
}

// normalizedRouteAlert is one alert extracted from an MQTT payload, reduced to
// what push needs: the transit type, the affected route key, the body text, and
// a stable id for dedupe.
type normalizedRouteAlert struct{ routeType, routeKey, body, id string }

// dispatchRouteAlerts pushes each alert whose dedupe key claim succeeds. When an
// alert has no id, the body's SHA-256 is used so identical bodies collapse. claim
// is injected (Redis SetNX in production) so the dedupe window is testable.
func dispatchRouteAlerts(ctx context.Context, alerts []normalizedRouteAlert, claim func(string, time.Duration) bool, dispatcher *Dispatcher) {
	for _, alert := range alerts {
		id := alert.id
		if id == "" {
			id = fmt.Sprintf("%x", sha256.Sum256([]byte(alert.body)))
		}
		key := alert.routeType + "\x00" + alert.routeKey + "\x00" + id
		if claim(key, 5*time.Minute) {
			dispatcher.routeAlert(ctx, alert.routeType, alert.routeKey, alert.body)
		}
	}
}

// routeAlerts parses an MQTT disruption payload into normalized alerts. Each
// transit type scopes its alerts differently, so the route key comes from a
// per-type extractor; an alert that names no route yields one entry with an
// empty key, which dispatches line-wide to every subscriber of that type.
// Alerts are deduped on key+body, since TDX repeats one disruption across the
// routes it scopes.
func routeAlerts(topic string, payload []byte) []normalizedRouteAlert {
	routeType := alertRouteType(topic)
	if routeType == "" {
		return nil
	}
	items := alertItems(payload)
	seen := map[string]struct{}{}
	out := make([]normalizedRouteAlert, 0, len(items))
	for _, m := range items {
		body := firstString(m, "Description", "NewsContent", "AlertDescription", "Message")
		if body == "" {
			body = firstString(m, "NewsTitle", "Title")
		}
		if body == "" {
			continue
		}
		id := firstString(m, "NewsID", "AlertID", "UpdateTime")
		for _, key := range alertRouteKeys(routeType, m) {
			if key != "" && strings.Contains(topic, "/InterCity") {
				key, _ = shared.CanonicalSubroute("InterCity", key, 0)
			}
			dedupe := key + "\x00" + body
			if _, ok := seen[dedupe]; ok {
				continue
			}
			seen[dedupe] = struct{}{}
			out = append(out, normalizedRouteAlert{routeType: routeType, routeKey: key, body: body, id: id})
		}
	}
	return out
}

// alertRouteType maps an MQTT topic to the transit type its payload describes,
// or "" for a topic that carries no disruption info.
func alertRouteType(topic string) string {
	switch {
	case strings.Contains(topic, "/Bus/"):
		return "bus"
	case strings.Contains(topic, "/Metro/"):
		return "mrt"
	case strings.Contains(topic, "/TRA/"):
		return "tra"
	case strings.Contains(topic, "/THSR/"):
		return "thsr"
	}
	return ""
}

// alertRouteKeys returns the route keys one alert applies to. Bus alerts scope
// to routes and TRA alerts to train numbers, both of which the app subscribes
// by. THSR and metro alerts scope only to stations, lines, and line sections —
// none of which is a subscription key — so they fall through to the empty key
// and dispatch line-wide, as does a rail alert whose scope names no train.
//
// Bus has no such fallback: it spans thousands of routes across every
// operator, and route-less bus News (fare changes, timetable notices) would
// otherwise push to every bus subscriber in the country.
func alertRouteKeys(routeType string, m map[string]any) []string {
	switch routeType {
	case "bus":
		return busRouteKeys(m)
	case "tra":
		if keys := scopeKeys(m, "Trains", "TrainNo"); len(keys) > 0 {
			return keys
		}
	}
	return []string{""}
}

// alertItems unwraps an MQTT payload into the individual alert objects it
// carries. Bus news/alerts arrive as a bare JSON array, while metro and TRA
// wrap several alerts in an authority envelope
// ({"AuthorityCode":"TRTC","Alerts":[...]}); a lone object is treated as a
// one-element payload.
func alertItems(payload []byte) []map[string]any {
	var raw any
	if json.Unmarshal(payload, &raw) != nil {
		return nil
	}
	var items []any
	switch v := raw.(type) {
	case []any:
		items = v
	case map[string]any:
		if nested, ok := v["Alerts"].([]any); ok {
			items = nested
		} else {
			items = []any{v}
		}
	}
	out := make([]map[string]any, 0, len(items))
	for _, item := range items {
		if m, ok := item.(map[string]any); ok {
			out = append(out, m)
		}
	}
	return out
}

// busRouteKeys returns every route key one bus alert applies to. News payloads
// carry no scope at all; Alert payloads list the affected routes under
// Scope.SubRoutes / Scope.Routes, where TDX publishes IDs and UIDs
// inconsistently across operators. Both are emitted — a key with no
// subscribers simply pushes nothing — and duplicates are dropped.
func busRouteKeys(m map[string]any) []string {
	keys := []string{}
	if top := firstString(m, "SubRouteUID", "RouteUID"); top != "" {
		keys = append(keys, top)
	}
	keys = append(keys, scopeKeys(m, "SubRoutes", "SubRouteUID", "SubRouteID")...)
	keys = append(keys, scopeKeys(m, "Routes", "RouteUID", "RouteID")...)
	return dedupeStrings(keys)
}

// scopeKeys reads one Scope list (Scope.SubRoutes, Scope.Trains, …) and
// returns each entry's first non-empty value among fields. TDX publishes IDs
// and UIDs inconsistently across operators, so callers pass both: a key with
// no subscribers simply pushes nothing.
func scopeKeys(m map[string]any, list string, fields ...string) []string {
	scope, _ := m["Scope"].(map[string]any)
	entries, _ := scope[list].([]any)
	keys := make([]string, 0, len(entries))
	for _, entry := range entries {
		if e, ok := entry.(map[string]any); ok {
			if key := firstString(e, fields...); key != "" {
				keys = append(keys, key)
			}
		}
	}
	return dedupeStrings(keys)
}

// dedupeStrings drops repeats while preserving order.
func dedupeStrings(values []string) []string {
	seen := make(map[string]struct{}, len(values))
	out := values[:0]
	for _, v := range values {
		if _, ok := seen[v]; ok {
			continue
		}
		seen[v] = struct{}{}
		out = append(out, v)
	}
	return out
}

// firstString returns the trimmed value of the first key in keys that maps to a
// non-empty string, or "" if none do. Used to read a value that TDX may publish
// under any of several field names.
func firstString(m map[string]any, keys ...string) string {
	for _, key := range keys {
		if value, ok := m[key].(string); ok && strings.TrimSpace(value) != "" {
			return strings.TrimSpace(value)
		}
	}
	return ""
}
