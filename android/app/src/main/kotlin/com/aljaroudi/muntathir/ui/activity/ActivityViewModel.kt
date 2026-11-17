package com.aljaroudi.muntathir.ui.activity

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.aljaroudi.muntathir.core.highlight.QuranUserStore
import com.aljaroudi.muntathir.core.prayer.PrayerName
import com.aljaroudi.muntathir.core.progress.PrayerCompletion
import com.aljaroudi.muntathir.core.progress.PrayerProgress
import com.aljaroudi.muntathir.core.progress.PrayerTiming
import com.aljaroudi.muntathir.core.progress.ProgressActivity
import com.aljaroudi.muntathir.core.progress.ProgressActivityKind
import com.aljaroudi.muntathir.data.user.ProgressStore
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

/** Swift `ActivityProgressView` totals. */
data class ActivityUiState(
    /** On-time prayer days per prayer, in [PrayerProgress.prayers] order. */
    val onTime: List<Pair<PrayerName, Int>> = PrayerProgress.prayers.map { it to 0 },
    val outsideTime: Int = 0,
    val timingUnavailable: Int = 0,
    val hasPrayers: Boolean = false,
    /** Seconds per reading kind. */
    val reading: Map<ProgressActivityKind, Double> = emptyMap(),
    val beads: Double = 0.0,
    /** `null` while the highlights store is unavailable. */
    val bookmarks: Int? = null,
    val highlights: Int? = null,
    val failed: Boolean = false,
) {
    companion object {
        fun of(
            prayers: List<PrayerCompletion>,
            activities: List<ProgressActivity>,
        ): ActivityUiState {
            val days = PrayerProgress.prayers.associateWith { PrayerProgress.days(it, prayers).values }

            fun count(timing: PrayerTiming) = days.values.sumOf { values -> values.count { it == timing } }
            val totals = ProgressActivity.totals(activities)
            return ActivityUiState(
                onTime = PrayerProgress.prayers.map { it to days.getValue(it).count { t -> t == PrayerTiming.OnTime } },
                outsideTime = count(PrayerTiming.OutsideTime),
                timingUnavailable = count(PrayerTiming.Unavailable),
                hasPrayers = prayers.isNotEmpty(),
                reading = ProgressActivityKind.reading.associateWith { totals[it] ?: 0.0 },
                beads = totals[ProgressActivityKind.Tasbih] ?: 0.0,
            )
        }
    }
}

@OptIn(ExperimentalCoroutinesApi::class)
@HiltViewModel
class ActivityViewModel
    @Inject
    constructor(
        progress: ProgressStore,
        private val user: QuranUserStore,
    ) : ViewModel() {
        private val attempt = MutableStateFlow(0)

        private val totals =
            attempt.flatMapLatest {
                combine(progress.prayerFlow, progress.activityFlow, ActivityUiState::of)
                    .catch { emit(ActivityUiState(failed = true)) }
            }

        val state: StateFlow<ActivityUiState> =
            combine(totals, user.bookmarks, user.highlights, user.unavailable) { totals, bookmarks, highlights, down ->
                totals.copy(
                    bookmarks = bookmarks.size.takeUnless { down },
                    highlights = highlights.size.takeUnless { down },
                )
            }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), ActivityUiState())

        val userUnavailable: StateFlow<Boolean> = user.unavailable

        fun retry() {
            attempt.value++
        }

        fun reopenUserData() {
            viewModelScope.launch { user.reopen() }
        }
    }
