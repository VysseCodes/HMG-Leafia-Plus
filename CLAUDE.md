# HMG Leafia Plus: notes for Claude

Community tooling for Hyundai/Kia/Genesis **Gen5W** head units (Telechips TCC803x/TCC897x, Android 4.4.2, Dalvik), installed through **NEMESIS** (xwtk/hmg_nemesis, AGPL-3.0). Maintainer: VysseCodes (Ko-fi vyssecodes). Reference car: 2023 Kia EV6 (CVEV.USA, firmware 260507, with HUD).

## Working conventions

- Root commands on a head unit go through NEMESIS: `adb shell "nemesis root -c '...'"`. `nemesis root <uid> -c` runs as another uid (1000 = system).
- Anything that writes to `/system` ships as a NEMESIS package with a stock checksum gate, a backup, and an uninstall that restores the exact stock bytes.
- Test packages on the mock head unit (below) before anyone runs them on a car, and say which cars a change was tested on.
- Commits: describe the change in plain words. Don't rewrite or force-push shared history without the maintainer's OK.
- No links to Claude chats or sessions in commits, PR descriptions or comments: no `Claude-Session:` trailers and no claude.ai session URLs. A `Co-Authored-By: Claude` line is fine.

## Hard rules

- Only each car's newest firmware is supported (260507 US/Canada, 260902 Korea). Don't port older firmware; ask the owner to update the head unit. On a known car with other firmware the installer falls back to basic mode and says to update (`MODE_UPDATE`).

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
| `kits/leafia` | The one read-only USB kit, in four sizes set by a `LEAFIA-LEVEL` file (`tools/build-kit.sh [quick|standard|port|full]`): `leafia-kit-quick.zip` (public only), `leafia-kit.zip` (standard: + private logs with the latest crash records, + keys), `leafia-kit-port.zip` (+ stock files), `leafia-kit-full.zip` (+ every crash record). The old fingerprint/support/deep zip names stay as copies of quick/standard/port; `tools/check-downloads.sh [--fix]` checks/rebuilds them all. Writes `LEAFIA/public/` (LEAFIA-REPORT.txt for the compatibility page, summary.txt, our install logs: safe to post) and `LEAFIA/private/` (`logs/`, `stock/` for porting, `keys/` firmware key files: only privately, when a maintainer asks). Packages carry a `BUILD` stamp (commit + date) that the install log and the kit show. |
| `docs/` | GitHub Pages compatibility checker (`docs/data/compat.json`; status `supported`/`testing`/`in-progress`/`no-wifi`; `product_prefix` may be a list). |
| `tools/build-package.sh` | Builds `dist/HMG_Leafia_Plus_Wireless_CarPlay_AA.zip` from the repo alone. |
| `tools/port.py` | Ports the app changes to a new car from its deep-kit collection (class-by-class compare, auto-merge, reference/framework checks, writes the patch set and `cars` line). |
| `tools/mkmenu.py` | Makes the `5_menu` fix (`HKMC_BtSettings`) for one stock tree and adds its line to `patches/common/optional`; finds the code by structure and refuses unknown shapes. |
| `tools/mkpatches.py`, `tools/mkdelta.py` | Patch-set and single-delta makers (need `pip install --require-hashes -r tools/requirements.txt`). |

## Supported cars (patches/cars)

| Prefix | Set | Car | Notes |
|---|---|---|---|
| `CVEV.` | ev6 | Kia EV6 260507 | reference car |
| `NEEV.USA.` / `NEEV23.USA.` | neev | Hyundai Ioniq 5 US 2022/2023 | app code identical to EV6, different APK wrappers |
| `DL3HEV.KOR.` / `DL3HEV22.KOR.` | dl3hev | Kia K5 Hybrid Korea 260902 (2022 has identical projection apps) | TCC897x; **no Wi-Fi hardware** (see gotchas): wireless projection impossible, installer refuses; compat status `no-wifi` |
| `NEEV.KOR.` | neev_kr | Hyundai Ioniq 5 Korea 260902 | ported automatically from an owner's kit; native Wi-Fi CarPlay + converters; first real car (#27) showed no `wlan0` and `wl` finds no adapter, kernel log still needed (TCC803x like the US cars); listed first among the Ioniq 5 lines in `cars` (first match wins); not yet tested on a real car |

## Gotchas learned the hard way

- **Deodex with `baksmali x -a 18`**, against the car's own framework dir with the full BOOTCLASSPATH order (core, conscrypt, okhttp, core-junit, bouncycastle, ext, framework, framework2, telephony-common, voip-common, mms-common, android.policy, services, apache-xml, webviewchromium, automotive) plus every other framework odex. `-a 19` silently mis-maps instance fields (KitKat libcore Object fields) and skips classes.
- Abstract Binder stubs implementing in-app interfaces can still deodex with wrong method names; compare against a known-good build before trusting a class.
- System apps: PackageManager only verifies `AndroidManifest.xml`, so stock APK + injected `classes.dex` installs fine; delete the odex and dexopt (`dexopt --preopt apk odex m=y,u=n`).
- Every outgoing SMS on these units needs `android.permission.TMSC_SEND` (Mobis) as well as `SEND_SMS`. Only system-uid callers pass: `nemesis root 1000 -c 'service call isms 5 s16 android s16 <number> i32 -1 s16 <text> i32 0 i32 0'`.
- CarPlay first-connect notice: DiPO looks it up by the phone's Bluetooth address before iAP2 identification, but saved it under the iPhone serial. The bridge build now saves both (`i/e.ev6LastBtId` + `service/aa`).
- CarPlay turn-by-turn maneuver index fix (Isaac Wisdom): `e/u.d(Object)` wrote into a clone of the index array.
- DiPO wireless reconnect crash (stock bug): an iAP2 drop clears the phone's iAP2 Bluetooth address (`e/b.aw`, read by `K()`), and a wireless session can restart before iAP2 is back; `service/q.a` (onSessionDetails) called `K().toUpperCase()` unchecked. The bridge build now falls back to the session's own id, or keeps the stored address. Every other `K()` caller already checks for null. Same method on all four sets (K5/Korean Ioniq 5 only rename DipoService accessors).
- The bridge's `EV6CPWL` log lines may not show in logcat even while it runs; don't read their absence as the bridge being dead.
- No `tail` on the unit; use shell loops. Remount only through `nemesis remount rw|ro`: toolbox `mount -o remount` is refused even as root (NEMESIS before 1.15 could also EPERM until reboot; 1.15 fixed it and puts a `mount` wrapper first on hook PATH). Featurexml region comes from `ro.mobis.targetdir`.
- Korean K5 Hybrid (TCC897x) has no Wi-Fi: the kernel sets up only SDHC0/SDHC2, the driver raises WIFI_REG_ON and gives up (`failed to power up DHD generic adapter, max retry reached`). US TCC803x units show `mmc1: new ... SDIO card` and `Firmware up`. The feature file `com.hkmc.software.wifi.module.xml` is present either way; `wifi_hw` in `common.sh` uses the driver's result instead, and preinstall refuses on `no`.
- With the wireless CarPlay/AA features on, `HKMC_BtSettings` (`BluetoothSettings`, pswitch on the menu id) sends Settings > Phone Projection to `wireless.WPPSettingsActivity` (no split-screen option; its device list only holds phones paired by `WirelessPhoneProjectionService`, never ours). Stock US/CA goes to Device Connections. Part `5_menu` (optional, `patches/common/optional`) keeps US/CA on Device Connections. lpatch `MAXOUT` is 12 MB for this 5.6 MB APK.
- Toast: `am broadcast -a com.hkmc.intent.action.TOAST -e com.hkmc.intent.extra.TOAST_MESSAGE "..." --ez com.hkmc.intent.extra.TOAST_POPUPSHOWING true`.

## Testing without a car

Mock head unit: `tools/mock/install-test.sh <zip> <ro.build.product> <region dir> <stock system dir>` installs and uninstalls the package against a copy of a stock `/system` (a kit's `LEAFIA/private/stock/` works), stubbing `getprop`/`setprop`/`am`/`settings`/`md5`/`chown`/`dexopt` and running `lpatch` under `qemu-arm-static`; it passes only if uninstall leaves `/system` byte-identical. `tools/mock/matrix.sh <zip>` runs every car in the git-ignored `tools/mock/cars.local`. Use `MOCK_SH=mksh` (the unit's shell lacks `printf`, `tail`, ...), `MOCK_NEMESIS=1.15`, `MOCK_ANDROID_DOWN=1` (NEMESIS 1.15 installs without asking while Android is down) and `MOCK_USB_DESCRIPTOR=1`. Stock trees and full builds can't live in this repo; contributors keep their own copies privately.

## Kia Connect (research summary, read-only)

Telematics lives in `HKMC_TAppService` (system uid). Remote commands arrive over MQTT (`mqtt_mosquitto`, a libmosquitto binder wrapper; MQTT 5; topics and host provisioned via the service hub) or a wake-up SMS that makes the unit call back over HTTPS. Commands execute through `BCMManager`/`HEVManager` -> automotive-service -> `micomd` (`/dev/ttyTCC2`) -> MICOM -> CAN. Modem: Qualcomm over USB (`/dev/ttyACM0` AT, `/dev/qcqmi0` data), Verizon (US). Status is reported as VSS paths. Planned direction: a read-only Home Assistant status bridge first, then wake-by-own-SMS testing, then reviewed commands one at a time through the stock services.

## Open threads

- Real-car tests pending: on-unit build package (all cars), CarPlay notice fix, K5 and Korean Ioniq 5 first installs, DiPO reconnect null check (all four sets).
- Reassemble deodexed apps with `smali a -j 1 --api 18`: with more threads smali writes a different (equivalent) dex each run.
- Also seen on the US Ioniq 5: Iap2ServerApp `InitSupportLanguage` index out of range on iAP2 disconnect; `/system` left mounted rw after install (`nemesis remount ro` got EBUSY and the parts ignore it).
- NEMESIS 1.15 (2026-10-21): checked against its zip/INI code and hook environment; its `carplay.session` package conflicts with ours (in `LEGACY`).
- Modem test plan for a volunteer (read-only identity/APN/SMS-in/wake tests).
- Possible: install guide on the site; changelog describing fixes in plain words.
