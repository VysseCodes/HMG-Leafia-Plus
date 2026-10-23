## What and why

<!-- In plain words: what does this change, and why? Link the issue if there is one. -->

## Testing

<!-- Which cars, and how: mock head unit (tools/mock/install-test.sh), or a real car? -->

- [ ] Mock head unit: install, then uninstall back to identical stock (cars: )
- [ ] Real car (cars: ), or not yet tested on a real car

## Checklist

- [ ] No manufacturer files added (only recipes, patch sets, checksums, our own code)
- [ ] Package scripts run on the head unit's shell (tested with `MOCK_SH=mksh`)
- [ ] Kit changed? Its zip in `docs/downloads/` is rebuilt (`tools/check-downloads.sh`)
- [ ] Docs updated if behaviour changed (README, `docs/data/compat.json`, `patches/README.md`)
