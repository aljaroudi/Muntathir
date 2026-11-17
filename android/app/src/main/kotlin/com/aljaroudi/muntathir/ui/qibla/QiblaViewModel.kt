package com.aljaroudi.muntathir.ui.qibla

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.aljaroudi.muntathir.core.location.SavedLocation
import com.aljaroudi.muntathir.core.prayer.PrayerCalculator
import com.aljaroudi.muntathir.core.qibla.QiblaAlignment
import com.aljaroudi.muntathir.location.QiblaMapConfig
import com.aljaroudi.muntathir.location.QiblaReading
import com.aljaroudi.muntathir.location.QiblaSensors
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class QiblaUiState(
    val reading: QiblaReading = QiblaReading(),
    /** Degrees from true north to the Kaaba, once there is a fix. */
    val bearing: Double? = null,
    val alignment: QiblaAlignment? = null,
    /** With hysteresis across readings (5° to lock, 8° to release). */
    val aligned: Boolean = false,
) {
    fun next(reading: QiblaReading): QiblaUiState {
        val fix = reading.fix
        val bearing =
            fix?.let {
                // Same calculation as the prayer screen; the zone is irrelevant to the bearing.
                PrayerCalculator.qibla(SavedLocation(it.latitude, it.longitude, "UTC"))
            }
        val heading = reading.heading
        val alignment = if (bearing != null && heading != null) QiblaAlignment.of(bearing, heading.degrees) else null
        return QiblaUiState(reading, bearing, alignment, alignment?.isAligned(previously = aligned) ?: false)
    }
}

/** Runs one [QiblaSensors] session at a time; the screen starts it while visible and stops it when hidden. */
@HiltViewModel
class QiblaViewModel
    @Inject
    constructor(
        private val sensors: QiblaSensors,
        val mapConfig: QiblaMapConfig,
    ) : ViewModel() {
        private val mutableState = MutableStateFlow(QiblaUiState())
        val state: StateFlow<QiblaUiState> = mutableState.asStateFlow()
        private var session: Job? = null

        /** A fresh session (opening, returning from the background, Retry, a permission change). */
        fun start() {
            session?.cancel()
            mutableState.value = QiblaUiState()
            session =
                viewModelScope.launch {
                    sensors.readings(optional = false).collect { reading -> mutableState.update { it.next(reading) } }
                }
        }

        fun stop() {
            session?.cancel()
            session = null
            mutableState.update { QiblaUiState(QiblaReading(status = it.reading.status)) }
        }
    }
