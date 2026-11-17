package com.aljaroudi.muntathir.data.library

import com.aljaroudi.muntathir.core.hadith.PackFlagStore
import com.aljaroudi.muntathir.core.hadith.PackFlags
import com.aljaroudi.muntathir.core.io.writeTextAtomically
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import java.io.File

/**
 * A pack's device-local flags (Swift `UserDefaults` keys) in a small JSON file under `no_backup`, outside the
 * library folder so removing the library keeps them. Reads come from memory; writes go to disk in order.
 */
class FilePackFlags(
    private val file: File,
    scope: CoroutineScope,
) : PackFlagStore {
    @OptIn(ExperimentalCoroutinesApi::class)
    private val writes = CoroutineScope(scope.coroutineContext + Dispatchers.IO.limitedParallelism(1))

    private var current: PackFlags? = null

    override fun read(): PackFlags =
        current ?: runCatching { json.decodeFromString<PackFlags>(file.readText()) }
            .getOrDefault(PackFlags())
            .also { current = it }

    override fun write(flags: PackFlags) {
        current = flags
        val text = json.encodeToString(PackFlags.serializer(), flags)
        writes.launch { file.writeTextAtomically(text) }
    }

    private companion object {
        val json = Json { ignoreUnknownKeys = true }
    }
}
