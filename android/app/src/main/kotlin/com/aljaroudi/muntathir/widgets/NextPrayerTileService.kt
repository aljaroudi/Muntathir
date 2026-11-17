package com.aljaroudi.muntathir.widgets

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.graphics.drawable.Icon
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.ui.components.Formats
import com.aljaroudi.muntathir.ui.components.title
import com.aljaroudi.muntathir.ui.navigation.OpenRequest

/**
 * Quick Settings tile: the next prayer and its time, read whenever the panel opens (so it needs no updates of
 * its own). Tapping opens Today.
 */
class NextPrayerTileService : TileService() {
    override fun onStartListening() {
        val tile = qsTile ?: return
        val deps = widgetDeps()
        val state = deps.model().state.value
        val location = state.location
        val next = state.prayerSettings.nextPrayer(deps.clock().instant())
        tile.icon = Icon.createWithResource(this, R.drawable.ic_notification)
        tile.label = next?.let { getString(it.name.title) } ?: getString(R.string.next_prayer)
        val detail =
            when {
                location == null -> getString(R.string.choose_a_location_in_muntathir)
                next == null -> getString(R.string.prayer_times_unavailable_for_this_location_and_d)
                else -> Formats.time(next.time, location.zone, widgetLocale)
            }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) tile.subtitle = detail
        tile.contentDescription = "${tile.label}, $detail"
        tile.state = if (next != null) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.updateTile()
    }

    @SuppressLint("StartActivityAndCollapseDeprecated")
    override fun onClick() {
        val intent = OpenRequest.intent(this, null)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val flags = PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            startActivityAndCollapse(PendingIntent.getActivity(this, 0, intent, flags))
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }
}
