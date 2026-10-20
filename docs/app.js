// HMG Leafia Plus compatibility checker. Runs entirely in the browser.
"use strict";

const $ = (id) => document.getElementById(id);
let DB = null;
let lastReport = "";

const STATUS = {
  ok: ["s-ok", "Ready"],
  native: ["s-native", "Built in"],
  build: ["s-build", "Needs a build"],
  no: ["s-no", "Not possible"],
  unknown: ["s-unknown", "Unknown"],
};

const TBT_CALLS = ["updateTBTInfo", "updateTBTSubInfo", "updateTBTSubInfo2C", "updateTBTTrapInfo",
  "updateTPTurnList", "updateTPTurnListNew", "updateTPCrossroadName", "updateTPFlexibleDestinationName",
  "updateLaneInfo", "updateOperationStatus", "responseNaviAliveStatus"];
const BRIDGE_FILES = ["/system/app/HKMC_DiPO.apk", "/system/app/HKMC_DiPO.odex",
  "/system/app/Iap2ServerApp.apk", "/system/app/Iap2ServerApp.odex"];

function parse(text) {
  const r = { props: {}, pkgs: [], files: {}, results: {}, notes: {}, spots: [], api: {}, perm: {}, features: [], valid: false };
  for (const raw of text.split(/\r?\n/)) {
    const line = raw.trim();
    if (!line || line.startsWith("#")) continue;
    if (line.startsWith("leafia-report")) { r.valid = true; continue; }
    let m;
    if ((m = line.match(/^prop ([^=]+)=(.*)$/))) r.props[m[1]] = m[2];
    else if ((m = line.match(/^pkg (\S+)/))) r.pkgs.push(m[1]);
    else if ((m = line.match(/^file (\S+) (?:md5=([0-9a-f]{32})|missing)/))) r.files[m[1]] = m[2] || null;
    else if ((m = line.match(/^RESULT (\S+) status=(\S+)(?:.* md5=([0-9a-f]{32}))?/))) r.results[m[1]] = { status: m[2], md5: m[3] || null };
    else if ((m = line.match(/^NATIVE_NOTE (\S+) (.*)$/))) r.notes[m[1]] = m[2];
    else if (line.startsWith("SPOT ")) r.spots.push(line);
    else if ((m = line.match(/^api (\S+)=([01])/))) r.api[m[1]] = m[2] === "1";
    else if ((m = line.match(/^permfile (\S+)=([01])/))) r.perm[m[1]] = m[2] === "1";
    else if ((m = line.match(/^feature (.+)$/))) r.features.push(m[1].trim());
  }
  return r;
}

function findVariant(r) {
  const product = r.props["ro.build.product"] || "";
  return DB.variants.find((v) => [].concat(v.product_prefix).some((p) => product.startsWith(p))) || null;
}

function filesMatch(r, v, list) {
  if (!v) return false;
  return list.every((f) => v.stock[f] && r.files[f] === v.stock[f]);
}

function recipeState(r, id) {
  const res = r.results[id];
  if (!res) return "unknown";
  return { PATCHABLE: "ok", APPLIED: "ok", NATIVE: "native", MISMATCH: "build", MISSING: "no" }[res.status] || "unknown";
}

function verdict(r) {
  const v = findVariant(r);
  const parts = [];
  const hasWifi = r.features.includes("com.hkmc.software.wifi.module");

  parts.push({ name: "Wireless projection (car hotspot)", state: hasWifi ? "ok" : "no",
    why: hasWifi ? "Wi-Fi module present. The package enables the wireless CarPlay/AA feature flags for your region folder ("
      + (r.props["ro.mobis.onebindir"] || "unknown") + ")." : "No Wi-Fi module reported, so wireless projection is not possible on this unit." });

  parts.push({ name: "Wireless Android Auto", state: hasWifi ? "ok" : "no",
    why: hasWifi ? "Uses the stock Android Auto app plus the wireless feature flags. Calls still go over Bluetooth, as on every Android Auto car." : "Needs a Wi-Fi module." });

  const core = recipeState(r, "carplay-core-wifi");
  parts.push({ name: "CarPlay Wi-Fi sessions", state: core,
    why: { ok: "The Wi-Fi session patch fits this firmware byte for byte.", native: "This firmware already accepts Wi-Fi CarPlay sessions (" + (r.notes["carplay-core-wifi"] || "known build") + ").",
      build: "This library differs at the patch spot, so it needs analysis.", no: "libCarPlayCore.so was not found.", unknown: "Not in this report." }[core] });

  const aud = recipeState(r, "carplay-audio-formats");
  const conv = recipeState(r, "carplay-utils-converter");
  // a codec counts as missing only when the report says so (older reports did not list them)
  const codecs = !["/system/lib/libstagefright_soft_aacdec.so", "/system/lib/libopus.so"].some((f) => f in r.files && r.files[f] === null);
  let audioState, audioWhy;
  if (aud === "ok" && (conv === "native" || (conv === "ok" && codecs))) {
    audioState = "ok";
    audioWhy = "The audio-format patch fits. " + (conv === "native" ? "This firmware has its own AAC/Opus converters." : "AAC and Opus are decoded with the head unit's own codecs.");
  } else if (aud === "ok" && conv === "ok" && !codecs) {
    audioState = "build"; audioWhy = "The patches fit, but the AAC or Opus codec library is missing on this unit.";
  } else if (aud === "unknown" && conv === "unknown") {
    audioState = "unknown"; audioWhy = "Not in this report.";
  } else {
    audioState = aud === "no" || conv === "no" ? "no" : "build";
    audioWhy = "Audio-format patch: " + (r.results["carplay-audio-formats"]?.status || "?") + ", converter: " + (r.results["carplay-utils-converter"]?.status || "?") + ".";
  }
  parts.push({ name: "CarPlay wireless audio", state: audioState, why: audioWhy });

  const built = v && (v.status === "supported" || v.status === "testing");
  const tested = v && v.status === "supported";
  const bridgeOk = filesMatch(r, v, BRIDGE_FILES);
  parts.push({ name: "CarPlay Bluetooth bridge", state: bridgeOk && built ? "ok" : "build",
    why: bridgeOk && built ? (tested ? "A tested build exists for these exact CarPlay apps." : "A build exists for these exact CarPlay apps; it hasn't been tried on a real car yet.") : "The CarPlay apps on this unit have no build yet. Sharing your report helps get one made." });

  const apiKnown = TBT_CALLS.some((c) => c in r.api);
  const apiMissing = TBT_CALLS.filter((c) => r.api[c] === false);
  const tbtFiles = Object.keys(v ? v.stock : {});
  let tbtState, tbtWhy;
  if (!apiKnown) { tbtState = "unknown"; tbtWhy = "Not in this report."; }
  else if (apiMissing.length) { tbtState = "no"; tbtWhy = "This firmware lacks cluster calls turn-by-turn needs: " + apiMissing.join(", ") + ". The package refuses to install it here."; }
  else if (filesMatch(r, v, tbtFiles) && built) { tbtState = "ok"; tbtWhy = "Cluster API present and a " + (tested ? "tested build" : "build (not yet tried on a real car)") + " exists. No HUD? That's fine; the HUD frames just go unused."; }
  else { tbtState = "build"; tbtWhy = "Cluster API present, but these navigation/projection apps have no build yet."; }
  parts.push({ name: "Turn-by-turn on cluster / HUD", state: tbtState, why: tbtWhy });

  const allGood = parts.every((p) => p.state === "ok" || p.state === "native");
  let overall;
  if (!r.valid) overall = ["no", "This doesn't look like an HMG Leafia Plus report."];
  else if (allGood && v && v.status === "supported") overall = ["ok", "Supported: install the Wireless CarPlay and Android Auto package."];
  else if (allGood && v && v.status === "testing") overall = ["ok", "Build ready, awaiting its first real-car test. You can install the package; uninstall puts everything back to stock."];
  else if (v && v.status === "in-progress") overall = ["build", "Support for " + v.name + " is in progress. Share your report to help."];
  else if (!hasWifi) overall = ["no", "This unit has no Wi-Fi module, so wireless projection isn't possible."];
  else overall = ["build", "Not supported yet. Share your report so a build can be made for this head unit."];
  return { v, parts, overall };
}

function chip(state) {
  const [cls, label] = STATUS[state] || STATUS.unknown;
  const el = document.createElement("span");
  el.className = "chip " + cls; el.textContent = label;
  return el;
}

function render(text) {
  const r = parse(text);
  lastReport = text;
  const { v, parts, overall } = verdict(r);
  $("result").classList.remove("hidden");
  $("carTitle").textContent = v ? v.name + " (" + v.region + ")" : "Unrecognised head unit";
  const facts = [["Firmware", r.props["ro.build.product"] || "?"], ["Device", r.props["ro.product.device"] || "?"],
    ["Chip", r.props["ro.board.platform"] || r.props["ro.hardware"] || "?"], ["Region folder", r.props["ro.mobis.onebindir"] || "?"]];
  const cf = $("carFacts"); cf.textContent = "";
  for (const [k, val] of facts) {
    const d = document.createElement("div"), s = document.createElement("span"), b = document.createElement("b");
    s.textContent = k; b.textContent = val; d.append(s, b); cf.append(d);
  }
  const ov = $("overall");
  ov.className = "overall " + STATUS[overall[0]][0]; ov.textContent = overall[1];
  const tb = $("parts"); tb.textContent = "";
  for (const p of parts) {
    const tr = document.createElement("tr"), a = document.createElement("td"), b = document.createElement("td");
    a.textContent = p.name;
    const why = document.createElement("small"); why.textContent = p.why;
    b.append(chip(p.state), why);
    tr.append(a, b); tb.append(tr);
  }
  const summary = parts.map((p) => "- " + p.name + ": " + (STATUS[p.state] || STATUS.unknown)[1]).join("\n");
  const title = "Report: " + (r.props["ro.build.product"] || "unknown head unit");
  let body = "**Verdict:** " + overall[1] + "\n\n" + summary + "\n\n<details><summary>LEAFIA-REPORT.txt</summary>\n\n```\n" + text.trim() + "\n```\n</details>\n";
  const base = "https://github.com/" + DB.repo + "/issues/new?title=" + encodeURIComponent(title) + "&body=";
  if ((base + encodeURIComponent(body)).length > 7800) {
    body = "**Verdict:** " + overall[1] + "\n\n" + summary + "\n\nThe report was too long for a link. Please attach LEAFIA-REPORT.txt to this issue.\n";
  }
  $("share").href = base + encodeURIComponent(body);
  $("result").scrollIntoView({ behavior: "smooth", block: "start" });
}

function renderCompat() {
  const tb = $("compat"); tb.textContent = "";
  for (const v of DB.variants) {
    const tr = document.createElement("tr");
    const cells = [["", v.name + " · " + v.region], ["Firmware", v.firmware], ["Chip", v.chip]];
    for (const [label, c] of cells) { const td = document.createElement("td"); td.textContent = c; if (label) td.dataset.label = label; tr.append(td); }
    const st = document.createElement("td");
    st.append(chip(v.status === "supported" || v.status === "testing" ? "ok" : v.status === "in-progress" ? "build" : "unknown"));
    if (v.status === "testing") st.lastChild.textContent = "Testing";
    if (v.status === "in-progress") st.lastChild.textContent = "In progress";
    if (v.status === "supported") st.lastChild.textContent = "Supported";
    const notes = document.createElement("td");
    notes.textContent = v.notes || (v.verified || []).join("; ");
    tr.append(st, notes); tb.append(tr);
  }
}

function readFile(f) { const fr = new FileReader(); fr.onload = () => render(String(fr.result)); fr.readAsText(f); }

async function init() {
  DB = await (await fetch("data/compat.json")).json();
  renderCompat();
  const drop = $("drop");
  ["dragenter", "dragover"].forEach((e) => drop.addEventListener(e, (ev) => { ev.preventDefault(); drop.classList.add("over"); }));
  ["dragleave", "drop"].forEach((e) => drop.addEventListener(e, (ev) => { ev.preventDefault(); drop.classList.remove("over"); }));
  drop.addEventListener("drop", (ev) => { const f = ev.dataTransfer.files[0]; if (f) readFile(f); });
  $("file").addEventListener("change", (ev) => { const f = ev.target.files[0]; if (f) readFile(f); });
  $("pasteBtn").addEventListener("click", () => { const t = $("paste").value; if (t.trim()) render(t); });
  document.querySelectorAll("[data-sample]").forEach((b) => b.addEventListener("click", async () => {
    render(await (await fetch(b.dataset.sample)).text());
  }));
  $("copy").addEventListener("click", async () => {
    try { await navigator.clipboard.writeText(lastReport); $("copy").textContent = "Copied"; }
    catch (e) { $("copy").textContent = "Copy failed"; }
    setTimeout(() => { $("copy").textContent = "Copy report"; }, 1500);
  });
}
init();
