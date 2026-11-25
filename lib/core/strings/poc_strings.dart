/// User-facing text for the POC, kept in one place.
///
/// The real app would use its ARB localization instead.
abstract final class PocStrings {
  static const appTitle = 'Agora POC';

  // Home (stand-in for the rest of the app)
  static const homeTitle = 'QiSpine (POC)';
  static const homeStartCall = 'Start a video consultation';
  static const homeStartCallHint =
      'Pick your name and role, test your device, then join.';
  static const homeOngoingCall = 'Call in progress';
  static const homeReturnToCall = 'Return to call';
  static const homeBrowseHint =
      'Minimise the call and scroll here to test the floating window.';
  static const homeSampleItems = [
    'Today\'s exercises',
    'Pain diary',
    'Upcoming appointments',
    'Care plan',
    'Reports',
    'Help & support',
  ];

  // Pre-call
  static const preCallTitle = 'Get ready';
  static const yourName = 'Your name';
  static const channel = 'Room (channel)';
  static const tokenField = 'Token';
  static const tokenPaste = 'Paste token';
  static const tokenReset = 'Use built-in token';
  static const tokenSavedHint =
      'Pasted token, saved on this phone. Valid 24 h, only for this room.';
  static const tokenBuiltInHint =
      'Built-in token. When it expires, paste a new one from the Agora '
      'console (Generate temp token, same room name).';
  static const tokenClipboardEmpty = 'Clipboard has no text to paste.';
  static const preCallBlockedByCall =
      'You are already in a call. Leave it before starting a new one.';
  static const roleGuest = 'Patient';
  static const roleHost = 'Doctor (host)';
  static const sectionDevice = 'Check your device';
  static const sectionCall = 'Call settings';
  static const echoTest = 'Test mic & speaker';
  static const echoTestRunning =
      'Speak now — you\'ll hear yourself after 3 s. Tap to stop.';
  static const networkTest = 'Test network';
  static const networkTestRunning = 'Testing… takes about 30 s';
  static const quality = 'Video quality';
  static const noiseSuppression = 'AI noise suppression';
  static const noiseSuppressionHint = 'Paid Agora add-on';
  static const blur = 'Blur background';
  static const blurUnsupported = 'Not supported on this device';
  static const beauty = 'Beauty filter';
  static const encryption = 'Encrypt call';
  static const encryptionHint =
      'Everyone must use the same passphrase. Web demo can\'t join.';
  static const passphrase = 'Passphrase';
  static const join = 'Join call';
  static const startMuted = 'Mic';
  static const startCameraOff = 'Camera';
  static const preparing = 'Starting camera…';
  static const notConfigured =
      'Agora is not configured. Run with --dart-define-from-file=agora.local.json';
  static const permissionDenied =
      'Camera and microphone access are needed to join.';
  static const permissionPermanentlyDenied =
      'Camera or microphone is blocked. Allow it in Settings.';
  static const engineError = 'The video engine could not start.';

  // Call
  static const statusJoining = 'Joining…';
  static const joinSlow = 'No connection yet. Still trying…';
  static const cancelJoin = 'Cancel';
  static const ongoingCallTitle = 'Video consultation in progress';
  static const ongoingCallText = 'Tap to return to the call';
  static const statusInCall = 'In call';
  static const statusReconnecting = 'Reconnecting…';
  static const statusEnded = 'Call ended';
  static const statusFailed = 'Call failed';
  static const tokenUnavailable = 'Could not get a token from the server.';
  static const tokenExpired = 'The token expired and could not be renewed.';
  static const connectionFailed =
      'Could not connect to the call. Check your internet and try again.';
  static const tokenRejected =
      'This call link has expired or is not valid for this room.';
  static const removedByHost = 'The host removed you from the call.';
  static const tokenExpiring = 'Renewing access…';
  static const sharingScreen = 'You are sharing your screen';
  static const stopSharing = 'Stop';
  static const waitingForOthers = 'Waiting for others to join…';
  static const you = 'You';
  static const screenOf = 'Screen';
  static const videoFrozen = 'Video frozen';
  static const connectingVideo = 'Connecting video…';
  static const slowUploadWhileSharing =
      'Your connection is slow — your screen may freeze for others';
  static const encrypted = 'Encrypted';
  static const recording = 'REC';

  // Controls
  static const mute = 'Mute';
  static const unmute = 'Unmute';
  static const cameraOff = 'Stop video';
  static const cameraOn = 'Start video';
  static const speaker = 'Speaker';
  static const earpiece = 'Earpiece';
  static const soundOff = 'Sound off';
  static const audioSpeakerOption = 'Speaker';
  static const audioEarpieceOption = 'Phone';
  static const audioOffOption = 'Turn off sound';
  static const chat = 'Chat';
  static const more = 'More';
  static const leave = 'Leave';
  static const minimise = 'Minimise';

  // More sheet
  static const switchCamera = 'Flip camera';
  static const shareScreen = 'Share screen';
  static const shareScreenUnsupported = 'Needs an iOS extension (not in POC)';
  static const raiseHand = 'Raise hand';
  static const lowerHand = 'Lower hand';
  static const gridView = 'Grid view';
  static const speakerView = 'Speaker view';
  static const participants = 'People';
  static const snapshot = 'Snapshot';
  static const record = 'Record';
  static const stopRecording = 'Stop rec';
  static const stats = 'Stats';
  static const eventLog = 'Event log';
  static const audioOnly = 'Audio only';
  static const muteEveryone = 'Mute all';
  static const hostOnlyNote =
      'Host actions are demo-grade: a real app must enforce them on the server.';

  // Participants sheet
  static const pin = 'Pin';
  static const unpin = 'Unpin';
  static const askToMute = 'Ask to mute';
  static const removeFromCall = 'Remove from call';
  static const recordThisPerson = 'Record on this phone';

  // Chat
  static const chatHint = 'Message everyone';
  static const chatEmpty = 'No messages yet. Messages are not saved.';
  static const send = 'Send';

  // Mute request
  static const muteRequestTitle = 'Host asks you to mute';
  static const muteRequestAccept = 'Mute';
  static const muteRequestIgnore = 'Not now';

  // Results
  static const retry = 'Try again';
  static const rejoin = 'Rejoin';
  static const openSettings = 'Open Settings';
  static const backHome = 'Back to home';
  static const callLasted = 'Call lasted';

  // Quality sheet
  static const qualityBillingNote =
      'Agora bills by the resolution people receive, so higher quality '
      'costs more per minute.';
}
