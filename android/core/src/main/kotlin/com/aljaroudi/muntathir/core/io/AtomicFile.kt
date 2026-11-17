package com.aljaroudi.muntathir.core.io

import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption

/** Writes [text] beside this file, then moves it into place, so readers never see a partial file. */
fun File.writeTextAtomically(text: String) {
    parentFile?.mkdirs()
    val temporary = File(path + ".tmp")
    temporary.writeText(text)
    Files.move(temporary.toPath(), toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
}
