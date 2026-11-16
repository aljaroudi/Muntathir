package com.aljaroudi.muntathir.core

import java.io.File

/** Reads repository-root `shared/fixtures`, the same files the Apple tests use. */
object Fixtures {
    private val root = File(checkNotNull(System.getProperty("fixtures")) { "Run through Gradle." })

    fun text(name: String): String = root.resolve(name).readText()
}
