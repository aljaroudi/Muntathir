package com.aljaroudi.muntathir.core.quran

/** The bundled Arabic database is missing or unreadable, or an optional database is invalid. */
class QuranUnavailableException(
    cause: Throwable? = null,
) : Exception("Quran database unavailable", cause)
