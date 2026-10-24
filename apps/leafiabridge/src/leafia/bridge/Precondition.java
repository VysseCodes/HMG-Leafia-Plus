package leafia.bridge;

import android.content.Context;
import android.content.SharedPreferences;

/**
 * Battery preconditioning, DRY RUN.
 *
 * Decides what the stock navigation would tell the car (HEVManager:
 * setBattCondEvStation, setBattCondRouteDis, setBattCondRemainTime) and only
 * logs it. This build has no code that talks to the car; sending comes later,
 * in its own reviewed change, and will also check the car's own conditioning
 * setting (getHEVStatus 94) first.
 *
 * State lives in SharedPreferences because the process can be stopped between
 * broadcasts.
 */
final class Precondition {
    private static final long REPEAT_MS = 60 * 1000;   // repeat an unchanged "would send" at most once a minute

    private static Precondition sInstance;

    private final Context ctx;
    private final SharedPreferences prefs;

    static synchronized Precondition get(Context c) {
        if (sInstance == null) sInstance = new Precondition(c.getApplicationContext());
        return sInstance;
    }

    private Precondition(Context c) {
        ctx = c;
        prefs = c.getSharedPreferences("precondition", Context.MODE_PRIVATE);
    }

    synchronized void onRoute(Route r) {
        boolean charger = r.guiding() && Chargers.isCharger(r.dest);
        boolean wasCharger = prefs.getBoolean("charger", false);
        String lastDest = prefs.getString("dest", "");
        long now = System.currentTimeMillis();
        SharedPreferences.Editor e = prefs.edit();

        if (!r.dest.equals(lastDest) || r.state != prefs.getInt("state", -1)) {
            log("route " + r + " charger=" + (charger ? "yes" : "no"));
            e.putString("dest", r.dest).putInt("state", r.state);
        }
        if (charger) {
            if (!wasCharger || now - prefs.getLong("sentAt", 0) >= REPEAT_MS) {
                log("WOULD SEND setBattCondEvStation(1) setBattCondRouteDis(" + r.distM + " m)"
                        + " setBattCondRemainTime(" + minutes(r.timeS) + " min) for \"" + r.dest + "\"");
                e.putLong("sentAt", now);
            }
        } else if (wasCharger) {
            log("WOULD SEND setBattCondEvStation(0): route to a charger ended (" + r + ")");
        }
        e.putBoolean("charger", charger).apply();
    }

    synchronized void onStarKey(String action, String extras) {
        boolean manual = !prefs.getBoolean("manual", false);
        log("star key " + action + extras);
        log(manual
                ? "WOULD SEND manual preconditioning on (a nearby-charger trip, as the star-key feature will)"
                : "WOULD SEND manual preconditioning off");
        prefs.edit().putBoolean("manual", manual).apply();
    }

    private static long minutes(long seconds) {
        return seconds < 0 ? -1 : (seconds + 59) / 60;
    }

    private void log(String msg) {
        BridgeLog.log(ctx, "[precondition, dry run] " + msg);
    }
}
