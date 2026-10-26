package com.daudio.app.deviceconnections.ui.connectivitySettings;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.util.Log;

/**
 * The page the stock projection popup's Settings button asks for. Opens the head
 * unit's real Device Connections screen with the popup's own extras
 * (from_micom_popup, which Device Connections reads), then closes.
 */
public class PhoneProjectionSettingsActivity extends Activity {
    private static final String TAG = "LeafiaPopupFix";
    private static final String PP = "com.daudio.app.phoneprojection";

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        Intent in = getIntent();
        Intent out = new Intent(Intent.ACTION_MAIN)
                .setClassName(PP, PP + ".settings.ui.DeviceConnectionSettings")
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        if (in != null && in.getExtras() != null) out.putExtras(in.getExtras());
        try {
            startActivity(out);
            Log.i(TAG, "opened Device Connections for the projection popup");
        } catch (Exception e) {
            // a firmware with the screen under another name: its own action still finds it
            try {
                startActivity(new Intent(PP).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            } catch (Exception e2) {
                Log.w(TAG, "no Device Connections screen: " + e2);
            }
        }
        finish();
    }
}
