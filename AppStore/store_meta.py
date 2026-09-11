# App Store listing texts per locale. Limits: subtitle 30, promotionalText 170, keywords 100, description 4000.
META = {
"it": dict(
 subtitle="Le share Unraid in File",
 promo="Le tue share Unraid nell’app File, ovunque.",
 keywords="unraid,nas,file,file provider,share,smb,cloudflare,docker,server,server casa",
 description="""Unraid Drive porta le share del tuo server Unraid nell’app File, accanto a iCloud Drive: su iPhone, iPad e Apple Vision Pro, a casa o fuori.

IMPORTANTE: l’app da sola non fa nulla. Sul server Unraid serve un servizio come il container gratuito e open source unraid-gateway (istruzioni nella wiki): è lui che espone le share all’app.

COME FUNZIONA
Installa sul tuo server Unraid il piccolo container open source unraid-gateway, crea una chiave API Unraid, pubblica il gateway con Cloudflare o con un qualsiasi reverse proxy e aggiungilo nell’app. Le tue share compaiono tra le Posizioni dell’app File: apri, salva, sposta, rinomina ed elimina file da qualsiasi app che usa il selettore di File.

FUNZIONI
• Integrazione nativa con l’app File (File Provider): download su richiesta, upload riprendibili per i file grandi, sincronizzazione in background.
• Accesso per utente: inserisci utente e password Unraid e vedi esattamente le share che Unraid ti concede, in sola lettura dove Unraid lo prevede.
• Modalità di connessione: HTTPS diretto oppure Cloudflare Access con service token.
• Dashboard: stato e uso dell’array, controllo parità, temperature dei dischi, share, container del gateway, notifiche, CPU e memoria.
• Test di connessione con diagnosi chiare, modifica del server senza perdere le posizioni in File.
• Sincronizzazione iCloud opzionale della configurazione per ripristini senza fatica.
• Tema Sistema/Chiaro/Scuro e interfaccia in 7 lingue.
• Server demo per provare tutto offline.
• Nessun account, nessuna analisi, nessun server di terzi: l’app parla solo con il tuo gateway.
• Look Unraid: accenti arancione Unraid, icona in sei colori con varianti chiara, scura e tinta.
• Aggiornamento in background: le posizioni in File restano sincronizzate anche dopo un riavvio del gateway.
• Motore di sincronizzazione come i grandi cloud (con unraid-gateway 0.5+): id stabili e journal delle modifiche, così rinomine, spostamenti ed eliminazioni fatti ovunque sul NAS arrivano nell’app File in pochi minuti senza scansioni.
• Azioni rapide dalla Home: Apri l’app File, Test di connessione, Aggiungi server.
• Comandi rapidi e Siri: salva gli appunti o un file in una share, scarica un file, elenca una cartella, aggiorna le posizioni, test di connessione.
• Notifiche: avviso quando il gateway non è raggiungibile (e quando torna) e quando un file non è stato caricato o scaricato; si gestiscono dalle impostazioni di sistema.
• Walkthrough a ogni aggiornamento con novità, ripristino della configurazione da iCloud e consenso alle notifiche.

SU MAC
La stessa app (acquisto universale) porta le share nella barra laterale del Finder come gli altri cloud drive, con un pannello nella barra dei menu: stato della sincronizzazione, attività (download, upload, rinomine, eliminazioni), notifiche Unraid, pausa/ripresa, file offline, elenco errori, apertura al login e modalità solo barra dei menu.

REQUISITI
Un server Unraid (7.2 o successivo) con il container gratuito unraid-gateway e un modo per raggiungerlo in HTTPS da fuori casa (consigliato Cloudflare). Guida passo passo completa nella wiki indicata sotto.

Unraid Drive è un progetto indipendente e non è affiliato a Lime Technology / Unraid."""),
"es": dict(
 subtitle="Recursos Unraid en Archivos",
 promo="Tus recursos compartidos de Unraid en la app Archivos, donde estés.",
 keywords="unraid,nas,archivos,file provider,recursos,smb,cloudflare,docker,servidor,servidor casero",
 description="""Unraid Drive lleva los recursos compartidos de tu servidor Unraid a la app Archivos, junto a iCloud Drive: en iPhone, iPad y Apple Vision Pro, en casa o fuera.

IMPORTANTE: la app por sí sola no hace nada. En el servidor Unraid hace falta un servicio como el contenedor gratuito y de código abierto unraid-gateway (instrucciones en la wiki): es el que expone los recursos compartidos a la app.

CÓMO FUNCIONA
Instala en tu servidor Unraid el pequeño contenedor de código abierto unraid-gateway, crea una clave API de Unraid, publica el gateway con Cloudflare o cualquier proxy inverso y añádelo en la app. Tus recursos aparecen en Ubicaciones de la app Archivos: abre, guarda, mueve, renombra y elimina archivos desde cualquier app que use el selector de Archivos.

FUNCIONES
• Integración nativa con la app Archivos (File Provider): descarga bajo demanda, subidas reanudables para archivos grandes, sincronización en segundo plano.
• Acceso por usuario: introduce tu usuario y contraseña de Unraid y ve exactamente los recursos que Unraid te concede, de solo lectura donde Unraid lo indique.
• Modos de conexión: HTTPS directo o Cloudflare Access con service token.
• Panel: estado y uso del array, comprobación de paridad, temperatura de discos, recursos compartidos, contenedor del gateway, notificaciones, CPU y memoria.
• Prueba de conexión con diagnósticos claros; edita el servidor sin perder tus ubicaciones en Archivos.
• Sincronización opcional de la configuración con iCloud para restaurar sin esfuerzo.
• Tema Sistema/Claro/Oscuro e interfaz en 7 idiomas.
• Servidor demo para probarlo todo sin conexión.
• Sin cuentas, sin analíticas, sin servidores de terceros: la app solo habla con tu gateway.
• Estilo Unraid: acentos en naranja Unraid, icono en seis colores con variantes clara, oscura y tintada.
• Actualización en segundo plano: las ubicaciones en Archivos siguen sincronizadas tras un reinicio del gateway.
• Motor de sincronización como los grandes servicios en la nube (con unraid-gateway 0.5+): ids estables y diario de cambios, así los renombrados, movimientos y borrados hechos en el NAS llegan a Archivos en minutos sin escanear los recursos.
• Acciones rápidas en la pantalla de inicio: Abrir Archivos, Probar conexión, Añadir servidor.
• Atajos y Siri: guarda el portapapeles o un archivo en un recurso compartido, descarga un archivo, lista una carpeta, actualiza las ubicaciones, prueba la conexión.
• Notificaciones: aviso cuando el gateway no responde (y cuando vuelve) y cuando un archivo no se pudo subir o descargar; se gestionan desde los ajustes del sistema.
• Recorrido en cada actualización con las novedades, restauración de la configuración desde iCloud y permiso de notificaciones.

EN EL MAC
La misma app (compra universal) lleva los recursos compartidos a la barra lateral del Finder como los demás cloud drives, con un panel en la barra de menús: estado de la sincronización, actividad (descargas, subidas, renombrados, eliminaciones), notificaciones de Unraid, pausa/reanudación, archivos sin conexión, lista de errores, apertura al iniciar sesión y modo solo barra de menús.

REQUISITOS
Un servidor Unraid (7.2 o posterior) con el contenedor gratuito unraid-gateway y una forma de alcanzarlo por HTTPS desde fuera de casa (se recomienda Cloudflare). Guía paso a paso completa en la wiki enlazada abajo.

Unraid Drive es un proyecto independiente y no está afiliado a Lime Technology / Unraid."""),
"fr": dict(
 subtitle="Partages Unraid dans Fichiers",
 promo="Vos partages Unraid dans l’app Fichiers, partout.",
 keywords="unraid,nas,fichiers,file provider,partages,smb,cloudflare,docker,serveur,serveur maison",
 description="""Unraid Drive place les partages de votre serveur Unraid dans l’app Fichiers, à côté d’iCloud Drive : sur iPhone, iPad et Apple Vision Pro, à la maison ou en déplacement.

IMPORTANT : l’app seule ne fait rien. Le serveur Unraid doit exécuter un service tel que le conteneur gratuit et open source unraid-gateway (instructions dans le wiki) : c’est lui qui expose les partages à l’app.

COMMENT ÇA MARCHE
Installez sur votre serveur Unraid le petit conteneur open source unraid-gateway, créez une clé API Unraid, publiez la passerelle avec Cloudflare ou n’importe quel reverse proxy, puis ajoutez-la dans l’app. Vos partages apparaissent dans les Emplacements de l’app Fichiers : ouvrez, enregistrez, déplacez, renommez et supprimez des fichiers depuis toute app utilisant le sélecteur Fichiers.

FONCTIONS
• Intégration native à l’app Fichiers (File Provider) : téléchargement à la demande, envois reprenables pour les gros fichiers, synchronisation en arrière-plan.
• Accès par utilisateur : saisissez votre utilisateur et mot de passe Unraid et voyez exactement les partages qu’Unraid vous accorde, en lecture seule là où Unraid le prévoit.
• Modes de connexion : HTTPS direct ou Cloudflare Access avec service token.
• Tableau de bord : état et remplissage de la grappe, contrôle de parité, températures des disques, partages, conteneur de la passerelle, notifications, CPU et mémoire.
• Test de connexion avec diagnostics clairs ; modifiez le serveur sans perdre vos emplacements Fichiers.
• Synchronisation iCloud facultative de la configuration pour des restaurations sans effort.
• Thème Système/Clair/Sombre et interface en 7 langues.
• Serveur démo pour tout essayer hors ligne.
• Aucun compte, aucune analyse, aucun serveur tiers : l’app ne parle qu’à votre passerelle.
• Style Unraid : accents orange Unraid, icône en six couleurs avec variantes claire, sombre et teintée.
• Actualisation en arrière-plan : les emplacements Fichiers restent synchronisés même après un redémarrage de la passerelle.
• Moteur de synchronisation à la manière des grands clouds (avec unraid-gateway 0.5+) : identifiants stables et journal des changements, les renommages, déplacements et suppressions faits sur le NAS arrivent dans Fichiers en quelques minutes sans parcourir les partages.
• Actions rapides sur l’écran d’accueil : Ouvrir Fichiers, Tester la connexion, Ajouter un serveur.
• Raccourcis et Siri : enregistrez le presse-papiers ou un fichier dans un partage, téléchargez un fichier, listez un dossier, actualisez les emplacements, testez la connexion.
• Notifications : alerte quand la passerelle est injoignable (et quand elle revient) et quand un fichier n’a pu être envoyé ou téléchargé ; gérées depuis les réglages système.
• Visite guidée à chaque mise à jour avec les nouveautés, restauration de la configuration depuis iCloud et autorisation des notifications.

SUR MAC
La même app (achat universel) place les partages dans la barre latérale du Finder comme les autres cloud drives, avec un panneau dans la barre des menus : état de la synchronisation, activité (téléchargements, envois, renommages, suppressions), notifications Unraid, pause/reprise, fichiers hors ligne, liste des erreurs, ouverture à la connexion et mode barre des menus seule.

PRÉREQUIS
Un serveur Unraid (7.2 ou plus récent) avec le conteneur gratuit unraid-gateway et un moyen de l’atteindre en HTTPS depuis l’extérieur (Cloudflare recommandé). Guide complet pas à pas dans le wiki ci-dessous.

Unraid Drive est un projet indépendant, non affilié à Lime Technology / Unraid."""),
"de": dict(
 subtitle="Unraid-Freigaben in Dateien",
 promo="Deine Unraid-Freigaben in der Dateien-App, überall.",
 keywords="unraid,nas,dateien,file provider,freigaben,smb,cloudflare,docker,server,heimserver",
 description="""Unraid Drive bringt die Freigaben deines Unraid-Servers in die Dateien-App, neben iCloud Drive: auf iPhone, iPad und Apple Vision Pro, zu Hause oder unterwegs.

WICHTIG: Die App allein tut nichts. Auf dem Unraid-Server muss ein Dienst wie der kostenlose Open-Source-Container unraid-gateway laufen (Anleitung im Wiki): Er stellt der App die Freigaben bereit.

SO FUNKTIONIERT ES
Installiere den kleinen Open-Source-Container unraid-gateway auf deinem Unraid-Server, erstelle einen Unraid-API-Schlüssel, veröffentliche das Gateway über Cloudflare oder einen beliebigen Reverse Proxy und füge es in der App hinzu. Deine Freigaben erscheinen unter Orte in der Dateien-App: Öffne, sichere, verschiebe, benenne um und lösche Dateien aus jeder App, die die Dateien-Auswahl nutzt.

FUNKTIONEN
• Native Integration in die Dateien-App (File Provider): Download bei Bedarf, fortsetzbare Uploads für große Dateien, Synchronisierung im Hintergrund.
• Zugriff pro Benutzer: Gib Unraid-Benutzername und -Passwort ein und sieh genau die Freigaben, die Unraid dir gewährt, schreibgeschützt wo Unraid es vorsieht.
• Verbindungsarten: direktes HTTPS oder Cloudflare Access mit Service Token.
• Dashboard: Array-Status und -Belegung, Paritätsprüfung, Festplattentemperaturen, Freigaben, Gateway-Container, Mitteilungen, CPU und Speicher.
• Verbindungstest mit klarer Diagnose; Server bearbeiten, ohne die Orte in Dateien zu verlieren.
• Optionale iCloud-Synchronisierung der Konfiguration für mühelose Wiederherstellungen.
• Design System/Hell/Dunkel und Oberfläche in 7 Sprachen.
• Demo-Server, um alles offline auszuprobieren.
• Keine Konten, keine Analysen, keine Drittserver: Die App spricht nur mit deinem Gateway.
• Unraid-Look: Akzente in Unraid-Orange, App-Symbol in sechs Farben mit heller, dunkler und getönter Variante.
• Hintergrundaktualisierung: Die Orte in Dateien bleiben auch nach einem Neustart des Gateways synchron.
• Synchronisierung wie bei den großen Cloud-Diensten (mit unraid-gateway 0.5+): stabile Objekt-IDs und ein Änderungsjournal, sodass Umbenennungen, Verschiebungen und Löschungen auf dem NAS binnen Minuten in der Dateien-App erscheinen, ohne die Freigaben zu durchsuchen.
• Schnellaktionen auf dem Home-Bildschirm: Dateien öffnen, Verbindung testen, Server hinzufügen.
• Kurzbefehle und Siri: Zwischenablage oder Datei in eine Freigabe sichern, Datei laden, Ordner auflisten, Orte aktualisieren, Verbindung testen.
• Mitteilungen: Hinweis, wenn das Gateway nicht erreichbar ist (und wenn es zurück ist) und wenn eine Datei nicht hoch- oder heruntergeladen werden konnte; verwaltet in den Systemeinstellungen.
• Einführung bei jedem Update mit den Neuerungen, Wiederherstellung der Konfiguration aus iCloud und Mitteilungsfreigabe.

AUF DEM MAC
Dieselbe App (Universalkauf) bringt die Freigaben wie die anderen Cloud-Laufwerke in die Finder-Seitenleiste, mit einem Menüleisten-Panel: Synchronisierungsstatus, Aktivität (Downloads, Uploads, Umbenennungen, Löschungen), Unraid-Mitteilungen, Pause/Fortsetzen, Offline-Dateien, Fehlerliste, Start beim Anmelden und Nur-Menüleiste-Modus.

VORAUSSETZUNGEN
Ein Unraid-Server (7.2 oder neuer) mit dem kostenlosen Container unraid-gateway und ein Weg, ihn von außen per HTTPS zu erreichen (Cloudflare empfohlen). Vollständige Schritt-für-Schritt-Anleitung im unten verlinkten Wiki.

Unraid Drive ist ein unabhängiges Projekt und nicht mit Lime Technology / Unraid verbunden."""),
"zh-Hans": dict(
 subtitle="Unraid 共享，尽在“文件”",
 promo="随时随地在“文件”应用中访问你的 Unraid 共享。",
 keywords="unraid,nas,文件,file provider,共享,smb,cloudflare,docker,服务器,家庭服务器",
 description="""Unraid Drive 把你 Unraid 服务器上的共享文件夹带入“文件”应用，与 iCloud 云盘并列：在 iPhone、iPad 和 Apple Vision Pro 上，在家或外出时都可使用。

重要提示：本应用本身无法独立工作。Unraid 服务器上需要运行类似 unraid-gateway 的服务（免费开源容器，说明见 wiki），由它向应用提供共享。

工作原理
在 Unraid 服务器上安装小巧的开源容器 unraid-gateway，创建一个 Unraid API 密钥，通过 Cloudflare 或任意反向代理发布网关，然后在应用中添加它。你的共享会出现在“文件”应用的“位置”中：可以从任何使用“文件”选择器的应用打开、存储、移动、重命名和删除文件。

功能
• 原生“文件”应用集成（File Provider）：按需下载、大文件断点续传、后台同步。
• 按用户访问：输入 Unraid 用户名和密码，只看到 Unraid 授权给你的共享，Unraid 设为只读的保持只读。
• 连接方式：直接 HTTPS，或使用 Service Token 的 Cloudflare Access。
• 仪表盘：阵列状态与用量、校验检查、硬盘温度、共享、网关容器、通知、CPU 和内存。
• 连接测试提供清晰诊断；编辑服务器不会丢失“文件”中的位置。
• 可选的 iCloud 配置同步，轻松恢复设备。
• 跟随系统/浅色/深色主题，界面支持 7 种语言。
• 演示服务器，可离线体验全部功能。
• 无账户、无分析、无第三方服务器：应用只与你的网关通信。
• Unraid 风格：Unraid 橙色强调色，六种颜色的应用图标，支持浅色、深色和着色变体。
• 后台刷新：网关重启后，“文件”中的位置仍保持同步。
• 与主流云盘一致的同步引擎（配合 unraid-gateway 0.5+）：稳定的项目 ID 和变更日志，在 NAS 上任意位置进行的重命名、移动和删除都会在几分钟内出现在“文件”应用中，无需扫描共享。
• 主屏幕快捷操作：打开“文件”、测试连接、添加服务器。
• 快捷指令与 Siri：将剪贴板或文件保存到共享、下载文件、列出文件夹、刷新位置、测试连接。
• 通知：网关不可达（及恢复）时和文件无法上传或下载时提醒；在系统设置中管理。
• 每次更新后的引导：新功能介绍、从 iCloud 恢复配置、通知授权。

在 Mac 上
同一个应用（通用购买）像其他云盘一样把共享放入“访达”边栏，并提供菜单栏面板：同步状态、活动（下载、上传、重命名、删除）、Unraid 通知、暂停/恢复、离线文件、错误列表、登录时启动以及仅菜单栏模式。

要求
一台运行免费容器 unraid-gateway 的 Unraid 服务器（7.2 或更新版本），以及一种可从家庭网络外通过 HTTPS 访问它的方式（推荐 Cloudflare）。完整的分步指南见下方 wiki 链接。

Unraid Drive 是独立项目，与 Lime Technology / Unraid 无关。"""),
"ar": dict(
 subtitle="مجلدات Unraid في الملفات",
 promo="مجلدات Unraid المشتركة في تطبيق الملفات، في أي مكان.",
 keywords="unraid,nas,ملفات,file provider,مجلدات,smb,cloudflare,docker,خادم,خادم منزلي",
 description="""يضع Unraid Drive المجلدات المشتركة لخادم Unraid الخاص بك في تطبيق الملفات بجوار iCloud Drive: على iPhone وiPad وApple Vision Pro، في المنزل أو أثناء التنقل.

مهم: التطبيق وحده لا يعمل. يحتاج خادم Unraid إلى خدمة مثل حاوية unraid-gateway المجانية مفتوحة المصدر (التعليمات في الويكي): فهي التي تعرض المشاركات للتطبيق.

كيف يعمل
ثبّت الحاوية الصغيرة مفتوحة المصدر unraid-gateway على خادم Unraid، وأنشئ مفتاح API لـ Unraid، وانشر البوابة عبر Cloudflare أو أي وكيل عكسي، ثم أضفها في التطبيق. تظهر مجلداتك المشتركة ضمن المواقع في تطبيق الملفات: افتح الملفات واحفظها وانقلها وأعد تسميتها واحذفها من أي تطبيق يستخدم منتقي الملفات.

الميزات
• تكامل أصيل مع تطبيق الملفات (File Provider): تنزيل عند الطلب، رفع قابل للاستئناف للملفات الكبيرة، مزامنة في الخلفية.
• وصول لكل مستخدم: أدخل اسم مستخدم Unraid وكلمة المرور لترى بالضبط المجلدات التي يمنحك Unraid إياها، للقراءة فقط حيث يحدد Unraid ذلك.
• أوضاع الاتصال: HTTPS مباشر أو Cloudflare Access برمز خدمة.
• لوحة معلومات: حالة المصفوفة واستخدامها، فحص التكافؤ، درجات حرارة الأقراص، المجلدات المشتركة، حاوية البوابة، الإشعارات، المعالج والذاكرة.
• اختبار اتصال بتشخيص واضح؛ عدّل الخادم دون فقدان مواقعك في الملفات.
• مزامنة اختيارية للإعدادات عبر iCloud لاستعادة الجهاز بسهولة.
• سمة النظام/فاتح/داكن وواجهة بسبع لغات.
• خادم تجريبي لتجربة كل شيء دون اتصال.
• لا حسابات ولا تحليلات ولا خوادم خارجية: يتواصل التطبيق مع بوابتك فقط.
• مظهر Unraid: لمسات برتقالية بلون Unraid، وأيقونة بستة ألوان مع متغيرات فاتحة وداكنة وملوّنة.
• تحديث في الخلفية: تبقى المواقع في تطبيق الملفات متزامنة حتى بعد إعادة تشغيل البوابة.
• محرك مزامنة مثل خدمات التخزين السحابي الكبيرة (مع unraid-gateway 0.5+): معرّفات ثابتة وسجل تغييرات، فتصل عمليات إعادة التسمية والنقل والحذف على NAS إلى تطبيق الملفات خلال دقائق دون فحص المجلدات.
• إجراءات سريعة من الشاشة الرئيسية: فتح تطبيق الملفات، اختبار الاتصال، إضافة خادم.
• الاختصارات وSiri: احفظ الحافظة أو ملفًا في مشاركة، نزّل ملفًا، اعرض مجلدًا، حدّث المواقع، اختبر الاتصال.
• الإشعارات: تنبيه عند تعذّر الوصول إلى البوابة (وعند عودتها) وعند فشل رفع ملف أو تنزيله؛ تُدار من إعدادات النظام.
• جولة تعريفية مع كل تحديث تعرض الجديد وتستعيد الإعدادات من iCloud وتطلب إذن الإشعارات.

على Mac
التطبيق نفسه (شراء موحّد) يضع المشاركات في الشريط الجانبي لـ Finder مثل بقية خدمات التخزين السحابي، مع لوحة في شريط القوائم: حالة المزامنة، النشاط (التنزيلات والرفع وإعادة التسمية والحذف)، إشعارات Unraid، الإيقاف المؤقت/الاستئناف، الملفات دون اتصال، قائمة الأخطاء، التشغيل عند تسجيل الدخول ووضع شريط القوائم فقط.

المتطلبات
خادم Unraid (‏7.2 أو أحدث) يشغّل الحاوية المجانية unraid-gateway، وطريقة للوصول إليه عبر HTTPS من خارج المنزل (يُنصح بـ Cloudflare). دليل كامل خطوة بخطوة في الويكي المرتبط أدناه.

Unraid Drive مشروع مستقل وغير تابع لـ Lime Technology / Unraid."""),
}
for l, m in META.items():
    assert len(m["subtitle"]) <= 30, (l, "subtitle", len(m["subtitle"]))
    assert len(m["promo"]) <= 170, (l, "promo", len(m["promo"]))
    assert len(m["keywords"]) <= 100, (l, "keywords", len(m["keywords"]))
    assert len(m["description"]) <= 4000, (l, "description", len(m["description"]))

# "What's New" for the 1.1 update (build 19). Limit 4000.
WHATS_NEW = {
"en-US": "• Shortcuts and Siri: save the clipboard or a file to a share, get a file, list a folder, refresh the locations, test the connection.\n• Notifications when a gateway stops answering (and when it is back) and when a file could not be uploaded or downloaded; managed from the system Settings.\n• Walkthrough at every update with what's new, iCloud restore of your configuration and the notification permission.\n• Texts, headers and controls follow the icon colour you choose.\n• Mac: Finder location, menu bar panel, Homebrew cask and DMG.",
"it": "• Comandi rapidi e Siri: salva gli appunti o un file in una share, prendi un file, elenca una cartella, aggiorna le posizioni, test di connessione.\n• Notifiche quando un gateway non risponde (e quando torna) e quando un file non è stato caricato o scaricato; si gestiscono dalle Impostazioni di sistema.\n• Walkthrough a ogni aggiornamento con le novità, ripristino della configurazione da iCloud e consenso alle notifiche.\n• Testi, intestazioni e controlli seguono il colore dell’icona scelto.\n• Mac: posizione nel Finder, pannello nella barra dei menu, cask Homebrew e DMG.",
"es-ES": "• Atajos y Siri: guarda el portapapeles o un archivo en un recurso compartido, obtén un archivo, lista una carpeta, actualiza las ubicaciones, prueba la conexión.\n• Notificaciones cuando un gateway deja de responder (y cuando vuelve) y cuando un archivo no se pudo subir o descargar; se gestionan desde los Ajustes del sistema.\n• Recorrido en cada actualización con las novedades, restauración de la configuración desde iCloud y permiso de notificaciones.\n• Textos, encabezados y controles siguen el color del icono elegido.\n• Mac: ubicación en el Finder, panel en la barra de menús, cask de Homebrew y DMG.",
"fr-FR": "• Raccourcis et Siri : enregistrez le presse-papiers ou un fichier dans un partage, récupérez un fichier, listez un dossier, actualisez les emplacements, testez la connexion.\n• Notifications quand une passerelle ne répond plus (et quand elle revient) et quand un fichier n’a pu être envoyé ou téléchargé ; gérées depuis les Réglages système.\n• Visite guidée à chaque mise à jour avec les nouveautés, restauration de la configuration depuis iCloud et autorisation des notifications.\n• Textes, en-têtes et contrôles suivent la couleur d’icône choisie.\n• Mac : emplacement dans le Finder, panneau dans la barre des menus, cask Homebrew et DMG.",
"de-DE": "• Kurzbefehle und Siri: Zwischenablage oder Datei in eine Freigabe sichern, Datei holen, Ordner auflisten, Orte aktualisieren, Verbindung testen.\n• Mitteilungen, wenn ein Gateway nicht mehr antwortet (und wenn es zurück ist) und wenn eine Datei nicht hoch- oder heruntergeladen werden konnte; verwaltet in den Systemeinstellungen.\n• Einführung bei jedem Update mit den Neuerungen, iCloud-Wiederherstellung der Konfiguration und Mitteilungsfreigabe.\n• Texte, Überschriften und Bedienelemente folgen der gewählten Symbolfarbe.\n• Mac: Finder-Ort, Menüleisten-Panel, Homebrew-Cask und DMG.",
"zh-Hans": "• 快捷指令与 Siri：将剪贴板或文件保存到共享、获取文件、列出文件夹、刷新位置、测试连接。\n• 网关停止响应（及恢复）时和文件无法上传或下载时的通知；在系统“设置”中管理。\n• 每次更新后的引导：新功能、从 iCloud 恢复配置、通知授权。\n• 文本、栏目标题和控件跟随所选图标颜色。\n• Mac：“访达”位置、菜单栏面板、Homebrew cask 和 DMG。",
"ar-SA": "• الاختصارات وSiri: احفظ الحافظة أو ملفًا في مشاركة، واحصل على ملف، واعرض مجلدًا، وحدّث المواقع، واختبر الاتصال.\n• إشعارات عند توقف بوابة عن الاستجابة (وعند عودتها) وعند فشل رفع ملف أو تنزيله؛ تُدار من إعدادات النظام.\n• جولة تعريفية مع كل تحديث تعرض الجديد وتستعيد الإعدادات من iCloud وتطلب إذن الإشعارات.\n• النصوص والعناوين وعناصر التحكم تتبع لون الأيقونة المختار.\n• Mac: موقع في Finder، لوحة شريط القوائم، cask لـ Homebrew وملف DMG.",
}
for l, t in WHATS_NEW.items():
    assert len(t) <= 4000, (l, "whatsNew", len(t))
