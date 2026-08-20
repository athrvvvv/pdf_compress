package com.atharv.pdfcompressor.pdf_compressor

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.atharv.pdfcompressor/share_intent"
    private var sharedPdfPath: String? = null
    private var methodChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            if (call.method == "getSharedPdf") {
                result.success(sharedPdfPath)
                sharedPdfPath = null
            } else {
                result.notImplemented()
            }
        }

        sharedPdfPath?.let { path ->
            methodChannel?.invokeMethod("onPdfShared", path)
        }
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null) return
        val action = intent.action
        val type = intent.type

        if (Intent.ACTION_SEND == action) {
            @Suppress("DEPRECATION")
            val uri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM) ?: intent.data
            uri?.let { copyUriToCache(it) }
        } else if (Intent.ACTION_VIEW == action) {
            val uri = intent.data
            uri?.let { copyUriToCache(it) }
        }
    }

    private fun copyUriToCache(uri: Uri) {
        try {
            contentResolver.openInputStream(uri)?.use { inputStream ->
                val fileName = "shared_${System.currentTimeMillis()}.pdf"
                val destFile = File(cacheDir, fileName)
                FileOutputStream(destFile).use { outputStream ->
                    inputStream.copyTo(outputStream)
                }
                val path = destFile.absolutePath
                sharedPdfPath = path
                methodChannel?.invokeMethod("onPdfShared", path)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
}
