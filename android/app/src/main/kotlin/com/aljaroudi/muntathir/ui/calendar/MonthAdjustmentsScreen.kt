package com.aljaroudi.muntathir.ui.calendar

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Remove
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.dp
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.core.app.AppError
import com.aljaroudi.muntathir.core.app.AppModel
import com.aljaroudi.muntathir.core.calendar.CalendarEngine
import com.aljaroudi.muntathir.core.calendar.CalendarException
import com.aljaroudi.muntathir.core.calendar.CalendarYear
import com.aljaroudi.muntathir.core.calendar.HijriMonth
import com.aljaroudi.muntathir.core.calendar.MonthOffset
import com.aljaroudi.muntathir.ui.components.Formats
import com.aljaroudi.muntathir.ui.components.ScreenScaffold
import com.aljaroudi.muntathir.ui.components.currentLocale
import com.aljaroudi.muntathir.ui.components.message
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.LocalDate
import javax.inject.Inject

data class MonthAdjustmentUi(
    val month: HijriMonth,
    val offset: Int,
    /** Source start (confirmed feed only) moved by [offset]; +1 starts a day earlier. */
    val start: LocalDate,
    val error: Int? = null,
)

/** Swift `MonthAdjustmentsView`, opened on the current Hijri month. */
@HiltViewModel
class MonthAdjustmentsViewModel
    @Inject
    constructor(
        private val model: AppModel,
        private val saved: SavedStateHandle,
    ) : ViewModel() {
        private val draft =
            MutableStateFlow(
                Draft(
                    saved[MONTH] ?: model.state.value.engine
                        .resolve(Instant.now())
                        .month.index,
                    saved[OFFSET],
                    null,
                ),
            )

        private data class Draft(
            val month: Int,
            val offset: Int?,
            val error: Int?,
        )

        val state: StateFlow<MonthAdjustmentUi> =
            combine(model.state, draft) { app, draft ->
                val month = HijriMonth(draft.month / 12, draft.month % 12 + 1)
                val offset =
                    draft.offset ?: app.preferences.monthOffsets
                        .firstOrNull { it.month == month }
                        ?.days ?: 0
                val source =
                    runCatching { CalendarEngine(app.zone, confirmed = app.confirmations.map { it.correction }) }
                        .getOrElse { CalendarEngine(app.zone) }
                MonthAdjustmentUi(month, offset, source.start(month).minusDays(offset.toLong()), draft.error)
            }.stateIn(viewModelScope, SharingStarted.Eagerly, initial())

        private fun initial(): MonthAdjustmentUi {
            val month = HijriMonth(draft.value.month / 12, draft.value.month % 12 + 1)
            return MonthAdjustmentUi(
                month,
                0,
                model.state.value.engine
                    .start(month),
            )
        }

        private fun edit(transform: (Draft) -> Draft) {
            draft.update(transform)
            saved[MONTH] = draft.value.month
            saved[OFFSET] = draft.value.offset
        }

        fun moveMonth(by: Int) = edit { Draft(it.month + by, null, null) }

        fun setOffset(days: Int) = edit { it.copy(offset = days.coerceIn(MonthOffset.range), error = null) }

        /** Returns whether the change was saved; on failure the error shows inline. */
        fun save(
            days: Int,
            onSaved: () -> Unit,
        ) {
            viewModelScope.launch {
                val month = state.value.month
                try {
                    model.correct(month, days)
                    edit { it.copy(offset = null, error = null) }
                    onSaved()
                } catch (error: CalendarException) {
                    edit { it.copy(error = AppError.Calendar(error.kind).message()) }
                }
            }
        }

        private companion object {
            const val MONTH = "month"
            const val OFFSET = "offset"
        }
    }

@Composable
fun MonthAdjustmentsScreen(
    viewModel: MonthAdjustmentsViewModel,
    onBack: (() -> Unit)?,
    modifier: Modifier = Modifier,
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    MonthAdjustmentsContent(
        state,
        onMonth = viewModel::moveMonth,
        onOffset = viewModel::setOffset,
        onSave = { viewModel.save(it) { onBack?.invoke() } },
        onBack = onBack,
        modifier = modifier,
    )
}

@Composable
fun MonthAdjustmentsContent(
    state: MonthAdjustmentUi,
    onMonth: (Int) -> Unit,
    onOffset: (Int) -> Unit,
    onSave: (Int) -> Unit,
    onBack: (() -> Unit)?,
    modifier: Modifier = Modifier,
) {
    val locale = currentLocale()
    ScreenScaffold(
        R.string.adjust_month,
        modifier,
        onBack,
        actions = {
            IconButton(onClick = { onSave(state.offset) }, Modifier.testTag("month-save")) {
                Icon(Icons.Filled.Check, stringResource(R.string.save))
            }
        },
    ) { padding ->
        Column(
            Modifier
                .padding(
                    padding,
                ).verticalScroll(rememberScrollState())
                .padding(16.dp)
                .widthIn(max = 640.dp)
                .fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = { onMonth(-1) }, enabled = state.month > HijriMonth(CalendarYear.FIRST, 1)) {
                    Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, stringResource(R.string.previous_month))
                }
                Text(
                    stringResource(
                        R.string.hijri_month_x_x,
                        Formats.number(state.month.month, locale),
                        Formats.number(state.month.year, locale),
                    ),
                    style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier.weight(1f),
                )
                IconButton(onClick = { onMonth(1) }, enabled = state.month < HijriMonth(CalendarYear.LAST, 12)) {
                    Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, stringResource(R.string.next_month))
                }
            }
            HorizontalDivider()
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(stringResource(R.string.day_adjustment), Modifier.weight(1f))
                FilledTonalIconButton(
                    onClick = { onOffset(state.offset - 1) },
                    enabled =
                        state.offset > MonthOffset.range.first,
                ) {
                    Icon(
                        Icons.Outlined.Remove,
                        stringResource(R.string.decrease_x, stringResource(R.string.day_adjustment)),
                    )
                }
                Text(
                    Formats.signed(state.offset, locale),
                    style = MaterialTheme.typography.titleMedium,
                    modifier =
                        Modifier.testTag("month-offset").semantics {
                            stateDescription =
                                Formats.signed(state.offset, locale)
                        },
                )
                FilledTonalIconButton(
                    onClick = { onOffset(state.offset + 1) },
                    enabled =
                        state.offset < MonthOffset.range.last,
                ) {
                    Icon(
                        Icons.Outlined.Add,
                        stringResource(R.string.increase_x, stringResource(R.string.day_adjustment)),
                    )
                }
            }
            Row {
                Text(stringResource(R.string.month_starts), Modifier.weight(1f))
                Text(Formats.date(state.start, "yMMMMd", locale), color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            state.error?.let { Text(stringResource(it), color = MaterialTheme.colorScheme.error) }
            TextButton(onClick = { onSave(0) }) {
                Text(stringResource(R.string.reset_adjustment), color = MaterialTheme.colorScheme.error)
            }
        }
    }
}
