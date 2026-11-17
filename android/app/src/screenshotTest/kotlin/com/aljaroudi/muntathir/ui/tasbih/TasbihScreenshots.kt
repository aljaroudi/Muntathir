package com.aljaroudi.muntathir.ui.tasbih

import androidx.compose.runtime.Composable
import com.aljaroudi.muntathir.core.tasbih.TasbihSession
import com.aljaroudi.muntathir.ui.ScreenPreviews
import com.aljaroudi.muntathir.ui.theme.MuntathirTheme
import com.android.tools.screenshot.PreviewTest

@PreviewTest
@ScreenPreviews
@Composable
fun TasbihScreenshot() {
    MuntathirTheme(dynamicColor = false) {
        TasbihContent(TasbihSession(total = 40), onAdvance = {}, onBack = {}, reduceMotion = true)
    }
}
