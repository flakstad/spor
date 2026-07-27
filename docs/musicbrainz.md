# MusicBrainz validation

The MusicBrainz workflow runs Datomic tutorial queries against a durable VevDB
store from Clojure and Kvist.

## Requirements

- the [source-build tools](building.md)
- JDK 25 or newer
- Clojure CLI

## Setup

Create the store and run both host suites:

```sh
scripts/musicbrainz_workshop_setup.sh --validate
```

The script fetches pinned tutorial sources under `build/upstream`.

If portable export chunks are missing, create them from a local Datomic Pro
installation:

```sh
DATOMIC_HOME=/path/to/datomic-pro \
  scripts/musicbrainz_workshop_setup.sh --from-datomic --validate
```

Ordinary VevDB validation does not require Datomic. `--from-datomic` uses a
local Datomic installation to read the backup and create the export.

Override the data and store paths:

```sh
VEV_MUSICBRAINZ_EXPORT_PREFIX=/path/to/export-prefix \
VEV_MUSICBRAINZ_STORE=/path/to/musicbrainz.db \
  scripts/musicbrainz_workshop_setup.sh --validate
```

## Individual suites

```sh
scripts/musicbrainz_workshop_clojure.sh
scripts/musicbrainz_workshop_kvist.sh
```

## Datomic comparison

The optional comparison requires a local Datomic Pro installation:

```sh
scripts/musicbrainz_sample.sh prepare
scripts/compare_musicbrainz_workshop.sh
```

For VevDB-only row and fingerprint checks:

```sh
scripts/compare_musicbrainz_workshop.sh --skip-datomic
```

Use `scripts/compare_musicbrainz_workshop.sh --help` for workload and timing
options.

The comparison checks row counts and portable result fingerprints. It is a
compatibility and regression test, not a published benchmark.
