# Recipe format

Recipes contain **no bytes from the head unit's files**: only hashes of the regions they check, and the new bytes they write (our own code).

One directive per line; anything after `#` is a comment.

```
id <name>
file <path on the head unit>
native <md5> [note]
verify <hex offset> <length> <md5 before> <md5 after>
patch <hex offset> <new bytes hex>
```

- `verify`: a region around each change (the changed bytes plus 16 unchanged bytes on each side). `md5 before` is the stock region; `md5 after` is the same region once patched.
- `patch`: only the bytes that change. Every patch must sit inside a verify region.
- `native`: the whole-file md5 of a library that already provides the feature. `lpatch` reports `NATIVE` and never patches it.

`lpatch check <recipe> [file]` prints a `SPOT` line per verify region and one `RESULT` line:

| Status | Meaning |
|---|---|
| `PATCHABLE` | Every region matches its stock hash; safe to apply |
| `APPLIED` | Every region matches its patched hash |
| `NATIVE` | Known file that already has the feature |
| `MISMATCH` | At least one region is neither; its `SPOT` line gives the region's md5 for analysis |
| `MISSING` | File not found |

`lpatch apply <recipe> <src> <dst>` writes a patched copy only when the file is `PATCHABLE`, then re-reads it and verifies every region.

Generate one with `tools/mkrecipe.py` from a stock/patched pair.

## Delta patches (apps)

For files whose changes are too large for a recipe (the projection apps), `lpatch` has two more commands:

- `lpatch delta <patch.lpd> <src> <dst>`: rebuilds a file from a delta. It writes nothing unless `src` has the exact md5 the delta was made from, and the rebuilt file has the exact md5 it records.
- `lpatch zipadd <src.apk> <classes.dex> <dst.apk>`: adds `classes.dex` (stored) to a stock APK that has none, keeping every original entry byte for byte. The output is deterministic, so its md5 can be checked.

Deltas are made with `tools/mkdelta.py`; per-car sets live in `/patches`.
