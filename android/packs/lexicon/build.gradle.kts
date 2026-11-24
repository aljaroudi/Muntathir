plugins {
    alias(libs.plugins.android.asset.pack)
}

assetPack {
    packName = "lexicon"
    dynamicDelivery {
        deliveryType = "on-demand"
    }
}
