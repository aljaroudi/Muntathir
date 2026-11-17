package com.aljaroudi.muntathir.ui.reader

import android.os.SystemClock
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.aljaroudi.muntathir.core.progress.ProgressActivity
import com.aljaroudi.muntathir.core.progress.ProgressActivityKind
import com.aljaroudi.muntathir.core.progress.ReadingActivityClock
import kotlinx.coroutines.delay
import java.util.UUID
import kotlin.time.Duration.Companion.seconds

/** One reading session: the clock, and the running total saved under a stable id. */
private class ReadingSession(
    private val kind: ProgressActivityKind,
    private val save: (ProgressActivity) -> Unit,
) {
    val clock = ReadingActivityClock()
    private val id = UUID.randomUUID().toString().uppercase()
    private val startedAt = System.currentTimeMillis() / 1000.0
    private var accumulated = 0.0

    fun now() = SystemClock.elapsedRealtime() / 1000.0

    fun flush() {
        val amount = clock.drain()
        if (amount <= 0) return
        accumulated += amount
        save(ProgressActivity(kind, accumulated, id, startedAt))
    }

    fun pause() {
        clock.pause(now())
        flush()
    }
}

/**
 * Swift `trackReading`: counts reading time while the screen is resumed and [enabled], pausing after five idle
 * minutes. Taps, drags and scrolls count as interaction. Saves every 15 seconds and when paused or left.
 */
@Composable
fun Modifier.trackReading(
    kind: ProgressActivityKind,
    enabled: Boolean,
    save: (ProgressActivity) -> Unit,
): Modifier {
    val record by rememberUpdatedState(save)
    // A new kind starts a new session (Swift `onChange(of: kind)`).
    val session = remember(kind) { ReadingSession(kind) { record(it) } }
    val state by LocalLifecycleOwner.current.lifecycle.currentStateFlow
        .collectAsStateWithLifecycle()
    val running = enabled && state.isAtLeast(Lifecycle.State.RESUMED)
    DisposableEffect(session) { onDispose { session.pause() } }
    LaunchedEffect(session, running) {
        if (!running) {
            session.pause()
            return@LaunchedEffect
        }
        session.clock.resume(session.now())
        while (true) {
            // A forced stop can lose up to one checkpoint.
            delay(15.seconds)
            session.clock.advance(session.now())
            session.flush()
        }
    }
    return pointerInput(session) {
        awaitEachGesture {
            awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
            session.clock.interact(session.now())
        }
    }
}
