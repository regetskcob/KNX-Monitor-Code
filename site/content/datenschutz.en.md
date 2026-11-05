---
title: "Privacy policy"
slug: "privacy"
description: "Privacy policy for the KNX Monitor app, the Home Assistant add-on and this website. In short: no tracking, installation data stays local, no account."
---

<p class="t-kennung hz-kennung">Last updated: October 2026</p>

> **In short:** We collect as little as possible: no account, no analytics, no tracking. Everything the app processes about your installation stays on your device or your KNX box unless you share it yourself. From version 1.9.1 the apps encrypt their files, and you can lock them and back them up yourself, each with the limits named below. Exceptions: in the store versions the app asks RevenueCat for your status when it starts, even if you have never bought anything; and on Android the QR scanner (Google ML Kit) sends technical diagnostic data to Google, see below.

## Controller

The controller within the meaning of the GDPR is the provider named in the [legal notice](https://www.regetskcob.de/legal/).

## The app (iPhone, iPad, Android, desktop)

### No data collection by us

The app does not send any data to us. It contains no advertising or tracking libraries and needs no account. We run no servers for the app.

### What is stored locally on your device

- Connection settings of your KNX interface (IP address, port)
- Data read from your ETS project or CSV export: group addresses, names, datapoint types, devices, rooms, links
- Captured telegrams, recordings, long-term history, check results (health, commissioning), your notes and comments with screenshots, photos of the distribution board
- App settings such as language, favourites and notification rules
- The app's most recent messages (up to 300 lines) in a file on the device, so that they survive a crash. They only leave the device if you share a diagnostics package
- With KNX Secure: the keys and tunnel passwords read from the keyring, so the app can reconnect and decrypt telegrams. They are kept in the system keychain (iOS/macOS Keychain, Android Keystore, Windows or Linux keyring), on this device only, unless you put them on your KNX box or in your own backup. A tunnel password entered by hand is not stored.

The password of a protected ETS project and the keyring password are only used to decrypt them during import and are not stored. You can delete all data in the app at any time or uninstall the app, which removes the data from the device.

### Encryption on the device (from version 1.9.1)

The apps on iPhone, iPad, Android, Mac, Windows and Linux encrypt their files, meaning installations, projects, history, recordings, comments and photos, with AES-256-GCM. The key is random and kept in the system keychain. This protects you if someone removes the storage or uses another user account. The limits:

- Without a usable keychain (Linux without libsecret) the files stay unencrypted.
- Settings such as gateway and user name are not encrypted. Whatever you export and share is no longer protected either.
- It cannot reliably stop programs and people working under your unlocked user account.
- On iPhone and iPad, files and the file key can be part of your own encrypted device backup, otherwise they would be lost when you change devices. The Secure keys stay on the device. On Android the app data is excluded from the system backup.

### App lock (from version 1.9.1, optional)

If you want, the app asks for Face ID, fingerprint, Windows Hello or the device code at start and after a time in the background that you choose, or for an app password of its own; on Linux there is only the password. The app does not see biometric data, your system does the check. We do not store the app password in plain text and do not know it; with the password the app creates a recovery key as PDF that you keep apart from the device. Without both, the only way is to delete the app's data on this device. The lock protects against someone holding the device, not against malware under your user account. The bus keeps running meanwhile, and alarms still fire.

### Backup (from version 1.9.1)

In the apps you save everything from this device into one file with its own password (at least 12 characters), on every plan and free of charge: installations, projects, keyrings, comments, recordings, history and settings. The file is only created when you trigger it and stays wherever you put it. We do not receive it and cannot reset the password. Not included are the app lock and the history on a box. The app declines very large amounts of data (over 256 MB) with a notice.

The format is open, so you can get at your data without our app too: a JSON file, key derived from the password with PBKDF2-HMAC-SHA256 (600,000 rounds), content encrypted with AES-256-GCM; decrypted, a ZIP with your files in plain text.

### Sync between your devices (optional, Plus and up)

If you turn on “Sync devices”, the app stores installations, projects, customer records, photos and watchers in encrypted form in your own storage: on iOS and macOS in the private app folder of your iCloud, on Android in the hidden app folder of your Google Drive. You don't need an account with us, and nothing goes to us. Encryption happens on the device with AES-256-GCM; the key comes from your sync code and is kept in the device keychain. Apple or Google only see unreadable blocks with random-looking names, their size and times, and that they belong to your account. On Android the app gets a permission through Google Play services that covers only this app folder. Not synced: history, keyrings, settings and all data of a business. The privacy policies of [Apple](https://www.apple.com/legal/privacy/) or [Google](https://policies.google.com/privacy) apply as well. When you turn it off you can delete the data in the cloud too; files on the device stay. If the sync code is lost, nobody can read the data in the cloud, not even us.

### Network access

The app only accesses your local network to communicate via KNXnet/IP with the KNX interface or IP router you choose and to discover interfaces on the network. iOS asks for the "Local Network" permission for this. The app itself does not communicate with the internet; the exceptions are purchases and checking your purchase status (see "In-app purchases") and the QR scanner on Android (see "Camera and QR code").

### Camera, QR code and photos

The camera only runs when you start it: to read a QR code (KNX box, handover, device labels) or to take a photo of the distribution board. The camera image of a scan is analysed on the device and is neither stored nor transmitted by the app. Photos you take or choose stay in the installation's folder on the device; the app removes location and device data from the image. They are not in the diagnostics or handover package, and only go into a service report if you select them there. They are included in your own backup.

The QR code of the KNX box contains the Wi-Fi credentials and the box password; with them the app joins the box's Wi-Fi and pairs. Afterwards only the device access and the box's Wi-Fi are stored in the system keychain, not the box password.

On **Android**, Google's ML Kit recognises the QR code. ML Kit works on the device but sends technical diagnostic data to Google (for example device model, operating system, app version, performance and error data and a per-installation identifier) so that Google can run and improve the service. The camera image is not part of it. This only happens when you use the scanner. The legal basis is our legitimate interest in a working QR scanner (Art. 6(1)(f) GDPR). Data may be transferred to the USA. Details: [ML Kit data disclosure](https://developers.google.com/ml-kit/android-data-disclosure) and [Google's privacy policy](https://policies.google.com/privacy). On iOS, iPadOS and macOS the system itself (Apple Vision) recognises the code; no data is transmitted.

### KNX box

When you connect the app to a KNX box, it also puts your ETS project, your own datapoint types and the keyring on the box and reads its history. The box is your own device on the local network. The data only leaves it if you set up a destination yourself (see “The Home Assistant add-on”); it does not go to us. It is unencrypted on the SD card or SSD, so whoever has the medium can read it. Access is protected by the box password and paired devices, the password is stored only as a hash on the box; inside the box's Wi-Fi the connection has no TLS. If the box has internet, it sets its clock that way.

### Notifications

The app creates notifications about alarms and watchers locally on the device; your system asks for permission first, and you can switch them off in the app and in the system. No server push service is used. Notifications can be visible on the lock screen; you control that in the system settings.

### Export and sharing

Reports (PDF), CSV and ETS exports are only created when you trigger them. Where they go is up to you, via your operating system's share sheet. Recently created exports, including diagnostics packages, stay in the app as a copy so that you can share them again; you can delete them there. A fault report to your electrician includes the names of addresses and devices along with the bus recording while the switch for them is on; screenshots on your comments only if you explicitly include them. It only goes to the recipient you choose.

### In-app purchases (Plus and Pro)

You buy Plus and Pro through the App Store or Google Play; payment and payment details stay with Apple or Google. So that the app knows what you bought, we use the service RevenueCat (RevenueCat, Inc., USA). For this the app sends a random identifier, the store's purchase receipts and technical details (e.g. app version, operating system, language, IP address) to RevenueCat. Your name, email address or data about your KNX installation are not included. This happens when you open the “Plus and Pro” page, buy or restore something, and every time the app starts, to check your plan, **even if you have never bought anything.** The legal basis is the performance of the purchase contract if you buy (Art. 6(1)(b) GDPR), otherwise our legitimate interest in recognising purchased plans reliably (Art. 6(1)(f) GDPR). Data may be transferred to the USA. Details: [RevenueCat privacy policy](https://www.revenuecat.com/privacy/). There are no purchases on Windows, on Linux and in the add-on, so none of this happens there.

### App Store and Google Play

Downloading the app is subject to the privacy policies of Apple or Google. If you have agreed to it in your device settings, Apple or Google provide us with aggregated, non-personal statistics (e.g. install counts, crash reports). We have no influence on this and cannot identify individuals from it.

## The Home Assistant add-on

The add-on runs on your own Home Assistant host. All data (project, Secure keys, telegrams, long-term history, recordings, settings) is kept in the add-on's data folder on that host, is unencrypted and part of your Home Assistant backups (protect them with a backup encryption key) and is removed when you uninstall the add-on. The apps' encryption, app lock and backup do not exist in the add-on; your Home Assistant takes care of that there. The add-on records the bus continuously while it is running. Access goes through the Home Assistant interface (ingress) and is authenticated by Home Assistant. For notifications and for reading the KNX integration, the add-on uses the Home Assistant API on the same host. It sends nothing to us. Data only goes to destinations you set up yourself, under those providers’ rules: notifications to ntfy, a webhook or Home Assistant, measurements to InfluxDB; Prometheus fetches them when you request it. The same applies to the box.

## This website

### Hosting on GitHub Pages

This website is served by GitHub Pages, a service of GitHub, Inc., 88 Colin P. Kelly Jr. Street, San Francisco, CA 94107, USA. When you visit the site, GitHub processes technically necessary data, in particular your IP address, date and time of the request and browser information, and stores it in server logs for security purposes. The legal basis is our legitimate interest in providing the website securely and reliably (Art. 6(1)(f) GDPR). Data may be transferred to the USA; GitHub is certified under the EU-US Data Privacy Framework. See [GitHub's privacy statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement) for details.

### No cookies, no tracking, no third-party content

This website sets no cookies, uses no analytics or tracking tools and embeds no third-party content. The fonts (Literata, Mona Sans, Monaspace and Material Symbols) are served by this website itself, not by Google Fonts or any other provider.

### Support via GitHub Issues

Support and feedback go through GitHub Issues. An issue is publicly visible and requires a GitHub account; processing there is governed by [GitHub's privacy statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement). We use what you write in an issue only to handle your request (Art. 6(1)(b) or (f) GDPR). Please don't post confidential data such as passwords or your ETS project there.

### Support by e-mail and diagnostics package

If you e-mail us, for example with a diagnostics package from the app, we process your e-mail address, your message and the content of the package only to handle your request (Art. 6(1)(b) or (f) GDPR). A diagnostics package contains the bus recording around the fault, group addresses, datapoint types and devices from your project, your description and comments, the app’s recent messages and technical facts, including the gateway’s name. It also records whether and when you hid the notice shown before writing to the bus. Names of group addresses and devices are included while the switch for them is on. Screenshots are only included if you explicitly turn that on; **they are not filtered,** everything visible on them reaches us. It does not contain the ETS project file, passwords, keyring and keys. Where recognisable, the app removes IP addresses, host names, MAC and serial numbers, email addresses and known names of project, installation and customer from the texts. **The package can still relate to people:** telegram values can show when someone is at home, and the filter does not recognise names you type or that appear in group addresses. You see exactly what is in it in the app before sending. We do not pass the package on, do not publish it and delete it once your request is done. E-mails to support@knx-monitor.de are received and stored through do.de, a service of Greenmark IT GmbH, Leinstraße 3, 31061 Alfeld (Leine), Germany.

## Instagram

We run the channel [@knxmonitor](https://www.instagram.com/knxmonitor/) on Instagram, a service of Meta Platforms Ireland Ltd. Our websites do not embed Instagram, they only link to it; Instagram's terms apply once you follow the link. Meta processes visitors' data under its own control and may also transfer it to the USA. Running such a channel can involve joint responsibility with the platform operator (CJEU, C-210/16, on Facebook fan pages). We see what Instagram shows us: public profiles, comments, messages and summarised statistics. We use this to talk to you and make our product known (Art. 6(1)(f) GDPR). Details: [Instagram privacy policy](https://privacycenter.instagram.com/policy/). You can also exercise your rights directly with Meta.

## Your rights

You have the right of access, rectification, erasure, restriction of processing, data portability and objection (Art. 15–21 GDPR), and the right to lodge a complaint with a data protection supervisory authority. Without a purchase the app sends no data to us, and we then hold no data about your use of the app. For any request, an email to the address in the [legal notice](https://www.regetskcob.de/legal/) is enough. The competent supervisory authority is the State Commissioner for Data Protection and Freedom of Information of North Rhine-Westphalia ([www.ldi.nrw.de](https://www.ldi.nrw.de)).
