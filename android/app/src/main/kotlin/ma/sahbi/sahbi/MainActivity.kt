package ma.sahbi.sahbi

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.PowerManager
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.MediaMetadataRetriever
import android.media.MediaRouter2
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.provider.Settings
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.zip.ZipInputStream
import java.security.MessageDigest
import java.util.concurrent.Executors

/**
 * Platform channel `ma.sahbi/platform`.
 *
 * - SAF pickers for audio files / folders (persistable read permission, no
 *   broad storage permission), with metadata from MediaMetadataRetriever and
 *   embedded art cached to app cache.
 * - Active audio output (speaker / wired / Bluetooth / USB).
 * - System output switcher (MediaRouter2, API 34+), with fallbacks.
 * - Media volume (STREAM_MUSIC).
 * - Save a document (ACTION_CREATE_DOCUMENT) for memory export.
 *
 * Extends AudioServiceActivity so audio_service shares the FlutterEngine.
 */
class MainActivity : AudioServiceActivity() {
    private val channelName = "ma.sahbi/platform"
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    private val reqPickFiles = 7101
    private val reqPickFolder = 7102
    private val reqSaveDoc = 7103

    private var pendingResult: MethodChannel.Result? = null
    private var pendingBytes: ByteArray? = null

    private val audioManager: AudioManager
        get() = getSystemService(AUDIO_SERVICE) as AudioManager

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result -> handle(call, result) }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ma.sahbi/mimo")
            .setMethodCallHandler { call, result -> handleMimo(call, result) }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "ma.sahbi/mimo_events")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                    MimoWakeService.events = { sink.success(it) }
                }

                override fun onCancel(arguments: Any?) {
                    MimoWakeService.events = null
                }
            })
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "pickAudioFiles" -> startPicker(result, reqPickFiles) {
                    Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "audio/*"
                        putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                    }
                }
                "pickAudioFolder" -> startPicker(result, reqPickFolder) {
                    Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                    }
                }
                "saveDocument" -> {
                    val name = call.argument<String>("name") ?: "sahbi_export.json"
                    val mime = call.argument<String>("mime") ?: "application/json"
                    val bytes = call.argument<ByteArray>("bytes")
                    if (bytes == null) {
                        result.error("bad_args", "bytes missing", null)
                        return
                    }
                    pendingBytes = bytes
                    startPicker(result, reqSaveDoc) {
                        Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = mime
                            putExtra(Intent.EXTRA_TITLE, name)
                        }
                    }
                }
                "getActiveAudioOutput" -> result.success(activeOutput())
                "openOutputSwitcher" -> result.success(openOutputSwitcher())
                "openBluetoothSettings" -> result.success(openBluetoothSettings())
                "getMediaVolume" -> result.success(mediaVolume())
                "adjustMediaVolume" -> {
                    val dir = call.argument<Int>("direction") ?: 0
                    if (audioManager.isVolumeFixed) {
                        result.success(null)
                    } else {
                        audioManager.adjustStreamVolume(
                            AudioManager.STREAM_MUSIC,
                            if (dir > 0) AudioManager.ADJUST_RAISE else AudioManager.ADJUST_LOWER,
                            AudioManager.FLAG_SHOW_UI,
                        )
                        result.success(mediaVolume())
                    }
                }
                "setMediaVolume" -> {
                    val level = (call.argument<Double>("level") ?: 0.5).coerceIn(0.0, 1.0)
                    if (audioManager.isVolumeFixed) {
                        result.success(null)
                    } else {
                        val max = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                        audioManager.setStreamVolume(
                            AudioManager.STREAM_MUSIC,
                            Math.round(level * max).toInt(),
                            AudioManager.FLAG_SHOW_UI,
                        )
                        result.success(mediaVolume())
                    }
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("platform_error", e.message, null)
        }
    }

    // ---- pickers ------------------------------------------------------------

    private fun startPicker(result: MethodChannel.Result, code: Int, build: () -> Intent) {
        if (pendingResult != null) {
            result.error("busy", "Another picker is open", null)
            return
        }
        pendingResult = result
        try {
            @Suppress("DEPRECATION")
            startActivityForResult(build(), code)
        } catch (e: ActivityNotFoundException) {
            pendingResult = null
            pendingBytes = null
            result.error("no_picker", "No document picker available", null)
        }
    }

    @Deprecated("Activity result API is not available on FlutterActivity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode !in listOf(reqPickFiles, reqPickFolder, reqSaveDoc)) return
        val result = pendingResult ?: return
        pendingResult = null
        val ok = resultCode == Activity.RESULT_OK && data != null

        when (requestCode) {
            reqSaveDoc -> {
                val bytes = pendingBytes
                pendingBytes = null
                val uri = data?.data
                if (!ok || uri == null || bytes == null) {
                    result.success(false)
                    return
                }
                io.execute {
                    val saved = try {
                        contentResolver.openOutputStream(uri, "wt")?.use { it.write(bytes) } != null
                    } catch (e: Exception) {
                        false
                    }
                    main.post { result.success(saved) }
                }
            }
            reqPickFiles -> {
                if (!ok) {
                    result.success(emptyList<Map<String, Any?>>())
                    return
                }
                val uris = mutableListOf<Uri>()
                val clip = data!!.clipData
                if (clip != null) {
                    for (i in 0 until clip.itemCount) uris.add(clip.getItemAt(i).uri)
                } else {
                    data.data?.let { uris.add(it) }
                }
                uris.forEach { persist(it) }
                io.execute {
                    val list = uris.map { describe(it, null) }
                    main.post { result.success(list) }
                }
            }
            reqPickFolder -> {
                val tree = data?.data
                if (!ok || tree == null) {
                    result.success(emptyList<Map<String, Any?>>())
                    return
                }
                persist(tree)
                io.execute {
                    val list = try {
                        listAudioInTree(tree)
                    } catch (e: Exception) {
                        emptyList()
                    }
                    main.post { result.success(list) }
                }
            }
        }
    }

    private fun persist(uri: Uri) {
        try {
            contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        } catch (_: SecurityException) {
            // Provider does not offer persistable grants; the URI works until reboot.
        }
    }

    private fun listAudioInTree(tree: Uri, maxFiles: Int = 500, maxDepth: Int = 4): List<Map<String, Any?>> {
        val out = mutableListOf<Map<String, Any?>>()
        val rootId = DocumentsContract.getTreeDocumentId(tree)
        fun walk(docId: String, depth: Int) {
            if (depth > maxDepth || out.size >= maxFiles) return
            val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, docId)
            contentResolver.query(
                children,
                arrayOf(
                    DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                    DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                    DocumentsContract.Document.COLUMN_MIME_TYPE,
                ),
                null, null, null,
            )?.use { c ->
                while (c.moveToNext() && out.size < maxFiles) {
                    val id = c.getString(0)
                    val name = c.getString(1) ?: "audio"
                    val mime = c.getString(2) ?: ""
                    if (mime == DocumentsContract.Document.MIME_TYPE_DIR) {
                        walk(id, depth + 1)
                    } else if (mime.startsWith("audio/")) {
                        val uri = DocumentsContract.buildDocumentUriUsingTree(tree, id)
                        out.add(describe(uri, name))
                    }
                }
            }
        }
        walk(rootId, 0)
        return out
    }

    private fun displayName(uri: Uri): String? = try {
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst()) c.getString(0) else null
        }
    } catch (_: Exception) {
        null
    }

    /** Metadata for one audio document. Never throws. */
    private fun describe(uri: Uri, knownName: String?): Map<String, Any?> {
        val name = knownName ?: displayName(uri) ?: "audio"
        val m = mutableMapOf<String, Any?>("uri" to uri.toString(), "name" to name)
        val r = MediaMetadataRetriever()
        try {
            r.setDataSource(this, uri)
            m["title"] = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_TITLE)
            m["artist"] = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ARTIST)
            m["album"] = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ALBUM)
            m["durationMs"] = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()
            r.embeddedPicture?.let { art ->
                val dir = File(cacheDir, "art").apply { mkdirs() }
                val f = File(dir, sha1(uri.toString()) + ".img")
                if (!f.exists()) f.writeBytes(art)
                m["artPath"] = f.absolutePath
            }
        } catch (_: Exception) {
            // Unreadable metadata is fine; the file name is used as title.
        } finally {
            try {
                r.release()
            } catch (_: Exception) {
            }
        }
        return m
    }

    private fun sha1(s: String): String =
        MessageDigest.getInstance("SHA-1").digest(s.toByteArray()).joinToString("") { "%02x".format(it) }

    // ---- audio output ---------------------------------------------------------

    private fun typeOf(d: AudioDeviceInfo): String = when (d.type) {
        AudioDeviceInfo.TYPE_BLUETOOTH_A2DP, AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "bluetooth"
        AudioDeviceInfo.TYPE_WIRED_HEADSET, AudioDeviceInfo.TYPE_WIRED_HEADPHONES, AudioDeviceInfo.TYPE_LINE_ANALOG -> "wired"
        AudioDeviceInfo.TYPE_USB_DEVICE, AudioDeviceInfo.TYPE_USB_HEADSET, AudioDeviceInfo.TYPE_USB_ACCESSORY -> "usb"
        AudioDeviceInfo.TYPE_HDMI, AudioDeviceInfo.TYPE_HDMI_ARC -> "hdmi"
        AudioDeviceInfo.TYPE_BUILTIN_SPEAKER, AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> "speaker"
        else -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            (d.type == AudioDeviceInfo.TYPE_BLE_HEADSET || d.type == AudioDeviceInfo.TYPE_BLE_SPEAKER)
        ) "bluetooth" else "other"
    }

    private fun activeOutput(): Map<String, Any?> {
        val am = audioManager
        val device: AudioDeviceInfo? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            // Actual routing for media on Android 13+.
            val attrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                .build()
            am.getAudioDevicesForAttributes(attrs).firstOrNull()?.let { routed ->
                am.getDevices(AudioManager.GET_DEVICES_OUTPUTS).firstOrNull { it.type == routed.type }
            }
        } else {
            null
        }
        val chosen = device ?: run {
            // Older Android: best guess by priority (media prefers BT > USB > wired > speaker).
            val outs = am.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
            val order = listOf("bluetooth", "usb", "wired", "speaker")
            order.firstNotNullOfOrNull { t -> outs.firstOrNull { typeOf(it) == t && !(t == "bluetooth" && it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO) } }
        }
        if (chosen == null) return mapOf("type" to "unknown", "name" to "", "isBluetooth" to false)
        val type = typeOf(chosen)
        val name = chosen.productName?.toString()?.takeIf { it.isNotBlank() && it != Build.MODEL } ?: ""
        return mapOf("type" to type, "name" to name, "isBluetooth" to (type == "bluetooth"))
    }

    private fun openOutputSwitcher(): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            try {
                if (MediaRouter2.getInstance(this).showSystemOutputSwitcher()) return "output_switcher"
            } catch (_: Exception) {
            }
        }
        // Android 11–13: SystemUI media output dialog. Not a public API, so it
        // is attempted defensively and falls back to Bluetooth settings.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                val i = Intent("com.android.systemui.action.LAUNCH_MEDIA_OUTPUT_DIALOG").apply {
                    setPackage("com.android.systemui")
                    putExtra("package_name", packageName)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                sendBroadcast(i)
                return "media_output_panel"
            } catch (_: Exception) {
            }
        }
        return if (openBluetoothSettings()) "bluetooth_settings" else "none"
    }

    private fun openBluetoothSettings(): Boolean = try {
        startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
        true
    } catch (_: Exception) {
        false
    }

    private fun mediaVolume(): Double? {
        val am = audioManager
        val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        if (max <= 0) return null
        return am.getStreamVolume(AudioManager.STREAM_MUSIC).toDouble() / max
    }

    /** Channel `ma.sahbi/mimo`: wake-word service, model unzip, heat. */
    private fun handleMimo(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "start" -> {
                    val i = Intent(this, MimoWakeService::class.java)
                        .setAction(MimoWakeService.ACTION_START)
                        .putExtra(MimoWakeService.EXTRA_MODEL, call.argument<String>("model"))
                        .putExtra(MimoWakeService.EXTRA_GRAMMAR, call.argument<String>("grammar"))
                        .putExtra(
                            MimoWakeService.EXTRA_WORDS,
                            (call.argument<List<String>>("words") ?: listOf("mimo")).toTypedArray(),
                        )
                        .putExtra(MimoWakeService.EXTRA_PAUSED, call.argument<Boolean>("paused") ?: false)
                        .putExtra(MimoWakeService.EXTRA_TITLE, call.argument<String>("title"))
                        .putExtra(MimoWakeService.EXTRA_TEXT, call.argument<String>("text"))
                        .putExtra(MimoWakeService.EXTRA_STOP, call.argument<String>("stopLabel"))
                        .putExtra(MimoWakeService.EXTRA_OPEN, call.argument<String>("openLabel"))
                        .putExtra(MimoWakeService.EXTRA_CHANNEL, call.argument<String>("channelName"))
                    try {
                        startForegroundService(i)
                        result.success(true)
                    } catch (e: Exception) {
                        // Android 12+: not allowed from the background.
                        result.error("fgs_not_allowed", e.message, null)
                    }
                }
                "stop" -> {
                    MimoWakeService.instance?.shutdown()
                    stopService(Intent(this, MimoWakeService::class.java))
                    result.success(true)
                }
                "pause" -> {
                    MimoWakeService.instance?.pause()
                    result.success(MimoWakeService.instance != null)
                }
                "resume" -> {
                    MimoWakeService.instance?.resume()
                    result.success(MimoWakeService.instance != null)
                }
                "isRunning" -> result.success(MimoWakeService.running)
                "unzip" -> {
                    val zip = call.argument<String>("zip")
                    val dest = call.argument<String>("dest")
                    if (zip == null || dest == null) {
                        result.error("bad_args", "zip and dest required", null)
                        return
                    }
                    io.execute {
                        try {
                            unzip(File(zip), File(dest))
                            main.post { result.success(true) }
                        } catch (e: Exception) {
                            main.post { result.error("unzip", e.message, null) }
                        }
                    }
                }
                "thermal" -> result.success(thermal())
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("mimo", e.message, null)
        }
    }

    /** Unzips with a path-traversal check (entries must stay inside dest). */
    private fun unzip(zip: File, dest: File) {
        dest.mkdirs()
        val root = dest.canonicalPath + File.separator
        ZipInputStream(zip.inputStream().buffered()).use { zin ->
            while (true) {
                val e = zin.nextEntry ?: break
                val out = File(dest, e.name)
                if (!out.canonicalPath.startsWith(root)) throw SecurityException("bad entry ${e.name}")
                if (e.isDirectory) {
                    out.mkdirs()
                } else {
                    out.parentFile?.mkdirs()
                    FileOutputStream(out).use { zin.copyTo(it) }
                }
                zin.closeEntry()
            }
        }
    }

    /** Battery temperature (°C) and battery saver, to rest the camera. */
    private fun thermal(): Map<String, Any?> {
        val b = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val t = b?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, Int.MIN_VALUE) ?: Int.MIN_VALUE
        val pm = getSystemService(POWER_SERVICE) as PowerManager
        return mapOf(
            "batteryC" to (if (t == Int.MIN_VALUE) null else t / 10.0),
            "powerSave" to pm.isPowerSaveMode,
        )
    }

    override fun onDestroy() {
        // The app is closing (not a rotation): never leave MIMO listening.
        if (isFinishing) {
            MimoWakeService.instance?.shutdown()
            try {
                stopService(Intent(this, MimoWakeService::class.java))
            } catch (_: Exception) {}
        }
        MimoWakeService.events = null
        io.shutdown()
        super.onDestroy()
    }
}
