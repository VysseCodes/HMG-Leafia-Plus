# LeafiaBridge

Our own Android app for HMG Leafia Plus features that run beside the stock apps. The patched stock apps only forward their data here (one small hook each); the logic lives in this app, so a feature change doesn't mean re-porting smali to every car.

**This build is a dry run.** It decides what it would do and logs it. It has no code that talks to the car.

## What it does now

- **Route updates** (`RouteReceiver`): the patched DiPO sends each CarPlay route update (destination, distance, time remaining, guidance state) to this package only. The receiver requires a `signature|system` permission, so no other app can fake a trip.
- **Battery preconditioning, dry run** (`Precondition`, `Chargers`): when the destination looks like an EV charger, it logs the calls the stock navigation would make (`setBattCondEvStation`, `setBattCondRouteDis`, `setBattCondRemainTime`), and logs the clear when that route ends.
- **Star keys** (`ShortcutReceiver`): logs every press, with all its extras, and the manual on/off it would send.

Log: logcat tag `LeafiaBridge`, and `files/leafia-bridge.log` in the app's data folder (destination names, so the Leafia kit only puts it in its private part).

## Building

```
apps/build.sh leafiabridge /tmp/LeafiaBridge.apk           # unsigned, for checks
apps/build.sh leafiabridge --check <LeafiaBridge.apk>      # compare an APK with the source (CI)
```

Needs a JDK 17, `python3` and `curl`; `d8`, `aapt2` and the API 19 `android.jar` are downloaded from Google at pinned SHA-256. The code and manifest are byte-for-byte reproducible.

The shipped APK (`packages/wireless-carplay-aa/comp/6_leafiabridge/files/LeafiaBridge.apk`) is signed with the maintainer's release key, which never leaves the maintainer's computer. Android only accepts an update to an installed system app with the same key, so every release must be signed with it:

```
LEAFIA_KEYSTORE=<keystore> LEAFIA_KEYPASS_FILE=<password file> apps/build.sh leafiabridge <out.apk>
```

After a rebuild, update its md5 in the `APKS` list in `comp/6_leafiabridge/scripts/common.sh`. CI checks that the shipped APK's code and manifest match this source.
