package fr.projetled.luma

import android.Manifest
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.concurrent.thread
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.ln
import kotlin.math.log10
import kotlin.math.sqrt

class MainActivity : FlutterActivity() {
    private val channelName = "fr.projetled.luma/audio"
    private val mainHandler = Handler(Looper.getMainLooper())
    private var audioChannel: MethodChannel? = null
    @Volatile private var recorder: AudioRecord? = null
    @Volatile private var audioThread: Thread? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val audioMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        audioChannel = audioMethodChannel
        audioMethodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                        result.error("permission", "Autorisation microphone manquante", null)
                    } else {
                        try { startAudio(); result.success(true) }
                        catch (error: Exception) { stopAudio(); result.error("audio", error.message, null) }
                    }
                }
                "stop" -> { stopAudio(); result.success(true) }
                else -> result.notImplemented()
            }
        }
    }

    @Synchronized private fun startAudio() {
        stopAudio()
        val rate = 22050
        val frameSize = 1024
        val minimum = AudioRecord.getMinBufferSize(rate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        if (minimum <= 0) error("Microphone non disponible")
        val audio = AudioRecord(MediaRecorder.AudioSource.MIC, rate, AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT, maxOf(minimum, frameSize * 2))
        if (audio.state != AudioRecord.STATE_INITIALIZED) { audio.release(); error("Initialisation audio impossible") }
        audio.startRecording()
        recorder = audio
        audioThread = thread(name = "LumaAudio", isDaemon = true) {
            val samples = ShortArray(frameSize)
            while (!Thread.currentThread().isInterrupted && recorder === audio) {
                val read = audio.read(samples, 0, samples.size)
                if (read < frameSize) continue
                val levels = spectrum(samples, rate)
                mainHandler.post { audioChannel?.invokeMethod("levels", levels) }
                try { Thread.sleep(66) } catch (_: InterruptedException) { break }
            }
        }
    }

    @Synchronized private fun stopAudio() {
        val audio = recorder
        recorder = null
        audioThread?.interrupt()
        audioThread = null
        try { if (audio?.recordingState == AudioRecord.RECORDSTATE_RECORDING) audio.stop() } catch (_: Exception) { }
        audio?.release()
    }

    private fun spectrum(samples: ShortArray, sampleRate: Int): List<Int> {
        val count = samples.size
        return (0 until 32).map { band ->
            val frequency = 55.0 * Math.pow(8000.0 / 55.0, band / 31.0)
            val bin = (0.5 + count * frequency / sampleRate).toInt().coerceIn(1, count / 2 - 1)
            val omega = 2.0 * PI * bin / count
            val coefficient = 2.0 * cos(omega)
            var q1 = 0.0; var q2 = 0.0
            for (i in samples.indices) {
                val window = 0.5 - 0.5 * cos(2.0 * PI * i / (count - 1))
                val q0 = (samples[i] / 32768.0) * window + coefficient * q1 - q2
                q2 = q1; q1 = q0
            }
            val magnitude = sqrt((q1 * q1 + q2 * q2 - coefficient * q1 * q2).coerceAtLeast(0.0)) / count
            val db = 20.0 * log10(magnitude + 1e-6)
            ((db + 50.0) * 8.0 / 40.0).toInt().coerceIn(0, 8)
        }
    }

    override fun onDestroy() {
        stopAudio()
        super.onDestroy()
    }
}
