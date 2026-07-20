# Pull Model

## Goal

Define how Vev should support Datomic/DataScript-style pull without
inventing a new surface syntax.

The exact syntax compatibility target is summarized in
[docs/datomic-syntax.md](datomic-syntax.md).

The main rule is:

- pull syntax at the boundary should stay as close as practical to
  Datomic/DataScript pull patterns
- internal representation can be plain typed data structures

## Why pull matters

Pull is one of the most useful parts of the Datomic/DataScript user model.

It gives callers:

- attribute-oriented entity reads
- nested traversal for refs
- a stable, tutorial-friendly way to ask for shaped data

For Vev, the biggest value is not novelty. It is compatibility:

- existing examples should transfer
- application code should not need a custom Vev-only pull dialect
- future JVM/Clojure interop becomes easier

## Canonical boundary syntax

The canonical external pull syntax should be Datomic/DataScript-style pull
data.

Examples:

```clojure
[:user/name :user/email]
```

```clojure
[:user/name {:user/friends [:user/name]}]
```

```clojure
[:db/id :user/name]
```

These should be understood as boundary syntax goals even if phase 1/2 supports
only a subset at first.

## Native API stance

As with queries, plain text is acceptable at the boundary, but it should not
be the engine's only internal representation.

Recommended split:

- external pull syntax: text
- parsed pull pattern: typed structure
- execution API: parsed pull pattern
- convenience API: parse-and-run helper

Conceptually:

```text
parse_pull(text) -> Pull_Pattern
pull(db, pattern, eid) -> Value
pull_text(db, text, eid) -> Value
```

`pull_text` is convenience.
`pull` with a parsed pattern should be the core path.

## Supported Subset

The current in-memory pull surface covers the common Datomic/DataScript tutorial
shape plus the main DataScript pull API semantics:

- plain attribute names
- `:db/id`
- one entity id, lookup ref, or ident at a time
- wildcard attrs
- nested ref maps
- reverse refs
- pull-many
- defaults, aliases, limits, recursion, component expansion, and named xforms

Current Kvist proof:

```clojure
(v.pull db [:db/id :user/name :user/email] 1)
```

```clojure
(v.pull db [:db/id :user/name] [:user/email "ada@example.com"])
```

```clojure
(v.pull db [:db/id :user/name] :user/ada)
```

Attribute option vectors support `:default`:

```clojure
(v.pull db [[:user/nickname :default "Unknown"]] 1)
```

And `:as`, either alone or combined with `:default`:

```clojure
(v.pull db [[:user/name :as :name]] 1)
```

```clojure
(v.pull db [[:user/nickname :default "Unknown" :as :nickname]] 1)
```

The `:as` and `:default` options can appear in either order.

Attribute option vectors also support `:limit` for capping multivalued attrs:

```clojure
(v.pull db [[:user/friend :limit 2]] 1)
```

`:limit` can be combined with `:as` in either order.

It also supports reverse ref attrs in the Datomic style:

```clojure
(v.pull db [:_user/friend] 2)
```

And one-level nested ref maps:

```clojure
(v.pull db [{:user/friend [:user/name]}] 1)
```

Maps can contain multiple nested ref entries:

```clojure
(v.pull db [{:user/friend [:user/name]
             :user/manager [:user/name]}] 1)
```

Forward nested refs can use `:limit` to cap cardinality-many attrs:

```clojure
(v.pull db [{:user/friend [:user/name :limit 2]}] 1)
```

The limited child pattern can include multiple attrs:

```clojure
(v.pull db [{:user/friend [:db/id :user/name :limit 2]}] 1)
```

Nested reverse refs can use `:limit` to cap fan-out:

```clojure
(v.pull db [{:_user/friend [:user/name :limit 2]}] 2)
```

And wildcard attrs for `:db/id` plus current forward attrs:

```clojure
(v.pull db [*] 1)
```

Use `pull-many` for the same pattern over multiple entity ids:

```clojure
(v.pull-many db [:db/id :user/name] ([]u64 [1 2]))
```

Remaining pull work is exact edge rendering and host API shape, not the basic
pull model.

The host API now has reusable prepared pull-pattern values for single pull and
pull-many. Clojure/Java/C callers can prepare a Datomic-shaped pull pattern
once, reuse it across immutable DB snapshots, and use the same API for direct
entity ids or same-attribute UUID lookup-ref batches.

## Pull semantics

Pull should:

- operate on immutable DB snapshots
- read by entity id
- respect schema/cardinality rules
- return nested data shaped by the pattern

The engine does not need to clone every DataScript implementation trick.
It does need to preserve the user-facing meaning.

## Entity API relationship

Pull and entities are complementary parts of the Datomic Peer model.

- `entity` provides a lazy, immutable, associative view for incremental and
  interactive navigation.
- `pull` and `pull-many` explicitly select and shape a hierarchy.
- both remain tied to one immutable DB value, including navigation through
  refs
- `touch` realizes all direct attributes and recursively realizes component
  entities

The entity API is therefore a first-class public API, not a secondary wrapper.
The Clojure representation should behave like ordinary keyword/map access while
retaining laziness and the entity's DB basis.

## Compatibility rule

Any pull divergence should be treated as costly.

Preferred approach:

- keep the Datomic/DataScript syntax
- document unsupported forms as unsupported
- only introduce syntax differences when there is a concrete embedding or
  implementation reason

The project should not create a Vev-specific pull language just because Kvist
makes a different surface easy to invent.
