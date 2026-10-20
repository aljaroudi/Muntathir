# Apple Watch

The `MuntathirWatch` scheme builds the watchOS 26+ companion app and its WidgetKit extension. The iPhone target embeds both. The watch shows the visible prayer times; settings remain on the iPhone.

WatchConnectivity transfers the latest location, method, visibility settings, and Hijri month corrections. The watch caches this snapshot and calculates times locally while disconnected. Open the iPhone app after installation or configuration changes. Delivery is opportunistic; changes can take time to reach a disconnected watch. Invalid snapshots preserve the last valid settings.

Enable the existing `group.com.aljaroudi.Muntathir` App Group for both watch targets when signing. App Groups share data between the watch app and its extension; WatchConnectivity transfers it between devices. Paired-device sync and watch-face rendering require device validation.

See [complications](../MuntathirWatchWidgets/) and [Apple setup](../).
