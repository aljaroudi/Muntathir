package com.aljaroudi.muntathir.ui.search

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.core.search.SemanticSearchClient
import com.aljaroudi.muntathir.ui.components.EmptyState
import com.aljaroudi.muntathir.ui.components.LoadingState
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** Swift `MeaningSearchResults`: nothing until the user asks, then searching, failed, or the results. */
sealed interface SmartSearchState<out T> {
    data object Idle : SmartSearchState<Nothing>

    data object Loading : SmartSearchState<Nothing>

    data object Failed : SmartSearchState<Nothing>

    data class Loaded<T>(
        val items: List<T>,
    ) : SmartSearchState<T>
}

/** Runs one opt-in smart search at a time; a new query or scope [reset]s it, withdrawing consent. */
class SmartSearchRunner<T>(
    private val scope: CoroutineScope,
    private val client: SemanticSearchClient?,
) {
    private val mutable = MutableStateFlow<SmartSearchState<T>>(SmartSearchState.Idle)
    val state: StateFlow<SmartSearchState<T>> = mutable.asStateFlow()
    private var job: Job? = null

    /** Whether smart search is configured; otherwise the button is hidden. */
    val available: Boolean get() = client != null

    fun run(load: suspend (SemanticSearchClient) -> List<T>) {
        val client = client ?: return
        job?.cancel()
        mutable.value = SmartSearchState.Loading
        job =
            scope.launch {
                mutable.value =
                    try {
                        SmartSearchState.Loaded(load(client))
                    } catch (cancellation: CancellationException) {
                        throw cancellation
                    } catch (_: Exception) {
                        SmartSearchState.Failed
                    }
            }
    }

    fun reset() {
        job?.cancel()
        mutable.value = SmartSearchState.Idle
    }

    companion object {
        /** Smart search is for meanings: a non-empty query within the API's length limit. */
        fun accepts(query: String) = query.isNotBlank() && query.length <= SemanticSearchClient.MAX_QUERY_LENGTH
    }
}

/**
 * The smart-search part of a results list: "No Results" and the Smart search button before consent, then
 * searching, "Search unavailable" with Try again, "No Results", or the caller's [rows].
 */
fun <T> LazyListScope.smartSearchSection(
    state: SmartSearchState<T>,
    available: Boolean,
    hasLocalResults: Boolean,
    onSearch: () -> Unit,
    rows: LazyListScope.(List<T>) -> Unit,
) {
    when (state) {
        SmartSearchState.Idle -> {
            if (!hasLocalResults) item(key = "smart-empty") { NoResults() }
            if (available) {
                item(key = "smart-button") {
                    Box(Modifier.fillMaxWidth().padding(16.dp), contentAlignment = Alignment.Center) {
                        Button(onClick = onSearch, Modifier.testTag("search-by-meaning")) {
                            Text(stringResource(R.string.smart_search))
                        }
                    }
                }
            }
        }

        SmartSearchState.Loading -> {
            item(key = "smart-loading") { LoadingState(stringResource(R.string.searching)) }
        }

        SmartSearchState.Failed -> {
            item(key = "smart-failed") {
                EmptyState(
                    stringResource(R.string.search_unavailable),
                    message = stringResource(R.string.you_can_still_search_downloaded_text_offline),
                    onAction = onSearch,
                )
            }
        }

        is SmartSearchState.Loaded -> {
            if (state.items.isEmpty()) item(key = "smart-empty") { NoResults() } else rows(state.items)
        }
    }
}

@Composable
private fun NoResults() = EmptyState(stringResource(R.string.no_results), Modifier.testTag("local-search-empty"))
