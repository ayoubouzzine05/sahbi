# Vosk (offline wake word) talks to its native library through JNA, which
# looks classes and members up by name at runtime: keep them from R8.
-keep class com.sun.jna.** { *; }
-keepclassmembers class * extends com.sun.jna.** { public *; }
-keep class org.vosk.** { *; }
-dontwarn java.awt.**
-dontwarn com.sun.jna.**
