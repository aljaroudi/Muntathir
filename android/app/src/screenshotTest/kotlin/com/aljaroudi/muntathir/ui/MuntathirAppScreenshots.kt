package com.aljaroudi.muntathir.ui

import androidx.compose.runtime.Composable
import androidx.compose.ui.tooling.preview.Devices
import androidx.compose.ui.tooling.preview.Preview
import com.aljaroudi.muntathir.core.app.AppTool
import com.aljaroudi.muntathir.ui.shell.TabsSettingsContent
import com.aljaroudi.muntathir.ui.shell.ToolsScreen
import com.aljaroudi.muntathir.ui.theme.MuntathirTheme
import com.android.tools.screenshot.PreviewTest

/** Form factors × languages × themes used by every screen-level screenshot test. */
@Preview(name = "Phone", device = Devices.PHONE, showBackground = true)
@Preview(name = "Phone AR dark", device = Devices.PHONE, locale = "ar", uiMode = 0x21, showBackground = true)
@Preview(name = "Foldable", device = Devices.FOLDABLE, showBackground = true)
@Preview(name = "Tablet AR", device = Devices.TABLET, locale = "ar", showBackground = true)
annotation class ScreenPreviews

@PreviewTest
@ScreenPreviews
@Composable
fun ToolsScreenshot() {
    MuntathirTheme(dynamicColor = false) { ToolsScreen(listOf(AppTool.Calendar), {}, {}) }
}

@PreviewTest
@ScreenPreviews
@Composable
fun TabsSettingsScreenshot() {
    MuntathirTheme(dynamicColor = false) {
        TabsSettingsContent(listOf(AppTool.Calendar, AppTool.Quran), {}, {}, { _, _ -> }, onBack = {})
    }
}
