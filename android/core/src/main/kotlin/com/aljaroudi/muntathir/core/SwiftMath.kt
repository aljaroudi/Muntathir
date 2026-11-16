package com.aljaroudi.muntathir.core

import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.sign

/**
 * Swift's `rounded()` / `round()`: halves round away from zero. Kotlin's `round` rounds halves to even,
 * which would shift ported results by a minute at exact half-minutes.
 */
internal fun Double.roundedAwayFromZero(): Double = sign * floor(abs(this) + 0.5)
