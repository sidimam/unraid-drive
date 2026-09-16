#!/usr/bin/env python3
"""App Store Connect submission helper for Unraid Drive (universal purchase, 4 platforms).

    ASC_ISSUER=… ASC_KEY=…/AuthKey_Z9NY29WQ4M.p8 python3 scripts/asc_submit.py <build number> <step> [--yes]

Steps (run them in order, each one prints what it finds before it writes; --yes is required to write):
  status   — versions, builds and review submissions of the app (read-only, no --yes needed)
  cancel   — withdraw the WAITING_FOR_REVIEW submissions of the platforms listed in CANCEL_PLATFORMS
  versions — for every platform: if an editable version exists (PREPARE_FOR_SUBMISSION / DEVELOPER_REJECTED /
             REJECTED / METADATA_REJECTED) rename it to VERSION and attach the build; otherwise create VERSION
  texts    — copy the localizations (description, keywords, promo, URLs) from the live version when the new one
             has none, then write the What's New of AppStore/store_meta.py for every locale
  review   — make sure every new version has an App Review detail (copied from the live version when missing)
  submit   — create a review submission per platform (or reuse an open READY_FOR_REVIEW one), add the version, submit
  all      — cancel, versions, texts, review, submit

The JWT comes from the kit's ascjwt.swift (same folder as the key). Nothing secret is printed.
History: 2026-09-12 moved 1.1 (waiting) to 1.3 build 36 and created visionOS 1.3; 2026-09-16 withdrew tvOS 1.3
(still waiting) and submitted 1.3.1 build 40 on iOS, macOS, tvOS and visionOS.
"""
import json, os, subprocess, sys, time, urllib.request, urllib.error, importlib.util

APP_ID = "6809862123"; KEY_ID = "Z9NY29WQ4M"; API = "https://api.appstoreconnect.apple.com/v1"
VERSION = os.environ.get("ASC_VERSION", "1.3.1")
PLATFORMS = ["IOS", "MAC_OS", "TV_OS", "VISION_OS"]
CANCEL_PLATFORMS = os.environ.get("ASC_CANCEL", "TV_OS").split(",") if os.environ.get("ASC_CANCEL", "TV_OS") else []
EDITABLE = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY", "WAITING_FOR_REVIEW"}
LIVE = {"READY_FOR_SALE", "READY_FOR_DISTRIBUTION", "PROCESSING_FOR_APP_STORE", "PENDING_DEVELOPER_RELEASE"}
LOCALE_MAP = {"it": "it", "es": "es-ES", "fr": "fr-FR", "de": "de-DE", "zh-Hans": "zh-Hans", "ar": "ar-SA", "en-US": "en-US"}

args = [a for a in sys.argv[1:] if not a.startswith("--")]
if len(args) < 2: sys.exit(__doc__)
BUILD_NO, STEP = args[0], args[1]
YES = "--yes" in sys.argv
issuer = os.environ["ASC_ISSUER"]; key = os.environ["ASC_KEY"]
jwt = subprocess.check_output(["swift", os.path.join(os.path.dirname(key), "ascjwt.swift"), key, KEY_ID, issuer], text=True).strip()

def call(method, path, body=None, ok404=False):
    req = urllib.request.Request(path if path.startswith("http") else API + path, method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={"Authorization": "Bearer " + jwt, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r: return json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        if e.code == 404 and ok404: return None
        sys.exit(f"{method} {path}: {e.code} {e.read().decode()[:600]}")

def write(method, path, body=None):
    if not YES: print(f"   (dry run) {method} {path} {json.dumps(body)[:160] if body else ''}"); return {}
    return call(method, path, body)

spec = importlib.util.spec_from_file_location("store_meta", os.path.join(os.path.dirname(__file__), "..", "AppStore", "store_meta.py"))
meta = importlib.util.module_from_spec(spec)
try: spec.loader.exec_module(meta)
except SystemExit: pass

def versions():
    r = call("GET", f"/apps/{APP_ID}/appStoreVersions?limit=50&fields[appStoreVersions]=platform,versionString,appVersionState,createdDate")
    return r["data"]

def builds():
    r = call("GET", f"/builds?filter[app]={APP_ID}&filter[version]={BUILD_NO}&include=preReleaseVersion&limit=20")
    pre = {i["id"]: i["attributes"] for i in r.get("included", [])}
    out = {}
    for d in r["data"]:
        p = pre.get((d["relationships"]["preReleaseVersion"]["data"] or {}).get("id"), {})
        if d["attributes"]["processingState"] == "VALID" and not d["attributes"]["expired"]:
            out[p.get("platform")] = (d["id"], p.get("version"))
    return out

def submissions(states=None):
    q = f"/reviewSubmissions?filter[app]={APP_ID}&limit=50&fields[reviewSubmissions]=platform,state,submittedDate"
    if states: q += "&filter[state]=" + ",".join(states)
    return call("GET", q)["data"]

def status():
    print("== versions"); [print(f"   {v['attributes']['platform']:10} {v['attributes']['versionString']:6} {v['attributes']['appVersionState']:24} {v['id']}") for v in versions()]
    print(f"== builds {BUILD_NO}"); [print(f"   {p:10} {b[1]} build {BUILD_NO} VALID {b[0]}") for p, b in builds().items()]
    print("== review submissions (open)"); [print(f"   {s['attributes']['platform']:10} {s['attributes']['state']:20} {s['attributes']['submittedDate']} {s['id']}") for s in submissions(["READY_FOR_REVIEW", "WAITING_FOR_REVIEW", "IN_REVIEW", "UNRESOLVED_ISSUES"])]

def cancel():
    for s in submissions(["WAITING_FOR_REVIEW", "IN_REVIEW", "UNRESOLVED_ISSUES"]):
        if s["attributes"]["platform"] in CANCEL_PLATFORMS:
            print(f"-- cancel {s['attributes']['platform']} submission {s['id']} ({s['attributes']['state']})")
            write("PATCH", f"/reviewSubmissions/{s['id']}", {"data": {"type": "reviewSubmissions", "id": s["id"], "attributes": {"canceled": True}}})
    if YES: time.sleep(5)

def step_versions():
    b = builds(); vs = versions()
    for p in PLATFORMS:
        if p not in b: print(f"-- {p}: no VALID build {BUILD_NO}, skipped"); continue
        bid = b[p][0]
        mine = [v for v in vs if v["attributes"]["platform"] == p]
        target = [v for v in mine if v["attributes"]["versionString"] == VERSION]
        editable = [v for v in mine if v["attributes"]["appVersionState"] in EDITABLE]
        rel = {"build": {"data": {"type": "builds", "id": bid}}}
        if target:
            v = target[0]; print(f"-- {p}: {VERSION} exists ({v['attributes']['appVersionState']}), attaching build {BUILD_NO}")
            write("PATCH", f"/appStoreVersions/{v['id']}", {"data": {"type": "appStoreVersions", "id": v["id"], "relationships": rel}})
        elif editable:
            v = editable[0]; print(f"-- {p}: renaming {v['attributes']['versionString']} ({v['attributes']['appVersionState']}) → {VERSION}, build {BUILD_NO}")
            write("PATCH", f"/appStoreVersions/{v['id']}", {"data": {"type": "appStoreVersions", "id": v["id"], "attributes": {"versionString": VERSION}, "relationships": rel}})
        else:
            print(f"-- {p}: creating {VERSION} with build {BUILD_NO}")
            write("POST", "/appStoreVersions", {"data": {"type": "appStoreVersions", "attributes": {"platform": p, "versionString": VERSION, "releaseType": "AFTER_APPROVAL"},
                  "relationships": {"app": {"data": {"type": "apps", "id": APP_ID}}, **rel}}})

def locs(vid):
    return call("GET", f"/appStoreVersions/{vid}/appStoreVersionLocalizations?limit=50")["data"]

def texts():
    """Every locale of the new version gets description (tvOS: TV_DESCRIPTION), keywords, promotional text and
    What's New from AppStore/store_meta.py; a locale the version does not have yet is created."""
    vs = versions()
    by_asc = {meta.ASC_LOCALE[k]: k for k in meta.META}
    for p in PLATFORMS:
        mine = [v for v in vs if v["attributes"]["platform"] == p]
        new = [v for v in mine if v["attributes"]["versionString"] == VERSION]
        if not new: print(f"-- {p}: no {VERSION} version"); continue
        new = new[0]
        if new["attributes"]["appVersionState"] not in EDITABLE - {"WAITING_FOR_REVIEW"}: print(f"-- {p}: {VERSION} is {new['attributes']['appVersionState']}, texts left alone"); continue
        have = {l["attributes"]["locale"]: l for l in locs(new["id"])}
        live = [v for v in mine if v["attributes"]["appVersionState"] in LIVE and v["id"] != new["id"]]
        urls = {}
        if live:
            for l in locs(live[0]["id"]): urls[l["attributes"]["locale"]] = {k: l["attributes"].get(k) for k in ("supportUrl", "marketingUrl")}
        for loc, k in by_asc.items():
            m = meta.META[k]
            attrs = {"description": meta.TV_DESCRIPTION[k] if p == "TV_OS" else m["description"], "keywords": m["keywords"],
                     "promotionalText": m["promo"]}
            if live: attrs["whatsNew"] = meta.WHATS_NEW[loc][:4000]  # a platform's first release has no What's New
            if loc in have:
                print(f"   {p} {loc}: description {len(attrs['description'])}, What's New {len(attrs.get('whatsNew', ''))}")
                write("PATCH", f"/appStoreVersionLocalizations/{have[loc]['id']}", {"data": {"type": "appStoreVersionLocalizations", "id": have[loc]["id"], "attributes": attrs}})
            else:
                attrs["locale"] = loc; attrs.update({k2: v2 for k2, v2 in urls.get(loc, {}).items() if v2})
                print(f"   {p} {loc}: creating localization (description {len(attrs['description'])})")
                write("POST", "/appStoreVersionLocalizations", {"data": {"type": "appStoreVersionLocalizations", "attributes": attrs,
                      "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": new["id"]}}}}})

def review():
    vs = versions()
    for p in PLATFORMS:
        mine = [v for v in vs if v["attributes"]["platform"] == p]
        new = [v for v in mine if v["attributes"]["versionString"] == VERSION]
        if not new: continue
        new = new[0]; d = call("GET", f"/appStoreVersions/{new['id']}/appStoreReviewDetail", ok404=True)
        if d and d.get("data"): print(f"-- {p}: review detail present (contact {d['data']['attributes'].get('contactFirstName')}, demo account {'yes' if d['data']['attributes'].get('demoAccountRequired') else 'no'})"); continue
        live = [v for v in mine if v["attributes"]["appVersionState"] in LIVE and v["id"] != new["id"]]
        src = None
        for cand in live + [v for v in vs if v["attributes"]["appVersionState"] in LIVE]:
            s = call("GET", f"/appStoreVersions/{cand['id']}/appStoreReviewDetail", ok404=True)
            if s and s.get("data"): src = s["data"]["attributes"]; break
        if not src: print(f"-- {p}: no review detail anywhere to copy"); continue
        attrs = {k: v for k, v in src.items() if v not in (None, "") and k in ("contactFirstName", "contactLastName", "contactPhone", "contactEmail", "demoAccountName", "demoAccountPassword", "demoAccountRequired", "notes")}
        print(f"-- {p}: creating review detail from live version")
        write("POST", "/appStoreReviewDetails", {"data": {"type": "appStoreReviewDetails", "attributes": attrs, "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": new["id"]}}}}})

def submit():
    vs = versions(); open_subs = submissions(["READY_FOR_REVIEW"])
    for p in PLATFORMS:
        new = [v for v in vs if v["attributes"]["platform"] == p and v["attributes"]["versionString"] == VERSION]
        if not new: print(f"-- {p}: no {VERSION} version"); continue
        vid = new[0]["id"]
        if new[0]["attributes"]["appVersionState"] not in {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED"}:
            print(f"-- {p}: {VERSION} is {new[0]['attributes']['appVersionState']}, not submitting"); continue
        reuse = [s for s in open_subs if s["attributes"]["platform"] == p]
        if reuse: sid = reuse[0]["id"]; print(f"-- {p}: reusing open submission {sid}")
        else:
            print(f"-- {p}: creating review submission")
            r = write("POST", "/reviewSubmissions", {"data": {"type": "reviewSubmissions", "attributes": {"platform": p}, "relationships": {"app": {"data": {"type": "apps", "id": APP_ID}}}}})
            sid = r.get("data", {}).get("id")
        if not sid: continue
        items = call("GET", f"/reviewSubmissions/{sid}/items?limit=20")["data"] if YES else []
        if not any((i["relationships"].get("appStoreVersion", {}).get("data") or {}).get("id") == vid for i in items):
            write("POST", "/reviewSubmissionItems", {"data": {"type": "reviewSubmissionItems", "relationships": {"reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sid}}, "appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}})
        r = write("PATCH", f"/reviewSubmissions/{sid}", {"data": {"type": "reviewSubmissions", "id": sid, "attributes": {"submitted": True}}})
        if YES: print(f"   {p}: submission {sid} → {r.get('data', {}).get('attributes', {}).get('state')}")

steps = {"status": status, "cancel": cancel, "versions": step_versions, "texts": texts, "review": review, "submit": submit}
if STEP == "all":
    for s in ("cancel", "versions", "texts", "review", "submit"): print(f"===== {s}"); steps[s]()
elif STEP in steps: steps[STEP]()
else: sys.exit(f"unknown step {STEP}")
