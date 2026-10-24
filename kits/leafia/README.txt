HMG Leafia Plus kit (read-only) - one kit for checking your car, reporting a
problem, and helping port the package to a new car

This copy's size is in LEAFIA-LEVEL: quick (public report only), standard
(+ logs and key files), port (+ stock system files, ~90 MB) or full (+ every
crash record). Use the one a maintainer asked for.

1. Copy everything in this zip to the root of an exFAT/FAT32 USB drive with
   at least 200 MB free. No other NEMESIS files on the drive.
2. Reporting a problem? Make it happen once just before (for CarPlay or
   Android Auto: try to connect), and run the kit before turning the car
   off: the Android log is lost when the car powers down.
3. Car on, plug in the drive, tap Yes. Wait for the success message
   (1-2 minutes).
4. The kit writes a LEAFIA folder on the drive:

   LEAFIA/public    Safe to share publicly.
                    - Checking your car: drop public/LEAFIA-REPORT.txt on
                      https://vyssecodes.github.io/HMG-Leafia-Plus/
                    - Reporting a problem: zip the public folder and attach
                      it to your GitHub issue.

   LEAFIA/private   Never post this. Only send it privately, and only when a
                    maintainer asks for it:
                    - logs/   Android and kernel logs: can include your
                              phone's name or Bluetooth address
                    - stock/  Hyundai/Kia system files, used to port the
                              package to your car
                    - keys/   firmware key files

Crash records: by default only the latest are collected (up to 300 from the
day before the newest one, and the newest day's crash dumps). If a
maintainer asks for all of them, create an empty file named ALL-CRASHES
next to NEMESIS.sh on the drive before running the kit.

Nothing on the car is changed. Accounts, paired phone data, Wi-Fi passwords,
the vehicle security partition, VIN and serial numbers are never collected.
