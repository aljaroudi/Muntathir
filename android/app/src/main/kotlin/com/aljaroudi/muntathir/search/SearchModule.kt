package com.aljaroudi.muntathir.search

import com.aljaroudi.muntathir.BuildConfig
import com.aljaroudi.muntathir.core.search.SemanticSearchClient
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

/** The smart-search client, or `null` when no valid endpoint is configured (the button is then hidden). */
class SmartSearch(
    val client: SemanticSearchClient?,
)

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
