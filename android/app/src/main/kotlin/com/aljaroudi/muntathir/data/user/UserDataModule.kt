package com.aljaroudi.muntathir.data.user

import android.content.Context
import com.aljaroudi.muntathir.core.highlight.QuranUserStore
import com.aljaroudi.muntathir.data.AppScope
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import java.io.File
import java.io.IOException
import java.util.UUID
import javax.inject.Singleton

/** Separate so instrumented tests can swap in an in-memory database. */
@Module
@InstallIn(SingletonComponent::class)
object UserDataModule {
    @Provides
    @Singleton
    fun database(
        @ApplicationContext context: Context,
    ): UserDatabase = UserDatabase.open(context)

    @Provides
    @Singleton
    fun userStore(
        @ApplicationContext context: Context,
        database: UserDatabase,
        @AppScope scope: CoroutineScope,
    ): QuranUserStore =
        QuranUserStore(RoomUserRecords(database.dao()), { installationID(context) }).also { store ->
            scope.launch { store.reopen() }
        }

    @Provides
    @Singleton
    fun progressStore(
        database: UserDatabase,
        @AppScope scope: CoroutineScope,
    ): ProgressStore = ProgressStore(database.dao(), scope)

    /**
     * Swift `QuranUserStore.localInstallationID`: a UUID in `no_backup`, so a restored device writes its own rows
     * instead of editing the source device's.
     */
    fun installationID(context: Context): String {
        val file = File(context.noBackupFilesDir, "QuranIdentity/installation-id")
        if (file.isFile) {
            val value = file.readText()
            runCatching { UUID.fromString(value) }.getOrElse { throw IOException("Invalid installation id") }
            return value
        }
        file.parentFile?.mkdirs()
        val value = UUID.randomUUID().toString().uppercase()
        val temporary = File(file.parentFile, "installation-id.tmp")
        temporary.writeText(value)
        if (!temporary.renameTo(file)) throw IOException("Unable to save the installation id")
        return value
    }
}
