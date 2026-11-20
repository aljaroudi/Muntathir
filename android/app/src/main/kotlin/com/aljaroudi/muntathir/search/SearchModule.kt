package com.aljaroudi.muntathir.search

import com.aljaroudi.muntathir.BuildConfig
import com.aljaroudi.muntathir.core.search.SemanticSearchClient
import com.aljaroudi.muntathir.core.search.SemanticSearchResult
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import kotlinx.coroutines.CancellationException
import javax.inject.Singleton

/** Returns null when local search should handle the request. An empty list is a completed online search. */
class SmartSearch(
    private val client: SemanticSearchClient?,
) {
    suspend fun <T> results(
        query: String,
        kind: String,
        sources: List<String>? = null,
        chapter: String? = null,
        languages: List<String>? = null,
        resolve: suspend (List<SemanticSearchResult>) -> List<T>,
    ): List<T>? {
        val service = client ?: return null
        return try {
            val hits = service.search(query, kind = kind, sources = sources, chapter = chapter, languages = languages)
            resolve(hits).takeIf { hits.isEmpty() || it.isNotEmpty() }
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: Exception) {
            null
        }
    }
}

/** Separate so instrumented tests can swap in a fake client. */
@Module
@InstallIn(SingletonComponent::class)
object SearchModule {
    @Provides
    @Singleton
    fun smartSearch(): SmartSearch =
        SmartSearch(
            SemanticSearchClient.endpoint(BuildConfig.SEMANTIC_SEARCH_URL)?.let {
                SemanticSearchClient(it, KtorSemanticSearchTransport())
            },
        )
}
