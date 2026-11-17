package com.aljaroudi.muntathir.widgets

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.updateAll
import com.aljaroudi.muntathir.core.app.AppModel
import com.aljaroudi.muntathir.data.AppScope
import com.aljaroudi.muntathir.data.QuranTranslations
import com.aljaroudi.muntathir.notifications.AlarmScheduler
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.time.Clock
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Keeps placed widgets current, like `Rescheduler` does for alerts: it re-renders them whenever what they show
 * changes, and keeps one alarm for the next boundary (a prayer passing, sunset or midnight). With no widgets
 * placed, it does nothing and the alarm is cancelled.
 */
@Singleton
class WidgetUpdater
    @Inject
    constructor(
        @param:ApplicationContext private val context: Context,
        private val model: AppModel,
        private val translations: QuranTranslations,
        private val clock: Clock,
        @param:AppScope private val scope: CoroutineScope,
    ) {
        private val alarms = context.getSystemService(AlarmManager::class.java)
        private val widgets: List<GlanceAppWidget> get() = listOf(PrayerWidget(), AyahWidget(), HijriWidget())
        private val updates = MutableStateFlow(0)

        /**
         * Bumped by every update. Widgets read it so that an open Glance session recomposes too: the time and the
         * language aren't Compose state, and `updateAll` alone doesn't recompose a running session.
         */
        val revision: StateFlow<Int> = updates

        fun start() {
            scope.launch {
                combine(model.state, translations.state) { app, translation ->
                    listOf(app.preferences, app.location, app.confirmations, translation.activeID, translation.revision)
                }.distinctUntilChanged().collect { update() }
            }
        }

        /** Re-renders every placed widget, then sets the alarm for the next change. */
        private suspend fun update() {
            val placed = placed()
            updates.update { it + 1 }
            placed.forEach { it.updateAll(context) }
            schedule(enabled = placed.isNotEmpty())
        }

        /** [update] off the caller, for receivers: [onDone] finishes their `goAsync`. */
        fun refresh(onDone: () -> Unit = {}) {
            scope.launch {
                try {
                    update()
                } finally {
                    onDone()
                }
            }
        }

        /** Resets only the alarm, after Glance itself rendered a newly placed widget (or one was removed). */
        fun reschedule() {
            scope.launch { schedule(enabled = placed().isNotEmpty()) }
        }

        private suspend fun placed(): List<GlanceAppWidget> {
            val manager = GlanceAppWidgetManager(context)
            return widgets.filter { manager.getGlanceIds(it.javaClass).isNotEmpty() }
        }

        private fun schedule(enabled: Boolean) {
            val intent =
                PendingIntent.getBroadcast(
                    context,
                    0,
                    Intent(context, WidgetRefreshReceiver::class.java),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
            if (!enabled) {
                alarms.cancel(intent)
                return
            }
            val state = model.state.value
            val at = state.prayerSettings.nextChange(clock.instant(), state.zone).toEpochMilli()
            // RTC, not RTC_WAKEUP: widgets only need to be right once the screen is on.
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarms.canScheduleExactAlarms()) {
                alarms.setExact(AlarmManager.RTC, at, intent)
            } else {
                // Plain set() may wait up to an hour; keep the window alerts use.
                alarms.setWindow(AlarmManager.RTC, at, AlarmScheduler.INEXACT_WINDOW.toMillis(), intent)
            }
        }
    }

/** The boundary alarm: re-render and set the next one. */
class WidgetRefreshReceiver : BroadcastReceiver() {
    override fun onReceive(
        context: Context,
        intent: Intent,
    ) {
        val pending = goAsync()
        context.widgetDeps().updater().refresh(pending::finish)
    }
}

/** Each widget's receiver; a newly placed or removed widget also resets the boundary alarm. */
abstract class WidgetReceiver : GlanceAppWidgetReceiver() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        super.onUpdate(context, appWidgetManager, appWidgetIds)
        context.widgetDeps().updater().reschedule()
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        context.widgetDeps().updater().reschedule()
    }
}

class PrayerWidgetReceiver : WidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = PrayerWidget()
}

class AyahWidgetReceiver : WidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = AyahWidget()
}

class HijriWidgetReceiver : WidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = HijriWidget()
}
