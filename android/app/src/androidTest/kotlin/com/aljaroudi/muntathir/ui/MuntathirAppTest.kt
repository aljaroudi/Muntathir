package com.aljaroudi.muntathir.ui

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import com.aljaroudi.muntathir.core.app.AppTool
import com.aljaroudi.muntathir.ui.shell.AppShell
import com.aljaroudi.muntathir.ui.theme.MuntathirTheme
import org.junit.Rule
import org.junit.Test

class MuntathirAppTest {
    @get:Rule val compose = createComposeRule()

    @Test
    fun tabsShowShortcutsAndToolsHidesThem() {
        compose.setContent { MuntathirTheme { AppShell(listOf(AppTool.Calendar)) } }
        compose.onNodeWithTag("tab-today").assertIsSelected()
        compose.onNodeWithTag("tab-calendar").assertIsDisplayed()
        compose.onNodeWithTag("tab-tools").performClick()
        compose.onNodeWithTag("tab-tools").assertIsSelected()
        compose.onNodeWithTag("holy-quran").assertIsDisplayed()
        compose.onNodeWithTag("calendar").assertDoesNotExist()
        compose.onNodeWithTag("holy-quran").performClick()
        compose.onNodeWithTag("tab-today").performClick()
        compose.onNodeWithTag("tab-today").assertIsSelected()
    }
}
