package com.aljaroudi.muntathir.ui

import org.junit.Assert.assertEquals
import org.junit.Test

class ReleaseNotesTest {
    @Test
    fun updateSelection() {
        val history = listOf("1.10.0", "1.2.0", "1.1.1").map { ReleaseNote(it, listOf("android"), emptyMap()) }
        fun pending(installed: String, seen: String?, onboarded: Boolean = true) =
            pendingReleaseNotes(history, installed, seen, onboarded).map { it.version }

        assertEquals(emptyList<String>(), pending("1.1.1", null, false))
        assertEquals(listOf("1.1.1"), pending("1.1.1", null))
        assertEquals(listOf("1.10.0", "1.2.0"), pending("1.10.0", "1.1.1"))
        assertEquals(emptyList<String>(), pending("1.10.0", "1.10.0"))
        assertEquals(emptyList<String>(), pending("1.10.1", "1.10.0"))
    }
}
