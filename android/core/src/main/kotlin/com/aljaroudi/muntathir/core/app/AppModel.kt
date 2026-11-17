package com.aljaroudi.muntathir.core.app

import com.aljaroudi.muntathir.core.calendar.CalendarEngine
import com.aljaroudi.muntathir.core.calendar.CalendarException
import com.aljaroudi.muntathir.core.calendar.HijriMonth
import com.aljaroudi.muntathir.core.calendar.MonthOffset
import com.aljaroudi.muntathir.core.feed.Announcement
import com.aljaroudi.muntathir.core.feed.CorrectionsFeed
import com.aljaroudi.muntathir.core.feed.FeedClient
import com.aljaroudi.muntathir.core.location.SavedLocation
import com.aljaroudi.muntathir.core.prayer.PrayerName
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.Serializable
import java.time.Instant
import java.time.ZoneId

/** Device-only state, never backed up (Swift `onboardingCompleted`, `onboardingStep`, `deviceLocation.v1`, `announcements.delivered`). */
@Serializable
data class DeviceState(
    val onboardingCompleted: Boolean = false,
    val onboardingStep: Int = 0,
    val liveLocation: SavedLocation? = null,
    val deliveredAnnouncements: Set<String> = emptySet(),
) {
    companion object {
        val STEPS = 0..4
    }
}

/** Persistence for [AppModel]; the app backs it with DataStore, tests with memory. */
interface AppStorage {
    /** The stored preferences, or `null` when missing, malformed or invalid. */
    suspend fun loadPreferences(): Preferences?

    suspend fun savePreferences(preferences: Preferences)

    suspend fun loadDevice(): DeviceState

    suspend fun saveDevice(state: DeviceState)
}

/** Posts one month announcement; returns whether it was delivered. */
fun interface Announcer {
    suspend fun post(announcement: Announcement): Boolean
}

sealed interface AppError {
    data object InvalidPreferences : AppError

    data class Calendar(
        val kind: CalendarException.Kind,
    ) : AppError

    data object NotificationsDisabled : AppError
}

/** A snapshot of everything screens and schedulers read. */
data class AppState(
    val preferences: Preferences,
    val device: DeviceState,
    val confirmations: List<Announcement>,
    /** Bumped by every preference or location change; guards against stale feed responses. */
    val revision: Int,
    val systemZone: ZoneId,
) {
    val location: SavedLocation? get() = device.liveLocation

    val zone: ZoneId get() = location?.zone ?: systemZone

    val engine: CalendarEngine by lazy {
        runCatching {
            CalendarEngine.withOffsets(zone, preferences.monthOffsets, confirmations.map { it.correction })
        }.getOrElse { CalendarEngine(zone) }
    }
}

/**
 * App-wide state and its validated mutations. Port of Swift `AppModel` without iCloud: every change is
 * validated (including building a calendar) before anything is saved, and failures leave state untouched.
 */
class AppModel private constructor(
    private val storage: AppStorage,
    private val feedClient: FeedClient?,
    private val announcer: Announcer,
    private val clock: () -> Instant,
    initial: AppState,
) {
    private val mutableState = MutableStateFlow(initial)
    val state: StateFlow<AppState> = mutableState.asStateFlow()

    private val mutableErrors = MutableSharedFlow<AppError>(extraBufferCapacity = 8)
    val errors: SharedFlow<AppError> = mutableErrors.asSharedFlow()

    private val mutex = Mutex()

    private fun fail(error: AppError): Boolean {
        mutableErrors.tryEmit(error)
        return false
    }

    /** Throws [CalendarException] when the combination can't form a calendar. */
    private fun check(
        location: SavedLocation?,
        offsets: List<MonthOffset>,
        confirmations: List<Announcement>,
        systemZone: ZoneId,
    ) {
        CalendarEngine.withOffsets(location?.zone ?: systemZone, offsets, confirmations.map { it.correction })
    }

    suspend fun update(change: (Preferences) -> Preferences): Boolean =
        mutex.withLock {
            val current = mutableState.value
            val updated = change(current.preferences).normalized()
            if (!updated.isValid) return fail(AppError.InvalidPreferences)
            try {
                check(
                    current.device.liveLocation,
                    updated.monthOffsets,
                    current.confirmations,
                    current.systemZone,
                )
            } catch (error: CalendarException) {
                return fail(AppError.Calendar(error.kind))
            }
            storage.savePreferences(updated)
            mutableState.value = current.copy(preferences = updated, revision = current.revision + 1)
            true
        }

    /** Stores a device fix locally; it never enters the backed-up preferences. */
    suspend fun applyLive(location: SavedLocation): Boolean =
        mutex.withLock {
            val current = mutableState.value
            if (!location.isValid) return false
            try {
                check(location, current.preferences.monthOffsets, current.confirmations, current.systemZone)
            } catch (error: CalendarException) {
                return fail(AppError.Calendar(error.kind))
            }
            val device = current.device.copy(liveLocation = location)
            storage.saveDevice(device)
            mutableState.value = current.copy(device = device, revision = current.revision + 1)
            true
        }

    /** Sets [month]'s adjustment; zero removes it. Throws [CalendarException] for an impossible calendar. */
    suspend fun correct(
        month: HijriMonth,
        days: Int,
    ) {
        val current = mutableState.value
        val rows = MonthOffset.replacing(current.preferences.monthOffsets, month, days)
        check(current.location, rows, current.confirmations, current.systemZone)
        update { it.copy(monthOffsets = rows) }
    }

    /** Swift `setPrayer`; the caller requests notification permission first and passes the result. */
    suspend fun setPrayer(
        prayer: PrayerName,
        enabled: Boolean,
        notificationsAllowed: Boolean = true,
    ): Boolean {
        if (enabled && !notificationsAllowed) return fail(AppError.NotificationsDisabled)
        return update {
            it.copy(enabledPrayers = if (enabled) it.enabledPrayers + prayer else it.enabledPrayers - prayer)
        }
    }

    suspend fun moveOnboarding(by: Int) =
        mutex.withLock {
            val current = mutableState.value
            val device =
                current.device.copy(
                    onboardingStep = (current.device.onboardingStep + by).coerceIn(DeviceState.STEPS),
                )
            storage.saveDevice(device)
            mutableState.value = current.copy(device = device)
        }

    suspend fun completeOnboarding(): Boolean =
        mutex.withLock {
            val current = mutableState.value
            if (current.location?.isValid != true) return false
            val device = current.device.copy(onboardingCompleted = true, onboardingStep = 0)
            storage.saveDevice(device)
            mutableState.value = current.copy(device = device)
            true
        }

    /** Applies a feed's confirmations and announces the current and next months'. Throws [CalendarException] on conflict. */
    suspend fun receive(feed: CorrectionsFeed) {
        val relevant =
            mutex.withLock {
                val current = mutableState.value
                val location = current.location ?: return
                val matching = feed.confirmations(location, current.preferences.monthOffsets)
                val next = current.copy(confirmations = matching)
                mutableState.value = next
                if (!next.preferences.announcementNotifications) return
                val month = next.engine.resolve(clock()).month
                matching.filter { it.month >= month && it.month <= month.advanced(1) }
            }
        announce(relevant)
    }

    private suspend fun announce(rows: List<Announcement>) {
        val delivered = mutableSetOf<String>()
        for (row in rows) {
            val key = "${row.id}.${row.revision}"
            if (key in mutableState.value.device.deliveredAnnouncements) continue
            if (announcer.post(row)) delivered += key
        }
        if (delivered.isEmpty()) return
        mutex.withLock {
            val current = mutableState.value
            val device = current.device.copy(deliveredAnnouncements = current.device.deliveredAnnouncements + delivered)
            storage.saveDevice(device)
            mutableState.value = current.copy(device = device)
        }
    }

    /**
     * Refreshes the corrections feed. A response for preferences or a location that changed while it was in
     * flight is dropped, so it can't overwrite the current calendar. Returns whether the refresh applied.
     */
    suspend fun refreshFeed(): Boolean {
        val client = feedClient ?: return true
        val before = mutableState.value
        val location = before.location ?: return true
        return try {
            val feed = client.refresh()
            val now = mutableState.value
            if (now.revision != before.revision || now.location != location) return false
            receive(feed)
            true
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            false
        }
    }

    companion object {
        suspend fun load(
            storage: AppStorage,
            feedClient: FeedClient? = null,
            announcer: Announcer = Announcer { false },
            systemZone: ZoneId = ZoneId.systemDefault(),
            clock: () -> Instant = Instant::now,
        ): AppModel {
            val preferences = storage.loadPreferences() ?: Preferences()
            val stored = storage.loadDevice()
            val device =
                stored.copy(
                    onboardingStep = stored.onboardingStep.coerceIn(DeviceState.STEPS),
                    liveLocation = stored.liveLocation?.takeIf { it.isValid },
                )
            var state = AppState(preferences, device, emptyList(), 0, systemZone)
            val location = state.location
            val cached = feedClient?.cachedFeed()
            if (cached != null && location != null) {
                runCatching { cached.confirmations(location, preferences.monthOffsets) }
                    .onSuccess { state = state.copy(confirmations = it) }
            }
            return AppModel(storage, feedClient, announcer, clock, state)
        }
    }
}
