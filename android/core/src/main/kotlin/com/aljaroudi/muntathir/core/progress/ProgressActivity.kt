package com.aljaroudi.muntathir.core.progress

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.util.UUID
import kotlin.math.floor

/** Titles and icons are app resources. */
@Serializable
enum class ProgressActivityKind {
    @SerialName("quranReading")
    QuranReading,

    @SerialName("hadithReading")
    HadithReading,

    @SerialName("supplicationReading")
    SupplicationReading,

    @SerialName("tasbih")
    Tasbih,
    ;

    companion object {
        val reading = listOf(QuranReading, HadithReading, SupplicationReading)
    }
}

/**
 * One session's running amount (seconds read, or beads counted). Records are snapshots: the same [id]
 * may be saved several times with growing amounts.
 */
@Serializable
data class ProgressActivity(
    val kind: ProgressActivityKind,
    val amount: Double,
    val id: String = UUID.randomUUID().toString().uppercase(),
    /** Seconds since the epoch. */
    val date: Double = System.currentTimeMillis() / 1000.0,
) {
    val isValid: Boolean
        get() = amount.isFinite() && amount > 0 && (kind != ProgressActivityKind.Tasbih || floor(amount) == amount)

    companion object {
        /** Sums per kind using each session's largest snapshot (max, not sum), so duplicates never inflate totals. */
        fun totals(activities: List<ProgressActivity>): Map<ProgressActivityKind, Double> =
            activities
                .filter { it.isValid }
                .groupBy { it.id }
                .values
                .map { session -> session.maxBy { it.amount } }
                .groupingBy { it.kind }
                .fold(0.0) { sum, activity -> sum + activity.amount }
    }
}

/**
 * Reading time that pauses in the background and after [IDLE_LIMIT] seconds without interaction.
 * Pass monotonic seconds (e.g. `SystemClock.elapsedRealtime() / 1000.0`) so clock changes can't inflate it.
 */
class ReadingActivityClock {
    private var lastTick: Double? = null
    private var lastInteraction = 0.0

    var elapsed = 0.0
        private set

    fun resume(now: Double) {
        if (lastTick != null) return
        lastTick = now
        lastInteraction = now
    }

    fun advance(now: Double) {
        val previous = lastTick ?: return
        elapsed += maxOf(0.0, minOf(now, lastInteraction + IDLE_LIMIT) - previous)
        lastTick = now
    }

    fun interact(now: Double) {
        if (lastTick == null) return
        advance(now)
        lastInteraction = now
    }

    fun pause(now: Double) {
        advance(now)
        lastTick = null
    }

    fun drain(): Double = elapsed.also { elapsed = 0.0 }

    companion object {
        const val IDLE_LIMIT = 300.0
    }
}
