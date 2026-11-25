# Agora POC

A separate app to try every Agora video feature that needs no extra Agora
product, on real phones, before touching the patient app.
Plugin: agora_rtc_engine 6.6.4 (native SDK 4.6.4).

## 1. One-time setup

1. In the Agora console, open your project and copy the **App ID** and the
   **Primary App Certificate**.
2. Token server (keeps the certificate on your laptop, like a real backend):
   ```
   cd token_server
   npm install
   copy secrets.local.example.json secrets.local.json   # paste App ID + certificate
   npm start
   ```
   It prints the addresses phones can use.
3. App config: copy `agora.local.example.json` to `agora.local.json` and fill
   in the App ID and `AGORA_TOKEN_SERVER_URL`:
   - USB Android phone: `http://127.0.0.1:8080`, then run `adb reverse tcp:8080 tcp:8080`
   - Phones on the same Wi-Fi: the `http://<laptop-ip>:8080` the server printed
   - Set `AGORA_TOKEN_EXPIRY_SECONDS` to `120` to test token renewal mid-call.

Both `secrets.local.json` and `agora.local.json` are git-ignored. Never
commit them or paste the certificate anywhere.

## 2. Run

```
flutter run --dart-define-from-file=agora.local.json
```

iOS needs a Mac: open `ios/Runner.xcworkspace` once to pick a signing team.
Use a real iPhone (PiP doesn't work in the simulator). Screen sharing is
Android-only in this POC (iOS needs a separate Broadcast Upload Extension).

## 3. Adding more people

- **More phones**: install the same build; each gets its own uid and token.
- **Browser tabs** (fastest way to get 4–6 people): open
  `http://localhost:8080/` on the laptop. It shows the App ID, channel, a
  User ID and a token for Agora's web demo
  (https://webdemo.agora.io/basicVideoCall/index.html). Reload it for each tab.
  Web-demo users show as "Guest ####" because they can't send their name.
- Encrypted calls: phones only (the web demo can't use the same key).

## 4. What to test

The event log (More → Event log) records every result with a time.

| # | Test | Pass if |
|---|------|---------|
| 1 | Pre-call: mic & speaker test | You hear yourself ~3 s later |
| 2 | Pre-call: network test | Up/down, loss and RTT shown in ~15–30 s |
| 3 | Blur / beauty / noise suppression on | Effect visible/audible; log shows it |
| 4 | Join 2 people | 1:1 layout, both see and hear each other |
| 5 | Join 3–9 people | Grid; speaking person gets a coloured ring |
| 6 | Speaker view, tap a tile | Pinned person fills the screen |
| 7 | Stats on (More → Stats) | Tiles show resolution/fps/kbps; small tiles say LOW |
| 8 | Mute / video off / flip camera 10× | Others see mic-off icon, avatar, no "Video frozen" |
| 9 | Chat between phones | Messages arrive; unread badge on Chat |
| 10 | Raise hand | ✋ shows on that person for everyone |
| 11 | Doctor (host): Ask to mute / Mute all / Remove | Patient gets a prompt / is removed |
| 12 | Share screen (Android) | Others see a "· Screen" tile, camera keeps going |
| 13 | Snapshot, Record 10 s | Files saved (path shown); pull with adb |
| 14 | Quality → Low / Full HD | Others' stats change resolution |
| 15 | Audio only | Everyone's video stops arriving, audio continues |
| 16 | Minimise (↓ or Back) | Floating window over Home; drag it; tap to return |
| 17 | Press Home | System PiP with live video |
| 18 | Wi-Fi off 10 s, then on | "Reconnecting…" banner, then back, no rejoin |
| 19 | Token expiry 120 s | "Token renewed" in log, call carries on |
| 20 | Encrypted call, 2 phones, same passphrase | Works; a wrong passphrase sees/hears nothing |

## Results so far (Samsung SM-M055F Android 14 + Android 16 emulator, 2026-11-21)

Working: pre-call preview, network test (RTT 34 ms, 0% loss), blur, join in
~150–250 ms, names/presence between devices, snapshot, recording (MP4),
Android screen share, floating window, system PiP, leave.

Screen share on a slow upload (emulator limited to 400 kbps up, 150 ms):
- Before tuning: screen stream starved to ~4 kbps; camera 180×320 at 5 fps.
- After tuning (540×960 cap, 10 fps, 600 kbps, keep-resolution, camera to
  Low while sharing): screen ~72–90 kbps at 5–8 fps. Choppy but alive.
- Shared screens now fit (letterbox) instead of crop, open in speaker view
  automatically, and support pinch-to-zoom (zoom not tested: adb can't pinch).
- "Video frozen" shows only after 2 s, never for screen shares (a still
  screen sends almost no frames, which Agora reports as "frozen").
- New joiners show initials + spinner until the first frame (was a grey box).
- Landscape: wide grid shapes, speaker view thumbnails on the right,
  icon-only control bar.

Ruled out: Android did not block camera/mic while the sharer was in another
app (both stayed "running" on phone and emulator).

Known limits:
- System dialogs (e.g. the screen-share consent) make the app "inactive",
  the same signal used for PiP. Agora's own example notes the notification
  shade and Recents screen do this too.
- The floating window returns to its default corner after system PiP.
- The emulator's display broke during long screen capture (emulator bug), so
  the slow-upload test still needs repeating with a real phone as sharer on
  real mobile data.

Not yet tested: token server (needs App Certificate), echo test, token
renewal, encryption, chat/host actions between two phones, 3+ people.

## Code layout

```
lib/features/call/
  domain/        Interfaces (CallEngine, MediaEffects, CallMessaging,
                 CallCapture, PreCallTests, PipService, TokenProvider)
                 and the in-call message format. No Agora types.
  data/agora/    One Agora adapter per interface, sharing one engine host
  data/          Token server client, permissions
  presentation/  Riverpod controllers (call, pre-call, chat, stats,
                 speaking, capture, media settings, log), layout rules,
                 screens, widgets, sheets
token_server/    Node token server (official agora-token 2.0.7)
```

Only `data/agora/` and `presentation/video/` import Agora. To try another
vendor, write new adapters and override the providers in `call_providers.dart`.

Tests: `flutter test` (58 tests: controllers, layout rules, message format,
token client).
