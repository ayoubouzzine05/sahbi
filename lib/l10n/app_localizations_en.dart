// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class L10nEn extends L10n {
  L10nEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Sahbi';

  @override
  String get tabHome => 'Sahbi';

  @override
  String get tabChat => 'Chat';

  @override
  String get tabMusic => 'Music';

  @override
  String get tabSettings => 'Settings';

  @override
  String get tapToTalk => 'Tap to talk';

  @override
  String get holdHint => 'or hold';

  @override
  String get stateIdle => 'Ready';

  @override
  String get stateListening => 'Listening…';

  @override
  String get stateThinking => 'Thinking…';

  @override
  String get stateSpeaking => 'Speaking…';

  @override
  String get stateError => 'Error';

  @override
  String get phaseSearching => 'Searching the web…';

  @override
  String get phaseWeather => 'Checking the weather…';

  @override
  String get phaseRetrying => 'Retrying…';

  @override
  String get phaseWaking => 'Just a moment…';

  @override
  String get stopListening => 'Stop listening';

  @override
  String get interruptSpeech => 'Interrupt';

  @override
  String get typeMessage => 'Message Sahbi…';

  @override
  String get send => 'Send';

  @override
  String get micOn => 'Mic on';

  @override
  String get offlineBanner =>
      'Offline: AI answers, search and cloud voice are unavailable';

  @override
  String get backendNotSetBanner =>
      'Server not configured. Add its URL in Settings.';

  @override
  String get aiNotConfiguredBanner => 'My brain is not working right now';

  @override
  String get serverUnreachableBanner =>
      'I can’t connect right now, try again in a moment';

  @override
  String get aiDisabledBanner => 'Sending to AI is turned off (Privacy)';

  @override
  String get errNoInternet => 'No internet';

  @override
  String get errNotConfigured => 'AI not configured';

  @override
  String get errServer => 'Something went wrong, try again in a moment';

  @override
  String get errTimeout => 'Timed out, try again';

  @override
  String get errRateLimited => 'Too many requests, wait a moment';

  @override
  String get errInvalidOutput => 'Invalid reply, try again';

  @override
  String get errUnauthorized => 'Authentication error';

  @override
  String get errBadRequest => 'Bad request';

  @override
  String get labelOffline => 'Pre-written reply (offline)';

  @override
  String get labelCommand => 'Local command';

  @override
  String get retry => 'Retry';

  @override
  String get copy => 'Copy';

  @override
  String get copied => 'Copied';

  @override
  String get replay => 'Replay';

  @override
  String get sourcesConfirmed => 'Confirmed by several sources';

  @override
  String get sourcesUnconfirmed => 'Not confirmed / sources disagree';

  @override
  String get sourceData => 'Data source';

  @override
  String get internetNeeded => 'Internet needed for this';

  @override
  String get searchUnavailable => 'Web search unavailable; answer not verified';

  @override
  String get translation => 'Translation';

  @override
  String get micRationaleTitle => 'Sahbi would like to hear you';

  @override
  String get micRationaleBody =>
      'I only use the microphone when you tap to talk. Audio is not kept. An indicator shows whenever the mic is on.';

  @override
  String get micAllow => 'Allow';

  @override
  String get micNotNow => 'Not now';

  @override
  String get micDenied => 'Without the mic you can type to me';

  @override
  String get micPermanentlyDenied =>
      'Microphone blocked. Enable it in app settings.';

  @override
  String get openAppSettings => 'Open settings';

  @override
  String get noRecognizer => 'No speech recognizer on this phone; please type';

  @override
  String get providerCloud => 'Cloud voice';

  @override
  String get providerDevice => 'On-device voice';

  @override
  String get providerTyped => 'Typed input';

  @override
  String get providerOff => 'Off';

  @override
  String get musicTitle => 'Music';

  @override
  String get addFiles => 'Add files';

  @override
  String get addFolder => 'Add folder';

  @override
  String get demoTracks => 'Demo tracks (CC0)';

  @override
  String get myTracks => 'My tracks';

  @override
  String get noTracks => 'Nothing yet. Add tracks from your phone.';

  @override
  String get nothingPlaying => 'Nothing playing';

  @override
  String get outputDevice => 'Audio output';

  @override
  String get outputUnknown => 'Unknown';

  @override
  String get outputSpeaker => 'Phone speaker';

  @override
  String get outputBluetooth => 'Bluetooth';

  @override
  String get outputWired => 'Wired headset';

  @override
  String get outputUsb => 'USB';

  @override
  String get openOutputSwitcher => 'Switch output';

  @override
  String get outputSwitcherUnavailable =>
      'Could not open the output switcher on this phone';

  @override
  String get outputPanelMaybe => 'If no panel opened, use Bluetooth settings';

  @override
  String get openBluetoothSettings => 'Bluetooth settings';

  @override
  String get outputNote =>
      'Sahbi plays to the current Android output. Switching speakers happens in the system panel.';

  @override
  String get streamingTitle => 'Spotify & YouTube Music';

  @override
  String get streamingSearchHint => 'What do you want to hear?';

  @override
  String get openSpotify => 'Open in Spotify';

  @override
  String get openYouTubeMusic => 'Open in YouTube Music';

  @override
  String get streamingNote =>
      'Opened via deep links. Spotify App Remote control is not configured, and YouTube Music has no public playback-control API.';

  @override
  String get prevTrack => 'Previous';

  @override
  String get nextTrack => 'Next';

  @override
  String get stopPlayback => 'Stop';

  @override
  String get removeTrack => 'Remove';

  @override
  String get systemVolume => 'Media volume';

  @override
  String get notificationsDenied =>
      'Notifications denied: playback works but without notification controls';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get secLanguage => 'Language';

  @override
  String get uiLanguage => 'App language';

  @override
  String get replyLanguage => 'Reply language';

  @override
  String get langDarija => 'Darija';

  @override
  String get langArabic => 'Arabic';

  @override
  String get langFrench => 'French';

  @override
  String get langEnglish => 'English';

  @override
  String get darijaScript => 'Darija script';

  @override
  String get scriptArabic => 'Arabic script';

  @override
  String get scriptLatin => 'Latin (3, 7, 9)';

  @override
  String get secVoice => 'Voice';

  @override
  String get sttProvider => 'Speech recognition';

  @override
  String get ttsProvider => 'Sahbi’s voice';

  @override
  String get modeAuto => 'Auto';

  @override
  String get modeCloud => 'Cloud';

  @override
  String get modeDevice => 'On-device';

  @override
  String get modeTyped => 'Typing only';

  @override
  String get modeOff => 'Off';

  @override
  String get activeNow => 'Active now';

  @override
  String get deviceVoice => 'Device voice';

  @override
  String get defaultVoice => 'Default';

  @override
  String get cloudVoice => 'Cloud voice';

  @override
  String get speechRate => 'Speed';

  @override
  String get pitch => 'Pitch';

  @override
  String get testVoice => 'Test voice';

  @override
  String get testVoiceText => 'Hi! I am Sahbi, how are you?';

  @override
  String get darijaQualityNote =>
      'Darija recognition quality has not been measured; it depends on the device and engine.';

  @override
  String get tapFaceToTalk => 'Tap face to talk';

  @override
  String get wakeWord => 'Wake phrase “Ya Sahbi”';

  @override
  String get wakeWordUnavailable =>
      'Not available in this build (needs a licensed on-device engine)';

  @override
  String get secAi => 'AI';

  @override
  String get backendUrl => 'Backend URL';

  @override
  String get configured => 'Configured';

  @override
  String get notConfigured => 'Not configured';

  @override
  String get lastHealthCheck => 'Last check';

  @override
  String get checkNow => 'Check now';

  @override
  String get never => 'Never';

  @override
  String get serviceLlm => 'AI answers';

  @override
  String get serviceSearch => 'Search';

  @override
  String get serviceWeather => 'Weather';

  @override
  String get serviceStt => 'Cloud STT';

  @override
  String get serviceTts => 'Cloud TTS';

  @override
  String get secInternet => 'Internet';

  @override
  String get online => 'Online';

  @override
  String get offline => 'Offline';

  @override
  String get networkOnly => 'Network is there, but I can’t connect';

  @override
  String get secMusic => 'Music';

  @override
  String get bluetoothStatus => 'Bluetooth';

  @override
  String get btConnectedOutput => 'Bluetooth audio connected';

  @override
  String get btNotOutput => 'Audio is not on Bluetooth';

  @override
  String get secMemory => 'Memory';

  @override
  String get memoryOffLabel => 'Off';

  @override
  String get memoryOnLabel => 'On';

  @override
  String get secPrivacy => 'Privacy';

  @override
  String get secPersonality => 'Personality';

  @override
  String get humor => 'Humour';

  @override
  String get formality => 'Tone';

  @override
  String get casual => 'Casual';

  @override
  String get polite => 'Polite';

  @override
  String get userName => 'What should I call you?';

  @override
  String get idleBehavior => 'Idle behaviour';

  @override
  String get secRobot => 'Robot (experimental)';

  @override
  String get robotExperimental => 'Enable experimental robot link';

  @override
  String get secAbout => 'About';

  @override
  String get licenses => 'Licences';

  @override
  String get version => 'Version';

  @override
  String get debugUnlocked => 'Debug screen unlocked';

  @override
  String get debugTitle => 'Debug';

  @override
  String get privacyTitle => 'Privacy';

  @override
  String get sendToAi => 'Send messages to the AI';

  @override
  String get cloudVoiceToggle => 'Cloud voice (STT/TTS)';

  @override
  String get micIndicator => 'Mic indicator: always shown';

  @override
  String get analyticsOff => 'No analytics';

  @override
  String get whatLeaves => 'What leaves the phone';

  @override
  String get privChat =>
      'Chat: your message text, recent turns and reply settings go to your server and then the AI provider. The server stores nothing.';

  @override
  String get privSearch =>
      'Search: queries chosen by the AI go to the search provider (Brave). Weather: the city name goes to Open-Meteo.';

  @override
  String get privVoice =>
      'Voice: in cloud mode your audio and text go via your server to the provider (Azure/OpenAI), not stored. In on-device mode Android’s engine handles it (which may itself use the cloud depending on the device).';

  @override
  String get privMemory =>
      'Memory: stays on the phone, encrypted. Remembered facts are sent with messages only if you consented.';

  @override
  String get privMusic =>
      'Music: your files stay on the phone. When you ask for a song you don\'t have, its name goes to the server to search YouTube, and it plays here in YouTube\'s official player. Spotify opens in its own app.';

  @override
  String get memoryTitle => 'Memory';

  @override
  String get consentTitle => 'Should I remember things?';

  @override
  String get consentBody =>
      'Memory stays on this phone, encrypted. You can view, edit, delete or export everything at any time. Remembered facts are sent to the AI with your messages so it knows you.';

  @override
  String get rememberFacts =>
      'Remember facts I tell you (e.g. “remember that I like tea”)';

  @override
  String get rememberHistory => 'Keep chat history';

  @override
  String get saveConsent => 'Save';

  @override
  String get addFact => 'Add fact';

  @override
  String get editItem => 'Edit';

  @override
  String get deleteItem => 'Delete';

  @override
  String get deleteAll => 'Delete everything';

  @override
  String get deleteAllConfirm =>
      'Sure? Everything will be erased, including the encryption key.';

  @override
  String get exportJson => 'Export JSON';

  @override
  String get exported => 'Exported';

  @override
  String get exportCancelled => 'Export cancelled';

  @override
  String get noMemories => 'Nothing stored';

  @override
  String get factsTab => 'Facts';

  @override
  String get historyTab => 'History';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get memoryUnreadable =>
      'Could not read the old memory (bad key or file). Starting fresh.';

  @override
  String get robotTitle => 'Robot link';

  @override
  String get robotNotice =>
      'No physical robot exists yet. This screen tests the protocol with a simulated robot. BLE and Wi-Fi are skeletons for later.';

  @override
  String get transportLocal => 'This phone';

  @override
  String get transportSim => 'Simulated robot';

  @override
  String get transportBle => 'Bluetooth LE';

  @override
  String get transportWifi => 'Wi-Fi';

  @override
  String get connect => 'Connect';

  @override
  String get disconnect => 'Disconnect';

  @override
  String get connected => 'Connected';

  @override
  String get disconnected => 'Disconnected';

  @override
  String get connecting => 'Connecting…';

  @override
  String get failed => 'Failed';

  @override
  String get bleNotBundled => 'No BLE engine in this build';

  @override
  String get wifiUrl => 'WebSocket URL';

  @override
  String get simulateTouch => 'Simulate touch';

  @override
  String get ping => 'Ping';

  @override
  String get btPermissionsDenied => 'Bluetooth permissions denied';

  @override
  String get providerHealth => 'Service health';

  @override
  String get lastErrors => 'Last errors';

  @override
  String get clear => 'Clear';

  @override
  String get noErrors => 'No errors';

  @override
  String get chipHello => 'Salam Sahbi';

  @override
  String get newChat => 'New chat';

  @override
  String get emptyChat => 'Say something!';

  @override
  String get listeningHint => 'Speak now…';

  @override
  String get liveTitle => 'Live camera';

  @override
  String get liveConnecting => 'Connecting…';

  @override
  String get liveHint => 'Show me something and ask about it';

  @override
  String get liveReconnecting => 'Reconnecting…';

  @override
  String get liveNotConfigured => 'The live camera is not working right now.';

  @override
  String get liveError => 'Could not start the live camera.';

  @override
  String get liveEnded => 'Session ended.';

  @override
  String get liveTimeLimit =>
      'Session stopped after 10 minutes to save the free quota. Start again if you like.';

  @override
  String get liveRetry => 'Retry';

  @override
  String get liveMute => 'Mute mic';

  @override
  String get liveUnmute => 'Unmute mic';

  @override
  String get liveSwitchCamera => 'Switch camera';

  @override
  String get liveEnd => 'End';

  @override
  String get liveNoCamera => 'No camera found on this phone.';

  @override
  String get liveNeedsInternet => 'Live camera needs the internet.';

  @override
  String get cameraRationaleTitle => 'Shall I look with you?';

  @override
  String get cameraRationaleBody =>
      'To see what you show me and understand you, I need the camera and microphone. Images and sound are sent only during the session to be understood; the app keeps nothing.';

  @override
  String get cameraDenied =>
      'Without camera and mic I can’t see. You can allow them in Settings.';

  @override
  String get openCamera => 'Camera';

  @override
  String get robotNameTitle => 'Robot name';

  @override
  String get robotNameHint => 'e.g. Zizou, Bobo… (empty = Sahbi)';

  @override
  String get robotNameDialogTitle => 'What do you want to call me?';

  @override
  String robotNameSaved(String name) {
    return 'Got it, my name is $name!';
  }

  @override
  String get voiceGenderTitle => 'Robot voice';

  @override
  String get voiceMale => 'Male';

  @override
  String get voiceFemale => 'Female';

  @override
  String get voiceGenderNote =>
      'The server voice (Gemini) changes right away. The phone voice depends on installed voices: if none is male, the pitch is lowered a little.';

  @override
  String get wakeByNameTitle => 'Answer when called by name';

  @override
  String wakeByNameSubtitle(String name) {
    return 'Only while the app is open. Say “$name” (or “$name, what’s the weather?”) without tapping. Uses some battery; some phones beep each time listening restarts.';
  }

  @override
  String get wakeByNameNoMic => 'Allow the microphone so I can hear my name.';

  @override
  String wakeListening(String name) {
    return 'Waiting for my name: $name';
  }

  @override
  String get keepScreenOn => 'Keep the screen on for the face';

  @override
  String get photoModeHint =>
      'Live video isn’t available right now. Point the camera at something and tap 📸 — I’ll explain it.';

  @override
  String get photoSnap => 'Take photo and explain';

  @override
  String get photoQuestion =>
      'What is this? Explain what you see in this photo.';

  @override
  String get photoThinking => 'Looking…';

  @override
  String get photoError =>
      'Couldn’t explain the photo right now. Try again later.';

  @override
  String ytSearching(String query) {
    return 'Searching YouTube for: $query…';
  }

  @override
  String get ytError => 'None of these videos can play here. Try another song.';

  @override
  String get ytNext => 'Next';

  @override
  String get ytClose => 'Close';

  @override
  String photosCaption(String source) {
    return 'Photos: $source. Tap to enlarge.';
  }

  @override
  String get photoOpenPage => 'Author & licence';

  @override
  String get photoFailed => 'Photo could not load';

  @override
  String photosFor(String query) {
    return 'Photos: $query';
  }

  @override
  String get proactiveTitle => 'Talk to me when I\'m quiet';

  @override
  String get proactiveSubtitle =>
      'Jokes, riddles and questions every few minutes while the app is open. After 10 minutes without an answer I go to sleep until you call my name. Each line uses one AI request.';

  @override
  String sleepingHint(String name) {
    return 'Sleeping… call “$name” to wake me up';
  }

  @override
  String get sleepingHintTap => 'Sleeping… tap to wake me up';

  @override
  String get conversationOn => 'I\'m with you — say “safi sir” to stop';

  @override
  String get conversationEnd => 'End conversation';

  @override
  String get liveAutoDescribe => 'Explain what I point at';

  @override
  String get liveAutoDescribeHint =>
      'Point the camera at something and hold it still';

  @override
  String get ytPlay => 'Play';

  @override
  String get ytPause => 'Pause';

  @override
  String get liveTapHint => 'Tap an object or point at it with your finger';

  @override
  String get pointLooking => 'Looking at what you point at…';

  @override
  String get pointNotFound =>
      'I can’t find anything there, tap right on the object';

  @override
  String pointQuestion(String label) {
    return 'What is this thing I’m pointing at ($label)? Talk only about this object.';
  }

  @override
  String get shakeTitle => 'Shake the phone';

  @override
  String get shakeSubtitle =>
      'Shake the phone and it gets dizzy; keep going and it gets annoyed with you. Works offline.';

  @override
  String get eyesOpen => 'Open his eyes (he can see)';

  @override
  String get eyesClose => 'Close his eyes (he can’t see)';

  @override
  String get eyesRationaleTitle => 'Can I see you?';

  @override
  String get eyesRationaleBody =>
      'I want to see like a real robot: my eyes follow movement, and when you show me something I react (scared, happy, amazed…). I use the front camera only while my face is on screen. A small picture goes to the AI only when you show me something new; the app keeps nothing. You can close my eyes with the eye button.';

  @override
  String get eyesSettingTitle => 'Robot eyes';

  @override
  String get eyesSettingSubtitle =>
      'Front camera while the face is on screen: the eyes follow movement and he reacts to what you show him.';

  @override
  String get eyesDenied =>
      'To see, he needs the camera. You can allow it in the phone settings.';

  @override
  String get micOnTip => 'Microphone on — tap to turn off';

  @override
  String get micOffTip => 'Microphone off — tap to turn on';

  @override
  String get cameraOnTip => 'Camera on — tap to turn off';

  @override
  String get cameraOffTip => 'Camera off — tap to turn on';

  @override
  String get micOffTitle => 'Microphone is off';

  @override
  String get micOffBody =>
      'MIMO can\'t hear anything right now. Turn the microphone on?';

  @override
  String get micTurnOn => 'Turn microphone on';

  @override
  String get cameraOffTitle => 'Camera is off';

  @override
  String get cameraOffBody =>
      'MIMO can\'t see anything right now. Turn the camera on?';

  @override
  String get cameraTurnOn => 'Turn camera on';

  @override
  String get wakeNoticeTitle => 'MIMO is listening';

  @override
  String get wakeNoticeText =>
      'Say \"MIMO\" to talk to it. Nothing is recorded.';

  @override
  String get wakeNoticeStop => 'Stop MIMO';

  @override
  String get wakeNoticeOpen => 'Open';

  @override
  String get wakeChannelName => 'MIMO listening for its name';

  @override
  String get settingsMicTitle => 'Microphone';

  @override
  String get settingsMicSubtitle =>
      'Off = it hears nothing: no \"MIMO\", no talking. You can still type.';

  @override
  String get settingsCameraTitle => 'Camera';

  @override
  String get wakeModelTitle => 'Offline \"MIMO\" wake word';

  @override
  String get wakeModelMissing =>
      'To hear its name even when minimised: one-time download (42 MB), then it works offline.';

  @override
  String get wakeModelDownload => 'Download (42 MB)';

  @override
  String wakeModelDownloading(int percent) {
    return 'Downloading… $percent%';
  }

  @override
  String get wakeModelReady =>
      'Ready: hears \"MIMO\" offline, even when minimised.';

  @override
  String get wakeModelFailed =>
      'Download failed. Check the internet and try again.';

  @override
  String get wakeModelRetry => 'Try again';

  @override
  String get wakeStartFailed =>
      'Could not start listening. Open the app and try again.';

  @override
  String get wakeStoppedNotice =>
      'MIMO stopped from the notification: microphone turned off.';

  @override
  String get quietHoursTitle => 'Quiet hours';

  @override
  String quietHoursValue(String start, String end) {
    return '$start to $end: it won\'t start talking by itself';
  }

  @override
  String get silenceTitle => 'Silence that ends a conversation';

  @override
  String silenceValue(int seconds) {
    return '$seconds s (or \"safi sir\")';
  }

  @override
  String get gamesTitle => 'Play with MIMO';

  @override
  String get gameRiddle => 'Riddle';

  @override
  String get gameTrivia => 'Trivia';

  @override
  String get gameReaction => 'Reaction game';

  @override
  String get gamesHint => 'Or say: “let’s play” or “riddle”';

  @override
  String get reactionWait => 'Wait until my eyes turn green…';

  @override
  String get reactionNow => 'Now! Tap!';

  @override
  String get reactionEarly => 'Too early! Again';

  @override
  String reactionResult(int ms) {
    return '$ms ms';
  }

  @override
  String get gameClose => 'Stop the game';

  @override
  String get behaviorTitle => 'Talks on its own';

  @override
  String get behaviorSubtitle =>
      'Short remarks, riddles and games, with cooldowns (never in quiet hours).';
}
