# R8 / ProGuard rules for the release build.
#
# ---------------------------------------------------------------------
# ML Kit text recognition — unused script variants
# ---------------------------------------------------------------------
# The google_mlkit_text_recognition plugin's Java side references all five
# script recognisers (Latin, Chinese, Devanagari, Japanese, Korean) from a
# single initialize() method, because it lets Dart choose at runtime.
#
# We only ever ask for Latin (see MlKitRecogniser), so only the Latin
# model is pulled in as a dependency — and R8 then fails the build
# because the other four classes are referenced but absent.
#
# Suppressing the warnings is the right fix rather than adding the four
# missing dependencies: each is a separate on-device model worth several
# megabytes, and a timetable printed in English needs none of them. The
# referencing code path is never executed, so the missing classes can
# never be loaded.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# Keep the Latin recogniser and the shared text-recognition surface. R8
# can't see that these are reached through the plugin's reflection-based
# method channel, so without this it may strip classes that are actually
# used at runtime.
-keep class com.google.mlkit.vision.text.latin.** { *; }
-keep class com.google.mlkit.vision.text.TextRecognition { *; }
-keep class com.google.mlkit.vision.text.TextRecognizer { *; }
-keep class com.google.mlkit.vision.text.TextRecognizerOptionsInterface { *; }

# ---------------------------------------------------------------------
# TensorFlow Lite — face embedding
# ---------------------------------------------------------------------
# The interpreter resolves ops and delegates by name at runtime.
-keep class org.tensorflow.lite.** { *; }
-dontwarn org.tensorflow.lite.**
