package com.aljaroudi.muntathir.widgets

import android.content.Context
import android.widget.RemoteViews
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.LocalContext
import androidx.glance.LocalSize
import androidx.glance.appwidget.AndroidRemoteViews
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.provideContent
import androidx.glance.layout.Column
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.core.app.AppState
import com.aljaroudi.muntathir.core.prayer.WidgetPrayerSettings
import com.aljaroudi.muntathir.core.sky.SolarPosition
import com.aljaroudi.muntathir.ui.components.Formats
import com.aljaroudi.muntathir.ui.components.title
import com.aljaroudi.muntathir.ui.navigation.OpenRequest
import java.time.Instant

/**
 * Swift `CombinedPrayerWidget` (small): the next prayer with its time and countdown, then as many upcoming
 * prayers as fit, on a sky tint that follows the sun.
 */
class PrayerWidget : GlanceAppWidget() {
    override val sizeMode = SizeMode.Responsive(setOf(COMPACT, MEDIUM, TALL))

    override suspend fun provideGlance(
        context: Context,
        id: GlanceId,
    ) {
        val deps = context.widgetDeps()
        provideContent {
            val app by deps.model().state.collectAsState()
            val revision by deps.updater().revision.collectAsState()
            key(revision) { PrayerContent(app, deps.clock().instant()) }
        }
    }

    private companion object {
        val COMPACT = DpSize(110.dp, 110.dp)
        val MEDIUM = DpSize(110.dp, 150.dp)
        val TALL = DpSize(110.dp, 190.dp)
    }
}

/** The prayer settings every surface (widget, tile, refresh alarm) reads from the app state. */
val AppState.prayerSettings: WidgetPrayerSettings
    get() =
        WidgetPrayerSettings(
            location,
            preferences.prayerMethod,
            preferences.hiddenPrayers,
            preferences.imsakMinutes,
        )

@Composable
private fun PrayerContent(
    app: AppState,
    now: Instant,
) {
    val context = LocalContext.current
    val locale = context.widgetLocale
    val location = app.location
    val upcoming = app.prayerSettings.upcomingPrayers(now)
    val elevation = location?.let { SolarPosition.calculate(now, it.latitude, it.longitude) }?.elevation
    val background =
        when {
            elevation == null -> R.drawable.widget_background
            elevation < -6 -> R.drawable.widget_sky_night
            elevation < 10 -> R.drawable.widget_sky_twilight
            else -> R.drawable.widget_sky_day
        }
    WidgetSurface(background, OpenRequest.intent(context, null)) {
        val next = upcoming.firstOrNull()
        when {
            location == null -> {
                Column {
                    WidgetText(context.getString(R.string.prayer_times), 15f, font = WidgetFont.Strong)
                    Spacer(GlanceModifier.height(4.dp))
                    WidgetText(
                        context.getString(R.string.choose_a_location_in_muntathir),
                        13f,
                        font = WidgetFont.Secondary,
                        maxLines = 3,
                    )
                }
            }

            next == null -> {
                WidgetText(
                    context.getString(R.string.prayer_times_unavailable_for_this_location_and_d),
                    13f,
                    font = WidgetFont.Secondary,
                    maxLines = 4,
                )
            }

            else -> {
                Column(GlanceModifier.fillMaxWidth()) {
                    WidgetText(context.getString(next.name.title), 15f, font = WidgetFont.Strong)
                    WidgetText(Formats.clockTime(next.time, location.zone, locale), 26f, font = WidgetFont.Strong)
                    WidgetCountdown(next.time, now)
                    val rows =
                        when {
                            LocalSize.current.height >= 190.dp -> 2
                            LocalSize.current.height >= 150.dp -> 1
                            else -> 0
                        }
                    for (prayer in upcoming.drop(1).take(rows)) {
                        Spacer(GlanceModifier.height(6.dp))
                        // One layout per row: Glance rows of RemoteViews children collapse or drop out.
                        val row =
                            RemoteViews(context.packageName, R.layout.widget_prayer_row).apply {
                                setTextViewText(R.id.widget_prayer_name, context.getString(prayer.name.title))
                                setTextViewText(
                                    R.id.widget_prayer_time,
                                    Formats.clockTime(prayer.time, location.zone, locale),
                                )
                            }
                        AndroidRemoteViews(row, GlanceModifier.fillMaxWidth())
                    }
                }
            }
        }
    }
}
