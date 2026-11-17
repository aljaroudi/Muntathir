plugins {
    alias(libs.plugins.android.asset.pack)
}

// Downloads right after install (the iOS "essential" pack); the app still waits for it before opening.
assetPack {
    packName = "supplications"
    dynamicDelivery {
        deliveryType = "fast-follow"
    }
}
