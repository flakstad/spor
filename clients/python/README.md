# Vev Python

This is a pure `ctypes` client over Vev's C ABI.

Current local development:

```sh
scripts/build_c_abi.sh
python3 clients/python/smoke.py
```

The adapter loads the native library in this order:

- explicit path passed to `vev.Library`
- `VEV_LIB`
- local repo `build/lib/<platform-library-name>`
- future bundled `native/<platform>/<platform-library-name>` package resource

The bundled-resource path mirrors the JVM native artifact layout and is intended
for future wheels.

`scripts/smoke_python_package.sh` verifies that future shape by checking the
package metadata, copying `vev.py` and the platform native library to a
temporary package-like directory, and importing it without `VEV_LIB`.

Planned package shape:

- a small Python package under the `vev` import name
- project metadata in `clients/python/pyproject.toml` for the future `vev`
  wheel
- explicit native library path support for local development and embedding
- later bundled platform wheels if the API stabilizes enough to justify them

Basic usage:

```python
import vev

with vev.create_conn() as conn:
    conn.transact('[{:db/id 1 :user/name "Ada"}]')
    with conn.db() as db:
        print(vev.q('[:find ?name :where [?e :user/name ?name]]', db))
        print(db.pull('[:user/name]', vev.Entity(1)))

with vev.connect("app.vev") as conn:
    conn.transact('[{:db/id 1 :user/name "Durable Ada"}]')
    print(vev.q('[:find ?name :where [?e :user/name ?name]]', conn))
```

`conn.query_text(...)` remains available as a convenience, but the DB-snapshot
shape is the closer match to Datomic/DataScript's immutable database values.
Use `conn.prepare(...)` when reusing the same query many times.

Typed builders can be committed in one durable bulk transaction when callers
want one SQLite commit and one tx id for several prepared builder groups:

```python
with vev.connect("app.vev") as conn:
    with vev.tx_builder(1) as first, vev.tx_builder(1) as second:
        first.add_string(1, ":user/name", "Ada")
        second.add_string(2, ":user/name", "Grace")
        report = conn.transact_bulk([first, second])
```

For an explicit native library path, use a library instance:

```python
lib = vev.Library("/path/to/libvev.dylib")
with lib.create_conn() as conn:
    ...
```

Parser tooling can inspect a single where clause with
`vev.parse_clause_edn('[?e :user/name ?name]')`.

Reusable pull patterns are prepared once and used through the same DB API:

```python
with vev.prepare_pull_pattern("[:user/name]") as pattern:
    pull = db.pull(pattern, vev.Entity(1))
    many = db.pull_many(pattern, [vev.Entity(1), vev.Entity(2)])
```

DB snapshots can also produce entity views. The view is tied to the immutable
DB value, not the live connection:

```python
with conn.db() as db:
    with db.entity(1) as ada:
        print(ada[":user/name"])
        print(ada.values(":user/email"))
        print(ada.touch())

    with db.entity_lookup_ref(":user/email", "ada@example.com") as ada:
        print(ada.id)
```

`open_memory()` remains as a compatibility alias for `create_conn()`.

The current API already wraps native handles with context managers for
connections, DB snapshots, entity views, prepared queries, prepared pull patterns,
statements, transaction reports, and durable Vev connections.

Durable stores are opened through Vev APIs with paths such as `app.vev`. The
Python package loads `libvev`, whose release build includes SQLite with FTS5.
Python application code does not install or configure SQLite.
