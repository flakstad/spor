# Historical database values

Vev implements Datomic-shaped `as-of`, `since`, and `history` database
filters. They return immutable database values: creating a historical view
does not mutate the connection or the source database.

The compatibility target is the Datomic Peer API:

| Operation | Boundary | Visible datoms |
| --- | --- | --- |
| `as-of` | Inclusive | Database state through the time point |
| `since` | Exclusive | Current assertions added after the time point |
| `history` | None | Assertions and retractions |

A time point may be a basis `t`, transaction entity id, or instant. In
Clojure, Vev accepts the same `java.util.Date` values produced by `#inst` that
Datomic accepts. Vev additionally accepts `java.time.Instant`.

```clojure
(require '[vev.core :as d])

(def now-db (d/db conn))
(def tx-db (d/as-of now-db tx))
(def date-db (d/as-of now-db #inst "2026-07-20T10:15:00.000Z"))
(def recent-db (d/since now-db #inst "2026-07-20T10:15:00.000Z"))
(def audit-db (d/history now-db))
```

## Datomic and Vev side by side

The Clojure names and argument order are identical:

```clojure
(require '[datomic.api :as datomic]
         '[vev.core :as vev])

;; Inclusive transaction boundary
(datomic/as-of datomic-db datomic-t)
(vev/as-of     vev-db     vev-tx)

;; Inclusive native date boundary; #inst is java.util.Date
(datomic/as-of datomic-db #inst "2026-07-20T10:15:00.000Z")
(vev/as-of     vev-db     #inst "2026-07-20T10:15:00.000Z")

;; Exclusive native date boundary
(datomic/since datomic-db #inst "2026-07-20T10:15:00.000Z")
(vev/since     vev-db     #inst "2026-07-20T10:15:00.000Z")

;; Assertions and retractions
(datomic/history datomic-db)
(vev/history     vev-db)
```

The executable example
[history_time_filters.clj](../examples/clojure/history_time_filters.clj)
creates equivalent databases in Datomic Peer and Vev, supplies the same
explicit `:db/txInstant` values, and asserts equal query results. Run it with:

```sh
scripts/compare_history_time_filters.sh
```

It checks transaction and native-date boundaries, an instant exactly at a
transaction, an instant between transactions, points before and after the
available history, history rows, and composed `history(as-of(db, instant))`
views. The comparison is pinned to Datomic Peer `1.0.7277` by default; set
`DATOMIC_VERSION` to exercise another Peer release.

## Instant resolution

Vev stores an instant on every transaction as `:db/txInstant`. An instant time
point resolves to the greatest transaction whose instant is less than or equal
to the supplied instant:

- before the first transaction resolves before all user data;
- exactly at a transaction includes it in `as-of` and excludes it from
  `since`;
- between transactions resolves to the earlier transaction;
- after the latest transaction resolves to the latest transaction.

Explicit `:db/txInstant` values must be monotonic and may not be later than the
wall clock. These constraints make the mapping deterministic. Host APIs use
millisecond precision, matching Vev's stored instant representation.

## Querying history

A five-position data clause has Datomic's `[e a v tx added]` shape. The fifth
value is a boolean, not a transaction-operation keyword:

```clojure
(d/q
  '[:find ?value ?tx ?added
    :where [?e :item/count ?value ?tx ?added]]
  (d/history db))
;; => #{[100 tx-1 true] [100 tx-2 false] [250 tx-2 true]}
```

`history` is a query database, not a current entity database. Entity views and
transactions against a history value are rejected. Use the ordinary database
or an `as-of` database when entity semantics are required.

## Composition

Filters compose as database values:

```clojure
(d/history (d/as-of db time-point))
(d/since (d/as-of db upper-bound) lower-bound)
```

Repeated `as-of` uses the earliest upper bound; repeated `since` uses the
latest lower bound. As in Datomic, combining `db-with` and `as-of` retains the
`as-of` boundary regardless of call order: it behaves as `with` followed by
`as-of`, not as an independent alternate timeline.

When lookup refs are used with `since`, remember that the identity assertion
may precede the lower bound. Resolve the entity against an unfiltered/current
database and pass it as an input when necessary.

## Other language APIs

| Language | Transaction coordinate | Native time point |
| --- | --- | --- |
| Kvist | `d.as-of db t`, `d.since db t` | The same functions with tagged `Data` read from `#inst` EDN |
| Java | `db.asOf(long)`, `db.since(long)` (`t` or tx id) | `Date` or `Instant` overloads |
| Python | `db.as_of(int)`, `db.since(int)` | `datetime` |
| JavaScript | `db.asOf(number\|bigint)`, `db.since(...)` | `Date` |
| Go | `db.AsOf(uint64)`, `db.Since(uint64)` | `AsOfTime(time.Time)`, `SinceTime(time.Time)` |
| Rust | `as_of(u64)`, `since(u64)` | `as_of_time(SystemTime)`, `since_time(SystemTime)` |
| C | `vev_db_as_of`, `vev_db_since` | `vev_db_*_instant_millis` |

All returned DB handles are independently owned and should be closed or
released according to the host binding.

Kvist uses the same overloaded names. Its EDN tagged values are represented as
`Data`, so a native instant can be constructed directly or read from EDN:

```clojure
(import data "kvist:data")
(import d "vev_app")

(defn inst [text: string] -> Data
  (data.tagged "inst" (data.from-string text)))

(let [earlier (d.as-of db (inst "2026-07-20T10:15:00.000Z"))
      recent (d.since db (inst "2026-07-20T10:15:00.000Z"))]
  ;; use the immutable DB values
  (d.close earlier)
  (d.close recent))
```

## Compatibility references

The behavior here follows Datomic's
[database filters reference](https://docs.datomic.com/reference/filters.html)
and
[Database API contract](https://docs.datomic.com/javadoc/datomic/Database.html).
Vev accepts its basis `t` values and transaction entity ids as transaction
coordinates; Datomic-specific entity-id encoding and Clojure-only protocols
are not copied.
