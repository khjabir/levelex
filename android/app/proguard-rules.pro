# flutter_local_notifications serialises scheduled notifications with GSON.
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keep class com.dexterous.** { *; }

# ML Kit keeps its own rules via consumer proguard files; nothing extra needed.

# Room instantiates generated *_Impl database classes reflectively. Keep their
# no-arg constructors (R8 full mode strips them otherwise), including
# WorkManager's WorkDatabase that ML Kit brings in transitively.
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep class androidx.work.impl.WorkDatabase_Impl { *; }

# ML Kit registers its components (SharedPrefManager, model loaders, the pose
# detector itself) through ComponentRegistrar classes that are named in
# manifest <meta-data> and instantiated reflectively. R8 full mode strips
# their no-arg constructors, after which InputImage.fromByteArray fails with
# a NullPointerException deep inside vision-common. Keep them explicitly.
-keep class com.google.firebase.components.ComponentRegistrar
-keep class * implements com.google.firebase.components.ComponentRegistrar { <init>(); }
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_** { *; }
-dontwarn com.google.mlkit.**
