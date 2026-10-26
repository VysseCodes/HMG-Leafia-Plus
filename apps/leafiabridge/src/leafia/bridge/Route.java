package leafia.bridge;

/** One route update, as forwarded by a projection app. */
final class Route {
    // route guidance states (iAP2 RouteGuidanceState)
    static final int NO_ROUTE = 0;
    static final int ACTIVE = 1;
    static final int ARRIVED = 2;
    static final int LOADING = 3;
    static final int LOCATING = 4;
    static final int REROUTING = 5;
    static final int PROCEED_TO_ROUTE = 6;

    final String source;
    final int state;
    final String dest;
    final long distM;
    final long timeS;

    Route(String source, int state, String dest, long distM, long timeS) {
        this.source = source == null ? "?" : source;
        this.state = state;
        this.dest = dest == null ? "" : dest;
        this.distM = distM;
        this.timeS = timeS;
    }

    /** a route is being followed (rerouting and the like still count) */
    boolean guiding() {
        return state == ACTIVE || state == REROUTING || state == PROCEED_TO_ROUTE
                || state == LOADING || state == LOCATING;
    }

    @Override
    public String toString() {
        return source + " state=" + state + " dest=\"" + dest + "\" distM=" + distM + " timeS=" + timeS;
    }
}
