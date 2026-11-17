package com.aljaroudi.muntathir.ui.rakaat

import androidx.camera.core.SurfaceRequest
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.aljaroudi.muntathir.camera.SujoodCamera
import com.aljaroudi.muntathir.core.app.AppModel
import com.aljaroudi.muntathir.core.progress.PrayerCompletion
import com.aljaroudi.muntathir.core.progress.PrayerProgress
import com.aljaroudi.muntathir.core.progress.PrayerSessionRecording
import com.aljaroudi.muntathir.core.rakaat.RakaatUpdate
import com.aljaroudi.muntathir.data.user.ProgressStore
import com.aljaroudi.muntathir.location.QiblaSensors
import com.aljaroudi.muntathir.ui.navigation.RakaatSessionRoute
import dagger.assisted.Assisted
import dagger.assisted.AssistedFactory
import dagger.assisted.AssistedInject
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.transformWhile
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.Instant
import javax.inject.Inject

@HiltViewModel
class RakaatSetupViewModel
    @Inject
    constructor(
        val qibla: QiblaSensors,
    ) : ViewModel()

/** What the session screen shows. Swift `RakaatSessionView`'s state. */
data class RakaatSessionState(
    val update: RakaatUpdate? = null,
    val ended: Boolean = false,
    val denied: Boolean = false,
    /** The camera couldn't be used or capture was interrupted. */
    val failed: Boolean = false,
    /** The completed prayer couldn't be saved; it can be retried. */
    val saveFailed: Boolean = false,
) {
    val preparing: Boolean get() = !ended && update?.calibrated != true

    val rakaat: Int get() = (update?.count ?: 0) / 2

    val complete: Boolean get() = update?.complete == true

    private val counting: Boolean get() = update?.calibrated == true && update.failure == null && !denied && !failed

    /** The lower half darkens while the face covers the camera. */
    val showsSujoodProgress: Boolean get() = counting && update!!.count % 2 == 1

    fun showsMilestoneTint(target: Int): Boolean =
        counting && update!!.count % 2 == 0 && (rakaat == 2 || rakaat == target)
}

/**
 * One counting session for [route]. Survives configuration changes; [end] (leaving the screen or the app) stops
 * the camera for good. One [PrayerSessionRecording] per session: the prayer is snapshotted when calibration
 * succeeds and saved once on completion.
 */
@HiltViewModel(assistedFactory = RakaatSessionViewModel.Factory::class)
class RakaatSessionViewModel
    @AssistedInject
    constructor(
        @Assisted val route: RakaatSessionRoute,
        private val camera: SujoodCamera,
        private val model: AppModel,
        private val history: ProgressStore,
        val qibla: QiblaSensors,
    ) : ViewModel() {
        @AssistedFactory
        interface Factory {
            fun create(route: RakaatSessionRoute): RakaatSessionViewModel
        }

        private val mutableState = MutableStateFlow(RakaatSessionState())
        val state: StateFlow<RakaatSessionState> = mutableState.asStateFlow()

        val preview: StateFlow<SurfaceRequest?> = camera.preview

        private val recording = PrayerSessionRecording()
        private var session: Job? = null
        private var unsaved: PrayerCompletion? = null

        /** Asked once per session; a recreated screen doesn't ask again. */
        var permissionRequested = false

        /** Starts counting with the camera permission result. */
        fun start(granted: Boolean) {
            if (state.value.ended || session != null) return
            if (!granted) {
                mutableState.update { it.copy(denied = true, ended = true) }
                return
            }
            session =
                viewModelScope.launch {
                    var finished = false
                    try {
                        camera
                            .updates(route.target)
                            .transformWhile {
                                emit(it)
                                !it.complete && it.failure == null
                            }.collect {
                                accept(it)
                                finished = it.complete || it.failure != null
                            }
                    } catch (cancellation: CancellationException) {
                        throw cancellation
                    } catch (_: Exception) {
                        // Reported below as an ended capture.
                    }
                    mutableState.update { it.copy(failed = it.failed || !finished, ended = true) }
                }
        }

        /** Ends the session and stops the camera; an ended session stays ended. */
        fun end() {
            session?.cancel()
            mutableState.update { if (it.ended) it else it.copy(ended = true) }
        }

        fun retrySave() {
            unsaved?.let(::save)
        }

        private fun accept(update: RakaatUpdate) {
            mutableState.update { it.copy(update = update) }
            val now = Instant.now()
            val completed =
                recording.update(update.calibrated, update.complete, update.failure != null, now) {
                    route.prayer?.let { prayer ->
                        val app = model.state.value
                        PrayerProgress.snapshot(prayer, now, app.location, app.preferences.prayerMethod)
                    }
                }
            completed?.let(::save)
        }

        private fun save(prayer: PrayerCompletion) {
            unsaved = prayer
            mutableState.update { it.copy(saveFailed = false) }
            viewModelScope.launch {
                // Leaving the screen right after completion must not drop the record.
                val saved = withContext(NonCancellable) { runCatching { history.save(prayer) }.isSuccess }
                if (saved) unsaved = null
                mutableState.update { it.copy(saveFailed = !saved) }
            }
        }
    }
