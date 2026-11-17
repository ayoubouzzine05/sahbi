import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';
import 'app_localizations_fr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of L10n
/// returned by `L10n.of(context)`.
///
/// Applications need to include `L10n.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: L10n.localizationsDelegates,
///   supportedLocales: L10n.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the L10n.supportedLocales
/// property.
abstract class L10n {
  L10n(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static L10n of(BuildContext context) {
    return Localizations.of<L10n>(context, L10n)!;
  }

  static const LocalizationsDelegate<L10n> delegate = _L10nDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en'),
    Locale('fr'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Sahbi'**
  String get appTitle;

  /// No description provided for @tabHome.
  ///
  /// In en, this message translates to:
  /// **'Sahbi'**
  String get tabHome;

  /// No description provided for @tabChat.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get tabChat;

  /// No description provided for @tabMusic.
  ///
  /// In en, this message translates to:
  /// **'Music'**
  String get tabMusic;

  /// No description provided for @tabSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get tabSettings;

  /// No description provided for @tapToTalk.
  ///
  /// In en, this message translates to:
  /// **'Tap to talk'**
  String get tapToTalk;

  /// No description provided for @holdHint.
  ///
  /// In en, this message translates to:
  /// **'or hold'**
  String get holdHint;

  /// No description provided for @stateIdle.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get stateIdle;

  /// No description provided for @stateListening.
  ///
  /// In en, this message translates to:
  /// **'Listening…'**
  String get stateListening;

  /// No description provided for @stateThinking.
  ///
  /// In en, this message translates to:
  /// **'Thinking…'**
  String get stateThinking;

  /// No description provided for @stateSpeaking.
  ///
  /// In en, this message translates to:
  /// **'Speaking…'**
  String get stateSpeaking;

  /// No description provided for @stateError.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get stateError;

  /// No description provided for @phaseSearching.
  ///
  /// In en, this message translates to:
  /// **'Searching the web…'**
  String get phaseSearching;

  /// No description provided for @phaseWeather.
  ///
  /// In en, this message translates to:
  /// **'Checking the weather…'**
  String get phaseWeather;

  /// No description provided for @phaseRetrying.
  ///
  /// In en, this message translates to:
  /// **'Retrying…'**
  String get phaseRetrying;

  /// No description provided for @phaseWaking.
  ///
  /// In en, this message translates to:
  /// **'Waking the server… (up to 1 min)'**
  String get phaseWaking;

  /// No description provided for @stopListening.
  ///
  /// In en, this message translates to:
  /// **'Stop listening'**
  String get stopListening;

  /// No description provided for @interruptSpeech.
  ///
  /// In en, this message translates to:
  /// **'Interrupt'**
  String get interruptSpeech;

  /// No description provided for @typeMessage.
  ///
  /// In en, this message translates to:
  /// **'Message Sahbi…'**
  String get typeMessage;

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @micOn.
  ///
  /// In en, this message translates to:
  /// **'Mic on'**
  String get micOn;

  /// No description provided for @offlineBanner.
  ///
  /// In en, this message translates to:
  /// **'Offline: AI answers, search and cloud voice are unavailable'**
  String get offlineBanner;

  /// No description provided for @backendNotSetBanner.
  ///
  /// In en, this message translates to:
  /// **'Server not configured. Add its URL in Settings.'**
  String get backendNotSetBanner;

  /// No description provided for @aiNotConfiguredBanner.
  ///
  /// In en, this message translates to:
  /// **'AI service not configured on the server'**
  String get aiNotConfiguredBanner;

  /// No description provided for @serverUnreachableBanner.
  ///
  /// In en, this message translates to:
  /// **'Server unreachable'**
  String get serverUnreachableBanner;

  /// No description provided for @aiDisabledBanner.
  ///
  /// In en, this message translates to:
  /// **'Sending to AI is turned off (Privacy)'**
  String get aiDisabledBanner;

  /// No description provided for @errNoInternet.
  ///
  /// In en, this message translates to:
  /// **'No internet'**
  String get errNoInternet;

  /// No description provided for @errNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'AI not configured'**
  String get errNotConfigured;

  /// No description provided for @errServer.
  ///
  /// In en, this message translates to:
  /// **'Server error'**
  String get errServer;

  /// No description provided for @errTimeout.
  ///
  /// In en, this message translates to:
  /// **'Timed out, try again'**
  String get errTimeout;

  /// No description provided for @errRateLimited.
  ///
  /// In en, this message translates to:
  /// **'Too many requests, wait a moment'**
  String get errRateLimited;

  /// No description provided for @errInvalidOutput.
  ///
  /// In en, this message translates to:
  /// **'Invalid reply, try again'**
  String get errInvalidOutput;

  /// No description provided for @errUnauthorized.
  ///
  /// In en, this message translates to:
  /// **'Authentication error'**
  String get errUnauthorized;

  /// No description provided for @errBadRequest.
  ///
  /// In en, this message translates to:
  /// **'Bad request'**
  String get errBadRequest;

  /// No description provided for @labelOffline.
  ///
  /// In en, this message translates to:
  /// **'Pre-written reply (offline)'**
  String get labelOffline;

  /// No description provided for @labelCommand.
  ///
  /// In en, this message translates to:
  /// **'Local command'**
  String get labelCommand;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get copied;

  /// No description provided for @replay.
  ///
  /// In en, this message translates to:
  /// **'Replay'**
  String get replay;

  /// No description provided for @sourcesConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Confirmed by several sources'**
  String get sourcesConfirmed;

  /// No description provided for @sourcesUnconfirmed.
  ///
  /// In en, this message translates to:
  /// **'Not confirmed / sources disagree'**
  String get sourcesUnconfirmed;

  /// No description provided for @sourceData.
  ///
  /// In en, this message translates to:
  /// **'Data source'**
  String get sourceData;

  /// No description provided for @internetNeeded.
  ///
  /// In en, this message translates to:
  /// **'Internet needed for this'**
  String get internetNeeded;

  /// No description provided for @searchUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Web search unavailable; answer not verified'**
  String get searchUnavailable;

  /// No description provided for @translation.
  ///
  /// In en, this message translates to:
  /// **'Translation'**
  String get translation;

  /// No description provided for @micRationaleTitle.
  ///
  /// In en, this message translates to:
  /// **'Sahbi would like to hear you'**
  String get micRationaleTitle;

  /// No description provided for @micRationaleBody.
  ///
  /// In en, this message translates to:
  /// **'I only use the microphone when you tap to talk. Audio is not kept. An indicator shows whenever the mic is on.'**
  String get micRationaleBody;

  /// No description provided for @micAllow.
  ///
  /// In en, this message translates to:
  /// **'Allow'**
  String get micAllow;

  /// No description provided for @micNotNow.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get micNotNow;

  /// No description provided for @micDenied.
  ///
  /// In en, this message translates to:
  /// **'Without the mic you can type to me'**
  String get micDenied;

  /// No description provided for @micPermanentlyDenied.
  ///
  /// In en, this message translates to:
  /// **'Microphone blocked. Enable it in app settings.'**
  String get micPermanentlyDenied;

  /// No description provided for @openAppSettings.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get openAppSettings;

  /// No description provided for @noRecognizer.
  ///
  /// In en, this message translates to:
  /// **'No speech recognizer on this phone; please type'**
  String get noRecognizer;

  /// No description provided for @providerCloud.
  ///
  /// In en, this message translates to:
  /// **'Cloud voice'**
  String get providerCloud;

  /// No description provided for @providerDevice.
  ///
  /// In en, this message translates to:
  /// **'On-device voice'**
  String get providerDevice;

  /// No description provided for @providerTyped.
  ///
  /// In en, this message translates to:
  /// **'Typed input'**
  String get providerTyped;

  /// No description provided for @providerOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get providerOff;

  /// No description provided for @musicTitle.
  ///
  /// In en, this message translates to:
  /// **'Music'**
  String get musicTitle;

  /// No description provided for @addFiles.
  ///
  /// In en, this message translates to:
  /// **'Add files'**
  String get addFiles;

  /// No description provided for @addFolder.
  ///
  /// In en, this message translates to:
  /// **'Add folder'**
  String get addFolder;

  /// No description provided for @demoTracks.
  ///
  /// In en, this message translates to:
  /// **'Demo tracks (CC0)'**
  String get demoTracks;

  /// No description provided for @myTracks.
  ///
  /// In en, this message translates to:
  /// **'My tracks'**
  String get myTracks;

  /// No description provided for @noTracks.
  ///
  /// In en, this message translates to:
  /// **'Nothing yet. Add tracks from your phone.'**
  String get noTracks;

  /// No description provided for @nothingPlaying.
  ///
  /// In en, this message translates to:
  /// **'Nothing playing'**
  String get nothingPlaying;

  /// No description provided for @outputDevice.
  ///
  /// In en, this message translates to:
  /// **'Audio output'**
  String get outputDevice;

  /// No description provided for @outputUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get outputUnknown;

  /// No description provided for @outputSpeaker.
  ///
  /// In en, this message translates to:
  /// **'Phone speaker'**
  String get outputSpeaker;

  /// No description provided for @outputBluetooth.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth'**
  String get outputBluetooth;

  /// No description provided for @outputWired.
  ///
  /// In en, this message translates to:
  /// **'Wired headset'**
  String get outputWired;

  /// No description provided for @outputUsb.
  ///
  /// In en, this message translates to:
  /// **'USB'**
  String get outputUsb;

  /// No description provided for @openOutputSwitcher.
  ///
  /// In en, this message translates to:
  /// **'Switch output'**
  String get openOutputSwitcher;

  /// No description provided for @outputSwitcherUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Could not open the output switcher on this phone'**
  String get outputSwitcherUnavailable;

  /// No description provided for @outputPanelMaybe.
  ///
  /// In en, this message translates to:
  /// **'If no panel opened, use Bluetooth settings'**
  String get outputPanelMaybe;

  /// No description provided for @openBluetoothSettings.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth settings'**
  String get openBluetoothSettings;

  /// No description provided for @outputNote.
  ///
  /// In en, this message translates to:
  /// **'Sahbi plays to the current Android output. Switching speakers happens in the system panel.'**
  String get outputNote;

  /// No description provided for @streamingTitle.
  ///
  /// In en, this message translates to:
  /// **'Spotify & YouTube Music'**
  String get streamingTitle;

  /// No description provided for @streamingSearchHint.
  ///
  /// In en, this message translates to:
  /// **'What do you want to hear?'**
  String get streamingSearchHint;

  /// No description provided for @openSpotify.
  ///
  /// In en, this message translates to:
  /// **'Open in Spotify'**
  String get openSpotify;

  /// No description provided for @openYouTubeMusic.
  ///
  /// In en, this message translates to:
  /// **'Open in YouTube Music'**
  String get openYouTubeMusic;

  /// No description provided for @streamingNote.
  ///
  /// In en, this message translates to:
  /// **'Opened via deep links. Spotify App Remote control is not configured, and YouTube Music has no public playback-control API.'**
  String get streamingNote;

  /// No description provided for @prevTrack.
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get prevTrack;

  /// No description provided for @nextTrack.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get nextTrack;

  /// No description provided for @stopPlayback.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get stopPlayback;

  /// No description provided for @removeTrack.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get removeTrack;

  /// No description provided for @systemVolume.
  ///
  /// In en, this message translates to:
  /// **'Media volume'**
  String get systemVolume;

  /// No description provided for @notificationsDenied.
  ///
  /// In en, this message translates to:
  /// **'Notifications denied: playback works but without notification controls'**
  String get notificationsDenied;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @secLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get secLanguage;

  /// No description provided for @uiLanguage.
  ///
  /// In en, this message translates to:
  /// **'App language'**
  String get uiLanguage;

  /// No description provided for @replyLanguage.
  ///
  /// In en, this message translates to:
  /// **'Reply language'**
  String get replyLanguage;

  /// No description provided for @langDarija.
  ///
  /// In en, this message translates to:
  /// **'Darija'**
  String get langDarija;

  /// No description provided for @langArabic.
  ///
  /// In en, this message translates to:
  /// **'Arabic'**
  String get langArabic;

  /// No description provided for @langFrench.
  ///
  /// In en, this message translates to:
  /// **'French'**
  String get langFrench;

  /// No description provided for @langEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get langEnglish;

  /// No description provided for @darijaScript.
  ///
  /// In en, this message translates to:
  /// **'Darija script'**
  String get darijaScript;

  /// No description provided for @scriptArabic.
  ///
  /// In en, this message translates to:
  /// **'Arabic script'**
  String get scriptArabic;

  /// No description provided for @scriptLatin.
  ///
  /// In en, this message translates to:
  /// **'Latin (3, 7, 9)'**
  String get scriptLatin;

  /// No description provided for @secVoice.
  ///
  /// In en, this message translates to:
  /// **'Voice'**
  String get secVoice;

  /// No description provided for @sttProvider.
  ///
  /// In en, this message translates to:
  /// **'Speech recognition'**
  String get sttProvider;

  /// No description provided for @ttsProvider.
  ///
  /// In en, this message translates to:
  /// **'Sahbi’s voice'**
  String get ttsProvider;

  /// No description provided for @modeAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get modeAuto;

  /// No description provided for @modeCloud.
  ///
  /// In en, this message translates to:
  /// **'Cloud'**
  String get modeCloud;

  /// No description provided for @modeDevice.
  ///
  /// In en, this message translates to:
  /// **'On-device'**
  String get modeDevice;

  /// No description provided for @modeTyped.
  ///
  /// In en, this message translates to:
  /// **'Typing only'**
  String get modeTyped;

  /// No description provided for @modeOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get modeOff;

  /// No description provided for @activeNow.
  ///
  /// In en, this message translates to:
  /// **'Active now'**
  String get activeNow;

  /// No description provided for @deviceVoice.
  ///
  /// In en, this message translates to:
  /// **'Device voice'**
  String get deviceVoice;

  /// No description provided for @defaultVoice.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get defaultVoice;

  /// No description provided for @cloudVoice.
  ///
  /// In en, this message translates to:
  /// **'Cloud voice'**
  String get cloudVoice;

  /// No description provided for @speechRate.
  ///
  /// In en, this message translates to:
  /// **'Speed'**
  String get speechRate;

  /// No description provided for @pitch.
  ///
  /// In en, this message translates to:
  /// **'Pitch'**
  String get pitch;

  /// No description provided for @testVoice.
  ///
  /// In en, this message translates to:
  /// **'Test voice'**
  String get testVoice;

  /// No description provided for @testVoiceText.
  ///
  /// In en, this message translates to:
  /// **'Hi! I am Sahbi, how are you?'**
  String get testVoiceText;

  /// No description provided for @darijaQualityNote.
  ///
  /// In en, this message translates to:
  /// **'Darija recognition quality has not been measured; it depends on the device and engine.'**
  String get darijaQualityNote;

  /// No description provided for @tapFaceToTalk.
  ///
  /// In en, this message translates to:
  /// **'Tap face to talk'**
  String get tapFaceToTalk;

  /// No description provided for @wakeWord.
  ///
  /// In en, this message translates to:
  /// **'Wake phrase “Ya Sahbi”'**
  String get wakeWord;

  /// No description provided for @wakeWordUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Not available in this build (needs a licensed on-device engine)'**
  String get wakeWordUnavailable;

  /// No description provided for @secAi.
  ///
  /// In en, this message translates to:
  /// **'AI'**
  String get secAi;

  /// No description provided for @backendUrl.
  ///
  /// In en, this message translates to:
  /// **'Backend URL'**
  String get backendUrl;

  /// No description provided for @configured.
  ///
  /// In en, this message translates to:
  /// **'Configured'**
  String get configured;

  /// No description provided for @notConfigured.
  ///
  /// In en, this message translates to:
  /// **'Not configured'**
  String get notConfigured;

  /// No description provided for @lastHealthCheck.
  ///
  /// In en, this message translates to:
  /// **'Last check'**
  String get lastHealthCheck;

  /// No description provided for @checkNow.
  ///
  /// In en, this message translates to:
  /// **'Check now'**
  String get checkNow;

  /// No description provided for @never.
  ///
  /// In en, this message translates to:
  /// **'Never'**
  String get never;

  /// No description provided for @serviceLlm.
  ///
  /// In en, this message translates to:
  /// **'AI answers'**
  String get serviceLlm;

  /// No description provided for @serviceSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get serviceSearch;

  /// No description provided for @serviceWeather.
  ///
  /// In en, this message translates to:
  /// **'Weather'**
  String get serviceWeather;

  /// No description provided for @serviceStt.
  ///
  /// In en, this message translates to:
  /// **'Cloud STT'**
  String get serviceStt;

  /// No description provided for @serviceTts.
  ///
  /// In en, this message translates to:
  /// **'Cloud TTS'**
  String get serviceTts;

  /// No description provided for @secInternet.
  ///
  /// In en, this message translates to:
  /// **'Internet'**
  String get secInternet;

  /// No description provided for @online.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get online;

  /// No description provided for @offline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get offline;

  /// No description provided for @networkOnly.
  ///
  /// In en, this message translates to:
  /// **'Network up but server not reachable'**
  String get networkOnly;

  /// No description provided for @secMusic.
  ///
  /// In en, this message translates to:
  /// **'Music'**
  String get secMusic;

  /// No description provided for @bluetoothStatus.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth'**
  String get bluetoothStatus;

  /// No description provided for @btConnectedOutput.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth audio connected'**
  String get btConnectedOutput;

  /// No description provided for @btNotOutput.
  ///
  /// In en, this message translates to:
  /// **'Audio is not on Bluetooth'**
  String get btNotOutput;

  /// No description provided for @secMemory.
  ///
  /// In en, this message translates to:
  /// **'Memory'**
  String get secMemory;

  /// No description provided for @memoryOffLabel.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get memoryOffLabel;

  /// No description provided for @memoryOnLabel.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get memoryOnLabel;

  /// No description provided for @secPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get secPrivacy;

  /// No description provided for @secPersonality.
  ///
  /// In en, this message translates to:
  /// **'Personality'**
  String get secPersonality;

  /// No description provided for @humor.
  ///
  /// In en, this message translates to:
  /// **'Humour'**
  String get humor;

  /// No description provided for @formality.
  ///
  /// In en, this message translates to:
  /// **'Tone'**
  String get formality;

  /// No description provided for @casual.
  ///
  /// In en, this message translates to:
  /// **'Casual'**
  String get casual;

  /// No description provided for @polite.
  ///
  /// In en, this message translates to:
  /// **'Polite'**
  String get polite;

  /// No description provided for @userName.
  ///
  /// In en, this message translates to:
  /// **'What should I call you?'**
  String get userName;

  /// No description provided for @idleBehavior.
  ///
  /// In en, this message translates to:
  /// **'Idle behaviour'**
  String get idleBehavior;

  /// No description provided for @secRobot.
  ///
  /// In en, this message translates to:
  /// **'Robot (experimental)'**
  String get secRobot;

  /// No description provided for @robotExperimental.
  ///
  /// In en, this message translates to:
  /// **'Enable experimental robot link'**
  String get robotExperimental;

  /// No description provided for @secAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get secAbout;

  /// No description provided for @licenses.
  ///
  /// In en, this message translates to:
  /// **'Licences'**
  String get licenses;

  /// No description provided for @version.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get version;

  /// No description provided for @debugUnlocked.
  ///
  /// In en, this message translates to:
  /// **'Debug screen unlocked'**
  String get debugUnlocked;

  /// No description provided for @debugTitle.
  ///
  /// In en, this message translates to:
  /// **'Debug'**
  String get debugTitle;

  /// No description provided for @privacyTitle.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get privacyTitle;

  /// No description provided for @sendToAi.
  ///
  /// In en, this message translates to:
  /// **'Send messages to the AI'**
  String get sendToAi;

  /// No description provided for @cloudVoiceToggle.
  ///
  /// In en, this message translates to:
  /// **'Cloud voice (STT/TTS)'**
  String get cloudVoiceToggle;

  /// No description provided for @micIndicator.
  ///
  /// In en, this message translates to:
  /// **'Mic indicator: always shown'**
  String get micIndicator;

  /// No description provided for @analyticsOff.
  ///
  /// In en, this message translates to:
  /// **'No analytics'**
  String get analyticsOff;

  /// No description provided for @whatLeaves.
  ///
  /// In en, this message translates to:
  /// **'What leaves the phone'**
  String get whatLeaves;

  /// No description provided for @privChat.
  ///
  /// In en, this message translates to:
  /// **'Chat: your message text, recent turns and reply settings go to your server and then the AI provider. The server stores nothing.'**
  String get privChat;

  /// No description provided for @privSearch.
  ///
  /// In en, this message translates to:
  /// **'Search: queries chosen by the AI go to the search provider (Brave). Weather: the city name goes to Open-Meteo.'**
  String get privSearch;

  /// No description provided for @privVoice.
  ///
  /// In en, this message translates to:
  /// **'Voice: in cloud mode your audio and text go via your server to the provider (Azure/OpenAI), not stored. In on-device mode Android’s engine handles it (which may itself use the cloud depending on the device).'**
  String get privVoice;

  /// No description provided for @privMemory.
  ///
  /// In en, this message translates to:
  /// **'Memory: stays on the phone, encrypted. Remembered facts are sent with messages only if you consented.'**
  String get privMemory;

  /// No description provided for @privMusic.
  ///
  /// In en, this message translates to:
  /// **'Music: your files stay on the phone. Spotify and YouTube Music open in their own apps.'**
  String get privMusic;

  /// No description provided for @memoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Memory'**
  String get memoryTitle;

  /// No description provided for @consentTitle.
  ///
  /// In en, this message translates to:
  /// **'Should I remember things?'**
  String get consentTitle;

  /// No description provided for @consentBody.
  ///
  /// In en, this message translates to:
  /// **'Memory stays on this phone, encrypted. You can view, edit, delete or export everything at any time. Remembered facts are sent to the AI with your messages so it knows you.'**
  String get consentBody;

  /// No description provided for @rememberFacts.
  ///
  /// In en, this message translates to:
  /// **'Remember facts I tell you (e.g. “remember that I like tea”)'**
  String get rememberFacts;

  /// No description provided for @rememberHistory.
  ///
  /// In en, this message translates to:
  /// **'Keep chat history'**
  String get rememberHistory;

  /// No description provided for @saveConsent.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get saveConsent;

  /// No description provided for @addFact.
  ///
  /// In en, this message translates to:
  /// **'Add fact'**
  String get addFact;

  /// No description provided for @editItem.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get editItem;

  /// No description provided for @deleteItem.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteItem;

  /// No description provided for @deleteAll.
  ///
  /// In en, this message translates to:
  /// **'Delete everything'**
  String get deleteAll;

  /// No description provided for @deleteAllConfirm.
  ///
  /// In en, this message translates to:
  /// **'Sure? Everything will be erased, including the encryption key.'**
  String get deleteAllConfirm;

  /// No description provided for @exportJson.
  ///
  /// In en, this message translates to:
  /// **'Export JSON'**
  String get exportJson;

  /// No description provided for @exported.
  ///
  /// In en, this message translates to:
  /// **'Exported'**
  String get exported;

  /// No description provided for @exportCancelled.
  ///
  /// In en, this message translates to:
  /// **'Export cancelled'**
  String get exportCancelled;

  /// No description provided for @noMemories.
  ///
  /// In en, this message translates to:
  /// **'Nothing stored'**
  String get noMemories;

  /// No description provided for @factsTab.
  ///
  /// In en, this message translates to:
  /// **'Facts'**
  String get factsTab;

  /// No description provided for @historyTab.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get historyTab;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @memoryUnreadable.
  ///
  /// In en, this message translates to:
  /// **'Could not read the old memory (bad key or file). Starting fresh.'**
  String get memoryUnreadable;

  /// No description provided for @robotTitle.
  ///
  /// In en, this message translates to:
  /// **'Robot link'**
  String get robotTitle;

  /// No description provided for @robotNotice.
  ///
  /// In en, this message translates to:
  /// **'No physical robot exists yet. This screen tests the protocol with a simulated robot. BLE and Wi-Fi are skeletons for later.'**
  String get robotNotice;

  /// No description provided for @transportLocal.
  ///
  /// In en, this message translates to:
  /// **'This phone'**
  String get transportLocal;

  /// No description provided for @transportSim.
  ///
  /// In en, this message translates to:
  /// **'Simulated robot'**
  String get transportSim;

  /// No description provided for @transportBle.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth LE'**
  String get transportBle;

  /// No description provided for @transportWifi.
  ///
  /// In en, this message translates to:
  /// **'Wi-Fi'**
  String get transportWifi;

  /// No description provided for @connect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get connect;

  /// No description provided for @disconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get disconnect;

  /// No description provided for @connected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get connected;

  /// No description provided for @disconnected.
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get disconnected;

  /// No description provided for @connecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get connecting;

  /// No description provided for @failed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get failed;

  /// No description provided for @bleNotBundled.
  ///
  /// In en, this message translates to:
  /// **'No BLE engine in this build'**
  String get bleNotBundled;

  /// No description provided for @wifiUrl.
  ///
  /// In en, this message translates to:
  /// **'WebSocket URL'**
  String get wifiUrl;

  /// No description provided for @simulateTouch.
  ///
  /// In en, this message translates to:
  /// **'Simulate touch'**
  String get simulateTouch;

  /// No description provided for @ping.
  ///
  /// In en, this message translates to:
  /// **'Ping'**
  String get ping;

  /// No description provided for @btPermissionsDenied.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth permissions denied'**
  String get btPermissionsDenied;

  /// No description provided for @providerHealth.
  ///
  /// In en, this message translates to:
  /// **'Service health'**
  String get providerHealth;

  /// No description provided for @lastErrors.
  ///
  /// In en, this message translates to:
  /// **'Last errors'**
  String get lastErrors;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @noErrors.
  ///
  /// In en, this message translates to:
  /// **'No errors'**
  String get noErrors;

  /// No description provided for @chipHello.
  ///
  /// In en, this message translates to:
  /// **'Salam Sahbi'**
  String get chipHello;

  /// No description provided for @newChat.
  ///
  /// In en, this message translates to:
  /// **'New chat'**
  String get newChat;

  /// No description provided for @emptyChat.
  ///
  /// In en, this message translates to:
  /// **'Say something!'**
  String get emptyChat;

  /// No description provided for @listeningHint.
  ///
  /// In en, this message translates to:
  /// **'Speak now…'**
  String get listeningHint;
}

class _L10nDelegate extends LocalizationsDelegate<L10n> {
  const _L10nDelegate();

  @override
  Future<L10n> load(Locale locale) {
    return SynchronousFuture<L10n>(lookupL10n(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en', 'fr'].contains(locale.languageCode);

  @override
  bool shouldReload(_L10nDelegate old) => false;
}

L10n lookupL10n(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return L10nAr();
    case 'en':
      return L10nEn();
    case 'fr':
      return L10nFr();
  }

  throw FlutterError(
    'L10n.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
