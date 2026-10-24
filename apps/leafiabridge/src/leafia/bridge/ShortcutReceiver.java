package leafia.bridge;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Bundle;

/**
 * The star keys. The head unit broadcasts these when a star key is pressed:
 *   com.mobis.intent.action.CUSTOM_SHORTCUT        dashboard star key
 *   com.mobis.intent.action.SWRC_CUSTOM_SHORTCUT   steering-wheel star key
 *   com.hkmc.intent.action.DIPO_CUSTOM_SHORTCUT    either, during CarPlay
 *   com.hkmc.intent.action.GPM_CUSTOM_SHORTCUT     either, during Android Auto
 * Their extras aren't documented, so every press logs them all.
 */
public class ShortcutReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context ctx, Intent i) {
        StringBuilder extras = new StringBuilder();
        Bundle b = i.getExtras();
        if (b != null) {
            for (String k : b.keySet()) {
                extras.append(' ').append(k).append('=').append(b.get(k));
            }
        }
        Precondition.get(ctx).onStarKey(i.getAction(), extras.toString());
    }
}
