# HMG Leafia Plus: notes for Claude

Community tooling for Hyundai/Kia/Genesis **Gen5W** head units (Telechips TCC803x/TCC897x, Android 4.4.2, Dalvik), installed through **NEMESIS** (xwtk/hmg_nemesis, AGPL-3.0). Maintainer: VysseCodes (Ko-fi vyssecodes). Reference car: 2023 Kia EV6 (CVEV.USA, firmware 260507, with HUD).

## Working conventions

- Root commands on a head unit go through NEMESIS: `adb shell "nemesis root -c '...'"`. `nemesis root <uid> -c` runs as another uid (1000 = system).
- Anything that writes to `/system` ships as a NEMESIS package with a stock checksum gate, a backup, and an uninstall that restores the exact stock bytes.
- Test packages on the mock head unit (below) before anyone runs them on a car, and say which cars a change was tested on.
- Commits: describe the change in plain words. Don't rewrite or force-push shared history without the maintainer's OK.

## Hard rules

- Never flash MICOM, the bootloader, or modem firmware. Never flash firmware meant for another car.
- No sending our own CAN frames without a separate review. Vehicle commands only through the stock services (BCMManager etc.), and each new one gets its own review.
- Never collect or publish per-car secrets: `/data` contents, the telesecurity partition, certificates/keys, account tokens, VIN, serials, SIM/IMEI/phone numbers. Model-level firmware keys only privately, with consent.
- The repo holds **no full manufacturer apps or libraries**. Allowed: hash-only recipes, delta patch sets (`patches/`), checksums, our own code.

## Layout

| Path | What |
|---|---|
| `tools/lpatch/` | Freestanding static ARM tool (no libc). `check`/`apply` (hash-gated recipes), `delta` (rebuild a file from `.lpd`, only from the exact stock original), `zipadd` (add classes.dex to a stock APK, deterministic), `md5`. Build: `tools/lpatch/build.sh` (also builds `lpatch-host`). Test: `tools/lpatch/test.sh` (fresh build vs committed binary under qemu, plus EV6 manifest rebuild if `~/hmg-private/stock/ev6` exists). |
| `recipes/` | Hash-only native-library patches (libCarPlayCore Wi-Fi sessions, libCarPlayAudio formats, libCarPlayUtils converter). Make with `tools/mkrecipe.py`. |
| `patches/` | Per-car delta sets for the projection apps + `cars` table + `<car>/stock` checksums + `<car>/manifest` expected results. See `patches/README.md`. |
| `packages/wireless-carplay-aa/` | NEMESIS package source: parts `1_projection` (feature flags, hotspot only), `2_tbt` (turn-by-turn), `3_bridge` (CarPlay Bluetooth bridge), `4_audio`. `scripts/build.sh` rebuilds the apps on the unit from stock files before any part runs. |
| `kits/fingerprint`, `kits/deep` | Read-only USB kits. Fingerprint report is public-safe; deep kit output goes privately (its `PRIVATE/` has firmware key files). |
| `docs/` | GitHub Pages compatibility checker (`docs/data/compat.json`; status `supported`/`testing`/`in-progress`; `product_prefix` may be a list). |
| `tools/build-package.sh` | Builds `dist/HMG_Leafia_Plus_Wireless_CarPlay_AA.zip` from the repo alone. |
| `tools/port.py` | Ports the app changes to a new car from its deep-kit collection (class-by-class compare, auto-merge, reference/framework checks, writes the patch set and `cars` line). |
| `tools/mkpatches.py`, `tools/mkdelta.py` | Patch-set and single-delta makers (need `pip install bsdiff4`). |

## Supported cars (patches/cars)

| Prefix | Set | Car | Notes |
|---|---|---|---|
| `CVEV.` | ev6 | Kia EV6 260507 | reference car |
| `NEEV.` / `NEEV23.` | neev | Hyundai Ioniq 5 2022/2023 | app code identical to EV6, different APK wrappers |
| `DL3HEV.KOR.` | dl3hev | Kia K5 Hybrid Korea 260902 | TCC897x; native Wi-Fi CarPlay + converters; 3 classes merged; not yet tested on a real car |
| `NEEV.KOR.` | neev_kr | Hyundai Ioniq 5 Korea 260902 | ported automatically from the deep kit; native Wi-Fi CarPlay + converters; listed above `NEEV.` in `cars` (first match wins); not yet tested on a real car |

## Gotchas learned the hard way

- **Deodex with `baksmali x -a 18`**, against the car's own framework dir with the full BOOTCLASSPATH order (core, conscrypt, okhttp, core-junit, bouncycastle, ext, framework, framework2, telephony-common, voip-common, mms-common, android.policy, services, apache-xml, webviewchromium, automotive) plus every other framework odex. `-a 19` silently mis-maps instance fields (KitKat libcore Object fields) and skips classes.
- Abstract Binder stubs implementing in-app interfaces can still deodex with wrong method names; compare against a known-good build before trusting a class.
- System apps: PackageManager only verifies `AndroidManifest.xml`, so stock APK + injected `classes.dex` installs fine; delete the odex and dexopt (`dexopt --preopt apk odex m=y,u=n`).
- Every outgoing SMS on these units needs `android.permission.TMSC_SEND` (Mobis) as well as `SEND_SMS`. Only system-uid callers pass: `nemesis root 1000 -c 'service call isms 5 s16 android s16 <number> i32 -1 s16 <text> i32 0 i32 0'`.
- CarPlay first-connect notice: DiPO looks it up by the phone's Bluetooth address before iAP2 identification, but saved it under the iPhone serial. The bridge build now saves both (`i/e.ev6LastBtId` + `service/aa`).
- CarPlay turn-by-turn maneuver index fix (Isaac Wisdom): `e/u.d(Object)` wrote into a clone of the index array.
- No `tail` on the unit; use shell loops. Remount can EPERM until reboot. Featurexml region comes from `ro.mobis.targetdir`.
- Toast: `am broadcast -a com.hkmc.intent.action.TOAST -e com.hkmc.intent.extra.TOAST_MESSAGE "..." --ez com.hkmc.intent.extra.TOAST_POPUPSHOWING true`.

## Testing without a car

Mock head-unit sandbox: rewrite the package scripts' `/system`, `/data`, `/storage` paths into a temp root, stub `getprop`/`setprop`/`am`/`settings`/`md5`/`chown`, a fake `dexopt` (copies apk to odex), and run `lpatch` through `qemu-arm-static` via `LPATCH=<wrapper>`. Run `pre.sh`, `post.sh`, `preun.sh`; the system tree must be byte-identical to stock after uninstall. Stock trees and full builds can't live in this repo; contributors keep their own copies privately (deep kit output, NEMESIS backups).

## Kia Connect (research summary, read-only)

Telematics lives in `HKMC_TAppService` (system uid). Remote commands arrive over MQTT (`mqtt_mosquitto`, a libmosquitto binder wrapper; MQTT 5; topics and host provisioned via the service hub) or a wake-up SMS that makes the unit call back over HTTPS. Commands execute through `BCMManager`/`HEVManager` -> automotive-service -> `micomd` (`/dev/ttyTCC2`) -> MICOM -> CAN. Modem: Qualcomm over USB (`/dev/ttyACM0` AT, `/dev/qcqmi0` data), Verizon (US). Status is reported as VSS paths. Planned direction: a read-only Home Assistant status bridge first, then wake-by-own-SMS testing, then reviewed commands one at a time through the stock services.

## Open threads

- Real-car tests pending: on-unit build package (all cars), CarPlay notice fix, K5 first install.
- Modem test plan for a volunteer (read-only identity/APN/SMS-in/wake tests).
- Possible: install guide on the site; changelog describing fixes in plain words.
