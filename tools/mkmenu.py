#!/usr/bin/env python3
"""Make the Phone Projection menu fix (part 5_menu) for one car's HKMC_BtSettings.

usage: mkmenu.py <stock dir> [--framework DIR] [--patches DIR] [--work DIR]

  <stock dir>  a stock tree (a port kit's LEAFIA/private/stock/) with
               app/HKMC_BtSettings.apk, app/HKMC_BtSettings.odex and
               framework/*.odex from the same firmware (or give --framework)

With the wireless CarPlay/AA features on, HKMC_BtSettings sends Settings > Phone
Projection to the wireless projection page. This adds a region check in front of
that choice, so US/Canada units keep opening Device Connections (the stock US
behaviour); other regions are unchanged. The edit is found by its structure, not
by label names, and the script stops unless the code is exactly the known shape.

Writes patches/common/HKMC_BtSettings.menu.<stock md5 prefix>.lpd and adds its line
to patches/common/optional (replacing an older line for the same stock file).
The head unit applies whichever line matches its own stock app.

Needs: java with baksmali/smali 2.5.2 (~/.local/share/smali, or BAKSMALI/SMALI),
the host lpatch (tools/lpatch/build.sh) and bsdiff4 (tools/requirements.txt).
"""
import argparse, hashlib, os, re, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
LPATCH = os.path.join(HERE, 'lpatch', 'lpatch-host')
MKDELTA = os.path.join(HERE, 'mkdelta.py')
SMALI_DIR = os.path.expanduser('~/.local/share/smali')
BAKSMALI = os.environ.get('BAKSMALI', os.path.join(SMALI_DIR, 'baksmali-2.5.2.jar'))
SMALI = os.environ.get('SMALI', os.path.join(SMALI_DIR, 'smali-2.5.2.jar'))
BCP = ['core', 'conscrypt', 'okhttp', 'core-junit', 'bouncycastle', 'ext', 'framework', 'framework2',
       'telephony-common', 'voip-common', 'mms-common', 'android.policy', 'services', 'apache-xml',
       'webviewchromium', 'automotive']
CLASS = 'com/android/settings2/bluetooth/BluetoothSettings.smali'
HOOK = '''    # HMG Leafia Plus: on US/Canada units Phone Projection keeps opening Device Connections
    # (as on stock US firmware) even with the wireless projection features on
    sget v0, Lcom/hkmc/BuildInfo;->REGION:I

    if-eq v0, v2, {lbl}

    add-int/lit8 v0, v0, -0x4

    if-eqz v0, {lbl}

'''
# the choice as it is in the 260507 EV6 app: wireless features -> wireless page,
# otherwise US (v2 = 1) or Canada (4) -> Device Connections
SHAPE = re.compile(
    r'    const-string v0, "com\.hkmc\.software\.connectivity\.carplay_wireless"\n\n'
    r'    invoke-static \{v0\}, Lcom/hkmc/Feature;->hasFeature\(Ljava/lang/String;\)Z\n\n'
    r'    move-result v0\n\n'
    r'    if-nez v0, (:cond_\w+)\n\n'
    r'    const-string v0, "com\.hkmc\.software\.connectivity\.androidauto_wireless"\n\n'
    r'    invoke-static \{v0\}, Lcom/hkmc/Feature;->hasFeature\(Ljava/lang/String;\)Z\n\n'
    r'    move-result v0\n\n'
    r'    if-eqz v0, (:cond_\w+)\n\n'
    r'(?:    \.line \d+\n)?    \1\n'
    r'(?:.*\n){1,8}?'
    r'    invoke-static \{v0\}, Lcom/android/settings2/bluetooth/\w+;->\w+\(Landroid/content/Context;\)V\n\n'
    r'    goto/16 :goto_\w+\n\n'
    r'(?:    \.line \d+\n)?    \2\n'
    r'    sget v0, Lcom/hkmc/BuildInfo;->REGION:I\n\n'
    r'    if-eq v0, v2, :cond_\w+\n')


def md5(p):
    return hashlib.md5(open(p, 'rb').read()).hexdigest()


def run(*a, **kw):
    subprocess.run(a, check=True, **kw)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('stock')
    ap.add_argument('--framework', help='framework dir (default: <stock dir>/framework)')
    ap.add_argument('--patches', default=os.path.join(HERE, '..', 'patches'))
    ap.add_argument('--work')
    a = ap.parse_args()
    odex = os.path.join(a.stock, 'app', 'HKMC_BtSettings.odex')
    apk = os.path.join(a.stock, 'app', 'HKMC_BtSettings.apk')
    fw = a.framework or os.path.join(a.stock, 'framework')
    for f in (odex, apk) + tuple(os.path.join(fw, b + '.odex') for b in BCP):
        if not os.path.isfile(f):
            sys.exit('missing ' + f)
    for f in (BAKSMALI, SMALI, LPATCH):
        if not os.path.isfile(f):
            sys.exit('missing %s (see --help)' % f)
    stock_md5 = md5(odex)
    work = a.work or tempfile.mkdtemp(prefix='mkmenu.')
    smali_dir = os.path.join(work, 'smali')
    shutil.rmtree(smali_dir, ignore_errors=True)
    extra = [os.path.join(fw, f) for f in sorted(os.listdir(fw))
             if f.endswith('.odex') and f[:-5] not in BCP]
    r = subprocess.run(['java', '-jar', BAKSMALI, 'x', '-a', '18', '-d', fw,
                        '-b', ':'.join(os.path.join(fw, b + '.odex') for b in BCP),
                        '-c', ':'.join(extra), '-o', smali_dir, odex],
                       capture_output=True, text=True)
    if r.returncode != 0 or 'Error occurred' in r.stdout + r.stderr:
        sys.exit('deodex failed (check the framework is from the same firmware):\n' + (r.stdout + r.stderr)[-2000:])
    p = os.path.join(smali_dir, CLASS)
    s = open(p, encoding='utf-8').read()
    if 'HMG Leafia Plus' in s:
        sys.exit('this HKMC_BtSettings already carries the fix: use the stock file')
    m = list(SHAPE.finditer(s))
    if len(m) != 1:
        sys.exit('the Phone Projection choice in %s is not the known shape (%d matches): merge by hand' % (CLASS, len(m)))
    s = s[:m[0].start()] + HOOK.format(lbl=m[0].group(2)) + s[m[0].start():]
    open(p, 'w', encoding='utf-8').write(s)
    dex = os.path.join(work, 'classes.dex')
    run('java', '-jar', SMALI, 'a', '--api', '18', '-j', '1', '-o', dex, smali_dir)

    name = 'HKMC_BtSettings.menu.%s.lpd' % stock_md5[:8]
    common = os.path.join(a.patches, 'common')
    lpd = os.path.join(common, name)
    run(sys.executable, MKDELTA, odex, dex, lpd, stdout=subprocess.DEVNULL)
    rebuilt, built = os.path.join(work, 'rebuilt.dex'), os.path.join(work, 'built.apk')
    run(LPATCH, 'delta', lpd, odex, rebuilt, stdout=subprocess.DEVNULL)
    run(LPATCH, 'zipadd', apk, rebuilt, built, stdout=subprocess.DEVNULL)
    line = '5_menu app HKMC_BtSettings common/%s %s' % (name, md5(built))

    opt = os.path.join(common, 'optional')
    lines = open(opt).read().splitlines() if os.path.exists(opt) else []
    lines = [l for l in lines if ('common/%s ' % name) not in l]
    lines.append(line)
    open(opt, 'w').write('\n'.join(lines) + '\n')
    print(line)


if __name__ == '__main__':
    main()
