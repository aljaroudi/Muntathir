package com.aljaroudi.muntathir.ui.hadith

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.core.content.res.ResourcesCompat
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.core.app.ReadingPreferences
import com.aljaroudi.muntathir.core.hadith.HadithIntroduction
import com.aljaroudi.muntathir.core.text.HadithText
import com.aljaroudi.muntathir.data.QuranTranslations
import com.aljaroudi.muntathir.data.ReadingSettings
import com.aljaroudi.muntathir.data.library.ContentLibraries
import com.aljaroudi.muntathir.ui.components.EmptyState
import com.aljaroudi.muntathir.ui.components.LoadingState
import com.aljaroudi.muntathir.ui.components.ScreenScaffold
import com.aljaroudi.muntathir.ui.components.currentLocale
import com.aljaroudi.muntathir.ui.navigation.HadithIntroductionRoute
import com.aljaroudi.muntathir.ui.quran.ReadingOptionsMenu
import com.aljaroudi.muntathir.ui.quran.ReadingSizeSheet
import com.aljaroudi.muntathir.ui.reader.ReaderText
import com.aljaroudi.muntathir.ui.reader.ReadingTextStyle
import dagger.assisted.Assisted
import dagger.assisted.AssistedFactory
import dagger.assisted.AssistedInject
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

@HiltViewModel(assistedFactory = HadithIntroductionViewModel.Factory::class)
class HadithIntroductionViewModel
    @AssistedInject
    constructor(
        @Assisted private val route: HadithIntroductionRoute,
        libraries: ContentLibraries,
        private val settings: ReadingSettings,
    ) : ViewModel() {
        @AssistedFactory
        interface Factory {
            fun create(route: HadithIntroductionRoute): HadithIntroductionViewModel
        }

        private val reader = libraries.hadith.reader
        val reading: StateFlow<ReadingPreferences> = settings.state

        /** `null` while loading; [Result.failure] when it can't be read. */
        private val mutableContent = MutableStateFlow<Result<HadithIntroduction>?>(null)
        val content: StateFlow<Result<HadithIntroduction>?> = mutableContent.asStateFlow()

        init {
            load()
        }

        fun load() {
            mutableContent.value = null
            viewModelScope.launch {
                mutableContent.value =
                    try {
                        Result.success(reader.introduction(route.id))
                    } catch (cancellation: CancellationException) {
                        throw cancellation
                    } catch (error: Exception) {
                        Result.failure(error)
                    }
            }
        }

        fun showsEnglish() = settings.state.value.showsHadithEnglish(QuranTranslations.preferredLanguages())

        fun setSize(percent: Int) = viewModelScope.launch { settings.update { it.copy(readingSizePercent = percent) } }
    }

/** Swift `HadithIntroductionView`: a book's introduction in Arabic, and English when shown. */
@Composable
fun HadithIntroductionScreen(
    viewModel: HadithIntroductionViewModel,
    onBack: (() -> Unit)?,
) {
    val content by viewModel.content.collectAsStateWithLifecycle()
    val reading by viewModel.reading.collectAsStateWithLifecycle()
    var sizing by rememberSaveable { mutableStateOf(false) }
    val context = LocalContext.current
    val lateef = remember { ResourcesCompat.getFont(context, R.font.lateef_regular) }
    val locale = currentLocale()
    ScreenScaffold(
        stringResource(R.string.introduction),
        onBack = onBack,
        actions = {
            ReadingOptionsMenu(onTextSize = { sizing = true })
        },
    ) { padding ->
        val result = content
        when {
            result == null -> {
                LoadingState(stringResource(R.string.loading_hadith), Modifier.padding(padding))
            }

            result.isFailure -> {
                EmptyState(
                    stringResource(R.string.unable_to_load_hadith),
                    Modifier.padding(padding),
                    onAction = viewModel::load,
                )
            }

            else -> {
                val introduction = result.getOrThrow()
                val arabic = remember(introduction) { HadithText.canonical(HadithText.markdown(introduction.arabic)) }
                val english = remember(introduction) { HadithText.canonical(HadithText.markdown(introduction.english)) }
                Box(
                    Modifier
                        .fillMaxSize()
                        .verticalScroll(
                            rememberScrollState(),
                        ).padding(padding)
                        .testTag("hadith-introduction-reader"),
                    contentAlignment = Alignment.TopCenter,
                ) {
                    Column(
                        Modifier.widthIn(max = 640.dp).fillMaxWidth().padding(20.dp),
                        verticalArrangement = Arrangement.spacedBy(20.dp),
                    ) {
                        if (arabic.length > 0) {
                            ReaderText(
                                arabic,
                                block = "introduction",
                                sizeSp = ReadingTextStyle.arabicSize(reading.readingSizePercent),
                                typeface = lateef,
                                rightToLeft = true,
                                modifier = Modifier.fillMaxWidth(),
                            )
                        }
                        if ((viewModel.showsEnglish() || arabic.length == 0) && english.length > 0) {
                            ReaderText(
                                english,
                                block = "introduction",
                                sizeSp = ReadingTextStyle.bodySize(reading.readingSizePercent),
                                modifier = Modifier.fillMaxWidth(),
                            )
                        }
                    }
                }
            }
        }
    }
    if (sizing) ReadingSizeSheet(reading.readingSizePercent, locale, viewModel::setSize) { sizing = false }
}
