# Queries and pull

## Datalog

Queries are data and take explicit inputs:

```clojure
(d/q '[:find ?name
       :in $ ?active
       :where
       [?e :person/active ?active]
       [?e :person/name ?name]]
     db
     true)
```

Supported query features include:

- relation, collection, tuple, and scalar `:find`
- database and value inputs
- data, predicate, and function clauses
- `not`, `not-join`, `or`, and `or-join`
- aggregates
- rules, including recursive rules
- pull expressions in `:find`
- `:with` and return maps

The EDN frontend accepts vector and map query forms. Native APIs also provide
prepared queries and typed result access.

## Pull

Pull returns selected attributes for one or more entities:

```clojure
(d/pull db
  [:person/name
   {:person/friends [:person/name]}]
  person-id)
```

Supported patterns include:

- attribute keywords
- wildcard `*`
- nested joins
- reverse attributes
- recursion limits
- `:as`, `:default`, `:limit`, and `:xform`
- lookup refs

## Entity reads

Entity views provide lazy attribute lookup against one immutable database
value. Reference attributes can be followed without reading from the live
connection.

Use pull when the result shape is known. Use entity views for incremental
navigation.

## Index reads

Use `datoms`, `seek-datoms`, `rseek-datoms`, or `index-range` when index order
is part of the operation. See [Data model](data-model.md#indexes).

Exact function names and result types vary by package. See the package
repository for the host language.
