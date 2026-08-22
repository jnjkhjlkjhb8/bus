package predict

import "time"

// _delayDecayBase is the per-stop exponential decay applied to a vehicle's
// observed schedule delay as it propagates downstream: a delay of D seconds at
// the vehicle's latest observed stop contributes D * delayDecayBase^(seqGap) at
// a stop seqGap stops further along.
//
// a constant geometric rate regardless of route, hour, or traffic — enough to
// beat the bare-schedule fallback, not a traffic model. Upgrade path: learn a
// per-route (or per-route/hour) decay from bus_eta_prediction_error residuals,
// or weight the decay by running time once bus_segment_time is dense.
const _delayDecayBase = 0.9

// _propagationStaleAfter bounds how old an upstream observation may be to still
// describe the vehicle's current delay. Beyond this the vehicle may have
// recovered or fallen further behind, so the observation is dropped and the
// caller falls through to the model tier.
const _propagationStaleAfter = 3 * time.Minute

// UpstreamObs is one fresh observation of a specific vehicle (plate) at a stop
// on a sub_route/Direction: its position (StopSequence) and how far ahead or
// behind schedule it was there (delaySeconds, positive = late), as of observedAt.
type UpstreamObs struct {
	StopSequence int
	DelaySeconds float64
	ObservedAt   time.Time
}

// latestUpstreamDelay picks, from a vehicle's observations strictly upstream of
// a target stop, the one closest to that stop (largest StopSequence < targetSeq)
// that is still fresh relative to now. It returns the observation's delay, its
// stop sequence, and whether a usable observation was found.
//
// Observations at or past the target stop are ignored: they are not upstream, so
// they carry no forward delay to propagate. Stale observations (older than
// propagationStaleAfter) are skipped.
func latestUpstreamDelay(obs []UpstreamObs, targetSeq int, now time.Time) (delay float64, seq int, ok bool) {
	seq = -1
	for _, o := range obs {
		if o.StopSequence >= targetSeq {
			continue
		}
		if now.Sub(o.ObservedAt) > _propagationStaleAfter {
			continue
		}
		if o.StopSequence > seq {
			seq = o.StopSequence
			delay = o.DelaySeconds
			ok = true
		}
	}
	return delay, seq, ok
}

// decayDelay applies the per-stop exponential decay across a sequence gap. A
// zero or negative gap returns the delay unchanged (the observation is at or
// past the target, which callers should already have filtered out).
func decayDelay(delay float64, seqGap int) float64 {
	if seqGap <= 0 {
		return delay
	}
	factor := 1.0
	for range seqGap {
		factor *= _delayDecayBase
	}
	return delay * factor
}

// PropagateDelay returns a downstream stop's baseline arrival plus the decayed
// upstream delay of the same vehicle, and whether a fresh enough upstream
// observation existed to propagate. When no usable observation is found the
// caller should fall through to the next prediction tier (the XGBoost model).
func PropagateDelay(baseline time.Time, targetSeq int, obs []UpstreamObs, now time.Time) (time.Time, bool) {
	if baseline.IsZero() {
		return time.Time{}, false
	}
	delay, seq, ok := latestUpstreamDelay(obs, targetSeq, now)
	if !ok {
		return time.Time{}, false
	}
	decayed := decayDelay(delay, targetSeq-seq)
	return baseline.Add(time.Duration(decayed) * time.Second), true
}
