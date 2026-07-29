# Transactions

Transactions accept the familiar entity-map and operation-vector data forms.

```clojure
[{:db/id -1
  :person/name "Ada"
  :person/email "ada@example.com"}
 [:db/add -1 :person/active true]]
```

Supported operations include:

```clojure
[:db/add entity attribute value]
[:db/retract entity attribute value]
[:db/retract entity attribute]
[:db/retractEntity entity]
[:db.fn/retractAttribute entity attribute]
[:db.fn/cas entity attribute old-value new-value]
```

Map transactions support tempids, lookup refs, nested component maps, reverse
attributes, upserts, and cardinality-many values.

## Reports

A successful transaction returns:

- the database value before the transaction
- the database value after the transaction
- committed datoms
- resolved tempids
- the transaction ID

Every transaction has a `:db/txInstant` fact. Metadata added to
`:db/current-tx` is stored on the same transaction entity.

```clojure
[{:db/id :db/current-tx
  :audit/user 42}
 {:db/id 1
  :person/name "Ada"}]
```

Failed transactions do not change the connection or notify listeners.

## Hypothetical transactions

`db-with` returns a new database value without changing its source:

```clojure
(def source (d/db conn))
(def changed
  (d/db-with source
    [[:db/add 1 :person/name "Ada"]]))
```

`source` and `conn` are unchanged.

## Transaction functions

The native API can register process-local callbacks that return transaction
data. These callbacks are embedding hooks, not Datomic stored functions.
VevDB does not persist host code.

See [History](history.md) for transaction time and log APIs.
