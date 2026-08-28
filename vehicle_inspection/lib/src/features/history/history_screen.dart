import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../core/widgets/state_views.dart';
import '../../domain/entities/inspection_summary.dart';
import '../sync/sync_banner.dart';
import 'widgets/inspection_row.dart';

/// Currently selected history tab.
final historyFilterProvider = StateProvider<InspectionHistoryFilter>(
  (ref) => InspectionHistoryFilter.all,
);

/// Free-text search across registration, make, model, VIN and reference.
final historySearchProvider = StateProvider<String>((ref) => '');

/// Filtered history, re-queried whenever inspections change or the filter moves.
///
/// Filtering happens in SQL rather than in Dart so the screen stays responsive
/// once a device holds hundreds of inspections.
final historyProvider =
    StreamProvider.autoDispose<List<InspectionSummary>>((ref) {
  final repository = ref.watch(inspectionRepositoryProvider);
  final filter = ref.watch(historyFilterProvider);
  final query = ref.watch(historySearchProvider);

  return repository.watchSummaries().asyncMap(
        (_) => repository.fetchSummaries(filter: filter, query: query),
      );
});

/// All inspections stored on this device.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  static const String routeName = '/history';

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    // Debounced so typing does not fire a query per keystroke.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      ref.read(historySearchProvider.notifier).state = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(historyFilterProvider);
    final history = ref.watch(historyProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My Inspections')),
      body: Column(
        children: [
          const SyncBanner(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search registration, VIN or ID',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                          setState(() {});
                        },
                      ),
              ),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final value in InspectionHistoryFilter.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(value.label),
                      selected: filter == value,
                      onSelected: (_) => ref
                          .read(historyFilterProvider.notifier)
                          .state = value,
                      labelStyle: const TextStyle(fontSize: 12.5),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: history.when(
              loading: () => const LoadingView(),
              error: (error, _) => ErrorView(
                error: error,
                onRetry: () => ref.invalidate(historyProvider),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return EmptyState(
                    icon: Icons.assignment_outlined,
                    title: _emptyTitle(filter),
                    message:
                        'Inspections you create are stored on this device and '
                        'appear here, online or not.',
                    action: FilledButton.icon(
                      onPressed: () => Navigator.of(context)
                          .pushNamed(AppRoutes.newInspection),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('New Inspection'),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) =>
                      InspectionRow(summary: items[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _emptyTitle(InspectionHistoryFilter filter) => switch (filter) {
        InspectionHistoryFilter.all => 'No inspections yet',
        InspectionHistoryFilter.drafts => 'No drafts in progress',
        InspectionHistoryFilter.submitted => 'Nothing submitted yet',
        InspectionHistoryFilter.pendingSync => 'Everything is synced',
      };
}
