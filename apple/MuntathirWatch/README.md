# Apple Watch

The `MuntathirWatch` scheme builds the watchOS 26+ app and its [complications](../MuntathirWatchWidgets/). The iPhone app embeds both.

The Watch shows prayer times and has no settings of its own. WatchConnectivity sends it the location, method, visibility, and month corrections. The Watch caches the latest valid snapshot and calculates times offline. Open the iPhone app after changing settings, since delivery is opportunistic.

Enable `group.com.aljaroudi.Muntathir` on both Watch targets. Check paired-device sync and watch-face rendering on real hardware.
