package com.aljaroudi.muntathir.core

import java.io.File

/** Reads repository-root `shared/fixtures`, the same files the Apple tests use. */
object Fixtures {
    private val root = File(checkNotNull(System.getProperty("fixtures")) { "Run through Gradle." })

    fun text(name: String): String = root.resolve(name).readText()

    /** A read-only file elsewhere in the repository, e.g. `web/public/calendar/corrections-v1.json`. */
    fun repository(path: String): File =
        File(checkNotNull(System.getProperty("repository")) { "Run through Gradle." }).resolve(path)
}
