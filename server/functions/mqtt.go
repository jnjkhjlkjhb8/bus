package main

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
)

// mqttTopicCfg is a subscription: an MQTT topic pattern and the Redis TTL applied
// to messages cached from it.
type mqttTopicCfg struct {
	pattern string
	ttl     time.Duration
}

// mqttTopics is the set of TDX MQTT subscriptions and their cache TTLs. Live
// near-stop bus data is short-lived (60s); news and alert topics keep 5 minutes.
var mqttTopics = []mqttTopicCfg{
	{"v2/Bus/RealTimeNearStop/City/#", 60 * time.Second},
	{"v2/Bus/News/City/+", 5 * time.Minute},
	{"v2/Bus/News/InterCity", 5 * time.Minute},
	{"v2/Rail/Metro/Alert/#", 5 * time.Minute},
	{"v3/Rail/TRA/Alert", 5 * time.Minute},
	{"v2/Rail/THSR/AlertInfo", 5 * time.Minute},
}

// startMQTT connects to the TDX MQTT broker over TLS and (re)subscribes to all
// topics on every connect. It returns nil when MQTT_CLIENT_ID / MQTT_USERNAME /
// MQTT_PASSWORD are unset, so MQTT is simply skipped in environments without
// credentials. Auto-reconnect is on; the initial connect failing is logged but
// not fatal — the client keeps retrying. Broker: mqtts://mqtt.transportdata.tw:8883
func startMQTT(rc *redis.Client, dispatcher *notificationDispatcher) mqtt.Client {
	clientID := os.Getenv("MQTT_CLIENT_ID")
	username := os.Getenv("MQTT_USERNAME")
	password := os.Getenv("MQTT_PASSWORD")
	if clientID == "" || username == "" || password == "" {
		log.Infoln("[MQTT] credentials not set — skipping MQTT subscriber")
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
			log.Infof("[MQTT] connection lost: %v", err)
		})
	c := mqtt.NewClient(opts)
	tok := c.Connect()
	tok.Wait()
	if err := tok.Error(); err != nil {
		log.Infof("[MQTT] initial connect failed: %v — will auto-retry", err)
	}
	return c
}

// mqttsubscribeall subscribes to every mqttTopics entry at QoS 1, routing each
// message to mqtthandle with that topic's TTL. It runs on every (re)connect, so
// subscriptions are restored after a dropped connection. Per-topic subscribe
// failures are logged.
func mqttsubscribeall(c mqtt.Client, rc *redis.Client, dispatcher *notificationDispatcher) {
	for _, t := range mqttTopics {
		pattern, ttl := t.pattern, t.ttl
		tok := c.Subscribe(pattern, 1, func(_ mqtt.Client, msg mqtt.Message) {
			mqtthandle(rc, msg, ttl, dispatcher)
		})
		tok.Wait()
		if err := tok.Error(); err != nil {
			log.Infof("[MQTT] subscribe failed topic=%s err=%v", pattern, err)
		} else {
			log.Infof("[MQTT] subscribed topic=%s", pattern)
		}
	}
}

// mqtthandle caches one MQTT message in Redis (key derived from the topic, with
// slashes turned into colons) and republishes it on that key for live streaming.
// It then dispatches route alerts, using SetNX on an "fcm:alert:" key as a
// cross-run dedupe claim so the same alert is not pushed twice within its window.
func mqtthandle(rc *redis.Client, msg mqtt.Message, ttl time.Duration, dispatcher *notificationDispatcher) {
	key := "mqtt:" + strings.ReplaceAll(msg.Topic(), "/", ":")
	if err := rc.Set(key, msg.Payload(), ttl).Err(); err != nil {
		log.Infof("[MQTT] redis set failed key=%s err=%v", key, err)
		return
	}
	if err := rc.Publish(key, msg.Payload()).Err(); err != nil {
		log.Infof("[MQTT] redis publish failed key=%s err=%v", key, err)
	}
	dispatchRouteAlerts(context.Background(), routeAlerts(msg.Topic(), msg.Payload()), func(key string, ttl time.Duration) bool {
		ok, err := rc.SetNX("fcm:alert:"+key, "1", ttl).Result()
		return err == nil && ok
	}, dispatcher)
}

// normalizedRouteAlert is one alert extracted from an MQTT payload, reduced to
// what push needs: the transit type, the affected route key, the body text, and
// a stable id for dedupe.
type normalizedRouteAlert struct{ routeType, routeKey, body, id string }

// dispatchRouteAlerts pushes each alert whose dedupe key claim succeeds. When an
// alert has no id, the body's SHA-256 is used so identical bodies collapse. claim
// is injected (Redis SetNX in production) so the dedupe window is testable.
func dispatchRouteAlerts(ctx context.Context, alerts []normalizedRouteAlert, claim func(string, time.Duration) bool, dispatcher *notificationDispatcher) {
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

// routeAlerts parses an MQTT alert payload into normalized alerts. Only bus
// alerts are currently emitted — other transit types resolve their type but
// return nil, since only bus alerts carry a per-route key to target. It accepts
// either a JSON array or a single object, extracts the route key and body from
// the first matching TDX field name, and dedupes on key+body.
func routeAlerts(topic string, payload []byte) []normalizedRouteAlert {
	routeType := ""
	switch {
	case strings.Contains(topic, "/Bus/"):
		routeType = "bus"
	case strings.Contains(topic, "/Metro/"):
		routeType = "mrt"
	case strings.Contains(topic, "/TRA/"):
		routeType = "tra"
	case strings.Contains(topic, "/THSR/"):
		routeType = "thsr"
	}
	if routeType != "bus" {
		return nil
	}
	var raw any
	if json.Unmarshal(payload, &raw) != nil {
		return nil
	}
	items, ok := raw.([]any)
	if !ok {
		items = []any{raw}
	}
	seen := map[string]struct{}{}
	out := make([]normalizedRouteAlert, 0, len(items))
	for _, item := range items {
		m, ok := item.(map[string]any)
		if !ok {
			continue
		}
		key := firstString(m, routeKeyFields(routeType)...)
		if key == "" {
			continue
		}
		body := firstString(m, "Description", "NewsContent", "AlertDescription", "Message")
		if body == "" {
			body = firstString(m, "NewsTitle", "Title")
		}
		if body == "" {
			continue
		}
		dedupe := key + "\x00" + body
		if _, ok := seen[dedupe]; ok {
			continue
		}
		seen[dedupe] = struct{}{}
		out = append(out, normalizedRouteAlert{routeType: routeType, routeKey: key, body: body, id: firstString(m, "NewsID", "AlertID", "UpdateTime")})
	}
	return out
}

// routeKeyFields returns the payload field names that hold the route key for a
// transit type. Only bus is mapped (to SubRouteUID); other types return nil,
// which makes routeAlerts skip them.
func routeKeyFields(routeType string) []string {
	if routeType == "bus" {
		return []string{"SubRouteUID"}
	}
	return nil
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
