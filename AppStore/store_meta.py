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
• Motore di sincronizzazione come i grandi cloud (con unraid-gateway 0.5+): id stabili e journal delle modifiche, così rinomine, spostamenti ed eliminazioni fatti ovunque sul NAS arrivano nell’app File in pochi minuti senza scansioni.
• Comandi rapidi e Siri: salva gli appunti o un file in una share, scarica un file, elenca una cartella, aggiorna le posizioni, test di connessione.
• Notifiche: avviso quando il gateway non è raggiungibile (e quando torna) e quando un file non è stato caricato o scaricato; si gestiscono dalle impostazioni di sistema.
• Walkthrough a ogni aggiornamento con novità, ripristino della configurazione da iCloud e consenso alle notifiche.
• Scegli quali share mostrare: dopo la connessione e in ogni momento nei dettagli del server, spunta le share da vedere in File, nel Finder, nei Comandi rapidi e su Apple TV; la scelta viaggia con la configurazione iCloud.
• Explorer di file nell’app in stile File, su tutti i dispositivi: elenco o icone, ordinamento, ricerca, informazioni, nuova cartella, caricamento, rinomina, sposta, copia, condividi, elimina; Quick Look più lettore mpv (MKV, AVI, WebM, FLAC…), lettori EPUB, fumetti CBZ e archivi ZIP.

NOVITÀ NELLA 1.3
Explorer di file in stile File su tutti i dispositivi con lettore mpv, EPUB, CBZ e ZIP; su Apple TV visualizzatori testo/PDF, apertura in Infuse/VLC e mpv anche dietro Cloudflare Access; scelta delle share da mostrare.

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
• Motor de sincronización como los grandes servicios en la nube (con unraid-gateway 0.5+): ids estables y diario de cambios, así los renombrados, movimientos y borrados hechos en el NAS llegan a Archivos en minutos sin escanear los recursos.
• Atajos y Siri: guarda el portapapeles o un archivo en un recurso compartido, descarga un archivo, lista una carpeta, actualiza las ubicaciones, prueba la conexión.
• Notificaciones: aviso cuando el gateway no responde (y cuando vuelve) y cuando un archivo no se pudo subir o descargar; se gestionan desde los ajustes del sistema.
• Recorrido en cada actualización con las novedades, restauración de la configuración desde iCloud y permiso de notificaciones.
• Elige qué recursos compartidos mostrar: tras conectar y en cualquier momento en los detalles del servidor, marca los que quieres ver en Archivos, el Finder, Atajos y el Apple TV; la elección viaja con la configuración de iCloud.
• Explorador de archivos en la app al estilo de Archivos, en todos los dispositivos: lista o iconos, orden, búsqueda, información, nueva carpeta, subida, renombrar, mover, copiar, compartir, eliminar; Vista rápida más reproductor mpv (MKV, AVI, WebM, FLAC…), lectores de EPUB, cómics CBZ y archivos ZIP.

NOVEDADES DE LA 1.3
Explorador de archivos al estilo de Archivos en todos los dispositivos con reproductor mpv, EPUB, CBZ y ZIP; en Apple TV visores de texto/PDF, apertura en Infuse/VLC y mpv también tras Cloudflare Access; elección de recursos compartidos que mostrar.

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
• Synchronisation iCloud facultative de la configuration pour des restaurations sans effort.
• Serveur démo pour tout essayer hors ligne.
• Aucun compte, aucune analyse, aucun serveur tiers : l’app ne parle qu’à votre passerelle.
• Actualisation en arrière-plan : les emplacements Fichiers restent synchronisés même après un redémarrage de la passerelle.
• Moteur de synchronisation à la manière des grands clouds (avec unraid-gateway 0.5+) : identifiants stables et journal des changements, les renommages, déplacements et suppressions faits sur le NAS arrivent dans Fichiers en quelques minutes sans parcourir les partages.
• Raccourcis et Siri : enregistrez le presse-papiers ou un fichier dans un partage, téléchargez un fichier, listez un dossier, actualisez les emplacements, testez la connexion.
• Notifications : alerte quand la passerelle est injoignable (et quand elle revient) et quand un fichier n’a pu être envoyé ou téléchargé ; gérées depuis les réglages système.
• Visite guidée à chaque mise à jour avec les nouveautés, restauration de la configuration depuis iCloud et autorisation des notifications.
• Choisissez les partages à afficher : après la connexion et à tout moment dans les détails du serveur, cochez ceux à voir dans Fichiers, le Finder, Raccourcis et sur l’Apple TV ; le choix suit la configuration iCloud.
• Explorateur de fichiers dans l’app, façon Fichiers, sur tous les appareils : liste ou icônes, tri, recherche, infos, nouveau dossier, envoi, renommer, déplacer, copier, partager, supprimer ; Coup d’œil plus lecteur mpv (MKV, AVI, WebM, FLAC…), lecteurs EPUB, BD CBZ et archives ZIP.

NOUVEAUTÉS DE LA 1.3
Explorateur de fichiers façon Fichiers sur tous les appareils avec lecteur mpv, EPUB, CBZ et ZIP ; sur Apple TV, visionneuses texte/PDF, ouverture dans Infuse/VLC et mpv aussi derrière Cloudflare Access ; choix des partages à afficher.

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
• Synchronisierung wie bei den großen Cloud-Diensten (mit unraid-gateway 0.5+): stabile Objekt-IDs und ein Änderungsjournal, sodass Umbenennungen, Verschiebungen und Löschungen auf dem NAS binnen Minuten in der Dateien-App erscheinen, ohne die Freigaben zu durchsuchen.
• Kurzbefehle und Siri: Zwischenablage oder Datei in eine Freigabe sichern, Datei laden, Ordner auflisten, Orte aktualisieren, Verbindung testen.
• Mitteilungen: Hinweis, wenn das Gateway nicht erreichbar ist (und wenn es zurück ist) und wenn eine Datei nicht hoch- oder heruntergeladen werden konnte; verwaltet in den Systemeinstellungen.
• Einführung bei jedem Update mit den Neuerungen, Wiederherstellung der Konfiguration aus iCloud und Mitteilungsfreigabe.
• Wähle, welche Freigaben angezeigt werden: nach dem Verbinden und jederzeit in den Serverdetails hakst du die Freigaben für Dateien, Finder, Kurzbefehle und Apple TV ab; die Auswahl reist mit der iCloud-Konfiguration.
• Datei-Explorer in der App im Stil von „Dateien“, auf allen Geräten: Liste oder Symbole, Sortierung, Suche, Info, neuer Ordner, Hochladen, Umbenennen, Bewegen, Kopieren, Teilen, Löschen; Übersicht plus mpv-Player (MKV, AVI, WebM, FLAC …), Reader für EPUB, CBZ-Comics und ZIP-Archive.

NEU IN 1.3
Datei-Explorer im Stil von „Dateien“ auf allen Geräten mit mpv-Player, EPUB, CBZ und ZIP; auf Apple TV Text-/PDF-Anzeige, Öffnen in Infuse/VLC und mpv auch hinter Cloudflare Access; Auswahl der angezeigten Freigaben.

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
• 与主流云盘一致的同步引擎（配合 unraid-gateway 0.5+）：稳定的项目 ID 和变更日志，在 NAS 上任意位置进行的重命名、移动和删除都会在几分钟内出现在“文件”应用中，无需扫描共享。
• 快捷指令与 Siri：将剪贴板或文件保存到共享、下载文件、列出文件夹、刷新位置、测试连接。
• 通知：网关不可达（及恢复）时和文件无法上传或下载时提醒；在系统设置中管理。
• 每次更新后的引导：新功能介绍、从 iCloud 恢复配置、通知授权。
• 选择要显示的共享：连接后以及随时在服务器详情中勾选要在“文件”、“访达”、快捷指令和 Apple TV 中看到的共享；选择随 iCloud 配置同步。
• 应用内“文件”风格的文件浏览器，支持所有设备：列表或图标、排序、搜索、简介、新建文件夹、上传、重命名、移动、拷贝、共享、删除；快速查看加 mpv 播放器（MKV、AVI、WebM、FLAC…），以及 EPUB、CBZ 漫画和 ZIP 阅读器。

1.3 版新功能
所有设备上的“文件”风格文件浏览器，带 mpv 播放器及 EPUB、CBZ、ZIP 阅读器；Apple TV 上还有文本/PDF 查看器、在 Infuse/VLC 中打开，以及 Cloudflare Access 后的 mpv；可选择要显示的共享。

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
• الاختصارات وSiri: احفظ الحافظة أو ملفًا في مشاركة، نزّل ملفًا، اعرض مجلدًا، حدّث المواقع، اختبر الاتصال.
• الإشعارات: تنبيه عند تعذّر الوصول إلى البوابة (وعند عودتها) وعند فشل رفع ملف أو تنزيله؛ تُدار من إعدادات النظام.
• جولة تعريفية مع كل تحديث تعرض الجديد وتستعيد الإعدادات من iCloud وتطلب إذن الإشعارات.
• اختر المشاركات التي تريد عرضها: بعد الاتصال وفي أي وقت من تفاصيل الخادم، حدّد المشاركات التي تظهر في الملفات وFinder والاختصارات وApple TV؛ ينتقل الاختيار مع إعدادات iCloud.
• مستعرض ملفات داخل التطبيق بأسلوب «الملفات» على كل الأجهزة: قائمة أو أيقونات، ترتيب، بحث، معلومات، مجلد جديد، رفع، إعادة تسمية، نقل، نسخ، مشاركة، حذف؛ نظرة سريعة مع مشغّل mpv (MKV وAVI وWebM وFLAC…) وقارئات EPUB وقصص CBZ وأرشيفات ZIP.

الجديد في 1.3
مستعرض ملفات بأسلوب «الملفات» على كل الأجهزة مع مشغّل mpv وقارئات EPUB وCBZ وZIP؛ على Apple TV عارضات نص/PDF وفتح في Infuse/VLC وmpv خلف Cloudflare Access أيضًا؛ اختيار المشاركات المعروضة.

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

# "What's New" for the 1.3 update (build 35). Limit 4000.
WHATS_NEW = {
'en-US': '• Transient network errors (connection refused, a dead VPN interface, a Wi-Fi hand-over) are retried before the Files app / Finder sees them.\n• The Files / Finder location is checked and rebuilt automatically on the first launch and after every update — no more manual Refresh or Rebuild.\n• Multi-selection in the explorer on every device: Copy, Cut, Move, Copy to, Download, Share and Delete on the whole selection (Apple TV: Copy, Cut, Delete).\n• Download files and folders to a place you choose.\n• Mac: Start without a window (menu bar only, or menu bar and Dock).\n• Move… and Copy to… now confirm the destination with a Move here / Copy here button; one Open entry for every file.\n• Mac: fixed a crash when playing MKV, AVI and the other mpv formats (the notarized app was killed as soon as the video loaded).\n• Restore first: a new or reinstalled device finds the configuration saved in iCloud, restores it and registers itself on the gateways again — same device id after a reinstall, no duplicates.\n• Apple TV: shows what is waiting in iCloud and receives every server with one pairing code; Rename and New folder in the explorer.\n• Video that does not start: the real reason (Cloudflare Access login, revoked device, gateway error) instead of “unrecognized file format”; streams keep playing after the session token expires.\n• A Files-style explorer inside the app on iPhone, iPad, Vision Pro and Mac: list or icons, sort, search, Info, new folder, upload, rename, move, copy, share, delete — through the gateway with your Unraid permissions.\n• Opens far more files: Quick Look plus a built-in mpv player (MKV, AVI, WebM, FLAC…), and readers for EPUB books, CBZ comics and ZIP archives.\n• Apple TV: file explorer with text/NFO/CSV and PDF viewers, Open in Infuse/VLC, mpv working behind Cloudflare Access.\n• Choose which shares to show, synced with iCloud.',
'it': '• Gli errori di rete transitori (connessione rifiutata, un’interfaccia VPN morta, un passaggio di Wi-Fi) vengono ritentati prima che File / Finder li vedano.\n• La posizione in File / Finder viene verificata e ricostruita automaticamente al primo avvio e dopo ogni aggiornamento: niente più Aggiorna o Ricostruisci manuali.\n• Multiselezione nell’explorer su tutti i dispositivi: Copia, Taglia, Sposta, Copia in, Scarica, Condividi ed Elimina sull’intera selezione (Apple TV: Copia, Taglia, Elimina).\n• Scarica file e cartelle dove vuoi.\n• Mac: Avvia senza finestra (solo barra dei menu, oppure barra dei menu e Dock).\n• Sposta… e Copia in… ora confermano la destinazione con il pulsante Sposta qui / Copia qui; una sola voce Apri per ogni file.\n• Mac: risolto il crash all’avvio di MKV, AVI e degli altri formati mpv (l’app notarizzata veniva chiusa appena il video si caricava).\n• Prima il ripristino: un dispositivo nuovo o reinstallato trova la configurazione salvata in iCloud, la ripristina e si registra di nuovo sui gateway — stesso id dopo una reinstallazione, niente doppioni.\n• Apple TV: mostra cosa attende in iCloud e riceve tutti i server con un solo codice di abbinamento; Rinomina e Nuova cartella nell’explorer.\n• Video che non parte: il motivo reale (login Cloudflare Access, dispositivo revocato, errore del gateway) invece di “unrecognized file format”; la riproduzione continua anche dopo la scadenza del token di sessione.\n• Explorer di file in stile File dentro l’app su iPhone, iPad, Vision Pro e Mac: elenco o icone, ordinamento, ricerca, Info, nuova cartella, caricamento, rinomina, sposta, copia, condividi, elimina — tramite il gateway con i tuoi permessi Unraid.\n• Apre molti più file: Quick Look più il lettore mpv integrato (MKV, AVI, WebM, FLAC…), e lettori per libri EPUB, fumetti CBZ e archivi ZIP.\n• Apple TV: explorer con visualizzatori testo/NFO/CSV e PDF, Apri in Infuse/VLC, mpv funzionante anche dietro Cloudflare Access.\n• Scegli quali share mostrare, sincronizzato con iCloud.',
'es-ES': '• Los errores de red transitorios (conexión rechazada, una interfaz VPN muerta, un cambio de Wi-Fi) se reintentan antes de que Archivos / Finder los vean.\n• La ubicación en Archivos / Finder se comprueba y reconstruye automáticamente en el primer inicio y tras cada actualización: se acabaron Actualizar y Reconstruir manuales.\n• Selección múltiple en el explorador en todos los dispositivos: Copiar, Cortar, Mover, Copiar en, Descargar, Compartir y Eliminar sobre toda la selección (Apple TV: Copiar, Cortar, Eliminar).\n• Descarga archivos y carpetas donde quieras.\n• Mac: Iniciar sin ventana (solo barra de menús, o barra de menús y Dock).\n• Mover… y Copiar en… ahora confirman el destino con el botón Mover aquí / Copiar aquí; una sola opción Abrir para cada archivo.\n• Mac: corregido el cierre inesperado al reproducir MKV, AVI y los demás formatos mpv (la app notarizada se cerraba en cuanto cargaba el vídeo).\n• Primero la restauración: un dispositivo nuevo o reinstalado encuentra la configuración guardada en iCloud, la restaura y vuelve a registrarse en los gateways — mismo id tras una reinstalación, sin duplicados.\n• Apple TV: muestra lo que espera en iCloud y recibe todos los servidores con un solo código de emparejamiento; Renombrar y Nueva carpeta en el explorador.\n• Vídeo que no arranca: el motivo real (inicio de sesión de Cloudflare Access, dispositivo revocado, error del gateway) en lugar de “unrecognized file format”; la reproducción sigue tras caducar el token de sesión.\n• Explorador de archivos al estilo de Archivos dentro de la app en iPhone, iPad, Vision Pro y Mac: lista o iconos, orden, búsqueda, Información, nueva carpeta, subida, renombrar, mover, copiar, compartir, eliminar — a través del gateway con tus permisos de Unraid.\n• Abre muchos más archivos: Vista rápida más el reproductor mpv integrado (MKV, AVI, WebM, FLAC…), y lectores de libros EPUB, cómics CBZ y archivos ZIP.\n• Apple TV: explorador con visores de texto/NFO/CSV y PDF, Abrir en Infuse/VLC, mpv funcionando también tras Cloudflare Access.\n• Elige qué recursos compartidos mostrar, sincronizado con iCloud.',
'fr-FR': '• Les erreurs réseau passagères (connexion refusée, interface VPN morte, bascule Wi-Fi) sont retentées avant que Fichiers / le Finder ne les voient.\n• L’emplacement dans Fichiers / le Finder est vérifié et reconstruit automatiquement au premier lancement et après chaque mise à jour : plus d’Actualiser ni de Reconstruire manuels.\n• Sélection multiple dans l’explorateur sur tous les appareils : Copier, Couper, Déplacer, Copier vers, Télécharger, Partager et Supprimer sur toute la sélection (Apple TV : Copier, Couper, Supprimer).\n• Téléchargez fichiers et dossiers où vous voulez.\n• Mac : Démarrer sans fenêtre (barre des menus seule, ou barre des menus et Dock).\n• Déplacer… et Copier vers… confirment désormais la destination avec le bouton Déplacer ici / Copier ici ; une seule entrée Ouvrir pour chaque fichier.\n• Mac : correction du plantage à la lecture des MKV, AVI et autres formats mpv (l’app notarisée se fermait dès le chargement de la vidéo).\n• La restauration d’abord : un appareil neuf ou réinstallé retrouve la configuration enregistrée dans iCloud, la restaure et se réenregistre sur les passerelles — même identifiant après une réinstallation, pas de doublons.\n• Apple TV : affiche ce qui attend dans iCloud et reçoit tous les serveurs avec un seul code de jumelage ; Renommer et Nouveau dossier dans l’explorateur.\n• Vidéo qui ne démarre pas : la vraie raison (connexion Cloudflare Access, appareil révoqué, erreur de passerelle) au lieu de « unrecognized file format » ; la lecture continue après l’expiration du jeton de session.\n• Explorateur de fichiers façon Fichiers dans l’app sur iPhone, iPad, Vision Pro et Mac : liste ou icônes, tri, recherche, Infos, nouveau dossier, envoi, renommer, déplacer, copier, partager, supprimer — via la passerelle avec vos permissions Unraid.\n• Ouvre bien plus de fichiers : Coup d’œil plus le lecteur mpv intégré (MKV, AVI, WebM, FLAC…), et des lecteurs pour livres EPUB, BD CBZ et archives ZIP.\n• Apple TV : explorateur avec visionneuses texte/NFO/CSV et PDF, Ouvrir dans Infuse/VLC, mpv fonctionnant aussi derrière Cloudflare Access.\n• Choix des partages à afficher, synchronisé avec iCloud.',
'de-DE': '• Vorübergehende Netzwerkfehler (Verbindung abgelehnt, tote VPN-Schnittstelle, WLAN-Wechsel) werden wiederholt, bevor Dateien / Finder sie sehen.\n• Der Speicherort in Dateien / Finder wird beim ersten Start und nach jedem Update automatisch geprüft und neu aufgebaut – kein manuelles Aktualisieren oder Neu aufbauen mehr.\n• Mehrfachauswahl im Explorer auf jedem Gerät: Kopieren, Ausschneiden, Bewegen, Kopieren nach, Laden, Teilen und Löschen für die ganze Auswahl (Apple TV: Kopieren, Ausschneiden, Löschen).\n• Dateien und Ordner an einen Ort deiner Wahl laden.\n• Mac: Ohne Fenster starten (nur Menüleiste, oder Menüleiste und Dock).\n• Bewegen… und Kopieren nach… bestätigen das Ziel jetzt mit der Taste Hierher bewegen / Hierher kopieren; ein einziger Eintrag Öffnen für jede Datei.\n• Mac: Absturz beim Abspielen von MKV, AVI und den anderen mpv-Formaten behoben (die notarisierte App wurde beim Laden des Videos beendet).\n• Wiederherstellen zuerst: ein neues oder neu installiertes Gerät findet die in iCloud gespeicherte Konfiguration, stellt sie wieder her und registriert sich erneut bei den Gateways — dieselbe Geräte-ID nach einer Neuinstallation, keine Duplikate.\n• Apple TV: zeigt, was in iCloud wartet, und erhält alle Server mit einem Kopplungscode; Umbenennen und Neuer Ordner im Explorer.\n• Video startet nicht: der wahre Grund (Cloudflare-Access-Anmeldung, widerrufenes Gerät, Gateway-Fehler) statt „unrecognized file format“; die Wiedergabe läuft nach Ablauf des Sitzungstokens weiter.\n• Datei-Explorer im Stil von „Dateien“ in der App auf iPhone, iPad, Vision Pro und Mac: Liste oder Symbole, Sortierung, Suche, Info, neuer Ordner, Hochladen, Umbenennen, Bewegen, Kopieren, Teilen, Löschen – über das Gateway mit deinen Unraid-Berechtigungen.\n• Öffnet viel mehr Dateien: Übersicht plus integrierter mpv-Player (MKV, AVI, WebM, FLAC …) sowie Reader für EPUB-Bücher, CBZ-Comics und ZIP-Archive.\n• Apple TV: Explorer mit Text-/NFO-/CSV- und PDF-Anzeige, Öffnen in Infuse/VLC, mpv auch hinter Cloudflare Access.\n• Auswahl der angezeigten Freigaben, mit iCloud synchronisiert.',
'zh-Hans': '• 短暂的网络错误（连接被拒绝、失效的 VPN 接口、Wi-Fi 切换）会在“文件”/访达看到之前自动重试。\n• “文件”/访达中的位置会在首次启动和每次更新后自动检查并重建，不再需要手动刷新或重建。\n• 所有设备的文件浏览器支持多选：对整个选择进行拷贝、剪切、移动、拷贝到、下载、共享和删除（Apple TV：拷贝、剪切、删除）。\n• 将文件和文件夹下载到你选择的位置。\n• Mac：启动时不打开窗口（仅菜单栏，或菜单栏和 Dock）。\n• “移动到”和“拷贝到”现在通过“移动到这里 / 拷贝到这里”按钮确认目标位置；每个文件只有一个“打开”。\n• Mac：修复播放 MKV、AVI 及其他 mpv 格式时的崩溃（经公证的应用在视频加载时即被终止）。\n• 先恢复：新设备或重装设备会找到保存在 iCloud 中的配置，恢复它并重新在网关上注册——重装后设备 ID 不变，不再重复。\n• Apple TV：显示 iCloud 中待恢复的内容，并用一个配对码接收所有服务器；浏览器中新增重命名和新建文件夹。\n• 视频无法播放：显示真正的原因（Cloudflare Access 登录、设备已吊销、网关错误），而不是“unrecognized file format”；会话令牌过期后播放仍继续。\n• iPhone、iPad、Vision Pro 和 Mac 上应用内的“文件”风格浏览器：列表或图标、排序、搜索、简介、新建文件夹、上传、重命名、移动、拷贝、共享、删除——通过网关并遵循你的 Unraid 权限。\n• 可打开更多文件：快速查看加内置 mpv 播放器（MKV、AVI、WebM、FLAC…），以及 EPUB 电子书、CBZ 漫画和 ZIP 压缩包阅读器。\n• Apple TV：带文本/NFO/CSV 和 PDF 查看器的浏览器、在 Infuse/VLC 中打开、mpv 在 Cloudflare Access 后也可用。\n• 选择要显示的共享，与 iCloud 同步。',
'ar-SA': '• تُعاد محاولة أخطاء الشبكة العابرة (رفض الاتصال، واجهة VPN معطّلة، تبديل Wi‑Fi) قبل أن تراها الملفات / Finder.\n• يتم فحص موقع الملفات / Finder وإعادة بنائه تلقائيًا عند التشغيل الأول وبعد كل تحديث — لا حاجة بعد الآن للتحديث أو إعادة البناء يدويًا.\n• تحديد متعدد في المستكشف على كل الأجهزة: نسخ وقص ونقل ونسخ إلى وتنزيل ومشاركة وحذف للتحديد كله (Apple TV: نسخ وقص وحذف).\n• نزّل الملفات والمجلدات إلى المكان الذي تختاره.\n• Mac: البدء بدون نافذة (شريط القوائم فقط، أو شريط القوائم وDock).\n• «نقل إلى» و«نسخ إلى» يؤكدان الآن الوجهة بزر «نقل إلى هنا / نسخ إلى هنا»؛ خيار «فتح» واحد لكل ملف.\n• Mac: إصلاح الانهيار عند تشغيل MKV وAVI وسائر صيغ mpv (كان التطبيق الموثّق يُغلق فور تحميل الفيديو).\n• الاستعادة أولاً: يجد الجهاز الجديد أو المعاد تثبيته الإعدادات المحفوظة في iCloud ويستعيدها ويعيد تسجيل نفسه على البوابات — نفس معرّف الجهاز بعد إعادة التثبيت، بلا تكرار.\n• Apple TV: يعرض ما ينتظر في iCloud ويستلم كل الخوادم برمز إقران واحد؛ إعادة التسمية ومجلد جديد في المستعرض.\n• فيديو لا يبدأ: السبب الحقيقي (تسجيل دخول Cloudflare Access، جهاز ملغى، خطأ في البوابة) بدل “unrecognized file format”؛ يستمر التشغيل بعد انتهاء رمز الجلسة.\n• مستعرض ملفات بأسلوب «الملفات» داخل التطبيق على iPhone وiPad وVision Pro وMac: قائمة أو أيقونات، ترتيب، بحث، معلومات، مجلد جديد، رفع، إعادة تسمية، نقل، نسخ، مشاركة، حذف — عبر البوابة وبصلاحيات Unraid الخاصة بك.\n• يفتح ملفات أكثر بكثير: نظرة سريعة مع مشغّل mpv مدمج (MKV وAVI وWebM وFLAC…) وقارئات لكتب EPUB وقصص CBZ وأرشيفات ZIP.\n• Apple TV: مستعرض مع عارضات نص/NFO/CSV وPDF، وفتح في Infuse/VLC، وmpv يعمل خلف Cloudflare Access أيضًا.\n• اختيار المشاركات المعروضة مع مزامنة iCloud.',
}
for l, t in WHATS_NEW.items():
    assert len(t) <= 4000, (l, "whatsNew", len(t))

# Paragraph appended to the tvOS listing (App Store Connect platform TV_OS), per locale.
TV_PARAGRAPH = {
"en-US": "ON APPLE TV\nThe same app on Apple TV (tvOS 17+): browse your shares and play photos, music and video straight from the NAS through unraid-gateway, with your Unraid user's permissions. Apple formats use the system player; MKV, AVI, WebM, FLAC and the rest play in the built-in open-source mpv player. Pair the TV with a 6-digit code from your iPhone, iPad or Mac: nothing to type on the remote.",
"it": "SU APPLE TV\nLa stessa app su Apple TV (tvOS 17+): sfoglia le share e riproduci foto, musica e video direttamente dal NAS tramite unraid-gateway, con i permessi del tuo utente Unraid. I formati Apple usano il lettore di sistema; MKV, AVI, WebM, FLAC e gli altri si riproducono con il lettore mpv open source integrato. Abbina la TV con un codice di 6 cifre da iPhone, iPad o Mac: niente da digitare sul telecomando.",
"es-ES": "EN EL APPLE TV\nLa misma app en Apple TV (tvOS 17+): explora tus recursos compartidos y reproduce fotos, música y vídeo directamente desde el NAS a través de unraid-gateway, con los permisos de tu usuario Unraid. Los formatos Apple usan el reproductor del sistema; MKV, AVI, WebM, FLAC y el resto se reproducen con el reproductor mpv de código abierto integrado. Empareja el TV con un código de 6 cifras desde tu iPhone, iPad o Mac: nada que escribir en el mando.",
"fr-FR": "SUR APPLE TV\nLa même app sur Apple TV (tvOS 17+) : parcourez vos partages et lisez photos, musique et vidéos directement depuis le NAS via unraid-gateway, avec les permissions de votre utilisateur Unraid. Les formats Apple utilisent le lecteur système ; MKV, AVI, WebM, FLAC et les autres sont lus par le lecteur mpv open source intégré. Jumelez la TV avec un code à 6 chiffres depuis votre iPhone, iPad ou Mac : rien à saisir sur la télécommande.",
"de-DE": "AUF APPLE TV\nDieselbe App auf Apple TV (tvOS 17+): Freigaben durchsuchen und Fotos, Musik und Videos direkt vom NAS über unraid-gateway wiedergeben, mit den Berechtigungen deines Unraid-Benutzers. Apple-Formate nutzen den Systemplayer; MKV, AVI, WebM, FLAC und der Rest laufen im integrierten Open-Source-Player mpv. Kopple den TV mit einem 6-stelligen Code von iPhone, iPad oder Mac: nichts auf der Fernbedienung zu tippen.",
"zh-Hans": "在 Apple TV 上\n同一个应用登陆 Apple TV（tvOS 17+）：浏览共享并通过 unraid-gateway 以你的 Unraid 用户权限直接播放 NAS 上的照片、音乐和视频。Apple 格式使用系统播放器；MKV、AVI、WebM、FLAC 等则由内置的开源 mpv 播放器播放。用 iPhone、iPad 或 Mac 上的 6 位代码配对电视，遥控器上无需输入任何内容。",
"ar-SA": "على Apple TV\nالتطبيق نفسه على Apple TV (tvOS 17+): استعرض مشاركاتك وشغّل الصور والموسيقى والفيديو مباشرة من NAS عبر unraid-gateway بصلاحيات مستخدم Unraid الخاص بك. صيغ Apple تستخدم مشغّل النظام؛ أما MKV وAVI وWebM وFLAC وغيرها فتُشغَّل بمشغّل mpv مفتوح المصدر المدمج. اقرن التلفاز برمز من 6 أرقام من iPhone أو iPad أو Mac: لا شيء تكتبه على جهاز التحكم.",
}

# Privacy policy text (App Store Connect → App Information → Privacy Policy Text). Required for tvOS,
# where the App Store has no browser to open the privacy policy URL. Mirrors PRIVACY.md / docs/index.html.
PRIVACY_TEXT = {
"en-US": "Unraid Drive connects to YOUR OWN Unraid server through the unraid-gateway service you run yourself. The developer operates no server and receives no data from the app.\n\nDATA THE APP PROCESSES\n• Gateway URL, Unraid API key, optional Unraid username/password and Cloudflare Access token: entered by you, stored in the device Keychain, sent only to the gateway URL you entered. If you turn on “Sync configuration with iCloud” (off by default), the server list is stored in iCloud Key-Value Storage and the secrets in iCloud Keychain, both provided by Apple and end-to-end encrypted.\n• Your files: transferred directly between your device and your gateway; files you open are cached on the device like with any cloud provider and can be removed at any time.\n• Server information shown in the dashboard is read from your Unraid API through your gateway and not stored beyond the app cache.\n• Apple TV: pairing uses a one-time 6-digit code; the server configuration is encrypted with that code and exchanged through your own iCloud account only.\n\nDATA THE APP DOES NOT COLLECT\nNo analytics, no advertising, no crash reporting, no account system. The demo server is a simulation that lives entirely on your device.\n\nYOUR CHOICES\nRemove a server to delete its Keychain entries and locations; turn iCloud sync off to delete the iCloud copy; uninstall the app to remove everything.\n\nCONTACT\ngithub.com/sidimam/unraid-drive/issues — Full policy: sidimam.github.io/unraid-drive",
"it": "Unraid Drive si collega al TUO server Unraid tramite il servizio unraid-gateway che gestisci tu. Lo sviluppatore non gestisce alcun server e non riceve dati dall’app.\n\nDATI TRATTATI DALL’APP\n• URL del gateway, API key di Unraid, utente/password Unraid e token Cloudflare Access facoltativi: inseriti da te, salvati nel Portachiavi del dispositivo, inviati solo all’URL del gateway che hai indicato. Se attivi “Sincronizza configurazione con iCloud” (disattivo per impostazione predefinita), l’elenco dei server è salvato nell’archivio chiave-valore di iCloud e i segreti nel Portachiavi iCloud, entrambi forniti da Apple e cifrati end-to-end.\n• I tuoi file: trasferiti direttamente tra il dispositivo e il tuo gateway; i file aperti sono memorizzati nella cache del dispositivo come con qualsiasi provider cloud e possono essere rimossi in ogni momento.\n• Le informazioni sul server mostrate nella dashboard sono lette dall’API di Unraid tramite il gateway e non conservate oltre la cache dell’app.\n• Apple TV: l’abbinamento usa un codice monouso di 6 cifre; la configurazione del server è cifrata con quel codice e scambiata solo tramite il tuo account iCloud.\n\nDATI CHE L’APP NON RACCOGLIE\nNessuna analisi, nessuna pubblicità, nessun servizio di crash report, nessun account. Il server demo è una simulazione che vive interamente sul dispositivo.\n\nLE TUE SCELTE\nRimuovi un server per cancellare le voci del Portachiavi e le posizioni; disattiva la sincronizzazione iCloud per cancellare la copia su iCloud; disinstalla l’app per rimuovere tutto.\n\nCONTATTI\ngithub.com/sidimam/unraid-drive/issues — Informativa completa: sidimam.github.io/unraid-drive",
"es-ES": "Unraid Drive se conecta a TU PROPIO servidor Unraid mediante el servicio unraid-gateway que ejecutas tú. El desarrollador no opera ningún servidor ni recibe datos de la app.\n\nDATOS QUE PROCESA LA APP\n• URL del gateway, clave API de Unraid, usuario/contraseña de Unraid y token de Cloudflare Access opcionales: los introduces tú, se guardan en el Llavero del dispositivo y se envían solo a la URL del gateway que indicaste. Si activas “Sincronizar configuración con iCloud” (desactivado por defecto), la lista de servidores se guarda en el almacenamiento clave-valor de iCloud y los secretos en el Llavero de iCloud, ambos de Apple y cifrados de extremo a extremo.\n• Tus archivos: se transfieren directamente entre el dispositivo y tu gateway; los archivos abiertos se almacenan en la caché del dispositivo como con cualquier proveedor en la nube y pueden eliminarse en cualquier momento.\n• La información del servidor mostrada en el panel se lee de tu API de Unraid a través del gateway y no se conserva más allá de la caché de la app.\n• Apple TV: el emparejamiento usa un código de 6 cifras de un solo uso; la configuración del servidor se cifra con ese código y se intercambia únicamente a través de tu cuenta de iCloud.\n\nDATOS QUE LA APP NO RECOPILA\nSin analíticas, sin publicidad, sin informes de fallos, sin sistema de cuentas. El servidor de demostración es una simulación que vive por completo en tu dispositivo.\n\nTUS OPCIONES\nElimina un servidor para borrar sus entradas del Llavero y ubicaciones; desactiva la sincronización con iCloud para borrar la copia de iCloud; desinstala la app para eliminar todo.\n\nCONTACTO\ngithub.com/sidimam/unraid-drive/issues — Política completa: sidimam.github.io/unraid-drive",
"fr-FR": "Unraid Drive se connecte à VOTRE PROPRE serveur Unraid via le service unraid-gateway que vous exploitez vous-même. Le développeur n’exploite aucun serveur et ne reçoit aucune donnée de l’app.\n\nDONNÉES TRAITÉES PAR L’APP\n• URL de la passerelle, clé API Unraid, identifiant/mot de passe Unraid et jeton Cloudflare Access facultatifs : saisis par vous, stockés dans le trousseau de l’appareil, envoyés uniquement à l’URL de passerelle indiquée. Si vous activez « Synchroniser la configuration avec iCloud » (désactivé par défaut), la liste des serveurs est stockée dans le stockage clé-valeur iCloud et les secrets dans le trousseau iCloud, tous deux fournis par Apple et chiffrés de bout en bout.\n• Vos fichiers : transférés directement entre votre appareil et votre passerelle ; les fichiers ouverts sont mis en cache sur l’appareil comme avec tout fournisseur cloud et peuvent être supprimés à tout moment.\n• Les informations serveur affichées dans le tableau de bord sont lues depuis votre API Unraid via la passerelle et ne sont pas conservées au-delà du cache de l’app.\n• Apple TV : le jumelage utilise un code à 6 chiffres à usage unique ; la configuration du serveur est chiffrée avec ce code et échangée uniquement via votre propre compte iCloud.\n\nDONNÉES QUE L’APP NE COLLECTE PAS\nAucune analyse, aucune publicité, aucun rapport de plantage, aucun système de compte. Le serveur de démonstration est une simulation qui vit entièrement sur votre appareil.\n\nVOS CHOIX\nSupprimez un serveur pour effacer ses entrées de trousseau et ses emplacements ; désactivez la synchronisation iCloud pour effacer la copie iCloud ; désinstallez l’app pour tout supprimer.\n\nCONTACT\ngithub.com/sidimam/unraid-drive/issues — Politique complète : sidimam.github.io/unraid-drive",
"de-DE": "Unraid Drive verbindet sich mit DEINEM EIGENEN Unraid-Server über den unraid-gateway-Dienst, den du selbst betreibst. Der Entwickler betreibt keinen Server und erhält keine Daten aus der App.\n\nVON DER APP VERARBEITETE DATEN\n• Gateway-URL, Unraid-API-Schlüssel, optional Unraid-Benutzername/Passwort und Cloudflare-Access-Token: von dir eingegeben, im Schlüsselbund des Geräts gespeichert, nur an die von dir angegebene Gateway-URL gesendet. Wenn du „Konfiguration mit iCloud synchronisieren“ aktivierst (standardmäßig aus), wird die Serverliste im iCloud-Key-Value-Speicher und die Geheimnisse im iCloud-Schlüsselbund gespeichert, beide von Apple bereitgestellt und Ende-zu-Ende-verschlüsselt.\n• Deine Dateien: werden direkt zwischen deinem Gerät und deinem Gateway übertragen; geöffnete Dateien werden wie bei jedem Cloud-Anbieter auf dem Gerät zwischengespeichert und können jederzeit entfernt werden.\n• Serverinformationen im Dashboard werden über das Gateway aus deiner Unraid-API gelesen und nicht über den App-Cache hinaus gespeichert.\n• Apple TV: Die Kopplung verwendet einen einmaligen 6-stelligen Code; die Serverkonfiguration wird mit diesem Code verschlüsselt und ausschließlich über dein eigenes iCloud-Konto ausgetauscht.\n\nDATEN, DIE DIE APP NICHT ERHEBT\nKeine Analysen, keine Werbung, keine Absturzberichte, kein Kontosystem. Der Demo-Server ist eine Simulation, die vollständig auf deinem Gerät läuft.\n\nDEINE WAHL\nEntferne einen Server, um seine Schlüsselbund-Einträge und Orte zu löschen; deaktiviere die iCloud-Synchronisierung, um die iCloud-Kopie zu löschen; deinstalliere die App, um alles zu entfernen.\n\nKONTAKT\ngithub.com/sidimam/unraid-drive/issues — Vollständige Richtlinie: sidimam.github.io/unraid-drive",
"zh-Hans": "Unraid Drive 通过你自己运行的 unraid-gateway 服务连接到你自己的 Unraid 服务器。开发者不运营任何服务器，也不会从应用接收任何数据。\n\n应用处理的数据\n• 网关地址、Unraid API 密钥、可选的 Unraid 用户名/密码和 Cloudflare Access 令牌：由你输入，保存在设备钥匙串中，只发送到你填写的网关地址。如果开启“通过 iCloud 同步配置”（默认关闭），服务器列表保存在 iCloud 键值存储中，密钥保存在 iCloud 钥匙串中，两者均由 Apple 提供并端到端加密。\n• 你的文件：直接在设备与你的网关之间传输；打开过的文件会像任何云服务一样缓存在设备上，可随时删除。\n• 仪表板中显示的服务器信息通过网关从你的 Unraid API 读取，不会在应用缓存之外保存。\n• Apple TV：配对使用一次性 6 位代码；服务器配置用该代码加密，仅通过你自己的 iCloud 账户交换。\n\n应用不会收集的数据\n没有分析、没有广告、没有崩溃报告、没有账户系统。演示服务器是完全运行在设备上的模拟。\n\n你的选择\n移除服务器即可删除其钥匙串条目和位置；关闭 iCloud 同步即可删除 iCloud 副本；卸载应用即可删除全部数据。\n\n联系方式\ngithub.com/sidimam/unraid-drive/issues — 完整政策：sidimam.github.io/unraid-drive",
"ar-SA": "يتصل Unraid Drive بخادم Unraid الخاص بك عبر خدمة unraid-gateway التي تشغّلها أنت. لا يشغّل المطوّر أي خادم ولا يتلقى أي بيانات من التطبيق.\n\nالبيانات التي يعالجها التطبيق\n• عنوان البوابة، مفتاح Unraid API، واسم مستخدم/كلمة مرور Unraid ورمز Cloudflare Access الاختياريان: تُدخلها أنت، وتُحفظ في سلسلة مفاتيح الجهاز، وتُرسل فقط إلى عنوان البوابة الذي أدخلته. إذا فعّلت «مزامنة الإعدادات مع iCloud» (معطّلة افتراضيًا)، تُحفظ قائمة الخوادم في مخزن القيم لـ iCloud والأسرار في سلسلة مفاتيح iCloud، وكلاهما من Apple ومشفّران من طرف إلى طرف.\n• ملفاتك: تُنقل مباشرة بين جهازك وبوابتك؛ الملفات التي تفتحها تُخزَّن مؤقتًا على الجهاز كما هو الحال مع أي مزود سحابي ويمكن حذفها في أي وقت.\n• معلومات الخادم المعروضة في لوحة المعلومات تُقرأ من Unraid API عبر بوابتك ولا تُحفظ خارج ذاكرة التطبيق المؤقتة.\n• Apple TV: يستخدم الاقتران رمزًا من 6 أرقام لمرة واحدة؛ تُشفَّر إعدادات الخادم بهذا الرمز وتُتبادل فقط عبر حساب iCloud الخاص بك.\n\nالبيانات التي لا يجمعها التطبيق\nلا تحليلات ولا إعلانات ولا تقارير أعطال ولا نظام حسابات. الخادم التجريبي محاكاة تعمل بالكامل على جهازك.\n\nخياراتك\nأزل خادمًا لحذف مدخلات سلسلة المفاتيح ومواقعه؛ عطّل مزامنة iCloud لحذف نسخة iCloud؛ احذف التطبيق لإزالة كل شيء.\n\nالتواصل\ngithub.com/sidimam/unraid-drive/issues — السياسة الكاملة: sidimam.github.io/unraid-drive",
}
for l, t in PRIVACY_TEXT.items():
    assert len(t) <= 4000, (l, "privacyPolicyText", len(t))
