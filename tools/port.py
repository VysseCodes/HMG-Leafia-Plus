#!/usr/bin/env python3
"""Port the Wireless CarPlay/AA app changes to a new car automatically.

Compares the new car's stock projection apps with a reference car's, class by
class, and carries the reference builds' changes over:

  * classes the new car has identical to the reference: the reference build's
    version is used as is
  * classes that differ on the new car but that we never changed: the new
    car's own version is used
  * classes that differ AND that we changed: merged automatically when the
    new car's version is the reference's with members renamed (obfuscation
    shifts), or when our change applies cleanly as a 3-way patch; otherwise
    the port stops and lists them for a person to merge

Every result is checked: each reference inside the app must resolve, every
system call must exist in the new car's framework. Then the builds are
assembled, the patch set is written to patches/<variant>/ and the car is added
to patches/cars.

usage:
  port.py --variant NAME --prefix PRODUCT_PREFIX --name "Car name"
          --new-stock DIR --new-fw DIR
          [--ref-variant ev6] --ref-stock DIR --ref-fw DIR --ref-builds DIR
          --out-builds DIR [--patches DIR] [--work DIR]

  *-stock    app/<App>.apk + app/<App>.odex + lib/libautoreceiver_infobank.so
  *-fw       the car's /system/framework (deep kit: NEMESIS-deep/share/framework)
  ref-builds 2_tbt/<files>/<App>.apk and 3_bridge/<files>/<App>.apk
  out-builds where the new car's full builds go (keep them private)

Needs baksmali and smali on PATH, the host lpatch (tools/lpatch/build.sh) and
`pip install --require-hashes -r tools/requirements.txt`.
"""
import argparse, filecmp, hashlib, os, re, shutil, subprocess, sys, tempfile, zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
LPATCH = os.path.join(HERE, 'lpatch', 'lpatch-host')
FILES = {'ev6': 'files', 'neev': 'files_neev', 'dl3hev': 'files_dl3hev'}
PARTS = [('2_tbt', ['HKMC_GPM', 'HKMC_DiPO', 'Iap2ServerApp', 'HKMC_Navi_ExSL']),
         ('3_bridge', ['Iap2ServerApp', 'HKMC_DiPO'])]
LIB = 'libautoreceiver_infobank.so'
BCP = ('core conscrypt okhttp core-junit bouncycastle ext framework framework2 telephony-common '
       'voip-common mms-common android.policy services apache-xml webviewchromium automotive').split()
SKIP = ('.line', '.local', '.end local', '.restart local', '.prologue', '.param', '.end param', '.source', '#')

def log(*a): print(*a, flush=True)
def md5(p): return hashlib.md5(open(p, 'rb').read()).hexdigest()
def run(*a, **k): return subprocess.run(a, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, **k)
def files_dir(v): return FILES.get(v, 'files_' + v)

def norm_lines(p):
    return [s for s in (l.strip() for l in open(p, encoding='utf-8', errors='replace')) if s and not s.startswith(SKIP)]

def classes(d):
    r = set()
    for dp, _, fs in os.walk(d):
        for f in fs:
            if f.endswith('.smali'): r.add(os.path.relpath(os.path.join(dp, f), d))
    return r

def deodex(odex, fw, out):
    """Deodex against the car's own framework. API 18 gives Dalvik's field
    layout; 19 mis-maps fields on these units."""
    have = set(os.listdir(fw))
    bcp = [b + '.odex' for b in BCP if b + '.odex' in have]
    extra = sorted(f for f in have if f.endswith('.odex') and f not in bcp)
    r = subprocess.run(['baksmali', 'x', '-a', '18', '-d', fw, '-b', ':'.join(bcp + extra), '-o', out, odex],
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    skipped = r.stderr.count('skipping class')
    if r.returncode or skipped:
        sys.exit('deodex of %s failed (%d classes skipped)' % (odex, skipped))

def disasm(apk, out):
    with tempfile.TemporaryDirectory() as t:
        d = os.path.join(t, 'classes.dex')
        open(d, 'wb').write(zipfile.ZipFile(apk).read('classes.dex'))
        run('baksmali', 'd', d, '-o', out)

# ---- member-rename mapping (obfuscated names shift between firmwares) ----
REF = re.compile(r'(L[\w/$]+;)->([\w$<>]+)(\([^)]*\)\S*|:\S+)')
FIELD_DECL = re.compile(r'^(\.field\s+(?:[\w-]+\s+)*?)([\w$]+)(:\S+)')
METHOD_DECL = re.compile(r'^(\.method\s+(?:[\w-]+\s+)*?)([\w$<>]+)(\(\S*)')

def own_class(lines):
    for l in lines:
        if l.startswith('.class'): return l.split()[-1]

def tokens(line, cls):
    """(class, name, signature) member tokens in a line, declarations included."""
    t = [(c, n, s) for c, n, s in REF.findall(line)]
    m = FIELD_DECL.match(line) or METHOD_DECL.match(line)
    if m: t.append((cls, m.group(2), m.group(3)))
    return t

def skeleton(line):
    line = REF.sub(lambda m: m.group(1) + '->@' + m.group(3), line)
    m = FIELD_DECL.match(line) or METHOD_DECL.match(line)
    if m: line = m.group(1) + '@' + line[m.end(2):]
    return line

def rename_map(e_lines, k_lines):
    """If K is E with only member names changed, return {(cls,name,sig): newname}."""
    if len(e_lines) != len(k_lines): return None
    cls = own_class(e_lines)
    if cls != own_class(k_lines): return None
    # declarations may be reordered: compare them as sets of skeletons
    m = {}
    for a, b in zip(e_lines, k_lines):
        if a == b: continue
        if skeleton(a) != skeleton(b): return None
        ta, tb = tokens(a, cls), tokens(b, cls)
        if len(ta) != len(tb): return None
        for (c1, n1, s1), (c2, n2, s2) in zip(ta, tb):
            if c1 != c2 or s1 != s2: return None
            if n1 != n2:
                if m.get((c1, n1, s1), n2) != n2: return None
                m[(c1, n1, s1)] = n2
    return m

def apply_map(lines_or_text, m, cls):
    def fix(line):
        line = REF.sub(lambda g: g.group(1) + '->' + m.get((g.group(1), g.group(2), g.group(3)), g.group(2)) + g.group(3), line)
        mm = FIELD_DECL.match(line.strip()) or METHOD_DECL.match(line.strip())
        if mm:
            new = m.get((cls, mm.group(2), mm.group(3)))
            if new:
                s = line.strip(); line = line[:len(line) - len(s)] + mm.group(1) + new + s[mm.end(2):]
        return line
    return [fix(l) for l in lines_or_text]

def three_way(e, t, k, tmp):
    """Apply our E->T change to K with patch(1)."""
    for n, d in (('e', e), ('t', t), ('k', k)): open(os.path.join(tmp, n), 'w').write('\n'.join(d) + '\n')
    diff = subprocess.run(['diff', '-u', os.path.join(tmp, 'e'), os.path.join(tmp, 't')], stdout=subprocess.PIPE, text=True).stdout
    r = subprocess.run(['patch', '-s', '--no-backup-if-mismatch', '-r', '-', os.path.join(tmp, 'k')], input=diff, text=True,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return open(os.path.join(tmp, 'k')).read().rstrip('\n').split('\n') if r.returncode == 0 else None

# ---- checks ----
def defs_of(root):
    defs, sup = {}, {}
    for dp, _, fs in os.walk(root):
        for f in fs:
            if not f.endswith('.smali'): continue
            c = None; m = set()
            for l in open(os.path.join(dp, f), encoding='utf-8', errors='replace'):
                s = l.strip()
                if s.startswith('.class'): c = s.split()[-1]
                elif s.startswith('.super'): sup[c] = s.split()[-1]
                elif s.startswith('.implements'): sup.setdefault(c + '#i', []).append(s.split()[-1])
                elif s.startswith('.method'): m.add(s.split()[-1])
                elif s.startswith('.field'): m.add(s.split(' = ')[0].split()[-1])
            defs[c] = m
    return defs, sup

def has(defs, sup, c, mem, d=0):
    if d > 30 or c not in defs: return None
    if mem in defs[c]: return True
    for p in [sup.get(c)] + sup.get(c + '#i', []):
        if p and has(defs, sup, p, mem, d + 1): return True
    return False

def unresolved(root, fw_defs=None):
    """Member references into this app (or, with fw_defs, into the framework) that do not exist."""
    defs, sup = fw_defs or defs_of(root)
    bad = set()
    for dp, _, fs in os.walk(root):
        for f in fs:
            if not f.endswith('.smali'): continue
            for l in open(os.path.join(dp, f), encoding='utf-8', errors='replace'):
                s = l.strip()
                if not s or s.startswith('#'): continue
                for c, mem, sig in REF.findall(s):
                    if c in defs and has(defs, sup, c, mem + sig) is False: bad.add(c + '->' + mem + sig)
    return bad

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    for a in ('variant', 'prefix', 'name', 'new-stock', 'new-fw', 'ref-stock', 'ref-fw', 'ref-builds', 'out-builds'):
        ap.add_argument('--' + a, required=True)
    ap.add_argument('--ref-variant', default='ev6')
    ap.add_argument('--patches', default=os.path.join(ROOT, 'patches'))
    ap.add_argument('--work')
    a = ap.parse_args()
    work = a.work or tempfile.mkdtemp(prefix='port-')
    os.makedirs(work, exist_ok=True)
    log('work dir:', work)

    # stock checksums of the new car, and the library
    stock = {}
    for _, names in PARTS:
        for n in names:
            for ext in ('apk', 'odex'):
                stock['/system/app/%s.%s' % (n, ext)] = md5(os.path.join(a.new_stock, 'app', '%s.%s' % (n, ext)))
    stock['/system/lib/' + LIB] = md5(os.path.join(a.new_stock, 'lib', LIB))
    if stock['/system/lib/' + LIB] != md5(os.path.join(a.ref_stock, 'lib', LIB)):
        sys.exit('STOP: %s differs from the reference car; it needs its own patch' % LIB)

    # framework definitions of the new car, for the system-call check
    fwdir = os.path.join(work, 'fw')
    if not os.path.isdir(fwdir):
        for f in sorted(os.listdir(a.new_fw)):
            if f.endswith('.odex'):
                subprocess.run(['baksmali', 'd', '-a', '18', '--allow-odex-opcodes', os.path.join(a.new_fw, f),
                                '-o', os.path.join(fwdir, f[:-5])], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    fw_defs = defs_of(fwdir)

    report, manual = [], []
    builds = {}
    for part, names in PARTS:
        for n in names:
            E = os.path.join(work, 'ref_' + n); K = os.path.join(work, 'new_' + n)
            if not os.path.isdir(E): deodex(os.path.join(a.ref_stock, 'app', n + '.odex'), a.ref_fw, E)
            if not os.path.isdir(K): deodex(os.path.join(a.new_stock, 'app', n + '.odex'), a.new_fw, K)
            T = os.path.join(work, '%s_%s_build' % (part, n))
            if not os.path.isdir(T): disasm(os.path.join(a.ref_builds, part, files_dir(a.ref_variant), n + '.apk'), T)
            ce, ck, ct = classes(E), classes(K), classes(T)
            changed = {c for c in ct if c not in ce or norm_lines(os.path.join(E, c)) != norm_lines(os.path.join(T, c))}
            differs = {c for c in ck if c not in ce or norm_lines(os.path.join(E, c)) != norm_lines(os.path.join(K, c))}
            # rename maps from every differing class that is a pure rename
            gmap, renamed = {}, set()
            for c in differs:
                if c in ce:
                    m = rename_map(norm_lines(os.path.join(E, c)), norm_lines(os.path.join(K, c)))
                    if m is not None: gmap.update(m); renamed.add(c)
            out = os.path.join(work, '%s_%s_new' % (part, n))
            if os.path.isdir(out): shutil.rmtree(out)
            shutil.copytree(T, out)
            took, merged = 0, []
            for c in sorted(differs):
                dst = os.path.join(out, c)
                if c not in changed:
                    os.makedirs(os.path.dirname(dst), exist_ok=True); shutil.copy(os.path.join(K, c), dst); took += 1
                    continue
                e, t, k = (norm_lines(os.path.join(x, c)) for x in (E, T, K))
                res = None
                if c in renamed:
                    res = apply_map(t, gmap, own_class(t)); how = 'renamed members'
                if res is None:
                    with tempfile.TemporaryDirectory() as tmp: res = three_way(e, t, k, tmp)
                    how = '3-way patch'
                if res is None:
                    manual.append('%s %s: %s' % (part, n, c)); continue
                open(dst, 'w').write('\n'.join(res) + '\n'); merged.append('%s (%s)' % (c, how))
            # our changed classes that we kept from the reference: carry renames into them
            for c in changed - differs:
                p = os.path.join(out, c)
                lines = open(p, encoding='utf-8').read().split('\n')
                fixed = apply_map(lines, gmap, own_class(norm_lines(p)))
                if fixed != lines: open(p, 'w').write('\n'.join(fixed)); merged.append('%s (renamed references)' % c)
            report.append('%s %s: %d classes differ on this car, %d taken as is, merged: %s'
                          % (part, n, len(differs), took, ', '.join(merged) or 'none'))
            builds[(part, n)] = out
    if manual:
        log('\n'.join(report))
        sys.exit('STOP: these classes differ on this car AND carry our changes; merge them by hand:\n  ' + '\n  '.join(manual))

    # checks: nothing new left unresolved, every system call exists
    problems = []
    for (part, n), out in builds.items():
        base = unresolved(os.path.join(work, '%s_%s_build' % (part, n))) | unresolved(os.path.join(work, 'new_' + n))
        new_bad = unresolved(out) - base
        if new_bad: problems.append('%s %s: unresolved %s' % (part, n, sorted(new_bad)[:5]))
        fw_bad = unresolved(out, fw_defs)
        if fw_bad: problems.append('%s %s: missing in this framework %s' % (part, n, sorted(fw_bad)[:5]))
    if problems:
        log('\n'.join(report))
        sys.exit('STOP: checks failed:\n  ' + '\n  '.join(problems))

    # assemble the full builds (private) and the patch set
    fd = files_dir(a.variant)
    for (part, n), out in builds.items():
        d = os.path.join(a.out_builds, part, fd); os.makedirs(d, exist_ok=True)
        dex = os.path.join(work, '%s_%s.dex' % (part, n))
        T = os.path.join(work, '%s_%s_build' % (part, n))
        if not any(not filecmp.cmp(os.path.join(T, c), os.path.join(out, c), shallow=False) for c in classes(T)) \
                and classes(T) == classes(out):
            # same code as the reference: reuse its dex byte for byte
            open(dex, 'wb').write(zipfile.ZipFile(os.path.join(a.ref_builds, part, files_dir(a.ref_variant), n + '.apk')).read('classes.dex'))
        else:
            run('smali', 'a', '-a', '19', out, '-o', dex)
        run(LPATCH, 'zipadd', os.path.join(a.new_stock, 'app', n + '.apk'), dex, os.path.join(d, n + '.apk'))
    shutil.copy(os.path.join(a.ref_builds, '2_tbt', files_dir(a.ref_variant), LIB), os.path.join(a.out_builds, '2_tbt', fd, LIB))
    FILES.setdefault(a.variant, fd)
    run(sys.executable, os.path.join(HERE, 'mkpatches.py'), a.variant, a.new_stock, a.out_builds, a.patches)
    with open(os.path.join(a.patches, a.variant, 'stock'), 'w') as f:
        for p, s in sorted(stock.items()): f.write('%s %s\n' % (os.path.basename(p), s))
    cars = os.path.join(a.patches, 'cars')
    lines = [l for l in (open(cars).read().splitlines() if os.path.exists(cars) else []) if l.split()[1:2] != [a.variant]]
    # the installer takes the first matching prefix, so go above any shorter one that also matches
    at = next((i for i, l in enumerate(lines) if l and not l.startswith('#') and a.prefix.startswith(l.split()[0])), len(lines))
    lines.insert(at, '%s %s %s' % (a.prefix, a.variant, a.name))
    open(cars, 'w').write('\n'.join(lines) + '\n')
    log('\n'.join(report))
    log('OK: patches/%s written and %s added to patches/cars' % (a.variant, a.name))

if __name__ == '__main__':
    main()
