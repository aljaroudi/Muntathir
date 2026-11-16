package com.aljaroudi.muntathir.ui.shell

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.ui.components.ScreenScaffold

/** Stands in for tools ported in later phases (Quran P3, Library P4, Tools P5). */
@Composable
fun ComingSoonScreen(
    title: String,
    onBack: (() -> Unit)?,
    modifier: Modifier = Modifier,
) {
    ScreenScaffold(title, modifier, onBack) { padding ->
        Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
            Text(stringResource(R.string.coming_soon), style = MaterialTheme.typography.bodyLarge)
        }
    }
}
