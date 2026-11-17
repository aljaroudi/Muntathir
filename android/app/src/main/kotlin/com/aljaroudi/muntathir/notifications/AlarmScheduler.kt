package com.aljaroudi.muntathir.notifications

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import com.aljaroudi.muntathir.core.app.AppModel
import com.aljaroudi.muntathir.core.app.AppState
import com.aljaroudi.muntathir.core.calendar.EventLibrary
import com.aljaroudi.muntathir.core.prayer.NotificationPlan
import com.aljaroudi.muntathir.core.prayer.ScheduledAlert
import com.aljaroudi.muntathir.data.AppScope
import com.aljaroudi.muntathir.widgets.WidgetUpdater
import dagger.hilt.android.AndroidEntryPoint
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import java.time.Clock
import java.time.Duration
import java.time.Instant
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Keeps one alarm set for the next prayer or event alert. Each alarm posts what's due, then schedules the
 * following one, so nothing has to track a list of pending alarms and the chain isn't limited to the iOS
 * 10-day window. Exact when allowed (`SCHEDULE_EXACT_ALARM`), otherwise within a 10-minute window.
 */
@Singleton
class AlarmScheduler
    @Inject
    constructor(
        @param:ApplicationContext private val context: Context,
        private val library: EventLibrary,
        private val clock: Clock,
    ) {
        private val alarms = context.getSystemService(AlarmManager::class.java)

        val canScheduleExact: Boolean
            get() = Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarms.canScheduleExactAlarms()

        /** Alerts strictly after [after] for [state], soonest first. */
        fun alerts(
            state: AppState,
            after: Instant,
        ): List<ScheduledAlert> {
            val location = state.location ?: return emptyList()
            return NotificationPlan.alerts(after, state.preferences, location, state.engine, library.events)
        }

        fun schedule(
            state: AppState,
            after: Instant = clock.instant(),
        ) {
            val next = alerts(state, after).firstOrNull()
            val intent = pendingIntent(next?.time)
            if (next == null) {
                alarms.cancel(intent)
                return
            }
            val at = next.time.toEpochMilli()
            if (canScheduleExact) {
                alarms.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, intent)
            } else {
                alarms.setWindow(AlarmManager.RTC_WAKEUP, at, INEXACT_WINDOW.toMillis(), intent)
            }
        }

        private fun pendingIntent(at: Instant?): PendingIntent =
            PendingIntent.getBroadcast(
                context,
                0,
                Intent(context, AlarmReceiver::class.java).putExtra(EXTRA_AT, at?.toEpochMilli() ?: 0L),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )

        companion object {
            const val EXTRA_AT = "at"
            val INEXACT_WINDOW: Duration = Duration.ofMinutes(10)

            /** Alerts older than this when their alarm finally fires (e.g. after a long doze) are dropped. */
            val GRACE: Duration = Duration.ofMinutes(30)
        }
    }

/** Fires at an alert's time: posts every alert due at that instant, then sets the next alarm. */
@AndroidEntryPoint
class AlarmReceiver : BroadcastReceiver() {
    @Inject lateinit var model: AppModel

    @Inject lateinit var scheduler: AlarmScheduler

    @Inject lateinit var notifier: Notifier

    @Inject lateinit var clock: Clock

    @Inject @AppScope
    lateinit var scope: CoroutineScope

    override fun onReceive(
        context: Context,
        intent: Intent,
    ) {
        val pending = goAsync()
        scope.launch {
            try {
                val state = model.state.value
                val now = clock.instant()
                val at = Instant.ofEpochMilli(intent.getLongExtra(AlarmScheduler.EXTRA_AT, 0))
                if (Duration.between(at, now) <= AlarmScheduler.GRACE) {
                    // Recompute from current settings: anything changed since scheduling is respected.
                    scheduler
                        .alerts(state, at.minusSeconds(1))
                        .takeWhile { it.time <= at }
                        .forEach { notifier.post(it, state.preferences) }
                }
                scheduler.schedule(state, maxOf(at, now))
            } finally {
                pending.finish()
            }
        }
    }
}

/**
 * Boot, clock, zone, locale, update and exact-alarm permission changes: rebuild the chain (Swift `reschedule()`),
 * and re-render widgets, whose times, dates and language depend on the same things.
 */
@AndroidEntryPoint
class RescheduleReceiver : BroadcastReceiver() {
    @Inject lateinit var model: AppModel

    @Inject lateinit var widgets: WidgetUpdater

    @Inject lateinit var scheduler: AlarmScheduler

    @Inject lateinit var notifier: Notifier

    override fun onReceive(
        context: Context,
        intent: Intent,
    ) {
        val state = model.state.value
        // Locale changes rename the channels.
        notifier.ensureChannels(state.preferences)
        scheduler.schedule(state)
        widgets.refresh(goAsync()::finish)
    }
}

/** Rebuilds channels and the alarm whenever anything notification planning reads changes. */
@Singleton
class Rescheduler
    @Inject
    constructor(
        private val model: AppModel,
        private val scheduler: AlarmScheduler,
        private val notifier: Notifier,
        @param:AppScope private val scope: CoroutineScope,
    ) {
        private data class Inputs(
            val preferences: com.aljaroudi.muntathir.core.app.Preferences,
            val location: com.aljaroudi.muntathir.core.location.SavedLocation?,
            val confirmations: List<com.aljaroudi.muntathir.core.feed.Announcement>,
        )

        fun start() {
            scope.launch {
                model.state
                    .map { Inputs(it.preferences, it.location, it.confirmations) }
                    .distinctUntilChanged()
                    .collect {
                        val state = model.state.value
                        notifier.ensureChannels(state.preferences)
                        scheduler.schedule(state)
                    }
            }
        }
    }
