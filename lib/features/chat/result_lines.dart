import '../music/music_models.dart';
import '../personality/emotion.dart';
import '../personality/personality_responses.dart';

/// Turns a REAL [ActionResult] into a spoken/displayed line. Success lines
/// are only produced for ok results; failures say what went wrong.
Line resultLine(ActionResult r) {
  final m = r.message;
  if (r.ok) {
    if (m.startsWith('Playing "')) {
      final t = m.substring(9, m.length - 1);
      return Line(
        darijaAr: 'يالاه! كنشغل ليك: $t',
        darijaLatin: 'Yallah! Kanchghel lik: $t',
        msa: 'هيا! أشغل لك: $t',
        fr: 'C’est parti : $t',
        en: 'Here we go: $t',
        emotion: Emotion.happy,
        intensity: 0.8,
      );
    }
    if (m.startsWith('Volume ')) {
      final v = m.substring(7);
      return Line(
        darijaAr: 'الصوت دابا $v',
        darijaLatin: 'Sout daba $v',
        msa: 'مستوى الصوت الآن $v',
        fr: 'Volume : $v',
        en: 'Volume is now $v',
        emotion: Emotion.happy,
        intensity: 0.4,
      );
    }
    const known = {
      'Paused': (
        'وقفت الموسيقى شوية',
        'W9eft lmusic chwiya',
        'أوقفت الموسيقى مؤقتا',
        'Musique en pause',
        'Paused',
      ),
      'Resumed': (
        'رجعنا للموسيقى',
        'Rje3na l lmusic',
        'استأنفت الموسيقى',
        'Reprise de la musique',
        'Resumed',
      ),
      'Stopped': (
        'صافي، حبست الموسيقى',
        'Safi, 7bést lmusic',
        'أوقفت الموسيقى',
        'Musique arrêtée',
        'Music stopped',
      ),
      'Next track': (
        'دوزت للي من بعد',
        'Douzt l li mn b3d',
        'الأغنية التالية',
        'Morceau suivant',
        'Next track',
      ),
      'Previous track': (
        'رجعت للي قبل',
        'Rje3t l li 9bel',
        'الأغنية السابقة',
        'Morceau précédent',
        'Previous track',
      ),
      'Stopped talking': (
        'صافي، سكتت',
        'Safi, skt',
        'حسنا، توقفت عن الكلام',
        'D’accord, je me tais',
        'Okay, I stopped talking',
      ),
      'Listening': (
        'سمعتك، هضر',
        'Sme3tek, hder',
        'أنا أستمع',
        'Je t’écoute',
        'Listening',
      ),
      'Language changed': (
        'صافي، بدلت اللغة',
        'Safi, beddelt lougha',
        'تم تغيير اللغة',
        'Langue changée',
        'Language changed',
      ),
      'Script changed': (
        'صافي، بدلت الكتابة',
        'Safi, beddelt lktaba',
        'تم تغيير طريقة الكتابة',
        'Écriture changée',
        'Script changed',
      ),
      'Opened settings': (
        'حليت ليك الإعدادات',
        '7elit lik settings',
        'فتحت الإعدادات',
        'Réglages ouverts',
        'Opened settings',
      ),
      'Opened camera': (
        'حليت الكاميرا، وريني آش بغيتي نشوف',
        '7elit camera, werrini ach bghiti nchouf',
        'فتحت الكاميرا، أرني ما تريد',
        'Caméra ouverte, montre-moi',
        'Camera open, show me',
      ),
      'Opened music': (
        'حليت ليك الموسيقى',
        '7elit lik lmusic',
        'فتحت الموسيقى',
        'Musique ouverte',
        'Opened music',
      ),
      'Opened Spotify': (
        'حليت ليك سبوتيفاي',
        '7elit lik Spotify',
        'فتحت سبوتيفاي',
        'Spotify ouvert',
        'Opened Spotify',
      ),
      'Opened YouTube Music': (
        'حليت ليك يوتيوب ميوزيك',
        '7elit lik YouTube Music',
        'فتحت يوتيوب ميوزك',
        'YouTube Music ouvert',
        'Opened YouTube Music',
      ),
      'Remembered': (
        'صافي، غادي نعقل على هادشي',
        'Safi, ghadi n3qel 3la hadchi',
        'حسنا، سأتذكر ذلك',
        'D’accord, je m’en souviendrai',
        'Okay, I will remember that',
      ),
    };
    final k = known[m];
    if (k != null) {
      return Line(
        darijaAr: k.$1,
        darijaLatin: k.$2,
        msa: k.$3,
        fr: k.$4,
        en: k.$5,
        emotion: Emotion.happy,
        intensity: 0.5,
      );
    }
    return PersonalityResponses.actionOk(m);
  }
  final code = m.split(':').first;
  const fails = {
    'no_tracks': (
      'ما عنديش موسيقى. زيد شي أغاني من صفحة الموسيقى.',
      'Ma3ndich music. Zid chi aghani mn page dyal lmusic.',
      'لا توجد موسيقى. أضف أغاني من صفحة الموسيقى.',
      'Aucune musique. Ajoute des morceaux dans l’onglet Musique.',
      'No tracks yet. Add some in the Music tab.',
    ),
    'no_local_match': (
      'ما لقيتش هاد الأغنية فالتيليفون. نقدر نقلب عليها فسبوتيفاي ولا يوتيوب ميوزيك.',
      'Ma l9itch had lghnya f tilifoun. N9der n9elleb 3liha f Spotify wla YouTube Music.',
      'لم أجد هذه الأغنية في الهاتف. يمكنني البحث في سبوتيفاي أو يوتيوب ميوزك.',
      'Pas trouvé sur le téléphone. Je peux chercher sur Spotify ou YouTube Music.',
      'Not found on the phone. I can search Spotify or YouTube Music.',
    ),
    'not_playing': (
      'ما كاينة حتى موسيقى خدامة.',
      'Ma kayna 7ta music khddama.',
      'لا توجد موسيقى قيد التشغيل.',
      'Aucune musique en cours.',
      'Nothing is playing.',
    ),
    'queue_empty': (
      'اللائحة خاوية.',
      'Lai7a khawya.',
      'القائمة فارغة.',
      'La file est vide.',
      'The queue is empty.',
    ),
    'end_of_queue': (
      'هادي آخر وحدة فاللائحة.',
      'Hadi akher we7da f lai7a.',
      'هذه آخر أغنية في القائمة.',
      'C’était le dernier morceau.',
      'That was the last track.',
    ),
    'nothing_to_stop': (
      'ما كاين ما نوقف.',
      'Ma kayn ma nw9ef.',
      'لا يوجد شيء لإيقافه.',
      'Rien à arrêter.',
      'Nothing to stop.',
    ),
    'volume_unavailable': (
      'ما قدرتش نبدل الصوت فهاد الجهاز.',
      'Ma9dertch nbeddel sout f had tilifoun.',
      'لم أستطع تغيير الصوت على هذا الجهاز.',
      'Impossible de changer le volume sur cet appareil.',
      'Could not change the volume on this device.',
    ),
    'memory_off': (
      'الذاكرة مطفية. شعلها من الإعدادات إلا بغيتي نعقل.',
      'Dakira mtfiya. Ch3elha mn settings ila bghiti n3qel.',
      'الذاكرة معطلة. فعلها من الإعدادات.',
      'La mémoire est désactivée. Active-la dans les réglages.',
      'Memory is off. Enable it in Settings if you want me to remember.',
    ),
    'mic_unavailable': (
      'ما قدرتش نحل الميكرو.',
      'Ma9dertch n7el lmicro.',
      'لم أستطع تشغيل الميكروفون.',
      'Impossible d’ouvrir le micro.',
      'Could not open the microphone.',
    ),
    'youtube_not_found': (
      'ما لقيتش هاد الأغنية فيوتيوب. جرب تقول ليا السمية ديال الفنان ولا الأغنية بشكل آخر.',
      'Ma l9itch had lghnya f YouTube. Jreb t9oul liya smiyt lfannan wla lghnya b chkel akhor.',
      'لم أجد هذه الأغنية في يوتيوب. جرّب اسم الفنان أو الأغنية بطريقة أخرى.',
      'Je n’ai pas trouvé ce morceau sur YouTube. Essaie autrement le nom de l’artiste ou du titre.',
      'Couldn’t find that song on YouTube. Try the artist or title another way.',
    ),
    'youtube_unavailable': (
      'ما قدرتش نقلب فيوتيوب دابا. شوف الأنترنيت ولا السيرفر.',
      'Ma9dertch n9elleb f YouTube daba. Chouf l internet wla serveur.',
      'لم أستطع البحث في يوتيوب الآن. تحقق من الإنترنت أو الخادم.',
      'Impossible de chercher sur YouTube maintenant. Vérifie internet ou le serveur.',
      'Couldn’t search YouTube right now. Check the internet or the server.',
    ),
    'camera unavailable': (
      'ما قدرتش نحل الكاميرا دابا.',
      'Ma9dertch n7el camera daba.',
      'لم أستطع فتح الكاميرا الآن.',
      'Impossible d’ouvrir la caméra maintenant.',
      'Could not open the camera right now.',
    ),
  };
  final f = fails[code];
  if (f != null) {
    return Line(
      darijaAr: f.$1,
      darijaLatin: f.$2,
      msa: f.$3,
      fr: f.$4,
      en: f.$5,
      emotion: Emotion.sad,
      intensity: 0.4,
    );
  }
  return PersonalityResponses.actionFailed(m);
}
