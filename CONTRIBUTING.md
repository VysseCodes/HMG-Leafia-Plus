# Contributing

Thanks for helping! You don't need to write code to contribute:

- **Report your car.** Run the Leafia kit and drop its report on the
  [compatibility page](https://vyssecodes.github.io/HMG-Leafia-Plus/); it files the issue for you. Cars in the
  page's "Help add your car" list are the most wanted.
- **Test a build** on your car and tell us how it went, especially for cars marked *testing*.
- **Report a problem** with the issue form: it walks you through the Leafia kit.
- **Code:** read on.

Security problems go through [SECURITY.md](SECURITY.md), not public issues.

## Setup (Linux)

| Need | For | Fedora / Ubuntu package |
|---|---|---|
| `clang`, `lld` | building `lpatch` and `libev6aac.so` | `clang lld` |
| `qemu-arm-static` | running the ARM `lpatch` in tests and the mock head unit | `qemu-user-static` |
| Python 3 + `bsdiff4` | patch tools and tests | `pip install --require-hashes -r tools/requirements.txt` |
| `mksh` (recommended) | testing scripts in the head unit's own shell | `mksh` |
| `zip`, `unzip` | packages and kits | `zip unzip` |

## Layout

| Path | What |
|---|---|
| `packages/wireless-carplay-aa/` | The NEMESIS package: `scripts/` (install, uninstall, on-unit build), `comp/<part>/` (one folder per part). |
| `patches/` | Per-car patch sets that rebuild the projection apps from the car's own stock files, and `cars` (which product id uses which set). See [patches/README.md](patches/README.md). |
| `recipes/` | Byte-checked native-library patches applied by `lpatch`. |
| `tools/lpatch/` | `lpatch`, the small static ARM tool that patches on the head unit. |
| `src/ev6aac/` | `libev6aac.so`, the AAC/Opus audio converter for wireless CarPlay. |
| `kits/leafia/` | The read-only USB kit: compatibility report, problem summary, and private logs, stock files and keys. |
| `docs/` | The compatibility website (GitHub Pages). |
| `tools/` | Builders, the porting tool, and the mock head unit. |

## Build

```sh
tools/build-package.sh                       # dist/HMG_Leafia_Plus_Wireless_CarPlay_AA.zip
tools/build-kit.sh [quick|standard|port|full]  # dist/leafia-kit*.zip (default: standard)
tools/lpatch/build.sh                        # lpatch (ARM) and lpatch-host
src/ev6aac/build.sh                          # libev6aac.so (CLANG=clang-18 for a byte-identical build)
tools/mkmenu.py <stock dir>                  # the Phone Projection menu fix for one car
```

Make a recipe from a stock/patched library pair:

```sh
tools/mkrecipe.py <id> /system/lib/libX.so stock.so patched.so --desc "what it does"
```

## Test

```sh
tools/lpatch/test.sh                         # lpatch: fresh vs committed build, recipes, deltas
tools/check-downloads.sh                     # the website's kit zips match kits/
```

**Mock head unit.** `tools/mock/install-test.sh` installs and uninstalls the package against a copy of a car's
stock `/system` on your computer, and passes only if uninstall restores it byte for byte. The kit's
`LEAFIA/private/stock/` folder works as the stock tree:

```sh
MOCK_SH=mksh MOCK_NEMESIS=1.15 tools/mock/install-test.sh dist/HMG_Leafia_Plus_Wireless_CarPlay_AA.zip \
    CVEV.USA.0000.V015.012.260507 cvev_us /path/to/LEAFIA/private/stock
```

List your test cars in `tools/mock/cars.local` (git-ignored) and run them all with
`tools/mock/matrix.sh dist/HMG_Leafia_Plus_Wireless_CarPlay_AA.zip`. Run the hooks with `MOCK_SH=mksh`: the head
unit's shell lacks commands your desktop shell has (`printf`, `tail`, ...).

## Adding a car

Only a car's **newest firmware** is supported (currently 260507 in the US and Canada, 260902 in Korea). A report from older firmware gets a request to update the head unit, not a port.

1. The owner runs the **port** kit (`leafia-kit-port.zip`) and sends its `LEAFIA/private` folder privately.
2. `tools/port.py` ports the app changes to it and writes `patches/<car>/` plus its `cars` line
   (`tools/port.py --help`).
3. Mock-test it with the owner's `share/` folder.
4. Add it to `docs/data/compat.json` with status `testing`, and move it to `supported` once an owner confirms
   it on a real car.

Cars without a patch set already get **basic mode** (wireless Android Auto only).

## Rules

These keep cars safe and the project legal:

- **No manufacturer files in the repo**: only recipes, patch sets (deltas that rebuild from the car's own
  files), checksums and our own code. Stock firmware, full modified apps and key files stay private.
- **Every write to `/system`** needs a stock-checksum check first, a backup, and an uninstall that restores
  the exact stock bytes. Prove it on the mock head unit.
- **Never** flash MICOM, bootloaders or modem firmware, or anything meant for another car.
- **No raw CAN frames.** Vehicle commands only through the stock services, each reviewed separately.
- **Kits are read-only**, and their `public` output must stay safe to post: no VINs, serial numbers, phone
  details or account data.
- **Package scripts run on the head unit's toolbox shell (mksh):** no `printf`, `awk`, `tail` or other
  commands it lacks (`tools/build-package.sh` refuses `printf`).

## Pull requests

- Branch from `main`; `main` only changes through pull requests.
- Describe the change in plain words, and say what you tested: which cars, mock or real.
- CI must pass. For a first-time contributor, a maintainer approves the workflow run.
- CI only runs the checks for what you changed (lpatch, `libev6aac.so`, the kit, the package); a docs-only change runs none. Changing a workflow runs them all.
- If you change the kit, rebuild every published size: `tools/check-downloads.sh --fix`.
- Don't put links to AI chat sessions in commits or PR descriptions.

## Releases

CI (`.github/workflows/ci.yml`) builds and tests every push and pull request; its downloads are temporary.
A **release** is the permanent, public download users install from. To make one, tag a commit on `main`:

```sh
git tag -a v1.2.0 -m "v1.2.0" && git push origin v1.2.0
```

`.github/workflows/release.yml` then runs all of CI and, only if everything passes, publishes a GitHub
Release with the package, the four Leafia kit sizes and `SHA256SUMS`, built from exactly that commit (the package's
build stamp names the version). Tags not on `main` are refused.

By contributing you agree your work is licensed under the project's [GPL-3.0](LICENSE).
