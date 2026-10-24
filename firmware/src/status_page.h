#pragma once

// Served at "/". It polls /status.json, so the firmware never formats HTML itself.
static const char kStatusPage[] = R"HTML(<!doctype html>
<html lang="en">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Projector UART bridge</title>
<style>
:root { --bg:#f4f5f2; --card:#fff; --fg:#1d2420; --muted:#5c6862; --line:#d3d9d4; --ok:#15803d; --warn:#b45309; --bad:#b91c1c; }
@media (prefers-color-scheme: dark) { :root { --bg:#131815; --card:#1a201c; --fg:#e4ebe6; --muted:#9aa8a0; --line:#34403a; --ok:#4ade80; --warn:#fbbf24; --bad:#f87171; color-scheme: dark; } }
body { margin:0; background:var(--bg); color:var(--fg); font:15px/1.5 system-ui,-apple-system,sans-serif; padding:24px max(16px,env(safe-area-inset-left)); }
main { max-width:640px; margin:0 auto; display:grid; gap:16px; }
h1 { font-size:1.3rem; margin:0; }
.sub { color:var(--muted); font-size:.9rem; }
section { background:var(--card); border:1px solid var(--line); border-radius:10px; padding:14px 16px; }
h2 { font-size:.75rem; letter-spacing:.08em; text-transform:uppercase; color:var(--muted); margin:0 0 8px; }
dl { display:grid; grid-template-columns:max-content 1fr; gap:6px 16px; margin:0; }
dt { color:var(--muted); }
dd { margin:0; font-family:ui-monospace,Menlo,monospace; font-variant-numeric:tabular-nums; overflow-wrap:anywhere; }
.pill { display:inline-block; padding:1px 8px; border-radius:99px; border:1px solid currentColor; font:600 .8rem system-ui,sans-serif; }
.ok { color:var(--ok); } .warn { color:var(--warn); } .bad { color:var(--bad); }
#err { color:var(--bad); }
.fw { display:grid; gap:8px; }
.fw label { color:var(--muted); font-size:.9rem; }
.fw input, .fw button { font:inherit; }
.fw button { justify-self:start; padding:6px 14px; border-radius:6px; border:1px solid var(--line); background:var(--fg); color:var(--card); cursor:pointer; }
.fw button:disabled { opacity:.5; cursor:default; }
.fw button:focus-visible, .fw input:focus-visible { outline:2px solid var(--ok); outline-offset:2px; }
progress { width:100%; }
</style>
<main>
  <header>
    <h1>Projector UART bridge</h1>
    <div class="sub">Console: <code>nc <span id="host">projector-uart.local</span> 2323</code> &middot; refreshes every 2 s <span id="err"></span></div>
  </header>
  <section><h2>Projector</h2><dl>
    <dt>UART</dt><dd id="uart">-</dd>
    <dt>Last byte</dt><dd id="last">-</dd>
    <dt>Received</dt><dd id="rx">-</dd>
    <dt>Sent</dt><dd id="tx">-</dd>
  </dl></section>
  <section><h2>Console</h2><dl>
    <dt>Client</dt><dd id="client">-</dd>
  </dl></section>
  <section><h2>Bridge</h2><dl>
    <dt>Network</dt><dd id="net">-</dd>
    <dt>Address</dt><dd id="ip">-</dd>
    <dt>Signal</dt><dd id="rssi">-</dd>
    <dt>Uptime</dt><dd id="up">-</dd>
    <dt>Last reset</dt><dd id="reset">-</dd>
    <dt>Free memory</dt><dd id="heap">-</dd>
  </dl></section>
  <section><h2>Firmware update</h2>
    <form id="fw" class="fw">
      <label for="fw-file">Firmware file (<code>.pio/build/esp32-c6-supermini/firmware.bin</code>)</label>
      <input id="fw-file" type="file" accept=".bin" required>
      <label for="fw-pass">OTA password</label>
      <input id="fw-pass" type="password" autocomplete="current-password" required>
      <button id="fw-go" type="submit">Upload and restart</button>
      <progress id="fw-bar" max="100" value="0" hidden></progress>
      <div id="fw-msg" class="sub"></div>
    </form>
  </section>
</main>
<script>
const $ = id => document.getElementById(id);
function dur(s) {
  const d = Math.floor(s / 86400), h = Math.floor(s / 3600) % 24, m = Math.floor(s / 60) % 60;
  return (d ? d + "d " : "") + (d || h ? h + "h " : "") + (d || h || m ? m + "m " : "") + (s % 60) + "s";
}
function bytes(n) { return n < 1024 ? n + " B" : n < 1048576 ? (n / 1024).toFixed(1) + " KiB" : (n / 1048576).toFixed(2) + " MiB"; }
function pill(cls, text) { return '<span class="pill ' + cls + '">' + text + '</span>'; }
async function refresh() {
  try {
    const r = await fetch("/status.json", { cache: "no-store" });
    const s = await r.json();
    const idle = s.uart_last_byte_age_s;
    $("uart").innerHTML = !s.projector_powered ? pill("warn", "projector off, TX released")
      : idle === null ? pill("warn", "no data yet")
      : idle < 60 ? pill("ok", "active") : pill("warn", "quiet");
    $("last").textContent = idle === null ? "never since boot" : dur(idle) + " ago";
    $("rx").textContent = bytes(s.uart_rx_bytes);
    $("tx").textContent = bytes(s.uart_tx_bytes);
    $("client").innerHTML = !s.client_ip ? pill("warn", "none")
      : (s.client_authenticated ? pill("ok", "logged in") : pill("warn", "at password prompt")) + " " + s.client_ip;
    $("net").innerHTML = s.mode === "station" ? pill("ok", "Wi-Fi") + " " + s.ssid
      : pill("warn", "fallback AP") + " " + s.ssid;
    $("ip").textContent = s.ip;
    $("rssi").textContent = s.mode === "station" ? s.rssi_dbm + " dBm" : "-";
    $("up").textContent = dur(s.uptime_s);
    $("reset").innerHTML = s.reset_reason.startsWith("BROWNOUT") ? pill("bad", s.reset_reason) : s.reset_reason;
    $("heap").textContent = bytes(s.free_heap);
    $("err").textContent = "";
  } catch (e) {
    $("err").textContent = "· bridge not answering";
  }
}
refresh();
setInterval(refresh, 2000);

$("fw").addEventListener("submit", e => {
  e.preventDefault();
  const file = $("fw-file").files[0];
  if (!file) return;
  const body = new FormData();
  body.append("firmware", file, file.name);
  const xhr = new XMLHttpRequest();
  xhr.open("POST", "/update");
  xhr.setRequestHeader("Authorization", "Basic " + btoa("admin:" + $("fw-pass").value));
  xhr.upload.onprogress = p => { if (p.lengthComputable) $("fw-bar").value = Math.round(p.loaded * 100 / p.total); };
  xhr.onload = () => {
    $("fw-go").disabled = false;
    if (xhr.status === 200) {
      $("fw-msg").textContent = "Written. The bridge is restarting, this page reconnects in about 10 s.";
    } else if (xhr.status === 401) {
      $("fw-msg").textContent = "Wrong OTA password. Nothing was written.";
    } else {
      $("fw-msg").textContent = xhr.responseText || "Upload failed with status " + xhr.status + ".";
    }
  };
  xhr.onerror = () => { $("fw-go").disabled = false; $("fw-msg").textContent = "Connection lost during upload. The old firmware is still active."; };
  $("fw-go").disabled = true;
  $("fw-bar").hidden = false;
  $("fw-bar").value = 0;
  $("fw-msg").textContent = "Uploading " + file.name + "...";
  xhr.send(body);
});
</script>
)HTML";
