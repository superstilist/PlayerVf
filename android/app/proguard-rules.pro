##############################################################################
# PlayerVf – ProGuard / R8 rules
##############################################################################

# ── Flutter ──────────────────────────────────────────────────────────────────
-keep class io.flutter.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-dontwarn io.flutter.**

# ── Chaquopy / Python bridge ──────────────────────────────────────────────────
-keep class com.chaquo.python.** { *; }
-keepclassmembers class com.chaquo.python.** { *; }
-dontwarn com.chaquo.python.**

# ── audio_service / ryanheise ────────────────────────────────────────────────
-keep class com.ryanheise.** { *; }
-keepclassmembers class com.ryanheise.** { *; }
-dontwarn com.ryanheise.**

# ── media_kit / libmpv ───────────────────────────────────────────────────────
-keep class com.alexmercerind.** { *; }
-keepclassmembers class com.alexmercerind.** { *; }
-dontwarn com.alexmercerind.**

# ── just_audio ───────────────────────────────────────────────────────────────
-keep class com.ryanheise.just_audio.** { *; }

# ── on_audio_query ───────────────────────────────────────────────────────────
-keep class com.lucasjosino.on_audio_query.** { *; }
-keepclassmembers class com.lucasjosino.on_audio_query.** { *; }
-dontwarn com.lucasjosino.**

# ── permission_handler ───────────────────────────────────────────────────────
-keep class com.baseflow.permissionhandler.** { *; }
-dontwarn com.baseflow.permissionhandler.**

# ── file_picker ──────────────────────────────────────────────────────────────
-keep class com.mr.flutter.plugin.filepicker.** { *; }
-dontwarn com.mr.flutter.plugin.filepicker.**

# ── device_info_plus ─────────────────────────────────────────────────────────
-keep class dev.fluttercommunity.plus.device_info.** { *; }
-dontwarn dev.fluttercommunity.plus.**

# ── shared_preferences ───────────────────────────────────────────────────────
-keep class io.flutter.plugins.sharedpreferences.** { *; }

# ── sqflite ──────────────────────────────────────────────────────────────────
-keep class com.tekartik.sqflite.** { *; }
-dontwarn com.tekartik.sqflite.**

# ── smtc_windows stub (no-op on Android) ─────────────────────────────────────
-dontwarn com.smtc.**

# ── Kotlin ───────────────────────────────────────────────────────────────────
-keep class kotlin.** { *; }
-keepclassmembers class kotlin.** { *; }
-keep class kotlinx.** { *; }
-keepclassmembers class kotlinx.** { *; }
-dontwarn kotlin.**
-dontwarn kotlinx.**

# ── JSON (org.json, used in MainActivity) ────────────────────────────────────
-keep class org.json.** { *; }

# ── Android / General ────────────────────────────────────────────────────────
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
-keepattributes Signature
-keepattributes Exceptions

# Keep all MainActivity and services in this app
-keep class com.example.untitled.** { *; }

# Preserve enum values (used by settings/models)
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# Keep Parcelable implementations
-keep class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator *;
}

# Keep Serializable implementations
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# Suppress common harmless warnings from transitive dependencies
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**
-dontwarn javax.annotation.**
-dontwarn sun.misc.**
