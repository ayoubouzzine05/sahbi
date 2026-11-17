import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/zellige.dart';
import '../../l10n/app_localizations.dart';
import 'memory_store.dart';

/// Consent + view/edit/delete/export for the encrypted local memory.
class MemoryScreen extends ConsumerStatefulWidget {
  const MemoryScreen({super.key});

  @override
  ConsumerState<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends ConsumerState<MemoryScreen> {
  bool? _facts;
  bool? _history;

  Future<String?> _editDialog(String title, [String initial = '']) {
    final c = TextEditingController(text: initial);
    final l = L10n.of(context);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          maxLines: 3,
          maxLength: 300,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: Text(l.save),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final mem = ref.watch(memoryStoreProvider);
    final messenger = ScaffoldMessenger.of(context);
    final facts = _facts ?? mem.consentFacts;
    final history = _history ?? mem.consentHistory;
    final dirty = facts != mem.consentFacts || history != mem.consentHistory;

    Widget itemTile(MemoryItem it) => ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(it.text, maxLines: 3, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${it.kind == 'fact' ? '' : '${it.kind} · '}${MaterialLocalizations.of(context).formatShortDate(it.createdAt)}',
        style: const TextStyle(fontSize: 11),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (it.kind == 'fact')
            IconButton(
              tooltip: l.editItem,
              icon: const Icon(Icons.edit_outlined, size: 20),
              onPressed: () async {
                final t = await _editDialog(l.editItem, it.text);
                if (t != null && t.isNotEmpty) await mem.update(it.id, t);
              },
            ),
          IconButton(
            tooltip: l.deleteItem,
            icon: const Icon(Icons.delete_outline_rounded, size: 20),
            onPressed: () => mem.delete(it.id),
          ),
        ],
      ),
    );

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(title: Text(l.memoryTitle)),
        body: ZelligeBackground(
          child: !mem.loaded
              ? const Center(child: ZelligeLoader())
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (mem.loadError != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          l.memoryUnreadable,
                          style: const TextStyle(color: SahbiColors.amber),
                        ),
                      ),
                    ZelligeCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l.consentTitle,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l.consentBody,
                            style: const TextStyle(
                              color: SahbiColors.textSecondary,
                              height: 1.45,
                            ),
                          ),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            value: facts,
                            onChanged: (v) =>
                                setState(() => _facts = v ?? false),
                            title: Text(l.rememberFacts),
                          ),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            value: history,
                            onChanged: (v) =>
                                setState(() => _history = v ?? false),
                            title: Text(l.rememberHistory),
                          ),
                          Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: FilledButton(
                              key: const Key('save_consent'),
                              onPressed: dirty
                                  ? () async {
                                      await mem.setConsent(
                                        facts: facts,
                                        history: history,
                                      );
                                      setState(() => _facts = _history = null);
                                    }
                                  : null,
                              child: Text(l.saveConsent),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${l.factsTab} (${mem.facts.length})',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        IconButton(
                          tooltip: l.addFact,
                          icon: const Icon(Icons.add_rounded),
                          onPressed: mem.consentFacts
                              ? () async {
                                  final t = await _editDialog(l.addFact);
                                  if (t != null && t.isNotEmpty) {
                                    await mem.addFact(t);
                                  }
                                }
                              : null,
                        ),
                      ],
                    ),
                    if (mem.facts.isEmpty)
                      Text(
                        l.noMemories,
                        style: const TextStyle(
                          color: SahbiColors.textSecondary,
                        ),
                      ),
                    for (final f in mem.facts) itemTile(f),
                    const SizedBox(height: 16),
                    Text(
                      '${l.historyTab} (${mem.history.length})',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (mem.history.isEmpty)
                      Text(
                        l.noMemories,
                        style: const TextStyle(
                          color: SahbiColors.textSecondary,
                        ),
                      ),
                    for (final h in mem.history.reversed.take(50)) itemTile(h),
                    const SizedBox(height: 24),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: mem.items.isEmpty && !mem.anyConsent
                              ? null
                              : () async {
                                  final ok = await ref
                                      .read(platformBridgeProvider)
                                      .saveDocument(
                                        'sahbi_memory_${DateTime.now().toIso8601String().substring(0, 10)}.json',
                                        utf8.encode(mem.exportJson()),
                                        'application/json',
                                      );
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        ok ? l.exported : l.exportCancelled,
                                      ),
                                    ),
                                  );
                                },
                          icon: const Icon(Icons.download_rounded),
                          label: Text(l.exportJson),
                        ),
                        OutlinedButton.icon(
                          key: const Key('delete_all'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: SahbiColors.coral,
                          ),
                          onPressed: () async {
                            final yes = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: Text(l.deleteAll),
                                content: Text(l.deleteAllConfirm),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: Text(l.cancel),
                                  ),
                                  FilledButton(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: SahbiColors.coral,
                                    ),
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: Text(l.deleteAll),
                                  ),
                                ],
                              ),
                            );
                            if (yes == true) {
                              await mem.deleteAll();
                              setState(() => _facts = _history = null);
                            }
                          },
                          icon: const Icon(Icons.delete_forever_outlined),
                          label: Text(l.deleteAll),
                        ),
                      ],
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
