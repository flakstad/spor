# VevDB Naming

The product name is **VevDB**. Use that spelling in headings, prose, package
descriptions, release notes, websites, and other discovery-facing surfaces.
Do not spell the product name “Vev DB”.

“Vev” is Norwegian for a loom, weave, or interconnected fabric. VevDB keeps
that metaphor while distinguishing the database from unrelated products and
from occupied package names.

Compact technical identifiers remain appropriate where changing them would
make APIs noisier or break established ecosystem conventions:

| Surface | Name |
| --- | --- |
| Product | `VevDB` |
| CLI command | `vevdb` |
| CLI release archive | `vevdb-cli-<platform>-<version>` |
| Core repository | `github.com/vevdb/vev` |
| Clojure | `com.vevdb/vev-clj`, namespace `vev.core`; source at `vevdb/vev-clj` |
| Java | `com.vevdb:vev-java`, class `com.vevdb.vev.Vev`; source at `vevdb/vev-java` |
| Node.js | `@vevdb/vev` |
| Python | distribution and import `vevdb` |
| Rust | crate `vevdb` |
| C ABI | `libvev`, `vev.h`, and `vev_*` |
| Kvist | existing `vev` and `vev_app` packages |
| Store files | `.vev` |

The JVM group and Java package follow the project-owned `vevdb.com` domain.
The earlier `dev.vevdb` prerelease identifier was provisional and is not the
public Maven Central coordinate.

Source directories, internal variable names, and compatibility-oriented test
names do not need mechanical renaming merely to repeat the product name.
