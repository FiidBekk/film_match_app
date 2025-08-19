package com.example.film_match_app

import android.os.Bundle
import android.content.pm.ActivityInfo
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // 1) Kifejezetten PORTRAIT
        requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT

        // 2) Ezután LOCKED – teljesen lezárja az aktuális állást (API 18+)
        window?.decorView?.post {
            requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_LOCKED
        }
    }
}
