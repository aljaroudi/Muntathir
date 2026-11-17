plugins {
    alias(libs.plugins.android.asset.pack)
}

assetPack {
    packName = "quran_translations"
    dynamicDelivery {
        deliveryType = "on-demand"
    }
}
