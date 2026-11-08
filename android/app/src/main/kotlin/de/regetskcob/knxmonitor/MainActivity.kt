package de.regetskcob.knxmonitor

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.Uri
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSpecifier
import android.os.Build
import android.media.AudioManager
import android.media.RingtoneManager
import android.media.ToneGenerator
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PersistableBundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.view.WindowManager
import com.google.android.gms.auth.api.identity.AuthorizationRequest
import com.google.android.gms.auth.api.identity.ClearTokenRequest
import com.google.android.gms.auth.api.identity.Identity
import com.google.android.gms.common.api.Scope
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File

class MainActivity : FlutterFragmentActivity() {
    /// Geöffnete Dateien, bis die App sie abholt (`incomingFiles`).
    private val incomingFiles = mutableListOf<Uri>()
    private var nativeChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // Vor super: Sonst hielte Flutter die Datei-URI für eine Route.
        takeIncomingFile(
            intent,
            remember = savedInstanceState == null &&
                intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY == 0,
        )
        super.onCreate(savedInstanceState)
        // Android 12+: System-Splash ohne Ausblend-Animation entfernen, sobald
        // Flutter zeichnet. Flutters Startbildschirm zeigt dasselbe Bild an
        // derselben Stelle; Samsungs Animation legte sonst ein schwarzes Bild
        // mit weißen Icon-Ecken über ihn.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            splashScreen.setOnExitAnimationListener { it.remove() }
        }
    }

    /// Ohne MulticastLock verwerfen viele Geräte Multicast im WLAN (Akku sparen),
    /// KNXnet/IP-Routing käme dann nicht an. Gehalten nur, solange Routing läuft.
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun onNewIntent(intent: Intent) {
        if (takeIncomingFile(intent, remember = true)) {
            nativeChannel?.invokeMethod("incomingFilesChanged", null)
        }
        super.onNewIntent(intent)
    }

    /// Nimmt eine geöffnete Datei aus dem Intent. Die URI verschwindet in jedem
    /// Fall aus ihm; die Leserechte daran bleiben, solange die Activity lebt.
    private fun takeIncomingFile(intent: Intent?, remember: Boolean): Boolean {
        val uri = intent?.data ?: return false
        if (intent.action != Intent.ACTION_VIEW || uri.scheme !in setOf("content", "file")) return false
        intent.data = null
        if (remember) incomingFiles.add(uri)
        return remember
    }

    /// Liest die wartenden Dateien abseits des UI-Threads, jede höchstens [maxBytes] groß.
    private fun readIncomingFiles(maxBytes: Long, done: (List<Map<String, Any>>) -> Unit) {
        val uris = incomingFiles.toList()
        incomingFiles.clear()
        Thread {
            val files = uris.map { readIncomingFile(it, maxBytes) }
            runOnUiThread { done(files) }
        }.start()
    }

    private fun readIncomingFile(uri: Uri, maxBytes: Long): Map<String, Any> {
        try {
            if (!mayReadIncoming(uri)) return mapOf("problem" to "unreadable")
            val input = contentResolver.openInputStream(uri) ?: return mapOf("problem" to "unreadable")
            input.use {
                val out = ByteArrayOutputStream()
                val buffer = ByteArray(64 * 1024)
                while (true) {
                    val n = it.read(buffer)
                    if (n < 0) break
                    if (out.size() + n > maxBytes) return mapOf("problem" to "tooLarge")
                    out.write(buffer, 0, n)
                }
                return mapOf("bytes" to out.toByteArray())
            }
        } catch (e: Exception) {
            return mapOf("problem" to "unreadable")
        } catch (e: OutOfMemoryError) {
            return mapOf("problem" to "tooLarge")
        }
    }

    /// Jede App darf diese Activity mit einer URI starten. Eigene Dateien (eigener
    /// Datenordner, eigene Provider) dürfen so nicht in die App zurückkommen.
    private fun mayReadIncoming(uri: Uri): Boolean {
        if (uri.scheme == "file") {
            val file = File(uri.path ?: return false).canonicalFile
            val own = File(applicationInfo.dataDir).canonicalPath + File.separator
            return file.isFile && !file.path.startsWith(own) &&
                file.name.lowercase().let { it.endsWith(".knxhandover") || it.endsWith(".knxreport") }
        }
        val authority = uri.authority ?: return false
        return packageManager.resolveContentProvider(authority, 0)?.packageName != packageName
    }

    /// Wartet auf die Einwilligung für Google Drive.
    private var drivePending: MethodChannel.Result? = null

    /// Zugriffstoken nur für den versteckten App-Ordner. Ohne [interactive] nie ein Dialog:
    /// Der Abgleich im Hintergrund darf nicht plötzlich etwas fragen. Geräte ohne
    /// Play-Dienste landen im Fehlerzweig, der Abgleich meldet den Dienst als nicht verfügbar.
    private fun driveToken(interactive: Boolean, result: MethodChannel.Result) {
        val request = AuthorizationRequest.builder()
            .setRequestedScopes(listOf(Scope("https://www.googleapis.com/auth/drive.appdata")))
            .build()
        Identity.getAuthorizationClient(this).authorize(request)
            .addOnSuccessListener { auth ->
                val pending = auth.pendingIntent
                when {
                    !auth.hasResolution() -> result.success(auth.accessToken)
                    interactive && pending != null -> {
                        drivePending?.success(null)
                        drivePending = result
                        startIntentSenderForResult(pending.intentSender, DRIVE_CONSENT, null, 0, 0, 0)
                    }
                    else -> result.success(null)
                }
            }
            .addOnFailureListener { result.error("drive", it.message, null) }
    }

    @Deprecated("Die Einwilligung liefert nur einen IntentSender")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == DRIVE_CONSENT) {
            val result = drivePending
            drivePending = null
            val token = try {
                Identity.getAuthorizationClient(this).getAuthorizationResultFromIntent(data).accessToken
            } catch (e: Exception) {
                null
            }
            result?.success(token)
            return
        }
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "knx/cloud").setMethodCallHandler { call, result ->
            when (call.method) {
                "driveToken" -> driveToken(call.argument<Boolean>("interactive") ?: false, result)
                "driveClearToken" -> {
                    val request = ClearTokenRequest.builder().setToken(call.argument<String>("token") ?: "").build()
                    Identity.getAuthorizationClient(this).clearToken(request)
                        .addOnCompleteListener { result.success(null) }
                }
                else -> result.notImplemented()
            }
        }
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "knx/native")
        nativeChannel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "incomingFiles" -> readIncomingFiles(call.argument<Number>("maxBytes")?.toLong() ?: 0L) {
                    result.success(it)
                }
                "multicastLock" -> {
                    setMulticastLock(call.argument<Boolean>("enabled") == true)
                    result.success(null)
                }
                "joinWifi" -> joinWifi(call.argument<String>("ssid") ?: "", call.argument<String>("password") ?: "") {
                    result.success(it)
                }
                "leaveWifi" -> {
                    leaveWifi()
                    result.success(null)
                }
                "alertSound" -> {
                    alertSound()
                    result.success(null)
                }
                "alertSoundQuiet" -> {
                    alertSound(vibrate = false)
                    result.success(null)
                }
                "ackSound" -> {
                    ackSound(call.argument<String>("kind") ?: "write")
                    result.success(null)
                }
                "notifyPermission" -> requestNotifyPermission { result.success(it) }
                "notify" -> {
                    notify(
                        call.argument<String>("id") ?: "",
                        call.argument<String>("title") ?: "Busclear",
                        call.argument<String>("body") ?: "",
                        call.argument<Boolean>("silent") == true,
                    )
                    result.success(null)
                }
                "listenInBackground" -> {
                    if (call.argument<Boolean>("on") == true) {
                        ListenService.start(
                            applicationContext,
                            call.argument<String>("title") ?: "Busclear",
                            call.argument<String>("text") ?: "",
                        )
                    } else {
                        ListenService.stop(applicationContext)
                    }
                    result.success(null)
                }
                // App-Sperre: Im App-Umschalter nichts zeigen, keine Screenshots.
                "secureScreen" -> {
                    if (call.argument<Boolean>("enabled") == true) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(null)
                }
                "copySecret" -> {
                    copySecret(call.argument<String>("text") ?: "", call.argument<Number>("seconds")?.toLong() ?: 60L)
                    result.success(true)
                }
                "keepAwake" -> {
                    // Wächter scharf: Display bleibt an, solange der Monitor offen ist.
                    if (call.argument<Boolean>("on") == true) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    /// Wächter und Alarme als Mitteilung; gleiche [id] ersetzt die vorige
    /// Mitteilung derselben Adresse (wie auf iOS). Ohne Erlaubnis zeigt
    /// Android nichts an, das ist dann gewollt.
    private fun notify(id: String, title: String, body: String, silent: Boolean) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        // Wächter (silent): eigener Kanal ohne Ton und Vibration – Ton und
        // Vibration steuert die App selbst; Alarme mit dem Ton des Systems.
        val channel = if (silent) WATCH_CHANNEL else ALERT_CHANNEL
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                if (silent) {
                    NotificationChannel(WATCH_CHANNEL, channelName("Wächter", "Watcher"), NotificationManager.IMPORTANCE_HIGH)
                        .apply {
                            setSound(null, null)
                            enableVibration(false)
                        }
                } else {
                    NotificationChannel(ALERT_CHANNEL, channelName("Alarme", "Alarms"), NotificationManager.IMPORTANCE_HIGH)
                }
            )
        }
        val open = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        @Suppress("DEPRECATION")
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, channel)
        } else {
            Notification.Builder(this).setPriority(Notification.PRIORITY_HIGH)
        }
        // On the lock screen only that something happened: names and values of the
        // installation stay hidden until the device is unlocked.
        @Suppress("DEPRECATION")
        val publicBuilder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, channel)
        } else {
            Notification.Builder(this)
        }
        val publicVersion = publicBuilder
            .setSmallIcon(R.drawable.ic_stat_knx)
            .setContentTitle("Busclear")
            .setContentText(
                if (silent) channelName("Wächter ausgelöst", "Watcher triggered")
                else channelName("Alarm ausgelöst", "Alarm triggered")
            )
            .setContentIntent(open)
            .build()
        val notification = builder
            .setSmallIcon(R.drawable.ic_stat_knx)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setContentIntent(open)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setPublicVersion(publicVersion)
            .build()
        try {
            manager.notify(id.hashCode(), notification)
        } catch (_: SecurityException) {
            // Mitteilungen nicht erlaubt.
        }
    }

    /// Copied secret (token, password, code): marked as sensitive so keyboard
    /// suggestions and the clipboard preview (Android 13+) hide it, and removed
    /// after [seconds] if the clipboard still holds this clip. Compared by the
    /// clip's description, never by reading the content: reading would show the
    /// system's "pasted from clipboard" notice.
    private val clipboardHandler = Handler(Looper.getMainLooper())
    private var secretClipStamp: Long? = null
    private var secretClipDue = 0L

    private fun copySecret(text: String, seconds: Long) {
        val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val clip = ClipData.newPlainText(SECRET_LABEL, text)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            clip.description.extras = PersistableBundle().apply {
                putBoolean(
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) ClipDescription.EXTRA_IS_SENSITIVE
                    else "android.content.extra.IS_SENSITIVE",
                    true,
                )
            }
        }
        clipboard.setPrimaryClip(clip)
        secretClipStamp = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            clipboard.primaryClipDescription?.timestamp
        } else {
            null
        }
        secretClipDue = System.currentTimeMillis() + seconds * 1000
        clipboardHandler.removeCallbacksAndMessages(null)
        clipboardHandler.postDelayed({ clearSecretClip() }, seconds * 1000)
    }

    /// Removes the copied secret if it is still the current clip. Without input
    /// focus Android does not reveal the clip; then once the app has it again.
    private fun clearSecretClip() {
        if (secretClipDue == 0L || System.currentTimeMillis() < secretClipDue) return
        val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val description = clipboard.primaryClipDescription ?: return
        secretClipDue = 0L
        val same = description.label == SECRET_LABEL &&
            (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || description.timestamp == secretClipStamp)
        if (!same) return
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                clipboard.clearPrimaryClip()
            } else {
                clipboard.setPrimaryClip(ClipData.newPlainText("", ""))
            }
        } catch (_: SecurityException) {
            // Not allowed right now; Android 13+ clears it by itself later.
        }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) clearSecretClip()
    }

    /// Wächter: Mitteilungston des Systems und ein kurzes Vibrieren.
    private fun alertSound(vibrate: Boolean = true) {
        try {
            val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            RingtoneManager.getRingtone(applicationContext, uri)?.play()
        } catch (_: Exception) {
            // kein Ton verfügbar
        }
        // Zwischen zwei Mitteilungen nur der Ton (Wächter auf oft sendenden Adressen).
        if (!vibrate) return
        @Suppress("DEPRECATION")
        val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator?.vibrate(VibrationEffect.createOneShot(250, VibrationEffect.DEFAULT_AMPLITUDE))
        } else {
            @Suppress("DEPRECATION")
            vibrator?.vibrate(250)
        }
    }

    /// Android 13+: Ohne Erlaubnis für Mitteilungen läuft der Vordergrunddienst
    /// zwar, seine Mitteilung (mit der man zurück in die App kommt) bliebe aber
    /// unsichtbar. Einmal fragen; liefert, ob erlaubt.
    private var permissionDone: ((Boolean) -> Unit)? = null

    private fun requestNotifyPermission(done: (Boolean) -> Unit) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        ) {
            return done(true)
        }
        permissionDone?.invoke(false)
        permissionDone = done
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFY_REQUEST)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != NOTIFY_REQUEST) return
        permissionDone?.invoke(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
        permissionDone = null
    }

    /// Klangquittung: kurze Töne aus dem Tongenerator, ohne Dateien und ohne
    /// Verzögerung. Schreiben = Piep, Antwort = Doppelpiep, fremder Absender =
    /// tiefer Fehlerton mit kurzem Vibrieren.
    private var tones: ToneGenerator? = null

    private fun ackSound(kind: String) {
        val generator = tones ?: try {
            ToneGenerator(AudioManager.STREAM_MUSIC, 90).also { tones = it }
        } catch (_: RuntimeException) {
            return
        }
        when (kind) {
            "response" -> generator.startTone(ToneGenerator.TONE_PROP_BEEP2, 150)
            "foreign" -> {
                generator.startTone(ToneGenerator.TONE_PROP_NACK, 300)
                @Suppress("DEPRECATION")
                val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    vibrator?.vibrate(VibrationEffect.createOneShot(120, VibrationEffect.DEFAULT_AMPLITUDE))
                }
            }
            else -> generator.startTone(ToneGenerator.TONE_PROP_BEEP, 80)
        }
    }

    private fun setMulticastLock(enabled: Boolean) {
        if (enabled) {
            if (multicastLock?.isHeld == true) return
            val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            multicastLock = wifi.createMulticastLock("knx-routing").apply {
                setReferenceCounted(false)
                acquire()
            }
        } else {
            multicastLock?.takeIf { it.isHeld }?.release()
            multicastLock = null
        }
    }

    /// WLAN der Busclear Box: Android fragt einmal nach. Das Netz hat kein Internet,
    /// deshalb wird der Prozess daran gebunden, sonst liefe der Verkehr zur Box
    /// über das Mobilnetz.
    private var boxNetwork: ConnectivityManager.NetworkCallback? = null

    private fun joinWifi(ssid: String, password: String, done: (String) -> Unit) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return done("unsupported")
        leaveWifi()
        val connectivity = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val specifier = WifiNetworkSpecifier.Builder().setSsid(ssid).setWpa2Passphrase(password).build()
        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .setNetworkSpecifier(specifier)
            .build()
        var answered = false
        fun answer(value: String) = runOnUiThread { if (!answered) { answered = true; done(value) } }
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                connectivity.bindProcessToNetwork(network)
                answer("joined")
            }
            override fun onUnavailable() = answer("denied")
            override fun onLost(network: Network) {
                connectivity.bindProcessToNetwork(null)
            }
        }
        boxNetwork = callback
        connectivity.requestNetwork(request, callback, 60000)
    }

    private fun leaveWifi() {
        val callback = boxNetwork ?: return
        val connectivity = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        connectivity.bindProcessToNetwork(null)
        try {
            connectivity.unregisterNetworkCallback(callback)
        } catch (_: IllegalArgumentException) {
        }
        boxNetwork = null
    }

    companion object {
        private const val NOTIFY_REQUEST = 4203
        private const val ALERT_CHANNEL = "alerts"
        private const val WATCH_CHANNEL = "watch"
        private const val SECRET_LABEL = "Busclear secret"
    }

    override fun onDestroy() {
        ListenService.stop(applicationContext)
        tones?.release()
        tones = null
        leaveWifi()
        setMulticastLock(false)
        super.onDestroy()
    }
}

private const val DRIVE_CONSENT = 4711
