import 'emotion.dart';
import 'personality_responses.dart';

/// Fixed lines said without the AI (instant, work offline).
class CompanionLines {
  CompanionLines._();

  /// After "safi sir": the conversation ends, back to waiting for the name.
  static const goodbye = Line(
    darijaAr: 'واخا، صافي. إلا بغيتيني عيط عليا بسميتي.',
    darijaLatin: 'Wakha, safi. Ila bghitini 3iyet 3liya b smiyti.',
    msa: 'حسنا. إذا احتجتني فنادني باسمي.',
    fr: 'D’accord. Appelle-moi par mon nom si tu as besoin de moi.',
    en: 'Okay. Call my name whenever you need me.',
    emotion: Emotion.happy,
    intensity: 0.5,
  );

  /// After 10 minutes without an answer.
  static const goodnight = Line(
    darijaAr: 'إيوا، أنا غادي نعس شوية. عيط عليا بسميتي إلا بغيتيني.',
    darijaLatin:
        'Iwa, ana ghadi n3es chwiya. 3iyet 3liya b smiyti ila bghitini.',
    msa: 'سأنام قليلا. نادني باسمي إذا احتجتني.',
    fr: 'Je vais faire une petite sieste. Appelle-moi par mon nom si tu as besoin de moi.',
    en: 'I’ll take a little nap. Call my name if you need me.',
    emotion: Emotion.sleepy,
    intensity: 0.8,
  );
}
