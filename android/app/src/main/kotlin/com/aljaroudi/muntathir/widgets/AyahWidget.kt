package com.aljaroudi.muntathir.widgets

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.LocalContext
import androidx.glance.LocalSize
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.provideContent
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.core.app.AppState
import com.aljaroudi.muntathir.core.quran.DailyAyah
import com.aljaroudi.muntathir.ui.navigation.OpenRequest
import com.aljaroudi.muntathir.ui.today.dailyTranslation
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import java.time.Instant

/**
 * Swift `DailyAyahWidget` (medium): today's verse in Hafs, with the selected installed translation below when
 * there is room. The verse turns over at sunset, like Today's card.
 */
class AyahWidget : GlanceAppWidget() {
    override val sizeMode = SizeMode.Responsive(setOf(SHORT, TALL))

    override suspend fun provideGlance(
        context: Context,
        id: GlanceId,
    ) {
        val deps = context.widgetDeps()
        val translations = deps.translations()
        val initial = translations.state.value.let { it.activeID to it.revision }
        val initialSchedule = deps.quran().dailyAyah(initial.first)
        provideContent {
            val translation by remember {
                translations.state.map { it.activeID to it.revision }.distinctUntilChanged()
            }.collectAsState(initial)
            // The schedule carries only the selected translation, as on Today.
            val schedule by produceState(initialSchedule, translation) {
                value = deps.quran().dailyAyah(translation.first)
            }
            val app by deps.model().state.collectAsState()
            val revision by deps.updater().revision.collectAsState()
            key(revision) { AyahContent(app, schedule, deps.clock().instant()) }
        }
    }

    private companion object {
        val SHORT = DpSize(250.dp, 110.dp)
        val TALL = DpSize(250.dp, 150.dp)
    }
}

@Composable
private fun AyahContent(
    app: AppState,
    schedule: DailyAyah,
    now: Instant,
) {
    val context = LocalContext.current
    // Sunset regardless of hidden times, as on Today.
    val ayah = schedule.verse(now, app.engine, app.prayerSettings.copy(hiddenPrayers = emptySet()))
    WidgetSurface(R.drawable.widget_ayah_background, OpenRequest.intent(context, null), Alignment.Center) {
        if (ayah == null) {
            WidgetText(context.getString(R.string.verse_unavailable), 13f, font = WidgetFont.Secondary)
            return@WidgetSurface
        }
        Column(GlanceModifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
            WidgetText(ayah.text, 22f, GlanceModifier.fillMaxWidth(), font = WidgetFont.Quran, maxLines = 2)
            val translation = dailyTranslation(ayah)
            if (translation != null && LocalSize.current.height >= 150.dp) {
                Spacer(GlanceModifier.height(6.dp))
                WidgetText(translation, 12f, GlanceModifier.fillMaxWidth(), font = WidgetFont.Centered, maxLines = 3)
            }
        }
    }
}
