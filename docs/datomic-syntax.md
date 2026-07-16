# Datomic Syntax Compatibility

## Goal

Pin down the Datomic/DataScript syntax that Vev should preserve at the
boundary so that existing tutorials, examples, and habits transfer with minimal
friction.

This document is about boundary syntax and user-visible semantics.
It does not require Vev to copy Datomic's internal implementation.

## Compatibility rule

Vev should preserve Datomic/DataScript syntax wherever practical for:

- transaction data
- transaction metadata
- query data
- pull patterns

Divergence should only happen when native embedding constraints or a simpler,
clearer engine boundary make it necessary.

## Transaction data

The official Datomic transaction reference describes transaction data as data,
not strings, with three main transaction forms:

- list forms
- map forms
- transaction functions

Current Vev supports the main Datomic/DataScript transaction shapes:

- list forms
- map forms
- built-in transaction functions such as `:db/cas`
- registered transaction functions called through `:db.fn/call` or ident shorthand

The remaining work is not a different transaction syntax; it is exact API
polish around diagnostics, host registration ergonomics, and any unported edge
cases from the upstream compatibility suites.

### Transaction list forms

These are the core transaction forms Vev should match first:

```clojure
[:db/add e a v]
[:db/retract e a v]
[:db/retract e a]
[:db/retractEntity e]
[:db.fn/retractAttribute e a]
[:db.fn/retractEntity e]
```

Important compatibility notes from Datomic:

- `:db/retract` may omit the value
- `:db/retractEntity` retracts the entity's current facts
- `:db.fn/retractAttribute` and `:db.fn/retractEntity` are supported aliases
- transaction data is authored as an ordered collection for convenience
- semantically it is still one atomic information set

### Entity identifiers in tx data

Datomic allows several ways to identify entities in transaction data. Vev
should aim to preserve this model:

- entity ids
- tempids
- lookup refs
- idents

Examples:

```clojure
[:db/add 42 :user/name "Anna"]
[:db/add "u1" :user/name "Anna"]
[:db/add [:user/email "anna@example.com"] :user/name "Anna"]
[:db/add :some/ident :flag/enabled true]
```

Current Vev supports numeric entity ids, string tempids, lookup refs, and
idents in list-form entity positions. Add/retract forms use the same entity
identifier surface. Repeated use of the same tempid in one transaction resolves
to the same entity and the transaction report exposes the resolved `tempids`
mapping. Lookup refs require a current `:db/unique` schema attr. Idents resolve
through current `:db/ident` facts.

For attrs declared with `:db/valueType :db.type/ref`, keyword ident values in
tx data resolve to entity refs:

```clojure
[:db/add 1 :user/friend :user/grace]
```

### Map forms

Map forms are part of the Datomic transaction surface and are supported by the
literal, text, prepared, and host-facing transaction APIs.

Examples:

```clojure
{:db/id 42
 :user/name "Anna"
 :user/email "anna@example.com"}
```

```clojure
{:db/id "u1"
 :user/name "Anna"}
```

Current Vev supports map forms in tx data with either an explicit `:db/id` in
any position or an auto-generated tempid. Explicit map `:db/id` values can be
entity ids, tempids, lookup refs, or idents:

```clojure
{:user/name "Anna"
 :user/email "anna@example.com"}
```

```clojure
{:db/id [:user/email "anna@example.com"]
 :user/name "Anna"}
```

Vector values in map forms expand to repeated facts for the same attr:

```clojure
{:db/id 42
 :user/tag ["engineer" "lisp"]}
```

Nested map values are supported with an explicit numeric, string, or ident
`:db/id`, or an auto-generated nested tempid. The parent map id can use the same entity id,
tempid, lookup-ref, or ident forms as other map ids:

```clojure
{:db/id 1
 :user/address {:db/id "address"
                :address/city "London"}}
```

```clojure
{:db/id 1
 :user/address {:address/city "London"}}
```

Generated map tempids are returned in the transaction report tempid mapping.

### Transaction metadata

Vev should follow Datomic's reified transaction model as closely as
practical.

The key Datomic convention is the reserved tempid:

```clojure
"datomic.tx"
```

This names the current transaction entity.

Example:

```clojure
[{:db/id "datomic.tx"
  :request/id "req-123"
  :tx/reason :profile-edit}
 [:db/add 42 :user/name "Anna"]]
```

This should be the default transaction-context model for Vev instead of
inventing a different metadata syntax.

Current Vev supports this shape: `"datomic.tx"`, `"datascript.tx"`, and
`:db/current-tx` resolve to the report transaction id. Facts targeting that
entity are ordinary datoms and are also mirrored into `tx-meta` entries for
report inspection.

## Query data

The official Datomic query reference defines queries as Datalog data.
Vev should preserve that boundary shape.

The core query shape is:

```clojure
[:find ...
 :with ...
 :in ...
 :where ...]
```

Vev's current compatibility target is that common Datomic/DataScript tutorial
queries should transfer through the EDN text/prepared API and, for Kvist
callers, through literal query macros.

### Query subset

The supported in-memory subset includes:

- `:find`
- scalar, tuple, collection, aggregate, pull, and return-map find specs
- `:with`
- `:in`
- `:where`
- data patterns
- predicate and function expressions over the supported built-ins
- scalar, collection, tuple, relation, relation-source, and named DB inputs
- `not` / `not-join`
- `or` / `or-join`
- `and` branches inside `or`
- rules, including recursive rules
- multi-source queries

### Query data patterns

Datomic data patterns have the general shape:

```clojure
[src-var? (variable | constant | '_')+]
```

The most common practical pattern is:

```clojure
[?e :attr ?v]
```

Attribute-existence shorthand is also accepted:

```clojure
[?e :attr]
```

Common variations are also supported:

```clojure
[?e :user/email "anna@example.com"]
[?e :user/email _]
```

### Remaining query work

Remaining query work is not broad syntax coverage. It is:

- exact parser object/diagnostic parity where Vev exposes parser APIs
- measured recursive-rule and large relation performance
- wrapper ergonomics for host languages

The important rule is:

- unsupported Datomic syntax should be documented as unsupported
- it should not be replaced with a Vev-specific query surface

## Pull patterns

The official Datomic pull reference defines pull patterns as EDN data.
Vev should preserve that surface.

### Pull pattern core grammar

The key Datomic pull shape is:

```clojure
[attr-spec+]
```

Where `attr-spec` can be:

- attribute name
- wildcard
- map spec
- attribute expression

### Pull subset

The supported in-memory subset includes:

- plain attribute names
- `:db/id`
- wildcard attrs
- nested map specs for refs
- reverse refs
- lookup refs and idents
- pull-many
- defaults, limits, aliases, recursion, component expansion, and named xforms

Examples:

```clojure
[:user/name :user/email]
```

```clojure
[:db/id :user/name]
```

```clojure
[:user/name {:user/friends [:user/name]}]
```

### Deferred pull features

These are part of Datomic pull and should remain syntax goals, but can be
deferred:

- recursion limits such as `{:person/friends 6}` or `{:person/friends ...}`
- richer attr options such as `:xform`

Again, the rule is to defer support, not invent different syntax.

## Internal representation

The compatibility rule applies at the boundary.
Inside Vev, parsed forms should become typed data structures:

- tx data -> typed transaction input
- query data -> typed query AST
- pull data -> typed pull AST

This is the intended split:

- Datomic-compatible syntax outside
- native typed structures inside

EDN `#inst` literals are first-class instant values rather than strings. Vev
also follows Datomic's reified transaction convention: every successful
transaction automatically asserts `[tx :db/txInstant instant]`, and explicit
import instants may target `"datomic.tx"` or `:db/current-tx`.

## First implementation priority

The implementation order should remain:

1. list-form tx data
2. tx metadata via `"datomic.tx"`
3. small query subset
4. small pull subset
5. map-form tx data
6. broader Datomic syntax surface

That keeps the first engine small while still locking in the right syntax
direction.

## Official references

This compatibility direction is based on the official Datomic references:

- Transaction data: https://docs.datomic.com/transactions/transaction-data-reference.html
- Transaction model: https://docs.datomic.com/transactions/model.html
- Query data reference: https://docs.datomic.com/query/query-data-reference.html
- Pull reference: https://docs.datomic.com/query/query-pull.html
