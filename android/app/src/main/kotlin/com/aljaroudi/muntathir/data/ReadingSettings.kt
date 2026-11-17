package com.aljaroudi.muntathir.data

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.core.DataStoreFactory
import androidx.datastore.core.Serializer
import androidx.datastore.dataStoreFile
import com.aljaroudi.muntathir.core.app.ReadingPreferences
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.runBlocking
import java.io.InputStream
import java.io.OutputStream

/**
 * Reader choices (text size, mode, translation, highlight palette, Saved grouping) in
 * `files/datastore/reading.v1.json`, which Auto Backup includes. iOS syncs the same keys through iCloud.
 */
class ReadingSettings(
    private val store: DataStore<ReadingPreferences>,
    scope: CoroutineScope,
) {
    val state: StateFlow<ReadingPreferences> =
        store.data.stateIn(scope, SharingStarted.Eagerly, runBlocking { store.data.first() })

    /** Applies [transform]; values iOS would reject fall back to their defaults. */
    suspend fun update(transform: (ReadingPreferences) -> ReadingPreferences) {
        store.updateData { transform(it).validated() }
    }

    companion object {
        const val FILE = "reading.v1.json"

        fun create(
            context: Context,
            scope: CoroutineScope,
        ) = ReadingSettings(
            DataStoreFactory.create(ReadingSerializer, scope = scope) { context.dataStoreFile(FILE) },
            scope,
        )
    }
}

private object ReadingSerializer : Serializer<ReadingPreferences> {
    override val defaultValue = ReadingPreferences()

    override suspend fun readFrom(input: InputStream) = ReadingPreferences.decode(input.readBytes().decodeToString())

    override suspend fun writeTo(
        t: ReadingPreferences,
        output: OutputStream,
    ) = output.write(t.encode().encodeToByteArray())
}
