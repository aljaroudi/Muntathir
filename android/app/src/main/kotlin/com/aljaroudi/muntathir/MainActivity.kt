package com.aljaroudi.muntathir

import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.appcompat.app.AppCompatActivity
import com.aljaroudi.muntathir.ui.MainViewModel
import com.aljaroudi.muntathir.ui.MuntathirApp
import com.aljaroudi.muntathir.ui.theme.MuntathirTheme
import dagger.hilt.android.AndroidEntryPoint

// AppCompatActivity provides per-app language on all supported API levels.
@AndroidEntryPoint
class MainActivity : AppCompatActivity() {
    private val viewModel: MainViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        setContent {
            MuntathirTheme {
                MuntathirApp(viewModel)
            }
        }
    }
}
