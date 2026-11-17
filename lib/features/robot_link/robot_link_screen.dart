import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/zellige.dart';
import '../../l10n/app_localizations.dart';
import 'ble_transport.dart';
import 'local_phone_transport.dart';
import 'protocol.dart';
import 'robot_transport.dart';
import 'simulated_robot_transport.dart';
import 'wifi_transport.dart';

/// Developer/experimental screen for the robot protocol.
class RobotLinkScreen extends ConsumerStatefulWidget {
  const RobotLinkScreen({super.key});

  @override
  ConsumerState<RobotLinkScreen> createState() => _RobotLinkScreenState();
}

class _RobotLinkScreenState extends ConsumerState<RobotLinkScreen> {
  String _kind = 'sim';
  final _wifi = TextEditingController(text: 'ws://192.168.4.1:8787/robot');

  @override
  void dispose() {
    _wifi.dispose();
    super.dispose();
  }

  RobotTransport? _build() {
    switch (_kind) {
      case 'local':
        return LocalPhoneTransport(onFace: (_) {});
      case 'sim':
        return SimulatedRobotTransport();
      case 'ble':
        return BleTransport(deviceId: 'SAHBI-BLE');
      case 'wifi':
        final u = Uri.tryParse(_wifi.text.trim());
        return u == null ? null : WifiTransport(url: u);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final link = ref.watch(robotLinkProvider);
    final c = link.connection;
    final t = link.transport;
    final connected = c == RobotConnection.connected;

    final status = switch (c) {
      RobotConnection.connected => (l.connected, SahbiColors.green),
      RobotConnection.connecting => (l.connecting, SahbiColors.amber),
      RobotConnection.failed => (l.failed, SahbiColors.coral),
      RobotConnection.disconnected => (
        l.disconnected,
        SahbiColors.textSecondary,
      ),
    };

    return Scaffold(
      appBar: AppBar(title: Text(l.robotTitle)),
      body: ZelligeBackground(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              l.robotNotice,
              style: const TextStyle(color: SahbiColors.amber, height: 1.4),
            ),
            const SizedBox(height: 12),
            ZelligeCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: 'local',
                        label: Text(
                          l.transportLocal,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      ButtonSegment(
                        value: 'sim',
                        label: Text(
                          l.transportSim,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      ButtonSegment(
                        value: 'ble',
                        label: Text(
                          l.transportBle,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      ButtonSegment(
                        value: 'wifi',
                        label: Text(
                          l.transportWifi,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                    selected: {_kind},
                    onSelectionChanged: connected
                        ? null
                        : (s) => setState(() => _kind = s.first),
                  ),
                  if (_kind == 'ble')
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        l.bleNotBundled,
                        style: const TextStyle(
                          fontSize: 12,
                          color: SahbiColors.textSecondary,
                        ),
                      ),
                    ),
                  if (_kind == 'wifi')
                    TextField(
                      controller: _wifi,
                      decoration: InputDecoration(labelText: l.wifiUrl),
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.circle, size: 12, color: status.$2),
                      const SizedBox(width: 6),
                      Text(status.$1),
                      if (t != null)
                        Text(
                          '  ·  ${t.label}',
                          style: const TextStyle(
                            color: SahbiColors.textSecondary,
                          ),
                        ),
                      const Spacer(),
                      if (connected || c == RobotConnection.connecting)
                        OutlinedButton(
                          onPressed: link.disconnect,
                          child: Text(l.disconnect),
                        )
                      else
                        FilledButton(
                          key: const Key('robot_connect'),
                          onPressed: () async {
                            final tr = _build();
                            if (tr == null) return;
                            await link.use(tr);
                            await link.connect();
                          },
                          child: Text(l.connect),
                        ),
                    ],
                  ),
                  if (link.lastError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        link.lastError!,
                        style: const TextStyle(
                          color: SahbiColors.coral,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  if (t?.info != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '${t!.info!.deviceId} · fw ${t.info!.firmware} · ${t.info!.capabilities.join(', ')}'
                        '${t.info!.battery != null ? ' · ${(t.info!.battery! * 100).round()}%' : ''}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: SahbiColors.textSecondary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: connected
                      ? () => link.send(
                          const RobotMessage(
                            type: 'system.ping',
                            ackRequested: true,
                          ),
                        )
                      : null,
                  icon: const Icon(Icons.network_ping_rounded, size: 18),
                  label: Text(l.ping),
                ),
                OutlinedButton.icon(
                  onPressed: connected && t is SimulatedRobotTransport
                      ? () => t.simulateTouch()
                      : null,
                  icon: const Icon(Icons.touch_app_outlined, size: 18),
                  label: Text(l.simulateTouch),
                ),
                OutlinedButton(
                  onPressed: connected
                      ? () => link.send(
                          const RobotMessage(
                            type: 'motor.move',
                            payload: {
                              'left': 0.3,
                              'right': 0.3,
                              'duration_ms': 400,
                            },
                            ackRequested: true,
                          ),
                        )
                      : null,
                  child: const Text('motor.move 0.3 / 400 ms'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              '${RobotProtocol.serviceUuid}\nv${RobotProtocol.version}',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: SahbiColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            ZelligeCard(
              child: link.eventLog.isEmpty
                  ? const Text('—')
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final e in link.eventLog.reversed)
                          Text(
                            e,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
