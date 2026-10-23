#!/usr/bin/env python3
"""Make the per-car patch set for the Wireless CarPlay/AA package.

usage: mkpatches.py <variant> <stock dir> <payload dir> <out patches dir>

  <stock dir>    the car's stock files: app/<name>.apk, app/<name>.odex,
                 lib/libautoreceiver_infobank.so
  <payload dir>  the modified builds: 2_tbt/<files>/..., 3_bridge/<files>/...
                 (<files> = files, files_neev, files_dl3hev for ev6/neev/dl3hev)

Writes <out>/<variant>/*.lpd, <out>/common/*.lpd and <out>/<variant>/manifest.
Each manifest line:  <part> <kind> <name> <patch> <expected md5 of the result>
The expected md5 of an app is the APK `lpatch zipadd` builds on the head unit
(stock APK + rebuilt classes.dex), computed here with the host build of lpatch.
"""
import hashlib, os, subprocess, sys, tempfile, zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
LPATCH = os.path.join(HERE, 'lpatch', 'lpatch-host')
MKDELTA = os.path.join(HERE, 'mkdelta.py')
FILES = {'ev6': 'files', 'neev': 'files_neev', 'dl3hev': 'files_dl3hev'}
PARTS = [('2_tbt', 'tbt', ['HKMC_GPM', 'HKMC_DiPO', 'Iap2ServerApp', 'HKMC_Navi_ExSL']),
         ('3_bridge', 'bridge', ['Iap2ServerApp', 'HKMC_DiPO'])]
LIB = 'libautoreceiver_infobank.so'

def md5(p): return hashlib.md5(open(p, 'rb').read()).hexdigest()
def run(*a): subprocess.run(a, check=True, stdout=subprocess.DEVNULL)

def main():
    if len(sys.argv) > 1 and sys.argv[1] in ('-h', '--help'):
        print(__doc__)
        return
    if len(sys.argv) != 5:
        sys.exit(__doc__)
    var, stock, pay, out = sys.argv[1:5]
    fdir = FILES.get(var, 'files_' + var)
    os.makedirs(os.path.join(out, var), exist_ok=True)
    os.makedirs(os.path.join(out, 'common'), exist_ok=True)
    lines = []
    with tempfile.TemporaryDirectory() as t:
        for part, stage, names in PARTS:
            for n in names:
                tgt_apk = os.path.join(pay, part, fdir, n + '.apk')
                dex = os.path.join(t, n + '.dex')
                open(dex, 'wb').write(zipfile.ZipFile(tgt_apk).read('classes.dex'))
                lpd = '%s.%s.lpd' % (n, stage)
                run(sys.executable, MKDELTA, os.path.join(stock, 'app', n + '.odex'), dex, os.path.join(out, var, lpd))
                built = os.path.join(t, n + '.built.apk')
                rebuilt = os.path.join(t, n + '.rebuilt.dex')
                run(LPATCH, 'delta', os.path.join(out, var, lpd), os.path.join(stock, 'app', n + '.odex'), rebuilt)
                run(LPATCH, 'zipadd', os.path.join(stock, 'app', n + '.apk'), rebuilt, built)
                lines.append('%s app %s %s/%s %s' % (part, n, var, lpd, md5(built)))
        lib_lpd = os.path.join(out, 'common', LIB.replace('.so', '.tbt.lpd'))
        run(sys.executable, MKDELTA, os.path.join(stock, 'lib', LIB), os.path.join(pay, '2_tbt', fdir, LIB), lib_lpd)
        lines.append('2_tbt file %s common/%s %s' % (LIB, os.path.basename(lib_lpd), md5(os.path.join(pay, '2_tbt', fdir, LIB))))
    open(os.path.join(out, var, 'manifest'), 'w').write('\n'.join(lines) + '\n')
    print('\n'.join(lines))

if __name__ == '__main__':
    main()
