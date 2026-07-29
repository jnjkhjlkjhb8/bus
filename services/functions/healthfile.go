package main

import (
	"os"
	"time"
)

// healthFilePath is the liveness marker addStaticCron touches after every
// cron job returns and each cron.Start() call touches once at boot. HEALTH_FILE
// overrides the default so tests don't share a fixed path with a real
// deployment; the default matches the tmpfs every role's compose service
// already mounts at /tmp (docker/docker-compose.yaml).
var healthFilePath = func() string {
	if p := os.Getenv("HEALTH_FILE"); p != "" {
		return p
	}
	return "/tmp/healthy"
}()

func touchHealthFile() {
	now := time.Now()
	if err := os.Chtimes(healthFilePath, now, now); err == nil {
		return
	}
	f, err := os.Create(healthFilePath)
	if err != nil {
		log.Warnf("[HEALTH] action=touch event=failed path=%s error=%v", healthFilePath, err)
		return
	}
	_ = f.Close()
}
