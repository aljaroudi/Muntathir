# Keep rules are added only when a library or reflection use requires them.

# asset-delivery-ktx references a play-services-basement annotation that isn't on the classpath. It's a
# compile-time annotation only, so nothing at runtime needs it.
-dontwarn com.google.android.gms.common.annotation.NoNullnessRewrite
