import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../admin_service.dart';

/// DriverDetailScreen — approve or reject a single driver application.
class DriverDetailScreen extends ConsumerStatefulWidget {
  final DriverQueueItem driver;

  const DriverDetailScreen({super.key, required this.driver});

  @override
  ConsumerState<DriverDetailScreen> createState() =>
      _DriverDetailScreenState();
}

class _DriverDetailScreenState extends ConsumerState<DriverDetailScreen> {
  bool _isLoading = false;

  Future<void> _approve() async {
    setState(() => _isLoading = true);
    try {
      await ref
          .read(adminServiceProvider)
          .approveDriver(widget.driver.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Driver approved successfully')),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _reject() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => _RejectDialog(),
    );
    if (reason == null || reason.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      await ref
          .read(adminServiceProvider)
          .rejectDriver(widget.driver.id, reason: reason);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Driver rejected')),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.driver;
    return Scaffold(
      appBar: AppBar(title: Text(d.fullName)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _InfoCard(title: 'Personal Details', items: {
            'Name': d.fullName,
            'Phone': d.phone,
          }),
          const SizedBox(height: 12),
          _InfoCard(title: 'License', items: {
            'License Number': d.licenseNumber,
          }),
          const SizedBox(height: 12),
          _InfoCard(title: 'Vehicle', items: {
            'Number': d.vehicleNumber,
            'Type': d.vehicleType,
            'Make': d.vehicleMake,
            'Model': d.vehicleModel,
          }),
          const SizedBox(height: 32),
          if (_isLoading)
            const Center(
                child: CircularProgressIndicator(color: AppTheme.primary))
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _reject,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.error,
                      side: const BorderSide(color: AppTheme.error),
                      minimumSize: const Size(0, 52),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _approve,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(0, 52),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Approve'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final Map<String, String> items;

  const _InfoCard({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                  letterSpacing: 0.5)),
          const SizedBox(height: 12),
          ...items.entries.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(e.key,
                          style: const TextStyle(
                              color: AppTheme.textHint, fontSize: 13)),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(e.value,
                          style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w500,
                              fontSize: 14)),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

class _RejectDialog extends StatefulWidget {
  @override
  State<_RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends State<_RejectDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reason for Rejection'),
      content: TextField(
        controller: _ctrl,
        decoration: const InputDecoration(
            hintText: 'e.g. Documents not clear'),
        maxLines: 3,
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        ElevatedButton(
            onPressed: () => Navigator.pop(context, _ctrl.text),
            child: const Text('Reject')),
      ],
    );
  }
}
