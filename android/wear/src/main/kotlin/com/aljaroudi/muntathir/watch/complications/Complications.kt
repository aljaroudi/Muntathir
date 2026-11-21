package com.aljaroudi.muntathir.watch.complications

import androidx.wear.watchface.complications.data.ComplicationType
import androidx.wear.watchface.complications.data.CountDownTimeReference
import androidx.wear.watchface.complications.data.TimeDifferenceComplicationText
import androidx.wear.watchface.complications.data.TimeDifferenceStyle
import com.aljaroudi.muntathir.core.prayer.PrayerMoment
import com.aljaroudi.muntathir.core.wear.Span
import com.aljaroudi.muntathir.core.wear.WatchSnapshot
import com.aljaroudi.muntathir.core.wear.WatchTimeline
import com.aljaroudi.muntathir.watch.Formats
import com.aljaroudi.muntathir.watch.R
import com.aljaroudi.muntathir.watch.title
import java.time.Instant
import java.util.Locale
import java.util.concurrent.TimeUnit

/** Swift `WatchDateWidget`: the corrected Hijri day and month. */
class HijriDateComplicationService : WatchComplicationService() {
    override val icon = R.drawable.ic_moon

    override fun spans(
        snapshot: WatchSnapshot,
        from: Instant,
        type: ComplicationType,
        locale: Locale,
    ): List<Span<Content>> {
        val engine = runCatching { snapshot.calendar.engine() }.getOrNull() ?: return emptyList()
        return WatchTimeline.days(engine.zone, from).map { span ->
            val day = engine.resolve(span.value)
            Span(
                span.start,
                span.end,
                content(Formats.number(day.day, locale), Formats.hijriMonth(day.month.month, locale), type),
            )
        }
    }

    override fun preview(
        type: ComplicationType,
        locale: Locale,
    ) = content(Formats.number(14, locale), Formats.hijriMonth(9, locale), type)

    private fun content(
        day: String,
        month: String,
        type: ComplicationType,
    ) = if (type == ComplicationType.SHORT_TEXT) {
        Content(plain(day), plain(month), "$day $month")
    } else {
        Content(plain("$day $month"), null, "$day $month")
    }
}

/** Swift `WatchNextPrayerWidget`: the next prayer and its time. */
class NextPrayerComplicationService : WatchComplicationService() {
    override val icon = R.drawable.ic_prayer

    override fun spans(
        snapshot: WatchSnapshot,
        from: Instant,
        type: ComplicationType,
        locale: Locale,
    ): List<Span<Content>> {
        val zone = snapshot.prayers.location?.zone ?: return emptyList()
        return WatchTimeline.nextPrayers(snapshot.prayers, from).map { span ->
            val prayer = span.value
            val name = getString(prayer.name.title)
            val time = Formats.clockTime(prayer.time, zone, locale)
            val spoken = "$name ${Formats.time(prayer.time, zone, locale)}"
            val content =
                if (type == ComplicationType.SHORT_TEXT) {
                    Content(plain(time), plain(name), spoken)
                } else {
                    Content(plain("$name $time"), null, spoken)
                }
            Span(span.start, span.end, content)
        }
    }

    override fun preview(
        type: ComplicationType,
        locale: Locale,
    ): Content {
        val name = getString(R.string.maghrib)
        val time = "6:24"
        return if (type ==
            ComplicationType.SHORT_TEXT
        ) {
            Content(plain(time), plain(name), name)
        } else {
            Content(plain("$name $time"), null, name)
        }
    }
}

/** Swift `WatchCountdownWidget`: the next prayer with a countdown the watch face keeps ticking. */
class CountdownComplicationService : WatchComplicationService() {
    override val icon = R.drawable.ic_prayer

    override fun spans(
        snapshot: WatchSnapshot,
        from: Instant,
        type: ComplicationType,
        locale: Locale,
    ): List<Span<Content>> {
        val zone = snapshot.prayers.location?.zone ?: return emptyList()
        return WatchTimeline.nextPrayers(snapshot.prayers, from).map { span ->
            val prayer = span.value
            val name = getString(prayer.name.title)
            Span(span.start, span.end, content(prayer, name, Formats.clockTime(prayer.time, zone, locale), type))
        }
    }

    override fun preview(
        type: ComplicationType,
        locale: Locale,
    ) = content(
        PrayerMoment(com.aljaroudi.muntathir.core.prayer.PrayerName.Maghrib, Instant.now().plusSeconds(5_400)),
        getString(R.string.maghrib),
        "6:24",
        type,
    )

    private fun content(
        prayer: PrayerMoment,
        name: String,
        time: String,
        type: ComplicationType,
    ): Content {
        val countdown =
            TimeDifferenceComplicationText
                .Builder(TimeDifferenceStyle.SHORT_DUAL_UNIT, CountDownTimeReference(prayer.time))
                .setMinimumTimeUnit(TimeUnit.MINUTES)
                .apply { if (type == ComplicationType.LONG_TEXT) setText("$name ^1") }
                .build()
        return Content(countdown, if (type == ComplicationType.SHORT_TEXT) plain(name) else plain(time), "$name $time")
    }
}
