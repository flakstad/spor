# VevDB for Python

**Status: in progress. Not published.**

This `ctypes` integration test will move to a standalone `vevdb` package
repository.

```sh
scripts/build_c_abi.sh
python3 clients/python/smoke.py
```

Example:

```python
import vevdb

with vevdb.create_conn() as conn:
    conn.transact('[{:db/id 1 :user/name "Ada"}]')
    with conn.db() as db:
        print(vevdb.q(
            '[:find ?name :where [?e :user/name ?name]]', db))
```

`vevdb.Library(path)` selects an explicit native library. `VEV_LIB` provides
the same override for tests.

Native handles are wrapped by context managers. SQLite is included in the
VevDB library.
