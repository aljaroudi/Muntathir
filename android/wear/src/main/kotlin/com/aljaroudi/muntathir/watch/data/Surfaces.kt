package com.aljaroudi.muntathir.watch.data

import android.content.ComponentName
import android.content.Context
import androidx.wear.tiles.TileService
import androidx.wear.watchface.complications.datasource.ComplicationDataSourceUpdateRequester
import com.aljaroudi.muntathir.watch.complications.CountdownComplicationService
import com.aljaroudi.muntathir.watch.complications.HijriDateComplicationService
import com.aljaroudi.muntathir.watch.complications.NextPrayerComplicationService
import com.aljaroudi.muntathir.watch.tile.PrayerTileService

/** Asks complications and the tile to re-render after the snapshot changed (Swift `reloadAllTimelines`). */
object Surfaces {
    fun refresh(context: Context) {
        listOf(
            HijriDateComplicationService::class.java,
            NextPrayerComplicationService::class.java,
            CountdownComplicationService::class.java,
        ).forEach {
            ComplicationDataSourceUpdateRequester.create(context, ComponentName(context, it)).requestUpdateAll()
        }
        TileService.getUpdater(context).requestUpdate(PrayerTileService::class.java)
    }
}
