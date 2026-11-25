// Local Agora token server for the POC.
//
// Stands in for the backend that would issue tokens in the real app: the App
// Certificate stays on this machine and devices only ever receive tokens.
//
// Usage:  node server.js            (reads token_server/secrets.local.json)
//
// Endpoints:
//   GET /rtc-token?channel=<name>&uid=<int>[&expire=<seconds>]  -> JSON
//   GET /                                                        -> web page
//       that makes a token for Agora's web demo (one per browser tab)

'use strict';

const fs = require('fs');
const http = require('http');
const os = require('os');
const path = require('path');
const { RtcTokenBuilder, RtcRole } = require('agora-token');

const PORT = Number(process.env.PORT || 8080);
const DEFAULT_EXPIRE_SECONDS = 3600;
const MIN_EXPIRE_SECONDS = 60;
const MAX_EXPIRE_SECONDS = 24 * 3600;
const MAX_UID = 2 ** 32 - 1;
// Agora's allowed channel-name characters, max 64 bytes.
const CHANNEL_PATTERN = /^[a-zA-Z0-9 !#$%&()+\-:;<=.>?@[\]^_{|}~,]{1,64}$/;
const WEB_DEMO_URL = 'https://webdemo.agora.io/basicVideoCall/index.html';

function loadSecrets() {
  const file = path.join(__dirname, 'secrets.local.json');
  if (!fs.existsSync(file)) {
    throw new Error(
      `Missing ${file}. Copy secrets.local.example.json and fill in the App ID and App Certificate.`,
    );
  }
  const secrets = JSON.parse(fs.readFileSync(file, 'utf8'));
  for (const key of ['AGORA_APP_ID', 'AGORA_APP_CERTIFICATE']) {
    if (!secrets[key] || secrets[key].startsWith('paste-')) {
      throw new Error(`${key} is not set in ${file}`);
    }
  }
  return secrets;
}

function parseRequest(query) {
  const channel = query.get('channel') || '';
  if (!CHANNEL_PATTERN.test(channel)) {
    return { error: 'channel is missing or has characters Agora does not allow' };
  }
  const uidText = query.get('uid') || '';
  const uid = Number(uidText);
  if (!/^\d+$/.test(uidText) || uid > MAX_UID) {
    return { error: `uid must be an integer from 0 to ${MAX_UID}` };
  }
  const expireText = query.get('expire');
  const expire = expireText === null ? DEFAULT_EXPIRE_SECONDS : Number(expireText);
  if (!Number.isInteger(expire) || expire < MIN_EXPIRE_SECONDS || expire > MAX_EXPIRE_SECONDS) {
    return { error: `expire must be ${MIN_EXPIRE_SECONDS}-${MAX_EXPIRE_SECONDS} seconds` };
  }
  return { channel, uid, expire };
}

function buildToken(secrets, { channel, uid, expire }) {
  return RtcTokenBuilder.buildTokenWithUid(
    secrets.AGORA_APP_ID,
    secrets.AGORA_APP_CERTIFICATE,
    channel,
    uid,
    RtcRole.PUBLISHER,
    expire,
    expire,
  );
}

function escapeHtml(text) {
  return String(text).replace(/[&<>"']/g, (c) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  })[c]);
}

function webDemoPage(secrets, channel, uid, token) {
  return `<!doctype html><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Agora POC token</title>
<style>body{font:15px system-ui;max-width:720px;margin:24px auto;padding:0 16px}
code{display:block;word-break:break-all;background:#eee;padding:8px;border-radius:6px;margin:4px 0 12px}</style>
<h2>Token for Agora's web demo</h2>
<p>Open the <a href="${WEB_DEMO_URL}" target="_blank">web demo</a> and paste these.
Reload this page for another browser tab (each tab needs its own User ID).</p>
<b>APP ID</b><code>${escapeHtml(secrets.AGORA_APP_ID)}</code>
<b>Channel Name</b><code>${escapeHtml(channel)}</code>
<b>User ID</b><code>${uid}</code>
<b>Token</b> (1 hour)<code>${escapeHtml(token)}</code>`;
}

function sendJson(res, status, body) {
  res.writeHead(status, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(body));
}

function lanAddresses() {
  return Object.values(os.networkInterfaces())
    .flat()
    .filter((i) => i && i.family === 'IPv4' && !i.internal)
    .map((i) => i.address);
}

function main() {
  const secrets = loadSecrets();
  const defaultChannel = secrets.AGORA_CHANNEL || 'qispine-poc';

  const server = http.createServer((req, res) => {
    const url = new URL(req.url, 'http://localhost');
    const started = new Date().toISOString().slice(11, 19);

    if (url.pathname === '/rtc-token') {
      const parsed = parseRequest(url.searchParams);
      if (parsed.error) {
        console.log(`${started} 400 ${parsed.error}`);
        return sendJson(res, 400, { error: parsed.error });
      }
      const token = buildToken(secrets, parsed);
      const expiresAt = Math.floor(Date.now() / 1000) + parsed.expire;
      console.log(`${started} token channel=${parsed.channel} uid=${parsed.uid} expire=${parsed.expire}s`);
      return sendJson(res, 200, { token, uid: parsed.uid, channel: parsed.channel, expiresAt });
    }

    if (url.pathname === '/') {
      const channel = url.searchParams.get('channel') || defaultChannel;
      if (!CHANNEL_PATTERN.test(channel)) return sendJson(res, 400, { error: 'bad channel' });
      // Range for web-demo users, kept well apart from the app's random uids
      // only for readability in logs; Agora just needs them unique.
      const uid = 1000 + Math.floor(Math.random() * 9000);
      const token = buildToken(secrets, { channel, uid, expire: DEFAULT_EXPIRE_SECONDS });
      console.log(`${started} web-demo token channel=${channel} uid=${uid}`);
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      return res.end(webDemoPage(secrets, channel, uid, token));
    }

    sendJson(res, 404, { error: 'not found' });
  });

  server.listen(PORT, '0.0.0.0', () => {
    console.log(`Agora POC token server on port ${PORT}`);
    console.log(`  This laptop:         http://localhost:${PORT}/`);
    for (const ip of lanAddresses()) {
      console.log(`  Phones on same Wi-Fi: http://${ip}:${PORT}`);
    }
    console.log(`  USB Android phone:   run "adb reverse tcp:${PORT} tcp:${PORT}", then use http://127.0.0.1:${PORT}`);
  });
}

main();
