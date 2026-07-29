# History

VevDB provides immutable historical database values over the same datom model.

| Operation | Boundary | Result |
| --- | --- | --- |
| `as-of` | inclusive | state through a point in time |
| `since` | exclusive | current assertions added after a point in time |
| `history` | none | assertions and retractions |

A time point can be a basis `t`, transaction entity ID, or instant.

```clojure
(def current (d/db conn))
(def earlier (d/as-of current t))
(def recent (d/since current t))
(def audit (d/history current))
```

These functions return immutable database values. They do not change the
connection or source value.

Five-position data clauses expose transaction and assertion state:

```clojure
(d/q '[:find ?value ?tx ?added
       :where
       [?e :person/name ?value ?tx ?added]]
     audit)
```

## Database metadata

```clojure
(d/basis-t db)
(d/next-t db)
(d/as-of-t earlier)
(d/since-t recent)
(d/history? audit)
```

`basis-t` is the basis of the source database. `as-of-t` and `since-t` report
the filter boundary.

Convert between basis values and transaction entity IDs with `t->tx` and
`tx->t`.

## Transaction log

```clojure
(d/tx-range (d/log conn) start end)
```

The start is inclusive. The end is exclusive. Either bound may be `nil`.
Results have `{:t t :data datoms}` shape.

Durable stores keep history across close and reopen.

Run the Datomic comparison:

```sh
scripts/compare_history_time_filters.sh
```
