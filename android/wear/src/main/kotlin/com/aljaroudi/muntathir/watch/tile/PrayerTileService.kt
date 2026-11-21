package com.aljaroudi.muntathir.watch.tile

import android.content.Context
import androidx.concurrent.futures.SuspendToFutureAdapter
import androidx.wear.protolayout.ActionBuilders
import androidx.wear.protolayout.DeviceParametersBuilders.DeviceParameters
import androidx.wear.protolayout.LayoutElementBuilders
import androidx.wear.protolayout.ModifiersBuilders
import androidx.wear.protolayout.ResourceBuilders
import androidx.wear.protolayout.TimelineBuilders
import androidx.wear.protolayout.material3.MaterialScope
import androidx.wear.protolayout.material3.Typography
import androidx.wear.protolayout.material3.materialScope
import androidx.wear.protolayout.material3.primaryLayout
import androidx.wear.protolayout.material3.text
import androidx.wear.protolayout.types.layoutString
import androidx.wear.tiles.RequestBuilders
import androidx.wear.tiles.TileBuilders
import androidx.wear.tiles.TileService
import com.aljaroudi.muntathir.core.prayer.PrayerMoment
import com.aljaroudi.muntathir.core.wear.WatchSnapshot
import com.aljaroudi.muntathir.core.wear.WatchTimeline
import com.aljaroudi.muntathir.watch.Formats
import com.aljaroudi.muntathir.watch.MainActivity
import com.aljaroudi.muntathir.watch.R
import com.aljaroudi.muntathir.watch.data.WatchStore
import com.aljaroudi.muntathir.watch.title
import com.google.common.util.concurrent.ListenableFuture
import java.time.Instant
import java.time.ZoneId

/**
 * "Prayer times" tile: the next prayer and its time, then the two after it. One timeline entry per prayer
 * boundary, so it moves on without being woken; the phone's snapshot refreshes it (`Surfaces`).
 */
class PrayerTileService : TileService() {
    override fun onTileRequest(requestParams: RequestBuilders.TileRequest): ListenableFuture<TileBuilders.Tile> =
        SuspendToFutureAdapter.launchFuture {
            tile(WatchStore.current(this@PrayerTileService), requestParams.deviceConfiguration, Instant.now())
        }

    override fun onTileResourcesRequest(
        requestParams: RequestBuilders.ResourcesRequest,
    ): ListenableFuture<ResourceBuilders.Resources> =
        SuspendToFutureAdapter.launchFuture {
            ResourceBuilders.Resources
                .Builder()
                .setVersion(RESOURCES)
                .build()
        }

    private fun tile(
        snapshot: WatchSnapshot?,
        device: DeviceParameters,
        now: Instant,
    ): TileBuilders.Tile {
        val zone = snapshot?.prayers?.location?.zone
        val spans =
            if (snapshot != null &&
                zone != null
            ) {
                WatchTimeline.nextPrayers(snapshot.prayers, now, count = 12)
            } else {
                emptyList()
            }
        val timeline = TimelineBuilders.Timeline.Builder()
        if (spans.isEmpty()) {
            timeline.addTimelineEntry(entry(layout(device) { message() }))
        } else {
            for ((index, span) in spans.withIndex()) {
                // The two prayers after the next one are the following spans' values.
                val upcoming = spans.drop(index).take(3).map { it.value }
                if (upcoming.size < 3) break
                val validity =
                    TimelineBuilders.TimeInterval
                        .Builder()
                        .setStartMillis(span.start.toEpochMilli())
                        .setEndMillis(span.end.toEpochMilli())
                        .build()
                timeline.addTimelineEntry(entry(layout(device) { prayers(upcoming, zone!!) }, validity))
            }
        }
        val builder =
            TileBuilders.Tile
                .Builder()
                .setResourcesVersion(RESOURCES)
                .setTileTimeline(timeline.build())
        // Ask again before the last entry runs out; without a snapshot, wait for the phone.
        spans.getOrNull(spans.size - 3)?.let {
            builder.setFreshnessIntervalMillis(it.end.toEpochMilli() - now.toEpochMilli())
        }
        return builder.build()
    }

    private fun entry(
        layout: LayoutElementBuilders.LayoutElement,
        validity: TimelineBuilders.TimeInterval? = null,
    ) = TimelineBuilders.TimelineEntry
        .Builder()
        .setLayout(
            LayoutElementBuilders.Layout
                .Builder()
                .setRoot(layout)
                .build(),
        ).apply { validity?.let { setValidity(it) } }
        .build()

    private fun layout(
        device: DeviceParameters,
        main: MaterialScope.() -> LayoutElementBuilders.LayoutElement,
    ) = materialScope(this, device) {
        primaryLayout(
            titleSlot = { text(getString(R.string.prayer_times).layoutString) },
            mainSlot = main,
            onClick = openApp(this@PrayerTileService),
        )
    }

    private fun MaterialScope.prayers(
        upcoming: List<PrayerMoment>,
        zone: ZoneId,
    ): LayoutElementBuilders.LayoutElement {
        val locale = Formats.locale(this@PrayerTileService)
        val next = upcoming.first()
        val column =
            LayoutElementBuilders.Column
                .Builder()
                .addContent(text(getString(next.name.title).layoutString, typography = Typography.TITLE_MEDIUM))
                .addContent(
                    text(Formats.time(next.time, zone, locale).layoutString, typography = Typography.DISPLAY_SMALL),
                )
        for (prayer in upcoming.drop(1)) {
            val line = "${getString(prayer.name.title)} ${Formats.time(prayer.time, zone, locale)}"
            column.addContent(text(line.layoutString, typography = Typography.BODY_SMALL))
        }
        return column.build()
    }

    private fun MaterialScope.message(): LayoutElementBuilders.LayoutElement =
        text(getString(R.string.sync_from_phone).layoutString, typography = Typography.BODY_MEDIUM, maxLines = 4)

    private companion object {
        const val RESOURCES = "1"

        fun openApp(context: Context): ModifiersBuilders.Clickable =
            ModifiersBuilders.Clickable
                .Builder()
                .setId("open")
                .setOnClick(
                    ActionBuilders.LaunchAction
                        .Builder()
                        .setAndroidActivity(
                            ActionBuilders.AndroidActivity
                                .Builder()
                                .setPackageName(context.packageName)
                                .setClassName(MainActivity::class.java.name)
                                .build(),
                        ).build(),
                ).build()
    }
}
