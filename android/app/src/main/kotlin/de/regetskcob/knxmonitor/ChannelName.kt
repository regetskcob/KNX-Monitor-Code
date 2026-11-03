package de.regetskcob.knxmonitor

import java.util.Locale

/// Name eines Mitteilungskanals in den Systemeinstellungen: Deutsch auf
/// deutschen Geräten, sonst Englisch (wie die App).
internal fun channelName(de: String, en: String): String =
    if (Locale.getDefault().language == "de") de else en
