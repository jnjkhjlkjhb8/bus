package main

import "testing"

// TestDatasetRegistryConsistency is the guard that replaces the three
// hand-synchronized lists: it proves the fetch list, the reverse target map, the
// whitelist, and the loader registry all agree because they derive from one
// datasetRegistry.
func TestDatasetRegistryConsistency(t *testing.T) {
	reg := datasetRegistry()

	// Every fetched table is consumed: it has a standalone loader, is folded into
	// another dataset's multi-table loader, or is an exportOnly table the GTFS
	// feed builder reads straight out of raw_tdx. A fetched table in none of
	// those categories would silently waste a nightly request.
	for _, d := range reg {
		if d.fetched() && d.loadKey == "" && d.foldedInto == "" && !d.exportOnly {
			t.Errorf("fetched dataset %q has neither a loader, foldedInto, nor exportOnly", d.rawTable)
		}
	}

	// exportOnly is the absence of a loader, not an alternative spelling of one:
	// a table carrying both would be loaded and silently ignored by this file's
	// other invariants.
	for _, d := range reg {
		if d.exportOnly && (d.loadKey != "" || d.foldedInto != "") {
			t.Errorf("exportOnly dataset %q also has loadKey %q / foldedInto %q",
				d.rawTable, d.loadKey, d.foldedInto)
		}
	}

	// Every standalone loader reads a fetched table (loaders never load unlanded
	// data), and its load partitions are a subset of what is landed.
	for _, d := range reg {
		if d.loadKey == "" {
			continue
		}
		if !d.fetched() {
			t.Errorf("loader dataset %q (loadKey %q) is not fetched", d.rawTable, d.loadKey)
		}
		land := map[string]bool{}
		for _, p := range d.partitions() {
			land[p] = true
		}
		for _, p := range d.loadPartitions() {
			if !land[p] {
				t.Errorf("dataset %q loads partition %q that is not landed", d.rawTable, p)
			}
		}
	}

	// Every foldedInto target names a real standalone loader.
	loadKeys := map[string]bool{}
	for _, d := range reg {
		if d.loadKey != "" {
			loadKeys[d.loadKey] = true
		}
	}
	for _, d := range reg {
		if d.foldedInto != "" && !loadKeys[d.foldedInto] {
			t.Errorf("dataset %q folds into unknown loader %q", d.rawTable, d.foldedInto)
		}
	}

	// loaderTransforms and datasetRegistry loadKeys are in exact correspondence:
	// no orphan binding, no dataset loadKey without a transform.
	transforms := loaderTransforms(nil)
	for k := range loadKeys {
		if _, ok := transforms[k]; !ok {
			t.Errorf("dataset loadKey %q has no loaderTransforms binding", k)
		}
	}
	for k := range transforms {
		if !loadKeys[k] {
			t.Errorf("loaderTransforms key %q has no datasetRegistry loadKey", k)
		}
	}

	// The whitelist is exactly the set of registry tables.
	for _, d := range reg {
		if !rawTDXTables[d.rawTable] {
			t.Errorf("registry table %q missing from whitelist", d.rawTable)
		}
	}
	if len(rawTDXTables) != len(reg) {
		t.Errorf("whitelist has %d tables, registry has %d", len(rawTDXTables), len(reg))
	}
}

// TestLoaderRegistryFoldsOperatorsIntoAtomicBusSnapshot asserts there is only
// one target writer for correlated bus static data. The raw operator dataset is
// still fetched, but it must not get a standalone loader transaction.
func TestLoaderRegistryFoldsOperatorsIntoAtomicBusSnapshot(t *testing.T) {
	for _, spec := range loaderRegistry(nil) {
		if spec.key == "bus_operator" {
			t.Fatal("bus_operator still has a standalone loader transaction")
		}
	}
	for _, dataset := range datasetRegistry() {
		if dataset.rawTable == "bus_operator" {
			if dataset.loadKey != "" || dataset.foldedInto != "bus" {
				t.Fatalf("bus_operator loadKey/foldedInto = %q/%q, want empty/bus", dataset.loadKey, dataset.foldedInto)
			}
			return
		}
	}
	t.Fatal("bus_operator dataset missing")
}

// TestFetchURLsRoundTripToTargets proves the fetch list and the reverse target
// map agree: every landing URL the ingestor builds resolves back through
// rawDumpTarget to the same table, partition column, and partition value.
func TestFetchURLsRoundTripToTargets(t *testing.T) {
	for _, d := range datasetRegistry() {
		if !d.fetched() {
			continue
		}
		for _, part := range d.partitions() {
			url := d.url(part)
			table, partCol, partVal, ok := rawDumpTarget(url)
			if !ok {
				t.Errorf("%s: rawDumpTarget did not resolve fetched URL", url)
				continue
			}
			if table != d.rawTable || partCol != d.partCol || partVal != part {
				t.Errorf("%s: got (%q,%q,%q), want (%q,%q,%q)",
					url, table, partCol, partVal, d.rawTable, d.partCol, part)
			}
		}
	}
}

// TestBusDatasetsCoverIngestBusAPIs keeps ingestBusAPIs (still used by the
// ingestor fan-out test) in step with the registry's bus datasets.
func TestBusDatasetsCoverIngestBusAPIs(t *testing.T) {
	got := map[string]bool{}
	for _, d := range datasetRegistry() {
		if d.family == familyBusCity {
			got[d.apiSeg] = true
		}
	}
	if len(got) != len(ingestBusAPIs) {
		t.Fatalf("bus datasets = %d apiSegs, ingestBusAPIs = %d", len(got), len(ingestBusAPIs))
	}
	for _, api := range ingestBusAPIs {
		if !got[api] {
			t.Errorf("ingestBusAPIs entry %q has no bus dataset", api)
		}
	}
}
