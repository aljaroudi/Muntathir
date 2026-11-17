package com.aljaroudi.muntathir.ui.calendar

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.core.calendar.EventLibrary
import com.aljaroudi.muntathir.core.figures.FigureLibrary
import com.aljaroudi.muntathir.data.FigureLoad
import com.aljaroudi.muntathir.data.FigureStore
import com.aljaroudi.muntathir.data.library
import com.aljaroudi.muntathir.ui.components.Formats
import com.aljaroudi.muntathir.ui.components.ScreenScaffold
import com.aljaroudi.muntathir.ui.components.currentLocale
import com.aljaroudi.muntathir.ui.navigation.Route
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.StateFlow
import javax.inject.Inject

@HiltViewModel
class EventsViewModel
    @Inject
    constructor(
        val library: EventLibrary,
        figures: FigureStore,
    ) : ViewModel() {
        /** Figures that observances link to, once loaded. */
        val figures: StateFlow<FigureLoad> = figures.state
    }

@Composable
fun EventsScreen(
    viewModel: EventsViewModel,
    open: (Route) -> Unit,
    onBack: (() -> Unit)?,
) {
    val figures by viewModel.figures.collectAsStateWithLifecycle()
    EventsScreen(viewModel.library, onBack, figures = figures.library, open = open)
}

/** Swift `EventsView`: every observance by Hijri month, independent of year. */
@Composable
fun EventsScreen(
    library: EventLibrary,
    onBack: (() -> Unit)?,
    modifier: Modifier = Modifier,
    figures: FigureLibrary? = null,
    open: (Route) -> Unit = {},
) {
    val locale = currentLocale()
    ScreenScaffold(R.string.events, modifier, onBack) { padding ->
        LazyColumn(
            state = rememberLazyListState(),
            contentPadding = padding,
            modifier = Modifier.testTag("events-list"),
        ) {
            (1..12).forEach { month ->
                val name = Formats.hijriMonth(month, locale)
                stickyHeader(key = "events-month-$month") {
                    Surface(color = MaterialTheme.colorScheme.surfaceContainer, modifier = Modifier.fillMaxWidth()) {
                        Text(
                            name,
                            style = MaterialTheme.typography.titleMedium,
                            modifier =
                                Modifier
                                    .padding(
                                        horizontal = 16.dp,
                                        vertical = 12.dp,
                                    ).testTag("events-month-$month")
                                    .semantics {
                                        heading()
                                    },
                        )
                    }
                }
                val events = EventLibrary.inMonth(month, library.events)
                if (events.isEmpty()) {
                    item(key = "events-empty-$month") {
                        Text(
                            stringResource(R.string.no_events),
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(16.dp),
                        )
                    }
                }
                items(events, key = { "event-${it.id}" }) { event ->
                    val day = Formats.number(event.day, locale)
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .padding(
                                horizontal = 16.dp,
                                vertical = 10.dp,
                            ).testTag("event-${event.id}"),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                        verticalAlignment = Alignment.Top,
                    ) {
                        Text(
                            day,
                            style = MaterialTheme.typography.titleLarge,
                            fontWeight = FontWeight.SemiBold,
                            modifier =
                                Modifier
                                    .background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(8.dp))
                                    .padding(horizontal = 10.dp, vertical = 6.dp)
                                    .semantics { contentDescription = "$day $name" },
                        )
                        EventTitle(event, locale, Modifier.weight(1f), figures, open)
                    }
                }
            }
        }
    }
}
