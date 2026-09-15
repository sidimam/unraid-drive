#!/usr/bin/env python3
"""Set the TestFlight "What to test" of every platform build of a given build number.

    ASC_ISSUER=… ASC_KEY=…/AuthKey_Z9NY29WQ4M.p8 python3 AppStore/testflight_notes.py 40

The text is the What's New of store_meta.py (7 locales) with a short preamble; a build that
App Store Connect is still processing is reported and skipped — run the script again later.
The JWT comes from the kit's ascjwt.swift (same folder as the key). Nothing is printed that is secret.
"""
import json, os, subprocess, sys, urllib.request, importlib.util
APP_ID = "6809862123"; KEY_ID = "Z9NY29WQ4M"; API = "https://api.appstoreconnect.apple.com/v1"
build_no = sys.argv[1] if len(sys.argv) > 1 else sys.exit("usage: testflight_notes.py <build number>")
issuer = os.environ["ASC_ISSUER"]; key = os.environ["ASC_KEY"]
jwt = subprocess.check_output(["swift", os.path.join(os.path.dirname(key), "ascjwt.swift"), key, KEY_ID, issuer], text=True).strip()

def call(method, path, body=None):
    req = urllib.request.Request(path if path.startswith("http") else API + path, method=method,
        data=json.dumps(body).encode() if body else None,
        headers={"Authorization": "Bearer " + jwt, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r: return json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        sys.exit(f"{method} {path}: {e.code} {e.read().decode()[:300]}")

spec = importlib.util.spec_from_file_location("store_meta", os.path.join(os.path.dirname(__file__), "store_meta.py"))
meta = importlib.util.module_from_spec(spec)
try: spec.loader.exec_module(meta)
except SystemExit: pass
PREAMBLE = {"en-US": "Build {b}: please check device registration, the iCloud rows in Settings (servers.json in iCloud Drive), Diagnostics and log, and the Files/Finder location after the update.\n\n",
            "it": "Build {b}: verifica la registrazione del dispositivo, le righe iCloud nelle Impostazioni (servers.json in iCloud Drive), Diagnostica e log, e la posizione File/Finder dopo l’aggiornamento.\n\n",
            "es-ES": "Build {b}: comprueba el registro del dispositivo, las filas de iCloud en Ajustes (servers.json en iCloud Drive), Diagnóstico y registro, y la ubicación de Archivos/Finder tras la actualización.\n\n",
            "fr-FR": "Build {b} : vérifiez l’enregistrement de l’appareil, les lignes iCloud des Réglages (servers.json dans iCloud Drive), Diagnostic et journal, et l’emplacement Fichiers/Finder après la mise à jour.\n\n",
            "de-DE": "Build {b}: bitte Geräteregistrierung, die iCloud-Zeilen in den Einstellungen (servers.json in iCloud Drive), Diagnose und Protokoll sowie den Dateien-/Finder-Speicherort nach dem Update prüfen.\n\n",
            "zh-Hans": "Build {b}：请检查设备注册、设置中的 iCloud 行（iCloud 云盘中的 servers.json）、诊断与日志，以及更新后的“文件”/Finder 位置。\n\n",
            "ar-SA": "الإصدار {b}: يرجى التحقق من تسجيل الجهاز وصفوف iCloud في الإعدادات (servers.json في iCloud Drive) والتشخيص والسجل وموقع الملفات/Finder بعد التحديث.\n\n"}
texts = {l: (PREAMBLE[l].format(b=build_no) + t)[:4000] for l, t in meta.WHATS_NEW.items()}

builds = call("GET", f"/builds?filter[app]={APP_ID}&filter[version]={build_no}&include=preReleaseVersion&limit=20")
platforms = {i["id"]: i["attributes"]["platform"] for i in builds.get("included", []) if i["type"] == "preReleaseVersions"}
if not builds["data"]: sys.exit(f"no build {build_no} in App Store Connect yet")
for b in builds["data"]:
    plat = platforms.get(b["relationships"]["preReleaseVersion"]["data"]["id"], "?")
    state = b["attributes"]["processingState"]
    if state != "VALID": print(f"{plat}: build {build_no} is {state} — run again later"); continue
    existing = {l["attributes"]["locale"]: l["id"] for l in call("GET", f"/builds/{b['id']}/betaBuildLocalizations?limit=50")["data"]}
    for locale, text in texts.items():
        if locale in existing:
            call("PATCH", f"/betaBuildLocalizations/{existing[locale]}", {"data": {"type": "betaBuildLocalizations", "id": existing[locale], "attributes": {"whatsNew": text}}})
        else:
            call("POST", "/betaBuildLocalizations", {"data": {"type": "betaBuildLocalizations", "attributes": {"locale": locale, "whatsNew": text},
                 "relationships": {"build": {"data": {"type": "builds", "id": b["id"]}}}}})
    print(f"{plat}: build {build_no} — What to test set in {len(texts)} locales")
