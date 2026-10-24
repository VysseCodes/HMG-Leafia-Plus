package leafia.bridge;

import java.util.Locale;

/** Does a destination name look like an EV charger? */
final class Chargers {
    // lower case; matched anywhere in the name
    private static final String[] NAMES = {
        "supercharger", "tesla destination charger",
        "electrify america", "electrify canada", "evgo", "chargepoint", "ionna",
        "blink charging", "ev connect", "shell recharge", "flo ", "petro-canada ev",
        "francis energy", "rivian adventure network", "mercedes-benz charging", "bp pulse",
        "ev charging", "ev charger", "ev station", "charging station", "charging hub",
        "fast charger", "dc fast", "recharge station",
        "충전소", "충전기", "e-pit", "이피트",
    };

    private Chargers() {}

    static boolean isCharger(String dest) {
        if (dest == null || dest.length() == 0) return false;
        String d = dest.toLowerCase(Locale.ROOT) + " ";
        for (String n : NAMES) {
            if (d.contains(n)) return true;
        }
        return false;
    }
}
