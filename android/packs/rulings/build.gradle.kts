plugins {
    alias(libs.plugins.android.asset.pack)
}

assetPack {
    packName = "rulings"
    dynamicDelivery {
        deliveryType = "on-demand"
    }
}
