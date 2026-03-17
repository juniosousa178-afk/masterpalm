package com.masterpalm.app

import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest
import java.security.cert.X509Certificate

class MainActivity : FlutterActivity() {
    private val channel = "com.masterpalm.app/signing_certs"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel).setMethodCallHandler { call, result ->
            if (call.method == "getSigningFingerprints") {
                try {
                    val pm = packageManager
                    val pkg = packageName
                    val packageInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        pm.getPackageInfo(pkg, PackageManager.GET_SIGNING_CERTIFICATES)
                    } else {
                        @Suppress("DEPRECATION")
                        pm.getPackageInfo(pkg, PackageManager.GET_SIGNATURES)
                    }
                    val sha1List = mutableListOf<String>()
                    val sha256List = mutableListOf<String>()
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        val certs = packageInfo.signingInfo?.apkContentsSigners ?: emptyArray()
                        for (cert in certs) {
                            val encoded = (cert as? X509Certificate)?.encoded ?: cert.toByteArray()
                            sha1List.add(bytesToHex(MessageDigest.getInstance("SHA-1").digest(encoded)))
                            sha256List.add(bytesToHex(MessageDigest.getInstance("SHA-256").digest(encoded)))
                        }
                    } else {
                        @Suppress("DEPRECATION")
                        val signatures = packageInfo.signatures ?: emptyArray()
                        for (sig in signatures) {
                            val encoded = sig.toByteArray()
                            sha1List.add(bytesToHex(MessageDigest.getInstance("SHA-1").digest(encoded)))
                            sha256List.add(bytesToHex(MessageDigest.getInstance("SHA-256").digest(encoded)))
                        }
                    }
                    result.success(mapOf(
                        "sha1" to sha1List,
                        "sha256" to sha256List
                    ))
                } catch (e: Exception) {
                    result.error("ERROR", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    private fun bytesToHex(bytes: ByteArray): String {
        return bytes.joinToString("") { "%02x".format(it) }
            .chunked(2)
            .joinToString(":")
            .uppercase()
    }
}
