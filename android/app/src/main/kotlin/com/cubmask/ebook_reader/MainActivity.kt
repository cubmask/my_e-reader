package com.cubmask.ebook_reader

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import android.provider.Settings
import android.view.WindowManager
import androidx.core.content.FileProvider
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

// Shares its Flutter engine with the read-aloud media service.
//
// Also answers the app's "ebook_reader/platform" channel: screen brightness
// and keep-awake while reading, picking books to add, books opened or shared
// from other apps, sharing and saving files, handing text to Translate, and
// the device's name.
class MainActivity : AudioServiceActivity() {
    private var channel: MethodChannel? = null
    private val main = Handler(Looper.getMainLooper())

    // Files other apps opened or shared with us, waiting for Dart to ask.
    private val incoming = mutableListOf<Map<String, String>>()
    private var pending: MethodChannel.Result? = null
    private var saveSource: File? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ebook_reader/platform").apply {
            setMethodCallHandler(::onCall)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null) receive(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        receive(intent)
    }

    private fun onCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setBrightness" -> {
                val value = call.argument<Double>("value")
                window.attributes = window.attributes.apply {
                    screenBrightness = value?.toFloat()?.coerceIn(0.01f, 1f)
                        ?: WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
                }
                result.success(null)
            }
            "keepScreenOn" -> {
                if (call.argument<Boolean>("on") == true) {
                    window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                } else {
                    window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                }
                result.success(null)
            }
            "pickBooks" -> {
                if (pending != null) return result.error("busy", "Already picking", null)
                pending = result
                val pick = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "*/*"
                    putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                }
                startActivityForResult(pick, PICK)
            }
            "takeIncoming" -> {
                result.success(incoming.toList())
                incoming.clear()
            }
            "shareFile" -> {
                val file = File(call.argument<String>("path")!!)
                val uri = FileProvider.getUriForFile(this, "$packageName.files", file)
                val send = Intent(Intent.ACTION_SEND).apply {
                    type = call.argument<String>("mimeType") ?: "application/octet-stream"
                    putExtra(Intent.EXTRA_STREAM, uri)
                    clipData = ClipData.newRawUri(file.name, uri)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                startActivity(Intent.createChooser(send, call.argument<String>("title")))
                result.success(true)
            }
            "shareText" -> {
                val send = Intent(Intent.ACTION_SEND).apply {
                    type = "text/plain"
                    putExtra(Intent.EXTRA_TEXT, call.argument<String>("text"))
                }
                startActivity(Intent.createChooser(send, call.argument<String>("title")))
                result.success(true)
            }
            "saveFile" -> {
                if (pending != null) return result.error("busy", "Already saving", null)
                val file = File(call.argument<String>("path")!!)
                pending = result
                saveSource = file
                val save = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = call.argument<String>("mimeType") ?: "application/octet-stream"
                    putExtra(Intent.EXTRA_TITLE, call.argument<String>("name") ?: file.name)
                }
                startActivityForResult(save, SAVE)
            }
            "deviceName" -> {
                // The name set under About tablet, which Samsung fills in
                // with the model's marketing name.
                val name = Settings.Global.getString(contentResolver, Settings.Global.DEVICE_NAME)
                result.success(name?.takeIf { it.isNotBlank() } ?: Build.MODEL)
            }
            "translate" -> {
                // Google Translate takes selected text from any app this way.
                val translate = Intent(Intent.ACTION_PROCESS_TEXT).apply {
                    type = "text/plain"
                    setPackage("com.google.android.apps.translate")
                    putExtra(Intent.EXTRA_PROCESS_TEXT, call.argument<String>("text"))
                    putExtra(Intent.EXTRA_PROCESS_TEXT_READONLY, true)
                }
                try {
                    startActivity(translate)
                    result.success(true)
                } catch (e: ActivityNotFoundException) {
                    result.success(false)
                }
            }
            else -> result.notImplemented()
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        val result = pending
        if (requestCode != PICK && requestCode != SAVE || result == null) return
        pending = null
        if (resultCode != Activity.RESULT_OK || data == null) {
            saveSource = null
            return result.success(if (requestCode == PICK) emptyList<Any>() else false)
        }
        if (requestCode == SAVE) {
            val source = saveSource
            saveSource = null
            val target = data.data
            Thread {
                val ok = try {
                    contentResolver.openOutputStream(target!!)!!.use { out ->
                        source!!.inputStream().use { it.copyTo(out) }
                    }
                    true
                } catch (e: Exception) {
                    false
                }
                main.post { result.success(ok) }
            }.start()
            return
        }
        val uris = buildList {
            data.clipData?.let { clip -> for (i in 0 until clip.itemCount) add(clip.getItemAt(i).uri) }
            if (isEmpty()) data.data?.let(::add)
        }
        Thread {
            val files = uris.mapNotNull(::copyToCache)
            main.post { result.success(files) }
        }.start()
    }

    // Books opened with this app ("Open with") or shared to it.
    private fun receive(intent: Intent?) {
        intent ?: return
        val uris = when (intent.action) {
            Intent.ACTION_VIEW -> listOfNotNull(intent.data)
            Intent.ACTION_SEND -> listOfNotNull(intent.streamUri())
            Intent.ACTION_SEND_MULTIPLE -> intent.streamUris()
            else -> emptyList()
        }
        if (uris.isEmpty()) return
        // Handled once, even if the activity is recreated.
        intent.action = Intent.ACTION_MAIN
        Thread {
            val files = uris.mapNotNull(::copyToCache)
            main.post {
                incoming.addAll(files)
                // Dart also asks once it starts, in case it wasn't listening yet.
                channel?.invokeMethod("incoming", null)
            }
        }.start()
    }

    @Suppress("DEPRECATION")
    private fun Intent.streamUri(): Uri? = getParcelableExtra(Intent.EXTRA_STREAM)

    @Suppress("DEPRECATION")
    private fun Intent.streamUris(): List<Uri> =
        getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM) ?: emptyList()

    // Copies a document to the cache, since content URIs don't outlive the
    // intent that granted them.
    private fun copyToCache(uri: Uri): Map<String, String>? = try {
        val name = displayName(uri) ?: uri.lastPathSegment?.substringAfterLast('/') ?: "book"
        val dir = File(cacheDir, "incoming").apply { mkdirs() }
        val file = File(dir, "${System.nanoTime()}_${name.replace('/', '_')}")
        contentResolver.openInputStream(uri)!!.use { input ->
            file.outputStream().use { input.copyTo(it) }
        }
        mapOf("path" to file.path, "name" to name)
    } catch (e: Exception) {
        null
    }

    private fun displayName(uri: Uri): String? =
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
            if (it.moveToFirst()) it.getString(0) else null
        }

    companion object {
        private const val PICK = 4101
        private const val SAVE = 4102
    }
}
