#!/usr/bin/env python3
"""Keep docs/data/compat.json's "built" lists in step with the patch sets.

usage: compat-built.py [--check]

For each car on the compatibility page, "built" lists the md5 of every file our
package installs on it (from patches/<set>/manifest and patches/common/optional),
so the page can tell a unit that already runs Leafia from one with unknown files.
The cars table (patches/cars) maps the car's product prefix to its patch set.
With --check nothing is written; it exits 1 if compat.json is out of date (CI).
"""
import json, os, sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
COMPAT = os.path.join(ROOT, 'docs', 'data', 'compat.json')
PATCHES = os.path.join(ROOT, 'patches')


def manifest_lines(path):
    if not os.path.exists(path):
        return []
    out = []
    for l in open(path):
        p = l.split()
        if len(p) == 5 and not p[0].startswith('#'):
            out.append(p)
    return out


def built_for(patch_set):
    built = {}
    lines = manifest_lines(os.path.join(PATCHES, patch_set, 'manifest'))
    lines += manifest_lines(os.path.join(PATCHES, 'common', 'optional'))
    for part, kind, name, _patch, md5 in lines:
        f = '/system/app/%s.apk' % name if kind == 'app' else '/system/lib/%s' % name
        if md5 not in built.setdefault(f, []):
            built[f].append(md5)
    return {f: sorted(v) for f, v in sorted(built.items())}


def main():
    check = '--check' in sys.argv[1:]
    sets = {}
    for l in open(os.path.join(PATCHES, 'cars')):
        p = l.split()
        if len(p) >= 2 and not p[0].startswith('#'):
            sets[p[0]] = p[1]
    raw = open(COMPAT, encoding='utf-8').read()
    db = json.loads(raw)
    for v in db['variants']:
        prefixes = v['product_prefix'] if isinstance(v['product_prefix'], list) else [v['product_prefix']]
        found = {sets[c] for c in sets for p in prefixes if c.startswith(p) or p.startswith(c)}
        if len(found) > 1:
            sys.exit('%s: product prefixes map to several patch sets %s' % (v['id'], sorted(found)))
        b = built_for(found.pop()) if found else {}
        if b:
            v['built'] = b
        else:
            v.pop('built', None)
    new = json.dumps(db, indent=2, ensure_ascii=False) + '\n'
    if new == raw:
        print('compat.json built lists are up to date')
        return
    if check:
        sys.exit('docs/data/compat.json "built" lists are out of date: run tools/compat-built.py')
    open(COMPAT, 'w', encoding='utf-8').write(new)
    print('updated docs/data/compat.json')


if __name__ == '__main__':
    main()
