-- Clear bus ETA training data polluted by the etamap cross-route bug.
--
-- Before the fix, bus_eta.go keyed live TDX ETAs on StopUID alone. TDX returns
-- one ETA per (stop x subroute x direction), so at multi-route stops entries
-- overwrote each other and every route recorded a random other route's arrival.
-- Every history row, travel average, and prediction-error sample gathered under
-- that bug is cross-contaminated, so the tables are truncated once the fix
-- deploys and clean data starts accumulating.
TRUNCATE bus_eta_history;
TRUNCATE bus_travel_avg;
TRUNCATE bus_eta_prediction_error;
