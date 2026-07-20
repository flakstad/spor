# Client API Contract

VevDB clients follow Datomic semantics at their primary public boundary.
Host-language conventions may affect capitalization, error handling, and
resource management, but not the database model or query result shape.

## Primary query

- The primary operation is named `q` or `query`.
- It accepts an immutable DB value; accepting a connection as a convenience is
  allowed when the client takes a fresh snapshot for the call.
- In-memory and durable storage use the same operation.
- Query inputs are values, or an EDN encoding where the host wrapper has not
  yet exposed typed inputs.
- The result follows `:find`:

| Find form | Result |
| --- | --- |
| `:find ?x ?y` | set of tuple values |
| `:find [?x ...]` | collection |
| `:find [?x ?y]` | tuple or nil |
| `:find ?x .` | scalar or nil |

Return maps produce maps inside the relation or collection selected by the
find form.

The host representations are the natural equivalents: Clojure sets/vectors,
Java `Set`/`List`, JavaScript `Set`/arrays, Python sets/tuples/lists, and the
corresponding tagged value variants in Go, Rust, and Odin.

## Advanced query APIs

Prepared statements, row handles, column batches, visitors, streaming, and
profiling are valid lower-level facilities. Their names must make that
distinction explicit; their row-oriented implementation must not leak into the
primary `q`/`query` API.

The C ABI intentionally retains these primitives because it is the portability
and performance layer. Host clients should use the owned shaped-query value
functions for their primary API and the result-handle functions for advanced
prepared or streaming work.
