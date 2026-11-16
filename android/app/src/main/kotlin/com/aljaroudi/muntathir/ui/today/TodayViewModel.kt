package com.aljaroudi.muntathir.ui.today

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.aljaroudi.muntathir.core.app.AppModel
import com.aljaroudi.muntathir.core.app.AppState
import com.aljaroudi.muntathir.core.calendar.CalendarEngine
import com.aljaroudi.muntathir.core.calendar.EventLibrary
import com.aljaroudi.muntathir.core.calendar.ResolvedDay
import com.aljaroudi.muntathir.core.calendar.UpcomingEvent
import com.aljaroudi.muntathir.core.location.SavedLocation
import com.aljaroudi.muntathir.core.prayer.PrayerCalculator
import com.aljaroudi.muntathir.core.prayer.PrayerMoment
import com.aljaroudi.muntathir.core.prayer.PrayerName
import com.aljaroudi.muntathir.core.prayer.WidgetPrayerSettings
import com.aljaroudi.muntathir.core.quran.Ayah
import com.aljaroudi.muntathir.core.quran.DailyAyah
import com.aljaroudi.muntathir.core.sky.MoonPosition
import com.aljaroudi.muntathir.core.sky.SolarArcMarker
import com.aljaroudi.muntathir.core.sky.SolarPosition
import com.aljaroudi.muntathir.data.QuranDatabase
import com.aljaroudi.muntathir.data.minutes
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import java.time.Clock
import java.time.Instant
import javax.inject.Inject

/** Everything the Today screen shows at one instant. Swift `TodayView`'s per-tick values. */
data class TodayUi(
    val now: Instant,
    val engine: CalendarEngine,
    val day: ResolvedDay,
    val location: SavedLocation?,
    /** Visible times for today, in order. */
    val prayers: List<PrayerMoment>,
    /** The next visible prayer (never Imsak, Sunrise…), today or tomorrow. */
    val next: PrayerMoment?,
    val enabledPrayers: Set<PrayerName>,
    val sun: SolarPosition?,
    val moon: MoonPosition?,
    val markers: List<SolarArcMarker>,
    val event: UpcomingEvent?,
    val ayah: Ayah?,
    val surahNames: Map<Int, String> = emptyMap(),
) {
    companion object {
        fun make(
            app: AppState,
            now: Instant,
            library: EventLibrary,
            daily: DailyAyah,
            surahNames: Map<Int, String>,
        ): TodayUi {
            val preferences = app.preferences
            val location = app.location
            val engine = app.engine
            val visible =
                WidgetPrayerSettings(
                    location,
                    preferences.prayerMethod,
                    preferences.hiddenPrayers,
                    preferences.imsakMinutes,
                )
            // Verse and event days roll over at sunset, whichever times are hidden.
            val sunset = WidgetPrayerSettings(location, preferences.prayerMethod, emptySet(), preferences.imsakMinutes)
            val prayers =
                location
                    ?.let { place ->
                        PrayerCalculator
                            .times(place.localDate(now), place, preferences.prayerMethod, preferences.imsakMinutes)
                            .filter { preferences.isVisible(it.name) }
                    }.orEmpty()
            return TodayUi(
                now = now,
                engine = engine,
                day = engine.resolve(now),
                location = location,
                prayers = prayers,
                next = visible.nextPrayer(now),
                enabledPrayers = preferences.enabledPrayers,
                sun = location?.let { SolarPosition.calculate(now, it.latitude, it.longitude) },
                moon = location?.let { MoonPosition.calculate(now, it.latitude, it.longitude) },
                markers = location?.let { SolarArcMarker.make(prayers, now, it) }.orEmpty(),
                event = library.upcomingEvent(now, engine, sunset::sunset),
                ayah = daily.verse(now, engine, sunset),
                surahNames = surahNames,
            )
        }
    }
}

private fun SavedLocation.localDate(instant: Instant) = instant.atZone(zone).toLocalDate()

@HiltViewModel
class TodayViewModel
    @Inject
    constructor(
        private val model: AppModel,
        library: EventLibrary,
        quran: QuranDatabase,
        clock: Clock,
    ) : ViewModel() {
        private val daily = MutableStateFlow(DailyAyah(emptyList()))
        private val names = MutableStateFlow(emptyMap<Int, String>())

        init {
            viewModelScope.launch {
                names.value = quran.surahNames()
                daily.value = quran.dailyAyah(QuranDatabase.ENGLISH)
            }
        }

        val state: StateFlow<TodayUi> =
            combine(model.state, clock.minutes(), daily, names) { app, now, daily, names ->
                TodayUi.make(app, now, library, daily, names)
            }.stateIn(
                viewModelScope,
                SharingStarted.WhileSubscribed(5_000),
                TodayUi.make(model.state.value, clock.instant(), library, daily.value, names.value),
            )

        /** Swift `setPrayer`: the screen asks for notification permission before enabling. */
        fun setAlert(
            prayer: PrayerName,
            enabled: Boolean,
            allowed: Boolean,
        ) = viewModelScope.launch { model.setPrayer(prayer, enabled, allowed) }

        fun hide(prayer: PrayerName) =
            viewModelScope.launch {
                model.update {
                    it.copy(
                        hiddenPrayers =
                            it.hiddenPrayers + prayer,
                    )
                }
            }
    }
