package leafia.bridge;

import android.content.Context;
import android.util.Log;

import java.io.File;
import java.io.FileOutputStream;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

/**
 * Logs to logcat (tag LeafiaBridge) and to files/leafia-bridge.log in the app's
 * private folder, which survives a power-off. The file holds destination names,
 * so the Leafia kit only collects it into its private part.
 */
final class BridgeLog {
    static final String TAG = "LeafiaBridge";
    private static final String FILE = "leafia-bridge.log";
    private static final long MAX_BYTES = 256 * 1024;

    private BridgeLog() {}

    static synchronized void log(Context ctx, String msg) {
        Log.i(TAG, msg);
        File f = new File(ctx.getFilesDir(), FILE);
        if (f.length() > MAX_BYTES) {
            // keep one older file, so the log never grows past twice the limit
            File old = new File(ctx.getFilesDir(), FILE + ".1");
            old.delete();
            f.renameTo(old);
        }
        String line = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(new Date())
                + " " + msg + "\n";
        FileOutputStream out = null;
        try {
            out = new FileOutputStream(f, true);
            out.write(line.getBytes("UTF-8"));
        } catch (Exception e) {
            Log.w(TAG, "could not write " + f + ": " + e);
        } finally {
            if (out != null) {
                try { out.close(); } catch (Exception ignored) {}
            }
        }
    }
}
