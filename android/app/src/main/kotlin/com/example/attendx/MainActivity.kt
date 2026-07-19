package com.example.attendx

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity (not FlutterActivity) is required by local_auth
// for the fingerprint/biometric prompt. This is the ACTIVE MainActivity —
// build.gradle namespace is com.example.attendx.
class MainActivity : FlutterFragmentActivity()
