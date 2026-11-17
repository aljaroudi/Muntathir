package com.aljaroudi.muntathir

import com.aljaroudi.muntathir.core.app.AppStorage
import com.aljaroudi.muntathir.core.app.DeviceState
import com.aljaroudi.muntathir.core.app.Preferences
import com.aljaroudi.muntathir.core.location.SavedLocation
import com.aljaroudi.muntathir.location.DeviceLocator

class MemoryStorage(
    var preferences: Preferences? = null,
    var device: DeviceState = DeviceState(),
) : AppStorage {
    override suspend fun loadPreferences() = preferences

    override suspend fun savePreferences(preferences: Preferences) {
        this.preferences = preferences
    }

    override suspend fun loadDevice() = device

    override suspend fun saveDevice(state: DeviceState) {
        device = state
    }
}

class FakeLocator(
    var fix: SavedLocation? = MECCA,
) : DeviceLocator {
    override fun hasPermission() = true

    override suspend fun locate() = fix

    companion object {
        val MECCA = SavedLocation(21.4225, 39.8262, "Asia/Riyadh")
    }
}
