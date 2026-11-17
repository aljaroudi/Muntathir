plugins {
    alias(libs.plugins.android.asset.pack)
}

assetPack {
    packName = "hadith"
    dynamicDelivery {
        deliveryType = "on-demand"
    }
}
