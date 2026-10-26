package leafia.bridge;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/**
 * Route updates from the patched projection apps.
 *
 * Action leafia.bridge.ROUTE, sent only to this package.
 * Extras (missing ones are left at their defaults):
 *   source     "carplay" (later also "androidauto")
 *   state      route guidance state as the phone reports it (iAP2: 0 no route,
 *              1 active, 2 arrived, 3 loading, 4 locating, 5 rerouting, 6 proceed to route)
 *   dest       destination name
 *   distM      distance remaining, metres (-1 unknown)
 *   timeS      time remaining, seconds (-1 unknown)
 */
public class RouteReceiver extends BroadcastReceiver {
    static final String ACTION = "leafia.bridge.ROUTE";

    @Override
    public void onReceive(Context ctx, Intent i) {
        if (!ACTION.equals(i.getAction())) return;
        Route r = new Route(
                i.getStringExtra("source"),
                i.getIntExtra("state", -1),
                i.getStringExtra("dest"),
                i.getLongExtra("distM", -1),
                i.getLongExtra("timeS", -1));
        Precondition.get(ctx).onRoute(r);
    }
}
