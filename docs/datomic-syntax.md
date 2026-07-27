# Datomic and DataScript compatibility

VevDB uses Datomic and DataScript syntax where it fits an embedded native
database. Compatibility is behavioral, not binary.

## Supported

- datoms and immutable database values
- map and operation-vector transactions
- schema, tempids, lookup refs, upserts, tuples, and transaction metadata
- `db-with`
- vector and map Datalog queries
- query inputs, predicates, functions, aggregates, rules, negation, and
  disjunction
- pull and entity reads
- EAVT, AEVT, AVET, and VAET reads
- `as-of`, `since`, `history`, and transaction logs

EDN text is the portable boundary. Clojure accepts ordinary Clojure data.
Other packages may provide native value wrappers.

## Different

- VevDB is embedded. It has no Datomic transactor or peer protocol.
- Durable stores are local VevDB files.
- VevDB does not run or persist Datomic stored functions.
- Native callback transaction functions are process-local extensions.
- Error text and parser representation are VevDB-specific.
- Package APIs reflect host-language ownership and type systems.

Do not assume an unlisted Datomic API is available. Check the relevant package
repository or the [C header](../include/vev.h).

The executable compatibility suite is the source of truth:

```sh
scripts/contact_book.sh
scripts/compare_history_time_filters.sh
scripts/compare_aggregates_tutorial.sh
scripts/compare_musicbrainz_workshop.sh
```
