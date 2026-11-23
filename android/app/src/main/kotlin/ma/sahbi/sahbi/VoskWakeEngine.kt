package ma.sahbi.sahbi

import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.NoiseSuppressor
import org.json.JSONObject
import org.vosk.Model
import org.vosk.Recognizer

/**
 * Offline wake word ("MIMO") with Vosk: a small grammar recogniser (the wake
 * words plus look-alike decoys such as "momo", "mama", "mimi") fed from one
 * AudioRecord at 16 kHz. Nothing leaves the phone, nothing is stored.
 *
 * - [pause] releases the microphone completely (another recorder may use it),
 *   [resume] opens it again; the model stays loaded.
 * - [release] stops the thread and frees the mic, recogniser and model.
 *
 * Callbacks run on the engine thread.
 */
class VoskWakeEngine(
    private val modelPath: String,
    private val grammarJson: String,
    private val wakeWords: Set<String>,
    private val onReady: () -> Unit,
    private val onWake: (String) -> Unit,
    private val onError: (code: String, message: String, fatal: Boolean) -> Unit,
) {
    @Volatile private var paused = false
    @Volatile private var stopped = false
    private var thread: Thread? = null
    private var record: AudioRecord? = null
    private var aec: AcousticEchoCanceler? = null
    private var ns: NoiseSuppressor? = null

    fun start() {
        if (thread != null) return
        thread = Thread({ loop() }, "mimo-wake").also { it.start() }
    }

    fun pause() {
        paused = true
    }

    fun resume() {
        paused = false
    }

    val isPaused: Boolean
        get() = paused

    fun release() {
        stopped = true
        thread?.interrupt()
        thread = null
    }

    private fun loop() {
        val model: Model
        try {
            model = Model(modelPath)
        } catch (e: Throwable) {
            onError("model", e.message ?: "model load failed", true)
            return
        }
        val rec: Recognizer
        try {
            rec = Recognizer(model, SAMPLE_RATE.toFloat(), grammarJson)
        } catch (e: Throwable) {
            model.close()
            onError("model", e.message ?: "recognizer failed", true)
            return
        }
        onReady()
        val buf = ShortArray(SAMPLE_RATE / 10) // 100 ms
        var lastHit = 0L
        var partialHits = 0
        try {
            while (!stopped) {
                if (paused) {
                    closeRecord()
                    partialHits = 0
                    sleepQuietly(80)
                    continue
                }
                val r = record ?: openRecord()
                if (r == null) {
                    sleepQuietly(1000)
                    continue
                }
                val n = r.read(buf, 0, buf.size)
                if (n <= 0) {
                    // Mic taken away / dead object: reopen after a moment.
                    closeRecord()
                    sleepQuietly(300)
                    continue
                }
                val isFinal = rec.acceptWaveForm(buf, n)
                val text = if (isFinal) {
                    field(rec.result, "text")
                } else {
                    field(rec.partialResult, "partial")
                }
                val hit = text.split(' ').any { it in wakeWords }
                // A final result is enough; a partial must repeat (≈200 ms)
                // so a decoy that is still being decided does not fire.
                partialHits = if (hit && !isFinal) partialHits + 1 else 0
                val now = System.currentTimeMillis()
                if (hit && (isFinal || partialHits >= 2) && now - lastHit > COOLDOWN_MS) {
                    lastHit = now
                    partialHits = 0
                    rec.reset()
                    onWake(text)
                }
            }
        } catch (e: Throwable) {
            onError("engine", e.message ?: e.javaClass.simpleName, true)
        } finally {
            closeRecord()
            try { rec.close() } catch (_: Throwable) {}
            try { model.close() } catch (_: Throwable) {}
        }
    }

    private fun openRecord(): AudioRecord? {
        val min = AudioRecord.getMinBufferSize(
            SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT,
        )
        val size = maxOf(min, SAMPLE_RATE / 5 * 2) * 2
        val r = try {
            AudioRecord(
                // VOICE_RECOGNITION: tuned for speech, no AGC surprises; the
                // echo canceller below (when the phone has one) keeps MIMO's
                // own voice from waking it.
                MediaRecorder.AudioSource.VOICE_RECOGNITION,
                SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, size,
            )
        } catch (e: SecurityException) {
            onError("permission", "RECORD_AUDIO not granted", true)
            stopped = true
            return null
        } catch (e: Throwable) {
            onError("mic", e.message ?: "AudioRecord failed", false)
            return null
        }
        if (r.state != AudioRecord.STATE_INITIALIZED) {
            r.release()
            onError("mic", "microphone busy", false)
            return null
        }
        try {
            if (AcousticEchoCanceler.isAvailable()) {
                aec = AcousticEchoCanceler.create(r.audioSessionId)?.also { it.enabled = true }
            }
            if (NoiseSuppressor.isAvailable()) {
                ns = NoiseSuppressor.create(r.audioSessionId)?.also { it.enabled = true }
            }
        } catch (_: Throwable) {}
        try {
            r.startRecording()
        } catch (e: Throwable) {
            r.release()
            onError("mic", e.message ?: "startRecording failed", false)
            return null
        }
        record = r
        return r
    }

    private fun closeRecord() {
        val r = record ?: return
        record = null
        try { aec?.release() } catch (_: Throwable) {}
        try { ns?.release() } catch (_: Throwable) {}
        aec = null
        ns = null
        try { r.stop() } catch (_: Throwable) {}
        r.release()
    }

    private fun field(json: String, key: String): String = try {
        JSONObject(json).optString(key, "")
    } catch (_: Throwable) {
        ""
    }

    private fun sleepQuietly(ms: Long) {
        try { Thread.sleep(ms) } catch (_: InterruptedException) {}
    }

    companion object {
        const val SAMPLE_RATE = 16000
        const val COOLDOWN_MS = 1500L
    }
}
