# Data model

## Datoms

VevDB stores facts as datoms:

```text
entity attribute value transaction added?
```

- `entity` is a stable integer ID.
- `attribute` is a keyword.
- `value` is a scalar or tuple.
- `transaction` identifies the transaction.
- `added?` distinguishes assertions from retractions in history.

Current state is the set of assertions not later retracted.

## Database values

A database value is an immutable snapshot. Reads take a database value, not a
live connection.

```clojure
(def before (d/db conn))
(d/transact conn [{:db/id 1 :person/name "Ada"}])
(def after (d/db conn))
```

`before` does not change when the transaction commits.

A connection owns the current database value and serializes writes. `db-with`
applies a transaction to a database value without changing a connection.

## Values

Stored values include:

- strings
- integers and floats
- booleans
- keywords and symbols
- references
- instants
- UUIDs
- tuples

Maps and sets structure transactions and query inputs. They are not stored as
datom values. Cardinality-many collections become separate datoms.

## Schema

Schema is stored as datoms on entities with `:db/ident`.

Supported schema properties include:

- `:db/valueType`
- `:db/cardinality`
- `:db/unique`
- `:db/isComponent`
- tuple attributes

Example:

```clojure
{:db/ident :person/email
 :db/valueType :db.type/string
 :db/cardinality :db.cardinality/one
 :db/unique :db.unique/identity}
```

VevDB also accepts schemaless attributes.

## Indexes

Database values expose four datom indexes:

- EAVT: entity, attribute, value, transaction
- AEVT: attribute, entity, value, transaction
- AVET: attribute, value, entity, transaction
- VAET: reference value, attribute, entity, transaction

The public APIs include `datoms`, `seek-datoms`, `rseek-datoms`, and
`index-range`.

See [Transactions](transactions.md), [Queries and pull](query-model.md), and
[History](history.md).
