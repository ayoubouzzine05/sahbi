// Main-flow integration test. Runs on a device/emulator:
//   flutter test integration_test
// Built without SAHBI_BACKEND_URL, so the AI is honestly "offline" and
// replies must be labelled as offline (cloud_off icon). Local commands work.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sahbi/features/face/robot_face.dart';
import 'package:sahbi/features/music/music_screen.dart';
import 'package:sahbi/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'home face → chat (offline label + local command) → music → settings',
    (t) async {
      await app.main();
      // The face animates forever, so pumpAndSettle would never return: pump frames.
      Future<void> frames([int n = 20]) async {
        for (var i = 0; i < n; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
      }

      await frames(30);
      expect(
        find.byType(RobotFace),
        findsWidgets,
        reason: 'home shows the robot face',
      );

      // First launch: the robot's eyes explain the camera once. Answer
      // "not now" like a user (its eyes stay closed).
      // Then the one-time offer of the offline "MIMO" wake model.
      for (var i = 0; i < 3; i++) {
        final dialog = find.byType(AlertDialog);
        if (dialog.evaluate().isEmpty) break;
        await t.tap(
          find.descendant(of: dialog, matching: find.byType(TextButton)).first,
        );
        await frames(10);
      }
      expect(find.byType(AlertDialog), findsNothing);

      // Chat: the home face has no tab bar; its keyboard button opens chat.
      await t.tap(find.byIcon(Icons.keyboard_alt_outlined));
      await frames();
      await t.enterText(find.byKey(const Key('chat_input')), 'chno smitek?');
      await t.pump(); // send button enables on the next frame
      await t.tap(find.byKey(const Key('chat_send')));
      await frames(30);
      expect(find.text('chno smitek?'), findsWidgets);
      expect(
        find.byIcon(Icons.cloud_off_rounded),
        findsWidgets,
        reason: 'no backend → reply is labelled offline',
      );

      // Local command works without the AI.
      await t.enterText(find.byKey(const Key('chat_input')), 'pause');
      await t.pump(); // send button enables on the next frame
      await t.tap(find.byKey(const Key('chat_send')));
      await frames(20);
      expect(find.text('pause'), findsWidgets);

      // Music tab shows the bundled demo tracks.
      await t.tap(find.byIcon(Icons.music_note_outlined));
      await frames();
      await t.scrollUntilVisible(
        find.textContaining('Atlas Breeze'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(MusicScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.textContaining('Atlas Breeze'), findsWidgets);

      // Settings tab opens.
      await t.tap(find.byIcon(Icons.tune_outlined));
      await frames();
      expect(find.byType(ListView), findsWidgets);
    },
  );
}
