package com.aljaroudi.muntathir.widgets

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.ui.unit.dp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.LocalContext
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.provideContent
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.width
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.core.app.AppState
import com.aljaroudi.muntathir.core.app.AppTool
import com.aljaroudi.muntathir.ui.components.Formats
import com.aljaroudi.muntathir.ui.navigation.OpenRequest
import java.time.Instant

/** Swift `IslamicCalendarWidget` (small): corrected Hijri day and month, weekday, Gregorian date. No weather. */
class HijriWidget : GlanceAppWidget() {
    override suspend fun provideGlance(
        context: Context,
        id: GlanceId,
    ) {
        val deps = context.widgetDeps()
        provideContent {
            val app by deps.model().state.collectAsState()
            val revision by deps.updater().revision.collectAsState()
            key(revision) { HijriContent(app, deps.clock().instant()) }
        }
    }
}

@Composable
private fun HijriContent(
    app: AppState,
    now: Instant,
) {
    val context = LocalContext.current
    val locale = context.widgetLocale
    val engine = app.engine
    val day = engine.resolve(now)
    val date = engine.localDate(now)
    WidgetSurface(R.drawable.widget_background, OpenRequest.intent(context, AppTool.Calendar)) {
        // Full width, so the month wraps at the widget's edge rather than at the day row's width.
        Column(GlanceModifier.fillMaxWidth()) {
            Row(verticalAlignment = Alignment.Bottom) {
                WidgetText(Formats.number(day.day, locale), 36f, font = WidgetFont.Strong)
                Spacer(GlanceModifier.width(8.dp))
                WidgetText(Formats.date(date, "EEE", locale), 12f, font = WidgetFont.Secondary)
            }
            WidgetText(Formats.hijriMonth(day.month.month, locale), 17f, font = WidgetFont.Strong, maxLines = 2)
            WidgetText(Formats.date(date, "dMMM", locale), 12f, font = WidgetFont.Secondary)
        }
    }
}
