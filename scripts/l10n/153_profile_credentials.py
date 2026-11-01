#!/usr/bin/env python3
"""1.5.3 — credentials in the profile: new strings (7 languages) replacing the iCloud Keychain ones.
Run from the repo root: python3 scripts/l10n/153_profile_credentials.py"""
import json

CAT = "App/Localizable.xcstrings"
L = ["it", "es", "fr", "de", "zh-Hans", "ar"]

NEW = {
"This profile has no credentials: open it and use Edit to enter them.": [
 "Questo profilo non ha credenziali: aprilo e usa Modifica per inserirle.",
 "Este perfil no tiene credenciales: ábrelo y usa Editar para introducirlas.",
 "Ce profil n’a pas d’identifiants : ouvrez-le et utilisez Modifier pour les saisir.",
 "Dieses Profil hat keine Zugangsdaten: Öffne es und gib sie unter „Bearbeiten“ ein.",
 "此配置文件没有凭据：打开它并使用“编辑”输入凭据。",
 "لا يحتوي هذا الملف الشخصي على بيانات اعتماد: افتحه واستخدم «تعديل» لإدخالها."],
"This profile has no credentials: open Unraid Drive and use Edit to enter them.": [
 "Questo profilo non ha credenziali: apri Unraid Drive e usa Modifica per inserirle.",
 "Este perfil no tiene credenciales: abre Unraid Drive y usa Editar para introducirlas.",
 "Ce profil n’a pas d’identifiants : ouvrez Unraid Drive et utilisez Modifier pour les saisir.",
 "Dieses Profil hat keine Zugangsdaten: Öffne Unraid Drive und gib sie unter „Bearbeiten“ ein.",
 "此配置文件没有凭据：打开 Unraid Drive 并使用“编辑”输入凭据。",
 "لا يحتوي هذا الملف الشخصي على بيانات اعتماد: افتح Unraid Drive واستخدم «تعديل» لإدخالها."],
"Device registration waiting for the profile credentials from iCloud.": [
 "Registrazione del dispositivo in attesa delle credenziali del profilo da iCloud.",
 "Registro del dispositivo a la espera de las credenciales del perfil desde iCloud.",
 "Enregistrement de l’appareil en attente des identifiants du profil depuis iCloud.",
 "Geräteregistrierung wartet auf die Zugangsdaten des Profils aus iCloud.",
 "设备注册正在等待来自 iCloud 的配置文件凭据。",
 "تسجيل الجهاز بانتظار بيانات اعتماد الملف الشخصي من iCloud."],
"waiting for the profile credentials from iCloud…": [
 "in attesa delle credenziali del profilo da iCloud…",
 "esperando las credenciales del perfil desde iCloud…",
 "en attente des identifiants du profil depuis iCloud…",
 "wartet auf die Zugangsdaten des Profils aus iCloud …",
 "正在等待来自 iCloud 的配置文件凭据…",
 "بانتظار بيانات اعتماد الملف الشخصي من iCloud…"],
"This profile arrived from iCloud without credentials. Open it and use Edit to enter them, or update Unraid Drive on the device that saved it.": [
 "Questo profilo è arrivato da iCloud senza credenziali. Aprilo e usa Modifica per inserirle, oppure aggiorna Unraid Drive sul dispositivo che lo ha salvato.",
 "Este perfil llegó de iCloud sin credenciales. Ábrelo y usa Editar para introducirlas, o actualiza Unraid Drive en el dispositivo que lo guardó.",
 "Ce profil est arrivé d’iCloud sans identifiants. Ouvrez-le et utilisez Modifier pour les saisir, ou mettez à jour Unraid Drive sur l’appareil qui l’a enregistré.",
 "Dieses Profil kam ohne Zugangsdaten aus iCloud. Öffne es und gib sie unter „Bearbeiten“ ein, oder aktualisiere Unraid Drive auf dem Gerät, das es gespeichert hat.",
 "此配置文件来自 iCloud，但没有凭据。打开它并使用“编辑”输入凭据，或在保存它的设备上更新 Unraid Drive。",
 "وصل هذا الملف الشخصي من iCloud دون بيانات اعتماد. افتحه واستخدم «تعديل» لإدخالها، أو حدّث Unraid Drive على الجهاز الذي حفظه."],
"Create the key in Unraid under Settings › Management Access › API Keys. It is saved in the profile, synced with it through your iCloud, and sent only to your gateway.": [
 "Crea la chiave in Unraid in Settings › Management Access › API Keys. Viene salvata nel profilo, sincronizzata con lui tramite il tuo iCloud e inviata solo al tuo gateway.",
 "Crea la clave en Unraid en Settings › Management Access › API Keys. Se guarda en el perfil, se sincroniza con él a través de tu iCloud y solo se envía a tu gateway.",
 "Créez la clé dans Unraid sous Settings › Management Access › API Keys. Elle est enregistrée dans le profil, synchronisée avec lui via votre iCloud et envoyée uniquement à votre passerelle.",
 "Erstelle den Schlüssel in Unraid unter Settings › Management Access › API Keys. Er wird im Profil gespeichert, mit ihm über dein iCloud synchronisiert und nur an dein Gateway gesendet.",
 "在 Unraid 的 Settings › Management Access › API Keys 中创建密钥。密钥保存在配置文件中，随配置文件通过你的 iCloud 同步，只会发送给你的网关。",
 "أنشئ المفتاح في Unraid من Settings › Management Access › API Keys. يُحفظ في الملف الشخصي ويُزامَن معه عبر iCloud الخاص بك ويُرسل إلى بوابتك فقط."],
"The other devices keep their configuration; only the shared copy in iCloud (profiles and their credentials) is deleted.": [
 "Gli altri dispositivi conservano la loro configurazione; viene eliminata solo la copia condivisa in iCloud (profili e relative credenziali).",
 "Los demás dispositivos conservan su configuración; solo se elimina la copia compartida en iCloud (perfiles y sus credenciales).",
 "Les autres appareils conservent leur configuration ; seule la copie partagée dans iCloud (profils et leurs identifiants) est supprimée.",
 "Die anderen Geräte behalten ihre Konfiguration; nur die gemeinsame Kopie in iCloud (Profile und ihre Zugangsdaten) wird gelöscht.",
 "其他设备保留各自的配置，仅删除 iCloud 中的共享副本（配置文件及其凭据）。",
 "تحتفظ الأجهزة الأخرى بإعداداتها؛ تُحذف النسخة المشتركة في iCloud فقط (الملفات الشخصية وبيانات اعتمادها)."],
"When on, each profile — name, URL, connection mode, shares to show and its credentials (Unraid API key, Cloudflare service token, Unraid user and password) — is saved in your iCloud, so a new or reinstalled device gets it complete. The readable servers.json in iCloud Drive › Unraid Drive has everything but the credentials. After restoring or replacing a device, Restore brings the profiles back and registers this device on each gateway. Turning sync off keeps the copies in iCloud for the other devices. The demo server is never synced.": [
 "Se attiva, ogni profilo — nome, URL, modalità di connessione, condivisioni da mostrare e le sue credenziali (API key di Unraid, service token Cloudflare, utente e password Unraid) — viene salvato nel tuo iCloud, così un dispositivo nuovo o reinstallato lo ritrova completo. Il servers.json leggibile in iCloud Drive › Unraid Drive contiene tutto tranne le credenziali. Dopo il ripristino o la sostituzione di un dispositivo, Ripristina riporta i profili e registra questo dispositivo su ogni gateway. Disattivando la sincronizzazione le copie in iCloud restano per gli altri dispositivi. Il server demo non viene mai sincronizzato.",
 "Si está activada, cada perfil — nombre, URL, modo de conexión, recursos compartidos que mostrar y sus credenciales (clave API de Unraid, token de servicio de Cloudflare, usuario y contraseña de Unraid) — se guarda en tu iCloud, de modo que un dispositivo nuevo o reinstalado lo recibe completo. El servers.json legible en iCloud Drive › Unraid Drive lo contiene todo salvo las credenciales. Tras restaurar o sustituir un dispositivo, Restaurar recupera los perfiles y registra este dispositivo en cada gateway. Al desactivar la sincronización, las copias en iCloud se conservan para los demás dispositivos. El servidor de demostración nunca se sincroniza.",
 "Si elle est activée, chaque profil — nom, URL, mode de connexion, partages à afficher et ses identifiants (clé API Unraid, jeton de service Cloudflare, utilisateur et mot de passe Unraid) — est enregistré dans votre iCloud, si bien qu’un appareil neuf ou réinstallé le retrouve complet. Le servers.json lisible dans iCloud Drive › Unraid Drive contient tout sauf les identifiants. Après la restauration ou le remplacement d’un appareil, Restaurer ramène les profils et enregistre cet appareil sur chaque passerelle. Désactiver la synchronisation conserve les copies dans iCloud pour les autres appareils. Le serveur de démonstration n’est jamais synchronisé.",
 "Wenn aktiviert, wird jedes Profil — Name, URL, Verbindungsmodus, anzuzeigende Freigaben und seine Zugangsdaten (Unraid-API-Schlüssel, Cloudflare-Service-Token, Unraid-Benutzer und -Passwort) — in deinem iCloud gespeichert, sodass ein neues oder neu installiertes Gerät es vollständig erhält. Die lesbare servers.json in iCloud Drive › Unraid Drive enthält alles außer den Zugangsdaten. Nach dem Wiederherstellen oder Ersetzen eines Geräts holt „Wiederherstellen“ die Profile zurück und registriert dieses Gerät bei jedem Gateway. Beim Ausschalten bleiben die Kopien in iCloud für die anderen Geräte erhalten. Der Demo-Server wird nie synchronisiert.",
 "开启后，每个配置文件——名称、URL、连接方式、要显示的共享及其凭据（Unraid API 密钥、Cloudflare 服务令牌、Unraid 用户名和密码）——都会保存在你的 iCloud 中，新设备或重装后的设备即可获得完整配置。iCloud 云盘 › Unraid Drive 中可读的 servers.json 包含除凭据外的所有内容。恢复或更换设备后，“恢复”会带回配置文件并在每个网关上注册本设备。关闭同步会为其他设备保留 iCloud 中的副本。演示服务器从不同步。",
 "عند التفعيل، يُحفظ كل ملف شخصي — الاسم وعنوان URL ووضع الاتصال والمشاركات المعروضة وبيانات اعتماده (مفتاح Unraid API ورمز خدمة Cloudflare واسم مستخدم Unraid وكلمة مروره) — في iCloud الخاص بك، فيحصل عليه أي جهاز جديد أو مُعاد تثبيته كاملًا. يحتوي ملف servers.json المقروء في iCloud Drive › Unraid Drive على كل شيء عدا بيانات الاعتماد. بعد استعادة جهاز أو استبداله، يعيد «استعادة» الملفات الشخصية ويسجّل هذا الجهاز على كل بوابة. إيقاف المزامنة يُبقي النسخ في iCloud للأجهزة الأخرى. لا تتم مزامنة الخادم التجريبي أبدًا."],
"Another device (or this one, before a reinstall) saved %lld server(s) in iCloud. Restore them here: every profile arrives from iCloud complete with its API key, Cloudflare service token and Unraid password, and this device registers itself on each gateway again.": [
 "Un altro dispositivo (o questo, prima di una reinstallazione) ha salvato %lld server in iCloud. Ripristinali qui: ogni profilo arriva da iCloud completo di API key, service token Cloudflare e password Unraid, e questo dispositivo si registra di nuovo su ogni gateway.",
 "Otro dispositivo (o este, antes de una reinstalación) guardó %lld servidor(es) en iCloud. Restáuralos aquí: cada perfil llega de iCloud completo con su clave API, su token de servicio de Cloudflare y su contraseña de Unraid, y este dispositivo vuelve a registrarse en cada gateway.",
 "Un autre appareil (ou celui-ci, avant une réinstallation) a enregistré %lld serveur(s) dans iCloud. Restaurez-les ici : chaque profil arrive d’iCloud complet avec sa clé API, son jeton de service Cloudflare et son mot de passe Unraid, et cet appareil se réenregistre sur chaque passerelle.",
 "Ein anderes Gerät (oder dieses, vor einer Neuinstallation) hat %lld Server in iCloud gespeichert. Stelle sie hier wieder her: Jedes Profil kommt vollständig mit API-Schlüssel, Cloudflare-Service-Token und Unraid-Passwort aus iCloud, und dieses Gerät registriert sich erneut bei jedem Gateway.",
 "另一台设备（或本机在重装前）在 iCloud 中保存了 %lld 个服务器。在此恢复：每个配置文件都会从 iCloud 完整送达，包括其 API 密钥、Cloudflare 服务令牌和 Unraid 密码，本设备会重新在每个网关上注册。",
 "حفظ جهاز آخر (أو هذا الجهاز قبل إعادة التثبيت) %lld خادمًا في iCloud. استعدها هنا: يصل كل ملف شخصي من iCloud كاملًا بمفتاح API ورمز خدمة Cloudflare وكلمة مرور Unraid، ويعيد هذا الجهاز تسجيل نفسه على كل بوابة."],
"One backup shared by iPhone, iPad, Vision Pro, Mac and Apple TV: the profiles, credentials included, in your iCloud. You can turn it on later in Settings › iCloud.": [
 "Un unico backup condiviso da iPhone, iPad, Vision Pro, Mac e Apple TV: i profili, credenziali comprese, nel tuo iCloud. Puoi attivarlo più tardi in Impostazioni › iCloud.",
 "Una única copia compartida por iPhone, iPad, Vision Pro, Mac y Apple TV: los perfiles, credenciales incluidas, en tu iCloud. Puedes activarla más tarde en Ajustes › iCloud.",
 "Une seule sauvegarde partagée par iPhone, iPad, Vision Pro, Mac et Apple TV : les profils, identifiants compris, dans votre iCloud. Vous pourrez l’activer plus tard dans Réglages › iCloud.",
 "Ein Backup für iPhone, iPad, Vision Pro, Mac und Apple TV: die Profile samt Zugangsdaten in deinem iCloud. Du kannst es später unter Einstellungen › iCloud einschalten.",
 "iPhone、iPad、Vision Pro、Mac 和 Apple TV 共用一份备份：配置文件（含凭据）存于你的 iCloud。你可以稍后在“设置”›“iCloud”中开启。",
 "نسخة احتياطية واحدة مشتركة بين iPhone وiPad وVision Pro وMac وApple TV: الملفات الشخصية مع بيانات اعتمادها في iCloud الخاص بك. يمكنك تفعيلها لاحقًا من الإعدادات › iCloud."],
"A configuration saved by Unraid Drive on another device was found. Restoring turns sync on; the profiles arrive with their credentials and this device is registered on each gateway again.": [
 "È stata trovata una configurazione salvata da Unraid Drive su un altro dispositivo. Il ripristino attiva la sincronizzazione; i profili arrivano con le loro credenziali e questo dispositivo viene registrato di nuovo su ogni gateway.",
 "Se encontró una configuración guardada por Unraid Drive en otro dispositivo. Restaurar activa la sincronización; los perfiles llegan con sus credenciales y este dispositivo vuelve a registrarse en cada gateway.",
 "Une configuration enregistrée par Unraid Drive sur un autre appareil a été trouvée. La restauration active la synchronisation ; les profils arrivent avec leurs identifiants et cet appareil est réenregistré sur chaque passerelle.",
 "Eine von Unraid Drive auf einem anderen Gerät gespeicherte Konfiguration wurde gefunden. Die Wiederherstellung schaltet die Synchronisierung ein; die Profile kommen mit ihren Zugangsdaten und dieses Gerät wird bei jedem Gateway erneut registriert.",
 "找到了 Unraid Drive 在另一台设备上保存的配置。恢复会开启同步；配置文件连同凭据一起送达，本设备会重新在每个网关上注册。",
 "تم العثور على إعدادات حفظها Unraid Drive على جهاز آخر. الاستعادة تفعّل المزامنة؛ تصل الملفات الشخصية مع بيانات اعتمادها ويُعاد تسجيل هذا الجهاز على كل بوابة."],
"These profiles were saved by an older version of Unraid Drive, without their credentials. Update Unraid Drive on your iPhone, iPad or Mac and open it once, or go there to Settings › Pair an Apple TV and enter this code.": [
 "Questi profili sono stati salvati da una versione precedente di Unraid Drive, senza credenziali. Aggiorna Unraid Drive su iPhone, iPad o Mac e aprilo una volta, oppure vai lì in Impostazioni › Abbina una Apple TV e inserisci questo codice.",
 "Estos perfiles los guardó una versión anterior de Unraid Drive, sin sus credenciales. Actualiza Unraid Drive en tu iPhone, iPad o Mac y ábrelo una vez, o ve allí a Ajustes › Emparejar un Apple TV e introduce este código.",
 "Ces profils ont été enregistrés par une version antérieure d’Unraid Drive, sans leurs identifiants. Mettez à jour Unraid Drive sur votre iPhone, iPad ou Mac et ouvrez-le une fois, ou allez-y dans Réglages › Jumeler une Apple TV et saisissez ce code.",
 "Diese Profile wurden von einer älteren Version von Unraid Drive ohne Zugangsdaten gespeichert. Aktualisiere Unraid Drive auf iPhone, iPad oder Mac und öffne es einmal, oder gehe dort zu Einstellungen › Apple TV koppeln und gib diesen Code ein.",
 "这些配置文件由旧版 Unraid Drive 保存，不含凭据。请在 iPhone、iPad 或 Mac 上更新 Unraid Drive 并打开一次，或在那里进入“设置 › 配对 Apple TV”并输入此代码。",
 "حُفظت هذه الملفات الشخصية بإصدار أقدم من Unraid Drive دون بيانات اعتمادها. حدّث Unraid Drive على iPhone أو iPad أو Mac وافتحه مرة واحدة، أو انتقل هناك إلى الإعدادات › إقران Apple TV وأدخل هذا الرمز."],
"The profiles arrive complete with their credentials and this Apple TV registers itself on each gateway.": [
 "I profili arrivano completi di credenziali e questa Apple TV si registra su ogni gateway.",
 "Los perfiles llegan completos con sus credenciales y este Apple TV se registra en cada gateway.",
 "Les profils arrivent complets avec leurs identifiants et cette Apple TV s’enregistre sur chaque passerelle.",
 "Die Profile kommen vollständig mit ihren Zugangsdaten an und dieses Apple TV registriert sich bei jedem Gateway.",
 "配置文件连同凭据完整送达，此 Apple TV 会在每个网关上注册。",
 "تصل الملفات الشخصية كاملة مع بيانات اعتمادها ويسجّل هذا الـ Apple TV نفسه على كل بوابة."],
"Use the iCloud configuration": [
 "Usa la configurazione di iCloud", "Usar la configuración de iCloud", "Utiliser la configuration iCloud",
 "iCloud-Konfiguration verwenden", "使用 iCloud 配置", "استخدام إعدادات iCloud"],
"Added from iCloud: %@": [
 "Aggiunti da iCloud: %@", "Añadidos desde iCloud: %@", "Ajoutés depuis iCloud : %@",
 "Aus iCloud hinzugefügt: %@", "已从 iCloud 添加：%@", "أُضيفت من iCloud: %@"],
}

# Strings no longer in the code (iCloud Keychain era): removed from the catalog.
OLD_PREFIXES = [
 "A configuration saved by Unraid Drive on another device was found. Restoring turns sync on; the secrets",
 "Another device (or this one, before a reinstall) saved %lld server(s) in iCloud. Restore them here: the list",
 "Apple TV cannot read the credentials from iCloud Keychain",
 "Create the key in Unraid under Settings › Management Access › API Keys. It is stored in this device's Keychain",
 "One backup shared by iPhone, iPad, Vision Pro and Mac:",
 "The other devices keep their configuration; only the shared copy is deleted. Secrets in iCloud Keychain",
 "When on, the server list (names, URLs, connection mode",
 "Credentials missing from the Keychain",
 "Credentials not available yet. After an iCloud restore",
 "Device registration waiting for the credentials from iCloud Keychain",
 "The credentials have not arrived from iCloud Keychain yet",
 "waiting for the credentials from iCloud Keychain",
]

c = json.load(open(CAT))
s = c["strings"]
gone = [k for k in s if any(k.startswith(p) for p in OLD_PREFIXES)]
for k in gone: del s[k]
for k, vals in NEW.items():
    assert len(vals) == len(L), k
    s[k] = {"localizations": {l: {"stringUnit": {"state": "translated", "value": v}} for l, v in zip(L, vals)}}
c["strings"] = s  # keep the existing order (Xcode re-sorts on its next save)
json.dump(c, open(CAT, "w"), ensure_ascii=False, indent=2, separators=(",", ": "))
open(CAT, "a").write("\n")
print(f"removed {len(gone)}, added {len(NEW)}")
