package com.aljaroudi.muntathir.ui

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import com.aljaroudi.muntathir.ui.theme.MuntathirTheme
import org.junit.Rule
import org.junit.Test

class MuntathirAppTest {
    @get:Rule val compose = createComposeRule()

    @Test
    fun showsTitle() {
        compose.setContent { MuntathirTheme { MuntathirApp() } }
        compose.onNodeWithTag("app-title").assertIsDisplayed()
    }
}
