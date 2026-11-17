package com.aljaroudi.muntathir.data

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.core.DataStoreFactory
import androidx.datastore.core.Serializer
import androidx.datastore.dataStoreFile
import com.aljaroudi.muntathir.core.text.SearchArea
import com.aljaroudi.muntathir.core.text.SearchHistory
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import java.io.InputStream
import java.io.OutputStream
import javax.inject.Inject
import javax.inject.Singleton

/** Recent searches per area in `files/datastore/search-history.v1.json` (backed up, like iOS UserDefaults). */
@Singleton
class SearchHistoryStore
    @Inject
    constructor(
        @ApplicationContext context: Context,
        @param:AppScope private val scope: CoroutineScope,
    ) {
        private val store: DataStore<SearchHistory> =
            DataStoreFactory.create(
                HistorySerializer,
                scope = CoroutineScope(scope.coroutineContext + Dispatchers.IO),
            ) {
                context.dataStoreFile(FILE)
            }

        val state: StateFlow<SearchHistory> = store.data.stateIn(scope, SharingStarted.Eagerly, SearchHistory())

        fun record(
            query: String,
            area: SearchArea,
        ) = update { it.recording(query, area) }

        fun remove(
            query: String,
            area: SearchArea,
        ) = update { it.removing(query, area) }

        fun clear(area: SearchArea) = update { it.clearing(area) }

        private fun update(transform: (SearchHistory) -> SearchHistory) {
            scope.launch { store.updateData(transform) }
        }

        companion object {
            const val FILE = "search-history.v1.json"
        }
    }

private object HistorySerializer : Serializer<SearchHistory> {
    override val defaultValue = SearchHistory()

    override suspend fun readFrom(input: InputStream): SearchHistory =
        runCatching {
            SearchHistory(Json.decodeFromString<Map<String, List<String>>>(input.readBytes().decodeToString()))
        }.getOrDefault(defaultValue)

    override suspend fun writeTo(
        t: SearchHistory,
        output: OutputStream,
    ) = output.write(Json.encodeToString(t.entries).encodeToByteArray())
}
