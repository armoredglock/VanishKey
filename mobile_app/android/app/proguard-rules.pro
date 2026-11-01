# Keep Google ML Kit & Barcode Scanning components from R8 stripping
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_barcode.** { *; }
-keep class com.google.android.gms.internal.mlkit_** { *; }
-keep class com.google.android.gms.vision.** { *; }
-keep class com.google.android.libraries.barhopper.** { *; }

# Keep mobile_scanner plugin classes
-keep class dev.steenbakker.mobile_scanner.** { *; }

# Keep CameraX
-keep class androidx.camera.** { *; }

# Keep reflection enums
-keepclassmembers enum * { *; }

-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.**
-dontwarn dev.steenbakker.mobile_scanner.**
