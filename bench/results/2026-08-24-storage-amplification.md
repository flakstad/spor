# Durable storage amplification — 2026-08-24

Local macOS measurements against the deterministic 1,000-assertion workload.
The baseline is VevDB `17a91713` (0.3.0). Each transaction in the after column
is an independent committed SQLite transaction. Sizes are measured after a WAL
checkpoint; timings include one CLI process and every commit.

| Shape | Before bytes | After bytes | Reduction | Before roots / manifests / chunks / attr-ranges | After | Before tx time | After tx time |
| --- | ---: | ---: | ---: | --- | --- | ---: | ---: |
| 1×1000 | 598,016 | 598,016 | 0.0% | 1 / 0 / 36 / 0 | 1 / 0 / 36 / 0 | 0.126 s | 0.089 s |
| 10×100 | 815,104 | 577,536 | 29.1% | 10 / 36 / 40 / 36 | 1 / 0 / 4 / 0 | 0.148 s | 0.107 s |
| 100×10 | 1,196,032 | 638,976 | 46.6% | 100 / 396 / 400 / 396 | 1 / 0 / 4 / 0 | 1.144 s | 0.971 s |
| 500×2 | 2,539,520 | 921,600 | 63.7% | 500 / 1,996 / 2,000 / 1,996 | 1 / 0 / 44 / 0 | 18.789 s | 1.353 s |
| 1000×1 | 4,247,552 | 1,277,952 | 69.9% | 1,000 / 3,996 / 4,000 / 3,996 | 1 / 0 / 64 / 0 | 73.157 s | 2.955 s |

`attr-ranges` is `vev_index_run_manifest_attr_ranges`; entity/attribute range
rows also remain zero. The remaining growth from 598 KiB to 1.278 MiB in the
1,000-transaction case is predominantly the
required transaction rows, `:db/txInstant` datoms, transaction metadata, and
their ordinary SQLite indexes—not retained historical chunk roots.

Median process-level open/query latency after the change stayed between
7.5–49.6 ms and 17.2–31.0 ms respectively. The checked-in JSON budget uses
wider limits for machine variation. The largest retained novelty was 115
transactions; all five shapes stayed below the 128-transaction/4,096-datom
checkpoint budget.

## Cause and trade-off

Each post-bootstrap transaction appended four chunk runs and four manifests.
The manifests shared parents, but each generation also stored run and range
metadata, and every immutable root kept the complete derived generation
reachable. The number of stored rows was linear in transactions while walking
successive parent chains made the bulk transaction path increasingly costly.
Logical compaction published a new shallow root but did not delete the old
generations or return pages to the file.

The replacement writes each commit to the canonical log and exposes the head
as the latest broad checkpoint plus a bounded novelty tail. At 128 novelty
transactions or 4,096 novelty datoms it publishes one new B-tree-like chunk
checkpoint and reclaims obsolete derived rows. Automatic commits do not run
`VACUUM`; explicit `reclaim-indexes` is the filesystem-truncating operation.
This preserves every logical transaction and immutable basis while removing
the per-transaction root/manifest/range multiplier.
