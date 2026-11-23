package ma.sahbi.sahbi

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper

/**
 * Keeps the "MIMO" wake word alive while the app is open or minimised, with
 * a visible notification ("Stop MIMO" / "Open"). Microphone only: the camera
 * is always closed in the background.
 *
 * Android 14+ only lets a microphone foreground service START while the app
 * is visible, so Flutter starts it when the mic toggle is on and the app is
 * open; it then survives minimising.
 *
 * It never outlives the app: `stopWithTask="true"` in the manifest, plus
 * [onTaskRemoved] (app swiped away) and MainActivity.onDestroy(isFinishing)
 * stop it, and every stop frees the microphone.
 */
class MimoWakeService : Service() {

    private var engine: VoskWakeEngine? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                // "Stop MIMO" in the notification: the user turned the mic off.
                emit(mapOf("type" to "stopped", "byUser" to true))
                shutdown()
            }
            ACTION_START -> start(intent)
            // Restarted by the system without our data: do not listen.
            else -> shutdown()
        }
        return START_NOT_STICKY
    }

    private fun start(intent: Intent) {
        try {
            goForeground(intent)
        } catch (e: Exception) {
            // ForegroundServiceStartNotAllowedException (app not visible),
            // missing permission… Never listen without the notification.
            emit(mapOf("type" to "error", "code" to "fgs_not_allowed", "message" to (e.message ?: "")))
            shutdown()
            return
        }
        running = true
        if (engine != null) {
            emit(mapOf("type" to "state", "running" to true, "paused" to (engine?.isPaused ?: false)))
            return
        }
        val model = intent.getStringExtra(EXTRA_MODEL) ?: run {
            emit(mapOf("type" to "error", "code" to "model", "message" to "no model path"))
            shutdown()
            return
        }
        val grammar = intent.getStringExtra(EXTRA_GRAMMAR) ?: "[\"mimo\", \"[unk]\"]"
        val words = intent.getStringArrayExtra(EXTRA_WORDS)?.toSet() ?: setOf("mimo")
        val e = VoskWakeEngine(
            modelPath = model,
            grammarJson = grammar,
            wakeWords = words,
            onReady = { emit(mapOf("type" to "state", "running" to true, "paused" to false)) },
            onWake = { text -> emit(mapOf("type" to "wake", "text" to text)) },
            onError = { code, message, fatal ->
                emit(mapOf("type" to "error", "code" to code, "message" to message))
                if (fatal) main.post { shutdown() }
            },
        )
        if (intent.getBooleanExtra(EXTRA_PAUSED, false)) e.pause()
        engine = e
        e.start()
    }

    private fun goForeground(intent: Intent) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(CHANNEL) == null) {
            val ch = NotificationChannel(
                CHANNEL,
                intent.getStringExtra(EXTRA_CHANNEL) ?: "MIMO",
                NotificationManager.IMPORTANCE_LOW,
            )
            ch.setShowBadge(false)
            nm.createNotificationChannel(ch)
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val open = PendingIntent.getActivity(
            this, 1,
            Intent(this, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT),
            flags,
        )
        val stop = PendingIntent.getService(
            this, 2, Intent(this, MimoWakeService::class.java).setAction(ACTION_STOP), flags,
        )
        val n = Notification.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_mimo)
            .setContentTitle(intent.getStringExtra(EXTRA_TITLE) ?: "MIMO")
            .setContentText(intent.getStringExtra(EXTRA_TEXT) ?: "")
            .setContentIntent(open)
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .addAction(
                Notification.Action.Builder(null, intent.getStringExtra(EXTRA_STOP) ?: "Stop MIMO", stop).build(),
            )
            .addAction(
                Notification.Action.Builder(null, intent.getStringExtra(EXTRA_OPEN) ?: "Open", open).build(),
            )
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIF_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
        } else {
            startForeground(NOTIF_ID, n)
        }
    }

    fun pause() {
        engine?.pause()
        emit(mapOf("type" to "state", "running" to running, "paused" to true))
    }

    fun resume() {
        engine?.resume()
        emit(mapOf("type" to "state", "running" to running, "paused" to false))
    }

    /** Frees the microphone and removes the notification. */
    fun shutdown() {
        engine?.release()
        engine = null
        if (running) {
            running = false
            emit(mapOf("type" to "state", "running" to false, "paused" to false))
        }
        try {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } catch (_: Exception) {}
        stopSelf()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // App swiped away from recents: nothing may keep listening.
        shutdown()
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        engine?.release()
        engine = null
        running = false
        if (instance === this) instance = null
        super.onDestroy()
    }

    companion object {
        const val ACTION_START = "ma.sahbi.mimo.START"
        const val ACTION_STOP = "ma.sahbi.mimo.STOP"
        const val EXTRA_MODEL = "model"
        const val EXTRA_GRAMMAR = "grammar"
        const val EXTRA_WORDS = "words"
        const val EXTRA_PAUSED = "paused"
        const val EXTRA_TITLE = "title"
        const val EXTRA_TEXT = "text"
        const val EXTRA_STOP = "stopLabel"
        const val EXTRA_OPEN = "openLabel"
        const val EXTRA_CHANNEL = "channelName"
        const val CHANNEL = "mimo_listening"
        const val NOTIF_ID = 4711

        @Volatile var running = false
        @Volatile var instance: MimoWakeService? = null

        /** Set by MainActivity's EventChannel (main thread). */
        var events: ((Map<String, Any?>) -> Unit)? = null
        private val main = Handler(Looper.getMainLooper())

        fun emit(m: Map<String, Any?>) {
            main.post { events?.invoke(m) }
        }
    }
}
