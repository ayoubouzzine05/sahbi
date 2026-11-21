// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class L10nFr extends L10n {
  L10nFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'Sahbi';

  @override
  String get tabHome => 'Sahbi';

  @override
  String get tabChat => 'Discussion';

  @override
  String get tabMusic => 'Musique';

  @override
  String get tabSettings => 'Réglages';

  @override
  String get tapToTalk => 'Appuie pour parler';

  @override
  String get holdHint => 'ou maintiens';

  @override
  String get stateIdle => 'Prêt';

  @override
  String get stateListening => 'J’écoute…';

  @override
  String get stateThinking => 'Je réfléchis…';

  @override
  String get stateSpeaking => 'Je parle…';

  @override
  String get stateError => 'Erreur';

  @override
  String get phaseSearching => 'Recherche sur le web…';

  @override
  String get phaseWeather => 'Je regarde la météo…';

  @override
  String get phaseRetrying => 'Nouvel essai…';

  @override
  String get phaseWaking => 'Je réveille le serveur… (jusqu\'à 1 min)';

  @override
  String get stopListening => 'Arrêter l’écoute';

  @override
  String get interruptSpeech => 'Interrompre';

  @override
  String get typeMessage => 'Écris à Sahbi…';

  @override
  String get send => 'Envoyer';

  @override
  String get micOn => 'Micro actif';

  @override
  String get offlineBanner =>
      'Hors ligne : réponses IA, recherche et voix cloud indisponibles';

  @override
  String get backendNotSetBanner =>
      'Serveur non configuré. Ajoute l’URL dans Réglages.';

  @override
  String get aiNotConfiguredBanner => 'Service IA non configuré sur le serveur';

  @override
  String get serverUnreachableBanner => 'Serveur injoignable';

  @override
  String get aiDisabledBanner => 'Envoi à l’IA désactivé (confidentialité)';

  @override
  String get errNoInternet => 'Pas d’internet';

  @override
  String get errNotConfigured => 'IA non configurée';

  @override
  String get errServer => 'Erreur serveur';

  @override
  String get errTimeout => 'Délai dépassé, réessaie';

  @override
  String get errRateLimited => 'Trop de requêtes, patiente un peu';

  @override
  String get errInvalidOutput => 'Réponse invalide, réessaie';

  @override
  String get errUnauthorized => 'Erreur d’authentification';

  @override
  String get errBadRequest => 'Requête invalide';

  @override
  String get labelOffline => 'Réponse pré-écrite (hors ligne)';

  @override
  String get labelCommand => 'Commande locale';

  @override
  String get retry => 'Réessayer';

  @override
  String get copy => 'Copier';

  @override
  String get copied => 'Copié';

  @override
  String get replay => 'Réécouter';

  @override
  String get sourcesConfirmed => 'Confirmé par plusieurs sources';

  @override
  String get sourcesUnconfirmed => 'Non confirmé / sources divergentes';

  @override
  String get sourceData => 'Source de données';

  @override
  String get internetNeeded => 'Internet nécessaire pour ça';

  @override
  String get searchUnavailable =>
      'Recherche web indisponible, réponse non vérifiée';

  @override
  String get translation => 'Traduction';

  @override
  String get micRationaleTitle => 'Sahbi aimerait t’entendre';

  @override
  String get micRationaleBody =>
      'J’utilise le micro seulement quand tu appuies pour parler. Je ne garde pas l’audio. Un indicateur s’affiche dès que le micro est actif.';

  @override
  String get micAllow => 'Autoriser';

  @override
  String get micNotNow => 'Pas maintenant';

  @override
  String get micDenied => 'Sans micro, tu peux m’écrire';

  @override
  String get micPermanentlyDenied =>
      'Micro bloqué. Active-le dans les réglages de l’app.';

  @override
  String get openAppSettings => 'Ouvrir les réglages';

  @override
  String get noRecognizer =>
      'Pas de reconnaissance vocale sur ce téléphone, écris-moi';

  @override
  String get providerCloud => 'Voix cloud';

  @override
  String get providerDevice => 'Voix de l’appareil';

  @override
  String get providerTyped => 'Saisie texte';

  @override
  String get providerOff => 'Désactivé';

  @override
  String get musicTitle => 'Musique';

  @override
  String get addFiles => 'Ajouter des fichiers';

  @override
  String get addFolder => 'Ajouter un dossier';

  @override
  String get demoTracks => 'Pistes démo (CC0)';

  @override
  String get myTracks => 'Mes morceaux';

  @override
  String get noTracks => 'Rien pour l’instant. Ajoute des morceaux.';

  @override
  String get nothingPlaying => 'Rien en lecture';

  @override
  String get outputDevice => 'Sortie audio';

  @override
  String get outputUnknown => 'Inconnue';

  @override
  String get outputSpeaker => 'Haut-parleur';

  @override
  String get outputBluetooth => 'Bluetooth';

  @override
  String get outputWired => 'Casque filaire';

  @override
  String get outputUsb => 'USB';

  @override
  String get openOutputSwitcher => 'Changer de sortie';

  @override
  String get outputSwitcherUnavailable =>
      'Impossible d’ouvrir le sélecteur de sortie sur ce téléphone';

  @override
  String get outputPanelMaybe =>
      'Si aucun panneau ne s’est ouvert, utilise les réglages Bluetooth';

  @override
  String get openBluetoothSettings => 'Réglages Bluetooth';

  @override
  String get outputNote =>
      'Sahbi joue sur la sortie Android actuelle. Le changement d’enceinte se fait dans le panneau système.';

  @override
  String get streamingTitle => 'Spotify et YouTube Music';

  @override
  String get streamingSearchHint => 'Que veux-tu écouter ?';

  @override
  String get openSpotify => 'Ouvrir dans Spotify';

  @override
  String get openYouTubeMusic => 'Ouvrir dans YouTube Music';

  @override
  String get streamingNote =>
      'Ouverture par liens profonds. Le contrôle Spotify (App Remote) n’est pas configuré et YouTube Music n’a pas d’API publique de contrôle.';

  @override
  String get prevTrack => 'Précédent';

  @override
  String get nextTrack => 'Suivant';

  @override
  String get stopPlayback => 'Arrêter';

  @override
  String get removeTrack => 'Retirer';

  @override
  String get systemVolume => 'Volume média';

  @override
  String get notificationsDenied =>
      'Notifications refusées : la lecture marche mais sans contrôles dans la notification';

  @override
  String get settingsTitle => 'Réglages';

  @override
  String get secLanguage => 'Langue';

  @override
  String get uiLanguage => 'Langue de l’app';

  @override
  String get replyLanguage => 'Langue des réponses';

  @override
  String get langDarija => 'Darija';

  @override
  String get langArabic => 'Arabe';

  @override
  String get langFrench => 'Français';

  @override
  String get langEnglish => 'Anglais';

  @override
  String get darijaScript => 'Écriture de la darija';

  @override
  String get scriptArabic => 'Arabe';

  @override
  String get scriptLatin => 'Latin (3, 7, 9)';

  @override
  String get secVoice => 'Voix';

  @override
  String get sttProvider => 'Reconnaissance vocale';

  @override
  String get ttsProvider => 'Voix de Sahbi';

  @override
  String get modeAuto => 'Auto';

  @override
  String get modeCloud => 'Cloud';

  @override
  String get modeDevice => 'Appareil';

  @override
  String get modeTyped => 'Texte seulement';

  @override
  String get modeOff => 'Désactivé';

  @override
  String get activeNow => 'Actif';

  @override
  String get deviceVoice => 'Voix de l’appareil';

  @override
  String get defaultVoice => 'Par défaut';

  @override
  String get cloudVoice => 'Voix cloud';

  @override
  String get speechRate => 'Vitesse';

  @override
  String get pitch => 'Hauteur';

  @override
  String get testVoice => 'Tester la voix';

  @override
  String get testVoiceText => 'Salut ! Je suis Sahbi, ça va ?';

  @override
  String get darijaQualityNote =>
      'La qualité de reconnaissance de la darija n’a pas été mesurée ; elle dépend de l’appareil et du moteur.';

  @override
  String get tapFaceToTalk => 'Toucher le visage pour parler';

  @override
  String get wakeWord => 'Mot d’éveil « Ya Sahbi »';

  @override
  String get wakeWordUnavailable =>
      'Indisponible dans cette version (moteur local sous licence requis)';

  @override
  String get secAi => 'IA';

  @override
  String get backendUrl => 'URL du serveur';

  @override
  String get configured => 'Configuré';

  @override
  String get notConfigured => 'Non configuré';

  @override
  String get lastHealthCheck => 'Dernière vérification';

  @override
  String get checkNow => 'Vérifier';

  @override
  String get never => 'Jamais';

  @override
  String get serviceLlm => 'Réponses IA';

  @override
  String get serviceSearch => 'Recherche';

  @override
  String get serviceWeather => 'Météo';

  @override
  String get serviceStt => 'Reconnaissance cloud';

  @override
  String get serviceTts => 'Synthèse cloud';

  @override
  String get secInternet => 'Internet';

  @override
  String get online => 'En ligne';

  @override
  String get offline => 'Hors ligne';

  @override
  String get networkOnly => 'Réseau présent mais serveur injoignable';

  @override
  String get secMusic => 'Musique';

  @override
  String get bluetoothStatus => 'Bluetooth';

  @override
  String get btConnectedOutput => 'Enceinte Bluetooth connectée';

  @override
  String get btNotOutput => 'L’audio ne passe pas par Bluetooth';

  @override
  String get secMemory => 'Mémoire';

  @override
  String get memoryOffLabel => 'Désactivée';

  @override
  String get memoryOnLabel => 'Activée';

  @override
  String get secPrivacy => 'Confidentialité';

  @override
  String get secPersonality => 'Personnalité';

  @override
  String get humor => 'Humour';

  @override
  String get formality => 'Ton';

  @override
  String get casual => 'Décontracté';

  @override
  String get polite => 'Poli';

  @override
  String get userName => 'Comment t’appeler ?';

  @override
  String get idleBehavior => 'Animations au repos';

  @override
  String get secRobot => 'Robot (expérimental)';

  @override
  String get robotExperimental => 'Activer le lien robot expérimental';

  @override
  String get secAbout => 'À propos';

  @override
  String get licenses => 'Licences';

  @override
  String get version => 'Version';

  @override
  String get debugUnlocked => 'Écran debug débloqué';

  @override
  String get debugTitle => 'Debug';

  @override
  String get privacyTitle => 'Confidentialité';

  @override
  String get sendToAi => 'Envoyer les messages à l’IA';

  @override
  String get cloudVoiceToggle => 'Voix cloud (STT/TTS)';

  @override
  String get micIndicator => 'Indicateur micro : toujours visible';

  @override
  String get analyticsOff => 'Aucune analytique';

  @override
  String get whatLeaves => 'Ce qui quitte le téléphone';

  @override
  String get privChat =>
      'Discussion : le texte, les derniers messages et tes réglages vont à ton serveur puis au fournisseur d’IA. Le serveur ne stocke rien.';

  @override
  String get privSearch =>
      'Recherche : les requêtes choisies par l’IA vont au moteur (Brave). Météo : le nom de la ville va à Open-Meteo.';

  @override
  String get privVoice =>
      'Voix : en mode cloud, ton audio et le texte passent par le serveur vers le fournisseur (Azure/OpenAI), sans stockage. En mode appareil, le moteur Android traite (il peut lui-même utiliser le cloud selon l’appareil).';

  @override
  String get privMemory =>
      'Mémoire : uniquement sur le téléphone, chiffrée. Les faits retenus sont envoyés avec les messages seulement si tu l’as accepté.';

  @override
  String get privMusic =>
      'Musique : tes fichiers restent sur le téléphone. Si tu demandes un morceau que tu n’as pas, son titre part au serveur pour chercher sur YouTube, et il se lit ici dans le lecteur officiel YouTube. Spotify s’ouvre dans son app.';

  @override
  String get memoryTitle => 'Mémoire';

  @override
  String get consentTitle => 'Je me souviens de toi ?';

  @override
  String get consentBody =>
      'La mémoire reste sur ce téléphone, chiffrée. Tu peux tout voir, modifier, supprimer ou exporter à tout moment. Les faits retenus sont envoyés à l’IA avec tes messages pour te connaître.';

  @override
  String get rememberFacts =>
      'Retenir les faits que je te dis (ex. « retiens que j’aime le thé »)';

  @override
  String get rememberHistory => 'Garder l’historique des discussions';

  @override
  String get saveConsent => 'Enregistrer';

  @override
  String get addFact => 'Ajouter un fait';

  @override
  String get editItem => 'Modifier';

  @override
  String get deleteItem => 'Supprimer';

  @override
  String get deleteAll => 'Tout supprimer';

  @override
  String get deleteAllConfirm =>
      'Sûr ? Tout sera effacé, clé de chiffrement comprise.';

  @override
  String get exportJson => 'Exporter en JSON';

  @override
  String get exported => 'Exporté';

  @override
  String get exportCancelled => 'Export annulé';

  @override
  String get noMemories => 'Rien en mémoire';

  @override
  String get factsTab => 'Faits';

  @override
  String get historyTab => 'Historique';

  @override
  String get cancel => 'Annuler';

  @override
  String get save => 'Enregistrer';

  @override
  String get memoryUnreadable =>
      'Impossible de lire l’ancienne mémoire (clé ou fichier invalide). Repart à zéro.';

  @override
  String get robotTitle => 'Lien robot';

  @override
  String get robotNotice =>
      'Aucun robot physique n’existe encore. Cet écran teste le protocole avec un robot simulé. BLE et Wi-Fi sont des squelettes pour plus tard.';

  @override
  String get transportLocal => 'Ce téléphone';

  @override
  String get transportSim => 'Robot simulé';

  @override
  String get transportBle => 'Bluetooth LE';

  @override
  String get transportWifi => 'Wi-Fi';

  @override
  String get connect => 'Connecter';

  @override
  String get disconnect => 'Déconnecter';

  @override
  String get connected => 'Connecté';

  @override
  String get disconnected => 'Déconnecté';

  @override
  String get connecting => 'Connexion…';

  @override
  String get failed => 'Échec';

  @override
  String get bleNotBundled => 'Aucun moteur BLE dans cette version';

  @override
  String get wifiUrl => 'URL WebSocket';

  @override
  String get simulateTouch => 'Simuler un toucher';

  @override
  String get ping => 'Ping';

  @override
  String get btPermissionsDenied => 'Permissions Bluetooth refusées';

  @override
  String get providerHealth => 'État des services';

  @override
  String get lastErrors => 'Dernières erreurs';

  @override
  String get clear => 'Effacer';

  @override
  String get noErrors => 'Aucune erreur';

  @override
  String get chipHello => 'Salam Sahbi';

  @override
  String get newChat => 'Nouvelle discussion';

  @override
  String get emptyChat => 'Dis-moi quelque chose !';

  @override
  String get listeningHint => 'Parle maintenant…';

  @override
  String get liveTitle => 'Caméra live';

  @override
  String get liveConnecting => 'Connexion…';

  @override
  String get liveHint => 'Montre-moi quelque chose et pose ta question';

  @override
  String get liveReconnecting => 'Reconnexion…';

  @override
  String get liveNotConfigured =>
      'La caméra live n’est pas configurée sur le serveur (clé Gemini requise).';

  @override
  String get liveError => 'Impossible de démarrer la caméra live.';

  @override
  String get liveEnded => 'Session terminée.';

  @override
  String get liveTimeLimit =>
      'Session arrêtée après 10 min pour préserver le quota gratuit. Relance si tu veux.';

  @override
  String get liveRetry => 'Réessayer';

  @override
  String get liveMute => 'Couper le micro';

  @override
  String get liveUnmute => 'Activer le micro';

  @override
  String get liveSwitchCamera => 'Changer de caméra';

  @override
  String get liveEnd => 'Terminer';

  @override
  String get liveNoCamera => 'Aucune caméra trouvée.';

  @override
  String get liveNeedsInternet => 'La caméra live a besoin d’Internet.';

  @override
  String get cameraRationaleTitle => 'Je regarde avec toi ?';

  @override
  String get cameraRationaleBody =>
      'Pour voir ce que tu me montres, j’ai besoin de la caméra et du micro. Les images (≈1 par seconde) et le son vont directement à Google Gemini pendant la session uniquement. L’app n’enregistre rien.';

  @override
  String get cameraDenied =>
      'Sans caméra et micro je ne peux pas voir. Autorise-les dans les réglages.';

  @override
  String get openCamera => 'Caméra';

  @override
  String get robotNameTitle => 'Nom du robot';

  @override
  String get robotNameHint => 'ex. Zizou, Bobo… (vide = Sahbi)';

  @override
  String get robotNameDialogTitle => 'Comment veux-tu m’appeler ?';

  @override
  String robotNameSaved(String name) {
    return 'C’est noté, je m’appelle $name !';
  }

  @override
  String get voiceGenderTitle => 'Voix du robot';

  @override
  String get voiceMale => 'Homme';

  @override
  String get voiceFemale => 'Femme';

  @override
  String get voiceGenderNote =>
      'La voix du serveur (Gemini) change tout de suite. La voix du téléphone dépend des voix installées : sans voix d’homme, on baisse un peu la hauteur.';

  @override
  String get wakeByNameTitle => 'Répondre quand on m’appelle par mon nom';

  @override
  String wakeByNameSubtitle(String name) {
    return 'Seulement quand l’app est ouverte. Dis « $name » (ou « $name, quel temps fait-il ? ») sans appuyer. Consomme un peu de batterie ; certains téléphones bipent à chaque relance.';
  }

  @override
  String get wakeByNameNoMic => 'Autorise le micro pour que j’entende mon nom.';

  @override
  String wakeListening(String name) {
    return 'J’attends mon nom : $name';
  }

  @override
  String get keepScreenOn => 'Garder l’écran allumé sur le visage';

  @override
  String get photoModeHint =>
      'Je ne peux pas lancer la vidéo en direct maintenant. Vise quelque chose et appuie sur 📸, je t’explique.';

  @override
  String get photoSnap => 'Photo et explication';

  @override
  String get photoQuestion =>
      'Qu’est-ce que c’est ? Explique-moi ce que tu vois sur cette photo.';

  @override
  String get photoThinking => 'Je regarde…';

  @override
  String get photoError =>
      'Je n’ai pas pu expliquer la photo. Réessaie plus tard.';

  @override
  String ytSearching(String query) {
    return 'Je cherche sur YouTube : $query…';
  }

  @override
  String get ytError =>
      'Aucune de ces vidéos ne peut être lue ici. Essaie un autre morceau.';

  @override
  String get ytNext => 'Suivant';

  @override
  String get ytClose => 'Fermer';

  @override
  String photosCaption(String source) {
    return 'Photos : $source. Touche pour agrandir.';
  }

  @override
  String get photoOpenPage => 'Auteur et licence';

  @override
  String get photoFailed => 'Photo indisponible';

  @override
  String photosFor(String query) {
    return 'Photos : $query';
  }

  @override
  String get proactiveTitle => 'Me parler quand je me tais';

  @override
  String get proactiveSubtitle =>
      'Blagues, devinettes et questions de temps en temps quand l’app est ouverte. Après 10 minutes sans réponse je m’endors jusqu’à ce que tu m’appelles par mon nom. Chaque phrase utilise une requête IA.';

  @override
  String sleepingHint(String name) {
    return 'Je dors… appelle « $name » pour me réveiller';
  }

  @override
  String get sleepingHintTap => 'Je dors… touche pour me réveiller';

  @override
  String get conversationOn => 'Je t’écoute — dis « safi sir » pour arrêter';

  @override
  String get conversationEnd => 'Terminer la conversation';

  @override
  String get liveAutoDescribe => 'Expliquer ce que je montre';

  @override
  String get liveAutoDescribeHint => 'Vise un objet et reste immobile';

  @override
  String get ytPlay => 'Lecture';

  @override
  String get ytPause => 'Pause';

  @override
  String get liveTapHint => 'Touche un objet ou montre-le du doigt';

  @override
  String get pointLooking => 'Je regarde ce que tu montres…';

  @override
  String get pointNotFound =>
      'Je ne trouve rien là, touche l’objet directement';

  @override
  String pointQuestion(String label) {
    return 'C’est quoi, ce que je montre ($label) ? Parle seulement de cet objet.';
  }
}
