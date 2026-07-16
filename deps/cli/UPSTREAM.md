# Kvist CLI Dependency

This directory vendors [`kvist-lang/cli`](https://github.com/kvist-lang/cli)
at commit `847c0a2d820628b3b58c82acbd4dded79ec64882`.

Kvist source dependencies are ordinary source directories imported by relative
path. Keeping the small CLI package in the Vev tree makes repository builds and
source releases independent of a package registry or an implicit compiler
package search path.
