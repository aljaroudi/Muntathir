package com.aljaroudi.muntathir.watch.complications

import android.app.PendingIntent
import android.content.Intent
import android.graphics.drawable.Icon
import androidx.annotation.DrawableRes
import androidx.wear.watchface.complications.data.ComplicationData
import androidx.wear.watchface.complications.data.ComplicationText
import androidx.wear.watchface.complications.data.ComplicationType
import androidx.wear.watchface.complications.data.LongTextComplicationData
import androidx.wear.watchface.complications.data.MonochromaticImage
import androidx.wear.watchface.complications.data.PlainComplicationText
import androidx.wear.watchface.complications.data.ShortTextComplicationData
import androidx.wear.watchface.complications.datasource.ComplicationDataTimeline
import androidx.wear.watchface.complications.datasource.ComplicationRequest
import androidx.wear.watchface.complications.datasource.SuspendingTimelineComplicationDataSourceService
import androidx.wear.watchface.complications.datasource.TimeInterval
import androidx.wear.watchface.complications.datasource.TimelineEntry
import com.aljaroudi.muntathir.core.wear.Span
import com.aljaroudi.muntathir.core.wear.WatchSnapshot
import com.aljaroudi.muntathir.watch.Formats
import com.aljaroudi.muntathir.watch.MainActivity
import com.aljaroudi.muntathir.watch.R
import com.aljaroudi.muntathir.watch.data.WatchStore
import java.time.Instant
import java.util.Locale

/** What a complication shows: [text] with an optional [title], read aloud as [description]. */
data class Content(
    val text: ComplicationText,
    val title: ComplicationText?,
    val description: String,
)

/**
 * Short and long text complications rendered as a timeline from the cached snapshot, so they stay right
 * between updates (Swift `WatchProvider`). Without a snapshot they ask to open the phone app.
 */
abstract class WatchComplicationService : SuspendingTimelineComplicationDataSourceService() {
    @get:DrawableRes
    protected abstract val icon: Int

    /** Spans from [from] onward; empty when there's nothing to show. */
    protected abstract fun spans(
        snapshot: WatchSnapshot,
        from: Instant,
        type: ComplicationType,
        locale: Locale,
    ): List<Span<Content>>

    /** Sample content for the watch face editor. */
    protected abstract fun preview(
        type: ComplicationType,
        locale: Locale,
    ): Content

    override suspend fun onComplicationRequest(request: ComplicationRequest): ComplicationDataTimeline? {
        val type = request.complicationType
        if (type != ComplicationType.SHORT_TEXT && type != ComplicationType.LONG_TEXT) return null
        val locale = Formats.locale(this)
        val spans = WatchStore.current(this)?.let { spans(it, Instant.now(), type, locale) }.orEmpty()
        if (spans.isEmpty()) return ComplicationDataTimeline(data(type, openPhone(type)), emptyList())
        return ComplicationDataTimeline(
            data(type, spans.first().value),
            spans.map { TimelineEntry(TimeInterval(it.start, it.end), data(type, it.value)) },
        )
    }

    override fun getPreviewData(type: ComplicationType): ComplicationData? =
        if (type == ComplicationType.SHORT_TEXT || type == ComplicationType.LONG_TEXT) {
            data(type, preview(type, Formats.locale(this)))
        } else {
            null
        }

    private fun openPhone(type: ComplicationType): Content {
        val message = getString(R.string.open_muntathir_on_your_phone)
        return Content(plain(if (type == ComplicationType.SHORT_TEXT) "—" else message), null, message)
    }

    private fun data(
        type: ComplicationType,
        content: Content,
    ): ComplicationData {
        val description = plain(content.description)
        val image = MonochromaticImage.Builder(Icon.createWithResource(this, icon)).build()
        val tap =
            PendingIntent.getActivity(
                this,
                0,
                Intent(this, MainActivity::class.java),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
        return if (type == ComplicationType.SHORT_TEXT) {
            ShortTextComplicationData
                .Builder(content.text, description)
                .setTitle(content.title)
                .setMonochromaticImage(image)
                .setTapAction(tap)
                .build()
        } else {
            LongTextComplicationData
                .Builder(content.text, description)
                .setTitle(content.title)
                .setMonochromaticImage(image)
                .setTapAction(tap)
                .build()
        }
    }

    protected fun plain(text: CharSequence): ComplicationText = PlainComplicationText.Builder(text).build()
}
