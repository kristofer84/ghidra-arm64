# Headless Ghidra that actually decompiles on arm64

Ghidra's release zip ships decompiler natives for **`linux_x86_64` and `win_x86_64` only**.
On arm64 the Java side runs perfectly - import, auto-analysis and scripting all work - and
then every single decompile fails, because the decompiler is a **separate native C++
process**, not Java. It reads like "Ghidra doesn't work here". This repository is the fix.

Grab the image:

```bash
docker pull ghcr.io/kristofer84/ghidra-arm64:12.1.3
```

Or build it yourself (~15 min the first time, mostly a 543 MB download):

```bash
./build.sh                    # -> ghidra:arm64
GHIDRA_VER=12.2 ./build.sh    # a different release
```

## How it works

`build.sh` is two stages:

1. a base image with a JDK and the official Ghidra release;
2. the C++ decompiler, built from the **source tag matching that release** and layered in at
   `os/linux_arm_64/decompile`.

Two traps make this less obvious than it sounds:

* **The release zip does not contain the decompiler source** and has no `buildNatives`
  script. You need a sparse, shallow checkout of the `ghidra` repository at the matching
  tag, taking only `Ghidra/Features/Decompiler/src/decompile/`, which is small.
* **The decompiler Makefile only knows x86.** `ARCH_TYPE` is `-m64` for `x86_64` and `-m32`
  for *everything else*, including aarch64, where no compiler accepts it. `make ARCH_TYPE=`
  on the command line overrides it, because command-line variables win even against an
  assignment inside an `ifeq`.

Running the amd64 build under qemu was rejected as the alternative: the analysis is mostly
JVM work, so emulating it is far slower than emulating one native helper would suggest.

## Usage

```bash
# import + analyse (once per binary; ~4 min for an 870 KB MIPS .so on a Pi 5)
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -v /path/to/work:/work ghidra:arm64 \
  /opt/ghidra/support/analyzeHeadless /work/proj PROJECT \
  -import /work/target.so -processor MIPS:LE:32:default

# decompile named functions from the saved project, no re-analysis
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -v /path/to/work:/work ghidra:arm64 \
  /opt/ghidra/support/analyzeHeadless /work/proj PROJECT -process target.so -noanalysis \
  -scriptPath /work -postScript DecompileFuncs.java funcA funcB

# or everything at once, to one greppable file
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -v /path/to/work:/work ghidra:arm64 \
  /opt/ghidra/support/analyzeHeadless /work/proj PROJECT -process target.so -noanalysis \
  -scriptPath /work -postScript DecompileAll.java /work/decomp.c
```

The project directory (`/work/proj` above) must **already exist**: `analyzeHeadless` fails
with `Directory not found` rather than creating it. Without `--user`, everything Ghidra
writes in the mounted volume is owned by `root`; `-e HOME=/tmp` is what makes `--user` work.

`DecompileFuncs.java` takes function names as arguments and prints C between
`@@@BEGIN`/`@@@END` markers, so it is easy to slice out of Ghidra's logging.

`FUN_xxxxxxxx` names work too, **which is the point**. Static functions have no symbol, so
a symbol-driven approach cannot see them, and on the Archer MR600 the function that actually
built a shell command was exactly such a function.

A raw address also **creates** the function if auto-analysis never made one. That is not a
corner case: a handler reached only through a dispatch table has no `jal` referencing it, so
Ghidra leaves it as unclaimed bytes and `getFunctionContaining` returns null. The
TL-WPA8630P's injectable `sub_4256CC` was exactly that: registered in an ops table under
`"devicelist"`, called by no one, invisible until `createFunction` was called on it.

## Why bother, versus disassembly

Capstone plus hand-rolled constant folding gets you a long way and was enough to map 841 call
sites. It loses values across stack spills and long basic blocks, which is exactly where the
interesting arguments live. Ghidra's data flow answers "*does this user-supplied string reach
that `system()` call*" directly, and twice the answer was no, where the disassembly had
been ambiguous enough to suggest otherwise.

## Notes

* `decompile` (the built native, ~3.8 MB) is **not committed**; `build.sh` regenerates it.
* The source checkout defaults to `${TMPDIR:-/tmp}/ghidra-src-<version>`; override with
  `SRC=`. It is cached, so rebuilds skip the fetch.
* `GHIDRA_TAG` defaults to `Ghidra_<GHIDRA_VER>_build`. Bump both together, since the native
  must match the release.
* The Dockerfile resolves the release zip from the GitHub release API, because the asset
  filename contains a build date (`ghidra_12.1.3_PUBLIC_20260817.zip`) that cannot be
  derived from the version. Set `GHIDRA_URL` to pin one exactly or to build offline.
* `build.sh` warns if the host is not arm64: the natives are built for the host, so the
  resulting image only runs there.

## CI

| workflow | trigger | does |
|---|---|---|
| `release.yml` | tag `v<version>`, or manual dispatch | builds, verifies, publishes `:version` and `:latest` |
| `verify.yml` | push to `main`, or a PR, touching `build.sh`, `Dockerfile*`, `*.java` or a workflow | builds and verifies, publishes nothing |
| `ghidra-release-watch.yml` | weekly | opens an issue when upstream Ghidra is newer than the pinned default |

The build and the verify step live once, in `_build.yml`, so the callers cannot drift apart.
Both run on an **arm64 runner**: native, and free for public repositories. Building the
native under qemu on x86 would be an order of magnitude slower.

Publishing is **tag-only**. A README or docs commit triggers nothing; a `v<version>` tag is
what mints an image. `verify.yml` still builds and decompiles a small aarch64 binary when the
recipe changes, so a broken `build.sh` is caught before it is tagged rather than at release
time.

Dependabot keeps the actions and the `eclipse-temurin` base image current. The `debian:13`
container used to compile the decompiler is only referenced from `build.sh`, not from a
`Dockerfile`, so Dependabot does not track it.

## Licence

Apache-2.0, matching Ghidra. See [NOTICE](NOTICE): the published images contain and
redistribute Ghidra, whose own `LICENSE` and `licenses/` directory travel unmodified inside
the image at `/opt/ghidra/`.
