package com.daudio.app.dipo.e;

import android.content.Context;
import android.content.Intent;
import android.os.SystemClock;

/**
 * LeafiaBridge hook inside DiPO (the CarPlay app). DiPO calls route() with each
 * parsed CarPlay route update; this forwards the destination, distance, time
 * left and guidance state to LeafiaBridge only. It lives in DiPO's own package
 * so it can read the parsed update through DiPO's accessors, and it never throws
 * back into DiPO.
 *
 * Hook (in e/u.c(Object), just before each parsed component goes on to the
 * cluster): invoke-static {v0}, Lcom/daudio/app/dipo/e/LeafiaForward;->route(Ljava/lang/Object;)V
 */
public final class LeafiaForward {
    private static final String PKG = "leafia.bridge";
    private static final String ACTION = PKG + ".ROUTE";
    private static final long REPEAT_MS = 10000;   // an unchanged update goes out at most every 10 s

    private static String sDest;
    private static int sState = Integer.MIN_VALUE;
    private static long sSentAt;

    private LeafiaForward() {}

    public static void route(Object o) {
        try {
            if (!(o instanceof c)) return;
            c r = (c) o;
            String dest = c.f(r);       // destination name
            int state = c.a(r);         // route guidance state
            long distM = c.g(r) & 0xffffffffL;   // distance remaining, metres (unsigned)
            long timeS = c.h(r);        // time remaining, seconds
            long now = SystemClock.elapsedRealtime();
            boolean same = state == sState && (dest == null ? sDest == null : dest.equals(sDest));
            if (same && now - sSentAt < REPEAT_MS) return;
            sState = state;
            sDest = dest;
            sSentAt = now;
            Context ctx = (Context) Class.forName("android.app.ActivityThread")
                    .getMethod("currentApplication").invoke(null);
            if (ctx == null) return;
            ctx.sendBroadcast(new Intent(ACTION).setPackage(PKG)
                    .putExtra("source", "carplay")
                    .putExtra("state", state)
                    .putExtra("dest", dest)
                    .putExtra("distM", distM)
                    .putExtra("timeS", timeS));
        } catch (Throwable t) {
            // never disturb CarPlay
        }
    }
}
