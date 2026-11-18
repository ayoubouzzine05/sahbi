// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class L10nAr extends L10n {
  L10nAr([String locale = 'ar']) : super(locale);

  @override
  String get appTitle => 'صاحبي';

  @override
  String get tabHome => 'صاحبي';

  @override
  String get tabChat => 'الهضرة';

  @override
  String get tabMusic => 'الموسيقى';

  @override
  String get tabSettings => 'الإعدادات';

  @override
  String get tapToTalk => 'ضغط باش تهضر';

  @override
  String get holdHint => 'ولا شد وهضر';

  @override
  String get stateIdle => 'واجد';

  @override
  String get stateListening => 'كنسمع…';

  @override
  String get stateThinking => 'كنفكر…';

  @override
  String get stateSpeaking => 'كنهضر…';

  @override
  String get stateError => 'وقع مشكل';

  @override
  String get phaseSearching => 'كنقلب فالأنترنيت…';

  @override
  String get phaseWeather => 'كنشوف الطقس…';

  @override
  String get phaseRetrying => 'كنعاود…';

  @override
  String get phaseWaking => 'كنفيّق السيرفر… (حتى دقيقة)';

  @override
  String get stopListening => 'حبس السمع';

  @override
  String get interruptSpeech => 'سكت';

  @override
  String get typeMessage => 'كتب لصاحبي…';

  @override
  String get send => 'صيفط';

  @override
  String get micOn => 'الميكرو خدام';

  @override
  String get offlineBanner =>
      'بلا أنترنيت: الأجوبة ديال الذكاء، البحث والصوت السحابي ما خدامينش';

  @override
  String get backendNotSetBanner =>
      'السيرفر ما مضبوطش. زيد العنوان فالإعدادات.';

  @override
  String get aiNotConfiguredBanner =>
      'خدمة الذكاء الاصطناعي ما مضبوطاش فالسيرفر';

  @override
  String get serverUnreachableBanner => 'ما قدرتش نوصل للسيرفر';

  @override
  String get aiDisabledBanner => 'الإرسال للذكاء الاصطناعي مطفي فالخصوصية';

  @override
  String get errNoInternet => 'ما كاينش الأنترنيت';

  @override
  String get errNotConfigured => 'الذكاء الاصطناعي ما مضبوطش';

  @override
  String get errServer => 'مشكل فالسيرفر';

  @override
  String get errTimeout => 'طول بزاف، عاود';

  @override
  String get errRateLimited => 'بزاف ديال الطلبات، تسنى شوية';

  @override
  String get errInvalidOutput => 'الجواب جا خايب، عاود';

  @override
  String get errUnauthorized => 'مشكل فالتوثيق';

  @override
  String get errBadRequest => 'طلب ماشي صحيح';

  @override
  String get labelOffline => 'جواب محضر من قبل (بلا أنترنيت)';

  @override
  String get labelCommand => 'أمر محلي';

  @override
  String get retry => 'عاود';

  @override
  String get copy => 'نسخ';

  @override
  String get copied => 'تنسخ';

  @override
  String get replay => 'عاود سمع';

  @override
  String get sourcesConfirmed => 'مأكد من بزاف ديال المصادر';

  @override
  String get sourcesUnconfirmed => 'ماشي مأكد / المصادر ما متافقينش';

  @override
  String get sourceData => 'مصدر ديال المعطيات';

  @override
  String get internetNeeded => 'خاص الأنترنيت لهادشي';

  @override
  String get searchUnavailable =>
      'البحث فالأنترنيت ما متوفرش دابا، الجواب ماشي مأكد';

  @override
  String get translation => 'الترجمة';

  @override
  String get micRationaleTitle => 'صاحبي بغا يسمعك';

  @override
  String get micRationaleBody =>
      'كنحتاج الميكرو غير ملي تضغط باش تهضر. ما كنسجلش الصوت ما كنخبيهش. الميكرو كيبان ديما ملي يكون خدام.';

  @override
  String get micAllow => 'سماح';

  @override
  String get micNotNow => 'ماشي دابا';

  @override
  String get micDenied => 'بلا ميكرو، تقدر تكتب ليا';

  @override
  String get micPermanentlyDenied => 'الميكرو مسدود. حلو من إعدادات التطبيق.';

  @override
  String get openAppSettings => 'حل الإعدادات';

  @override
  String get noRecognizer =>
      'ما كاينش التعرف على الصوت فهاد التيليفون، كتب ليا';

  @override
  String get providerCloud => 'صوت سحابي';

  @override
  String get providerDevice => 'صوت التيليفون';

  @override
  String get providerTyped => 'كتابة';

  @override
  String get providerOff => 'مطفي';

  @override
  String get musicTitle => 'الموسيقى';

  @override
  String get addFiles => 'زيد أغاني';

  @override
  String get addFolder => 'زيد دوسي';

  @override
  String get demoTracks => 'أغاني تجريبية (CC0)';

  @override
  String get myTracks => 'الأغاني ديالي';

  @override
  String get noTracks => 'ما كاين والو. زيد أغاني من التيليفون.';

  @override
  String get nothingPlaying => 'ما كاين حتى حاجة خدامة';

  @override
  String get outputDevice => 'فين خارج الصوت';

  @override
  String get outputUnknown => 'ما معروفش';

  @override
  String get outputSpeaker => 'سبيكر التيليفون';

  @override
  String get outputBluetooth => 'بلوتوث';

  @override
  String get outputWired => 'كاسك بالخيط';

  @override
  String get outputUsb => 'USB';

  @override
  String get openOutputSwitcher => 'بدل الخروج';

  @override
  String get outputSwitcherUnavailable =>
      'ما قدرتش نحل لوحة الخروج فهاد التيليفون';

  @override
  String get outputPanelMaybe =>
      'إلا ما تحلات حتى لوحة، استعمل إعدادات البلوتوث';

  @override
  String get openBluetoothSettings => 'إعدادات البلوتوث';

  @override
  String get outputNote =>
      'صاحبي كيخرج الصوت فالخروج الحالي ديال أندرويد. التبديل بين السبيكرات كيتدار من لوحة النظام.';

  @override
  String get streamingTitle => 'سبوتيفاي و يوتيوب ميوزيك';

  @override
  String get streamingSearchHint => 'شنو بغيتي تسمع؟';

  @override
  String get openSpotify => 'حل ف سبوتيفاي';

  @override
  String get openYouTubeMusic => 'حل ف يوتيوب ميوزيك';

  @override
  String get streamingNote =>
      'كنحلو التطبيق بروابط عادية. التحكم فسبوتيفاي (App Remote) ما مضبوطش، ويوتيوب ميوزيك ما عندوش API عمومية للتحكم.';

  @override
  String get prevTrack => 'اللي قبل';

  @override
  String get nextTrack => 'اللي من بعد';

  @override
  String get stopPlayback => 'وقف';

  @override
  String get removeTrack => 'حيد';

  @override
  String get systemVolume => 'صوت الوسائط';

  @override
  String get notificationsDenied =>
      'الإشعارات مسدودة: الموسيقى خدامة ولكن بلا تحكم فالإشعار';

  @override
  String get settingsTitle => 'الإعدادات';

  @override
  String get secLanguage => 'اللغة';

  @override
  String get uiLanguage => 'لغة التطبيق';

  @override
  String get replyLanguage => 'لغة الجواب';

  @override
  String get langDarija => 'الدارجة';

  @override
  String get langArabic => 'العربية';

  @override
  String get langFrench => 'الفرنسية';

  @override
  String get langEnglish => 'الإنجليزية';

  @override
  String get darijaScript => 'كتابة الدارجة';

  @override
  String get scriptArabic => 'حروف عربية';

  @override
  String get scriptLatin => 'حروف لاتينية (3، 7، 9)';

  @override
  String get secVoice => 'الصوت';

  @override
  String get sttProvider => 'التعرف على الصوت';

  @override
  String get ttsProvider => 'صوت صاحبي';

  @override
  String get modeAuto => 'أوتوماتيك';

  @override
  String get modeCloud => 'سحابي';

  @override
  String get modeDevice => 'التيليفون';

  @override
  String get modeTyped => 'كتابة فقط';

  @override
  String get modeOff => 'مطفي';

  @override
  String get activeNow => 'خدام دابا';

  @override
  String get deviceVoice => 'صوت التيليفون';

  @override
  String get defaultVoice => 'العادي';

  @override
  String get cloudVoice => 'الصوت السحابي';

  @override
  String get speechRate => 'السرعة';

  @override
  String get pitch => 'الطبقة';

  @override
  String get testVoice => 'جرب الصوت';

  @override
  String get testVoiceText => 'السلام! أنا صاحبي، كيداير؟';

  @override
  String get darijaQualityNote =>
      'جودة التعرف على الدارجة ما تقاساتش. كتختالف حسب التيليفون والمحرك.';

  @override
  String get tapFaceToTalk => 'ضغط على الوجه باش تهضر';

  @override
  String get wakeWord => 'كلمة التنبيه «يا صاحبي»';

  @override
  String get wakeWordUnavailable =>
      'ما متوفراش فهاد النسخة (كتحتاج محرك محلي بترخيص)';

  @override
  String get secAi => 'الذكاء الاصطناعي';

  @override
  String get backendUrl => 'عنوان السيرفر';

  @override
  String get configured => 'مضبوط';

  @override
  String get notConfigured => 'ما مضبوطش';

  @override
  String get lastHealthCheck => 'آخر فحص';

  @override
  String get checkNow => 'فحص دابا';

  @override
  String get never => 'عمر';

  @override
  String get serviceLlm => 'الأجوبة';

  @override
  String get serviceSearch => 'البحث';

  @override
  String get serviceWeather => 'الطقس';

  @override
  String get serviceStt => 'التعرف السحابي';

  @override
  String get serviceTts => 'الصوت السحابي';

  @override
  String get secInternet => 'الأنترنيت';

  @override
  String get online => 'متصل';

  @override
  String get offline => 'بلا أنترنيت';

  @override
  String get networkOnly => 'كاين الريزو ولكن السيرفر ما كيجاوبش';

  @override
  String get secMusic => 'الموسيقى';

  @override
  String get bluetoothStatus => 'البلوتوث';

  @override
  String get btConnectedOutput => 'سبيكر بلوتوث مكونيكطي';

  @override
  String get btNotOutput => 'الصوت ماشي فالبلوتوث';

  @override
  String get secMemory => 'الذاكرة';

  @override
  String get memoryOffLabel => 'مطفية';

  @override
  String get memoryOnLabel => 'شاعلة';

  @override
  String get secPrivacy => 'الخصوصية';

  @override
  String get secPersonality => 'الشخصية';

  @override
  String get humor => 'الضحك';

  @override
  String get formality => 'الأسلوب';

  @override
  String get casual => 'عادي';

  @override
  String get polite => 'مؤدب';

  @override
  String get userName => 'شنو نعيط ليك؟';

  @override
  String get idleBehavior => 'حركات ملي نكون فاضي';

  @override
  String get secRobot => 'الروبو (تجريبي)';

  @override
  String get robotExperimental => 'فعل رابط الروبو التجريبي';

  @override
  String get secAbout => 'على صاحبي';

  @override
  String get licenses => 'التراخيص';

  @override
  String get version => 'النسخة';

  @override
  String get debugUnlocked => 'شاشة الديباغ تحلات';

  @override
  String get debugTitle => 'ديباغ';

  @override
  String get privacyTitle => 'الخصوصية';

  @override
  String get sendToAi => 'صيفط الهضرة للذكاء الاصطناعي';

  @override
  String get cloudVoiceToggle => 'الصوت السحابي (STT/TTS)';

  @override
  String get micIndicator => 'مؤشر الميكرو: ديما كيبان';

  @override
  String get analyticsOff => 'ما كاين حتى تحليلات (analytics)';

  @override
  String get whatLeaves => 'شنو كيخرج من التيليفون';

  @override
  String get privChat =>
      'الهضرة: النص ديال الميساج، آخر الرسائل، والإعدادات كيمشيو للسيرفر ديالك وللمزود ديال الذكاء الاصطناعي. السيرفر ما كيخبيش الهضرة.';

  @override
  String get privSearch =>
      'البحث: الكلمات اللي كيقلب عليها الذكاء الاصطناعي كتمشي لمزود البحث (Brave). الطقس: اسم المدينة كيمشي لـ Open-Meteo.';

  @override
  String get privVoice =>
      'الصوت: فالوضع السحابي، الصوت ديالك والنص كيمشيو للسيرفر وللمزود (Azure/OpenAI) وما كيتخباوش. فوضع التيليفون، المحرك ديال أندرويد هو اللي كيعالج (يقدر يكون سحابي حسب الجهاز).';

  @override
  String get privMemory =>
      'الذاكرة: كتبقى غير فالتيليفون ومشفرة. الحوايج اللي عقلت عليهم كيتصيفطو مع الميساج غير إلا وافقتي.';

  @override
  String get privMusic =>
      'الموسيقى: الملفات ديالك كيبقاو فالتيليفون. سبوتيفاي ويوتيوب ميوزيك كيتحلو فالتطبيقات ديالهم.';

  @override
  String get memoryTitle => 'الذاكرة';

  @override
  String get consentTitle => 'واش نعقل عليك؟';

  @override
  String get consentBody =>
      'الذاكرة كتبقى غير فهاد التيليفون، مشفرة. تقدر تشوف، تبدل، تمسح ولا تصدر كلشي فأي وقت. الحوايج اللي عقلت عليهم كيتصيفطو للذكاء الاصطناعي مع الميساجات باش يعرفك.';

  @override
  String get rememberFacts =>
      'عقل على الحوايج اللي نقول ليك (مثلا: «عقل بلي كنبغي أتاي»)';

  @override
  String get rememberHistory => 'خبي تاريخ الهضرة';

  @override
  String get saveConsent => 'حفظ';

  @override
  String get addFact => 'زيد معلومة';

  @override
  String get editItem => 'بدل';

  @override
  String get deleteItem => 'مسح';

  @override
  String get deleteAll => 'مسح كلشي';

  @override
  String get deleteAllConfirm => 'متأكد؟ كلشي غادي يتمسح مع مفتاح التشفير.';

  @override
  String get exportJson => 'صدر JSON';

  @override
  String get exported => 'تصدر';

  @override
  String get exportCancelled => 'تلغى التصدير';

  @override
  String get noMemories => 'ما كاين حتى حاجة';

  @override
  String get factsTab => 'المعلومات';

  @override
  String get historyTab => 'التاريخ';

  @override
  String get cancel => 'إلغاء';

  @override
  String get save => 'حفظ';

  @override
  String get memoryUnreadable =>
      'ما قدرتش نقرا الذاكرة القديمة (مفتاح ولا ملف خايب). بديت من جديد.';

  @override
  String get robotTitle => 'رابط الروبو';

  @override
  String get robotNotice =>
      'ما كاين حتى روبو حقيقي دابا. هاد الشاشة كتجرب البروتوكول مع روبو مزور. البلوتوث والواي فاي غير هياكل للمستقبل.';

  @override
  String get transportLocal => 'هاد التيليفون';

  @override
  String get transportSim => 'روبو مزور';

  @override
  String get transportBle => 'بلوتوث LE';

  @override
  String get transportWifi => 'واي فاي';

  @override
  String get connect => 'كونيكطي';

  @override
  String get disconnect => 'قطع';

  @override
  String get connected => 'مكونيكطي';

  @override
  String get disconnected => 'مقطوع';

  @override
  String get connecting => 'كيتكونيكطا…';

  @override
  String get failed => 'ما خدمش';

  @override
  String get bleNotBundled => 'ما كاينش محرك بلوتوث فهاد النسخة';

  @override
  String get wifiUrl => 'عنوان WebSocket';

  @override
  String get simulateTouch => 'قيس الروبو';

  @override
  String get ping => 'Ping';

  @override
  String get btPermissionsDenied => 'أذونات البلوتوث ما تعطاوش';

  @override
  String get providerHealth => 'حالة الخدمات';

  @override
  String get lastErrors => 'آخر الأخطاء';

  @override
  String get clear => 'مسح';

  @override
  String get noErrors => 'ما كاين حتى خطأ';

  @override
  String get chipHello => 'سلام صاحبي';

  @override
  String get newChat => 'هضرة جديدة';

  @override
  String get emptyChat => 'قول ليا شي حاجة!';

  @override
  String get listeningHint => 'هضر دابا…';

  @override
  String get liveTitle => 'شوف معايا';

  @override
  String get liveConnecting => 'كنتكونيكطا…';

  @override
  String get liveHint => 'وريني شي حاجة وسولني عليها بالصوت';

  @override
  String get liveReconnecting => 'كنعاود نتكونيكطا…';

  @override
  String get liveNotConfigured =>
      'الكاميرا المباشرة ما مفعلاش فالسيرفر (خاص مفتاح Gemini).';

  @override
  String get liveError => 'ما قدرتش نتكونيكطا مع الكاميرا المباشرة.';

  @override
  String get liveEnded => 'سالات الجلسة.';

  @override
  String get liveTimeLimit =>
      'وقفت الجلسة بعد 10 دقايق باش نحافظو على الكوطا المجانية. عاود إلا بغيتي.';

  @override
  String get liveRetry => 'عاود';

  @override
  String get liveMute => 'سكت الميكرو';

  @override
  String get liveUnmute => 'حل الميكرو';

  @override
  String get liveSwitchCamera => 'بدل الكاميرا';

  @override
  String get liveEnd => 'سالي';

  @override
  String get liveNoCamera => 'ما لقيتش كاميرا فهاد التيليفون.';

  @override
  String get liveNeedsInternet => 'الكاميرا المباشرة خاصها الأنترنيت.';

  @override
  String get liveAiLabel => 'AI · Gemini Live';

  @override
  String get cameraRationaleTitle => 'نشوف معاك؟';

  @override
  String get cameraRationaleBody =>
      'باش نشوف آش كتوريني ونفهمك، خاصني الكاميرا والميكرو. الصور (تقريبا وحدة فالثانية) والصوت كيمشيو مباشرة لـ Google Gemini غير وقت الجلسة. التطبيق ما كيخزن والو.';

  @override
  String get cameraDenied =>
      'بلا الكاميرا والميكرو ما نقدرش نشوف. تقدر تعطيهم من الإعدادات.';

  @override
  String get openCamera => 'الكاميرا';

  @override
  String get robotNameTitle => 'سمية الروبو';

  @override
  String get robotNameHint => 'مثلا: زيزو، Bobo… (خليها خاوية = صاحبي)';

  @override
  String get robotNameDialogTitle => 'شنو بغيتي تسميني؟';

  @override
  String robotNameSaved(String name) {
    return 'صافي، دابا سميتي $name!';
  }

  @override
  String get voiceGenderTitle => 'الصوت ديال الروبو';

  @override
  String get voiceMale => 'راجل';

  @override
  String get voiceFemale => 'مرا';

  @override
  String get voiceGenderNote =>
      'صوت السيرفر (Gemini) كيتبدل مباشرة. صوت التيليفون كيتبع الأصوات اللي فالجهاز: إلا ما كانش صوت ديال راجل كنهبطو الطون شوية.';

  @override
  String get wakeByNameTitle => 'جاوب ملي نعيط عليك بسميتك';

  @override
  String wakeByNameSubtitle(String name) {
    return 'غير ملي التطبيق محلول. قول «$name» (ولا «$name، شنو الجو اليوم؟») بلا ما تضغط. كيصرف شوية ديال البطارية، وبعض التيليفونات كيديرو بيب ملي كيعاود يسمع.';
  }

  @override
  String get wakeByNameNoMic => 'خاص الإذن ديال الميكرو باش نسمع سميتي.';

  @override
  String wakeListening(String name) {
    return 'كنتسنا تعيط عليا: $name';
  }

  @override
  String get keepScreenOn => 'خلي الشاشة شاعلة فوجه الروبو';
}
