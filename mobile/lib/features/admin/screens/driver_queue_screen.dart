import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../admin_service.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

// Tracks which status tab is selected
final _selectedStatusProvider =
    StateProvider.autoDispose<String>((_) => 'under_review');

final _queueProvider =
    FutureProvider.autoDispose.family<List<DriverQueueItem>, String>(
  (ref, status) =>
      ref.watch(adminServiceProvider).getQueue(status: status),
);

final _statsProvider = FutureProvider.autoDispose<AdminStats>((ref) {
  return ref.watch(adminServiceProvider).getStats();
});

/// DriverQueueScreen — admin view of driver applications.
///
/// Three tabs: Under Review | Approved | Rejected
/// Each tab shows the list of drivers in that state.
/// Tapping a driver opens DriverDetailScreen for full review.
/// Stats card at top shows key numbers at a glance.

class DriverQueueScreen extends ConsumerWidget {
  const DriverQueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedStatus = ref.watch(_selectedStatusProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Driver Approvals'),
        backgroundColor: AppTheme.surface,
        elevation: 0,
      ),
      body: Column(
        children: [
          // ── Stats card ─────────────────────────────────────────────────
          _StatsCard(),

          // ── Tab bar ────────────────────────────────────────────────────
          Container(
            color: AppTheme.surface,
            child: Row(
              children: [
                _TabButton(
                  label: 'Under Review',
                  value: 'under_review',
                  selected: selectedStatus == 'under_review',
                  onTap: () => ref
                      .read(_selectedStatusProvider.notifier)
                      .state = 'under_review',
                ),
                _TabButton(
                  label: 'Approved',
                  value: 'approved',
                  selected: selectedStatus == 'approved',
                  onTap: () => ref
                      .read(_selectedStatusProvider.notifier)
                      .state = 'approved',
                ),
                _TabButton(
                  label: 'Rejected',
                  value: 'rejected',
                  selected: selectedStatus == 'rejected',
                  onTap: () => ref
                      .read(_selectedStatusProvider.notifier)
                      .state = 'rejected',
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: AppTheme.divider),

          // ── List ───────────────────────────────────────────────────────
          Expanded(
            child: ref.watch(_queueProvider(selectedStatus)).when(
              loading: () => const Center(
                  child:
                      CircularProgressIndicator(color: AppTheme.primary)),
              error: (e, _) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.cloud_off_outlined,
                        size: 48, color: AppTheme.textHint),
                    const SizedBox(height: 12),
                    Text(e.toString(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: AppTheme.textSecondary)),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () =>
                          ref.invalidate(_queueProvider(selectedStatus)),
                      child: const Text('Try Again'),
                    ),
                  ],
                ),
              ),
              data: (drivers) => drivers.isEmpty
                  ? const _EmptyQueue()
                  : RefreshIndicator(
                      color: AppTheme.primary,
                      onRefresh: () async =>
                          ref.invalidate(_queueProvider(selectedStatus)),
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: drivers.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 10),
                        itemBuilder: (_, i) =>
                            _DriverCard(driver: drivers[i]),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Stats card ────────────────────────────────────────────────────────────────

class _StatsCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncStats = ref.watch(_statsProvider);
    return asyncStats.maybeWhen(
      data: (stats) => Container(
        color: AppTheme.surface,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            _StatChip(
                label: 'Review',
                value: stats.underReview,
                color: AppTheme.warning),
            const SizedBox(width: 8),
            _StatChip(
                label: 'Approved',
                value: stats.approved,
                color: AppTheme.success),
            const SizedBox(width: 8),
            _StatChip(
                label: 'Online',
                value: stats.onlineNow,
                color: AppTheme.accent),
            const SizedBox(width: 8),
            _StatChip(
                label: 'Passengers',
                value: stats.totalPassengers,
                color: AppTheme.primary),
          ],
        ),
      ),
      orElse: () => const SizedBox(height: 8),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _StatChip(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(
              '$value',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color),
            ),
            Text(
              label,
              style: const TextStyle(
                  fontSize: 10, color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Tab button ────────────────────────────────────────────────────────────────

class _TabButton extends StatelessWidget {
  final String label;
  final String value;
  final bool selected;
  final VoidCallback onTap;
  const _TabButton(
      {required this.label,
      required this.value,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? AppTheme.primary : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
              color: selected ? AppTheme.primary : AppTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Driver card ───────────────────────────────────────────────────────────────

class _DriverCard extends StatelessWidget {
  final DriverQueueItem driver;
  const _DriverCard({required this.driver});

  @override
  Widget build(BuildContext context) {
    final dateStr =
        DateFormat('d MMM yyyy').format(driver.createdAt.toLocal());
    final statusColor = switch (driver.approvalStatus) {
      'under_review' => AppTheme.warning,
      'approved'     => AppTheme.success,
      'rejected'     => AppTheme.error,
      'suspended'    => AppTheme.error,
      _              => AppTheme.textSecondary,
    };

    return GestureDetector(
      onTap: () => context.push(
        AppRoutes.adminDriverDetail
            .replaceAll(':driverId', driver.id),
        extra: driver,
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppTheme.primaryLight.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person_outline,
                  color: AppTheme.primary, size: 24),
            ),
            const SizedBox(width: 12),

            // Name + vehicle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        driver.fullName,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      if (driver.faceVerified) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.verified,
                            size: 14, color: AppTheme.success),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    driver.vehicleDisplay,
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.textSecondary),
                  ),
                  Text(
                    'Applied $dateStr',
                    style: const TextStyle(
                        fontSize: 11, color: AppTheme.textHint),
                  ),
                ],
              ),
            ),

            // Status badge
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                driver.statusLabel,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: statusColor,
                ),
              ),
            ),

            const SizedBox(width: 4),
            const Icon(Icons.chevron_right,
                color: AppTheme.textHint, size: 18),
          ],
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyQueue extends StatelessWidget {
  const _EmptyQueue();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox_outlined, size: 56, color: AppTheme.textHint),
          SizedBox(height: 12),
          Text('No drivers in this queue',
              style: TextStyle(
                  fontSize: 15,
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
