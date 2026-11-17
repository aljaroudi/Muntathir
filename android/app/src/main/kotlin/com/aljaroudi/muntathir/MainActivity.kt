package com.aljaroudi.muntathir

import android.content.Intent
import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.appcompat.app.AppCompatActivity
import com.aljaroudi.muntathir.ui.MainViewModel
import com.aljaroudi.muntathir.ui.MuntathirApp
import com.aljaroudi.muntathir.ui.navigation.OpenRequest
import com.aljaroudi.muntathir.ui.theme.MuntathirTheme
import dagger.hilt.android.AndroidEntryPoint

// AppCompatActivity provides per-app language on all supported API levels.
@AndroidEntryPoint
class MainActivity : AppCompatActivity() {
    private val viewModel: MainViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        // A recreated activity already handled its launch intent.
        if (savedInstanceState == null) OpenRequest.from(intent)?.let(viewModel::open)
        setContent {
            MuntathirTheme {
                MuntathirApp(viewModel)
            }
        }
    }

    // singleTop: shortcuts, widgets and the tile reuse the running activity.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        OpenRequest.from(intent)?.let(viewModel::open)
    }
}
