import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../admin_service.dart';

final _pendingDriversProvider =
    FutureProvider<List<DriverQueueItem>>((ref) {
  return ref.watch(adminServiceProvider).getPendingDrivers();
});

/// DriverQueueScreen — admin view of drivers awaiting approval.
class DriverQueueScreen extends ConsumerWidget {
  const DriverQueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final driversAsync = ref.watch(_pendingDriversProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver Approvals'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(_pendingDriversProvider),
          ),
        ],
      ),
      body: driversAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppTheme.primary)),
        error: (e, _) => Center(
            child: Text('Error: $e',
                style: const TextStyle(color: AppTheme.error))),
        data: (drivers) => drivers.isEmpty
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle_outline_rounded,
                        size: 64, color: AppTheme.success),
                    SizedBox(height: 16),
                    Text('No pending drivers',
                        style: TextStyle(
                            fontSize: 16, color: AppTheme.textSecondary)),
                  ],
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: drivers.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final driver = drivers[index];
                  return ListTile(
                    tileColor: AppTheme.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: AppTheme.divider),
                    ),
                    leading: CircleAvatar(
                      backgroundColor:
                          AppTheme.primaryLight.withOpacity(0.3),
                      child: Text(
                        driver.fullName.substring(0, 1).toUpperCase(),
                        style: const TextStyle(
                            color: AppTheme.primary,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                    title: Text(driver.fullName,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600)),
                    subtitle: Text(
                        '${driver.vehicleMake} ${driver.vehicleModel} · ${driver.vehicleNumber}'),
                    trailing: const Icon(Icons.chevron_right_rounded,
                        color: AppTheme.textHint),
                    onTap: () => context.push(
                      AppRoutes.adminDriverDetail
                          .replaceFirst(':driverId', driver.id),
                      extra: driver,
                    ),
                  );
                },
              ),
      ),
    );
  }
}
