package com.aljaroudi.muntathir.data

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.core.DataStoreFactory
import androidx.datastore.core.Serializer
import androidx.datastore.dataStoreFile
import com.aljaroudi.muntathir.core.app.AppStorage
import com.aljaroudi.muntathir.core.app.DeviceState
import com.aljaroudi.muntathir.core.app.Preferences
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.first
import kotlinx.serialization.json.Json
import java.io.File
import java.io.InputStream
import java.io.OutputStream

/**
 * [AppStorage] on two DataStore files:
 * - `files/datastore/preferences.v1.json`, included in Auto Backup (the iOS `preferences.v1` blob);
 * - `no_backup/device.v1.json`, never backed up (onboarding progress, GPS fix, delivered announcements).
 */
class DataStoreAppStorage(
    private val preferences: DataStore<Preferences?>,
    private val device: DataStore<DeviceState>,
) : AppStorage {
    override suspend fun loadPreferences(): Preferences? = preferences.data.first()

    override suspend fun savePreferences(preferences: Preferences) {
        this.preferences.updateData { preferences }
    }

    override suspend fun loadDevice(): DeviceState = device.data.first()

    override suspend fun saveDevice(state: DeviceState) {
        device.updateData { state }
    }

    companion object {
        const val PREFERENCES_FILE = "preferences.v1.json"
        const val DEVICE_FILE = "device.v1.json"

        fun create(
            context: Context,
            scope: CoroutineScope,
        ) = DataStoreAppStorage(
            DataStoreFactory.create(PreferencesSerializer, scope = scope) { context.dataStoreFile(PREFERENCES_FILE) },
            DataStoreFactory.create(DeviceSerializer, scope = scope) { File(context.noBackupFilesDir, DEVICE_FILE) },
        )
    }
}

/** Malformed or invalid blobs read as `null`, so the app falls back to defaults instead of failing. */
private object PreferencesSerializer : Serializer<Preferences?> {
    override val defaultValue: Preferences? = null

    override suspend fun readFrom(input: InputStream): Preferences? =
        Preferences.decodeValid(input.readBytes().decodeToString())

    override suspend fun writeTo(
        t: Preferences?,
        output: OutputStream,
    ) {
        if (t != null) output.write(t.encode().encodeToByteArray())
    }
}

private object DeviceSerializer : Serializer<DeviceState> {
    private val json =
        Json {
            ignoreUnknownKeys = true
            explicitNulls = false
        }
    override val defaultValue = DeviceState()

    override suspend fun readFrom(input: InputStream): DeviceState =
        runCatching {
            json.decodeFromString<DeviceState>(
                input.readBytes().decodeToString(),
            )
        }.getOrDefault(defaultValue)

    override suspend fun writeTo(
        t: DeviceState,
        output: OutputStream,
    ) = output.write(json.encodeToString(t).encodeToByteArray())
}
