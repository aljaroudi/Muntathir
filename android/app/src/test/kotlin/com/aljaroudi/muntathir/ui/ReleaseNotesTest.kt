package com.aljaroudi.muntathir.ui

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ReleaseNotesTest {
    @Test
    fun updateSelection() {
        val history = listOf("1.10.0", "1.2.0", "1.1.1").map { ReleaseNote(it, listOf("android"), emptyMap()) }

        fun pending(
            installed: String,
            seen: String?,
            onboarded: Boolean = true,
        ) = hasUnseenReleaseNotes(history, installed, seen, onboarded)

        assertFalse(pending("1.1.1", null, false))
        assertTrue(pending("1.1.1", null))
        assertTrue(pending("1.10.0", "1.1.1"))
        assertFalse(pending("1.10.0", "1.10.0"))
        assertFalse(pending("1.10.1", "1.10.0"))
    }
}
