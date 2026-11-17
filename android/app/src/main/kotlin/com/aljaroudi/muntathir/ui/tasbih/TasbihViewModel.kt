package com.aljaroudi.muntathir.ui.tasbih

import androidx.lifecycle.ViewModel
import com.aljaroudi.muntathir.core.progress.ProgressActivity
import com.aljaroudi.muntathir.core.progress.ProgressActivityKind
import com.aljaroudi.muntathir.core.tasbih.TasbihSession
import com.aljaroudi.muntathir.data.user.ProgressStore
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.util.UUID
import javax.inject.Inject

/**
 * One visit's round (Swift `TasbihView` state): every counted bead saves the visit's running total for Activity
 * under one id, dated when the visit began.
 */
@HiltViewModel
class TasbihViewModel
    @Inject
    constructor(
        private val progress: ProgressStore,
    ) : ViewModel() {
        private val state = MutableStateFlow(TasbihSession())
        val session: StateFlow<TasbihSession> = state.asStateFlow()
        private var activityId = newId()
        private var startedAt = now()

        fun advance() {
            val previous = state.value
            val next = previous.advanced()
            if (next.total == previous.total) return
            state.value = next
            progress.record(ProgressActivity(ProgressActivityKind.Tasbih, next.total.toDouble(), activityId, startedAt))
        }

        /** Starts the next visit at zero. */
        fun reset() {
            state.value = TasbihSession()
            activityId = newId()
            startedAt = now()
        }

        private companion object {
            fun newId() = UUID.randomUUID().toString().uppercase()

            fun now() = System.currentTimeMillis() / 1000.0
        }
    }
