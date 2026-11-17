package com.aljaroudi.muntathir.assets

import android.content.Context
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

/** Separate so instrumented tests can serve fixture databases instead of Play. */
@Module
@InstallIn(SingletonComponent::class)
object AssetPackModule {
    @Provides
    @Singleton
    fun assetPacks(
        @ApplicationContext context: Context,
    ): AssetPackBackend = PlayAssetPackBackend(context)
}
