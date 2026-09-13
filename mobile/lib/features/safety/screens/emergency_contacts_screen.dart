import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../auth/widgets/primary_button.dart';
import '../safety_service.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

// FutureProvider loads contacts on open, autoDispose refreshes on re-open
final _contactsProvider =
    FutureProvider.autoDispose<List<EmergencyContact>>((ref) {
  return ref.watch(safetyServiceProvider).getContacts();
});

/// EmergencyContactsScreen — manages up to 3 emergency contacts.
///
/// These are the people who get SMS alerts when the passenger triggers
/// SOS or doesn't respond to a route deviation within 2 minutes.
///
/// Max 3 contacts (enforced by the backend).
/// One can be marked as primary — they're contacted first.
class EmergencyContactsScreen extends ConsumerWidget {
  const EmergencyContactsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncContacts = ref.watch(_contactsProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Emergency Contacts'),
        backgroundColor: AppTheme.surface,
        elevation: 0,
      ),
      body: asyncContacts.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppTheme.primary)),
        error: (e, _) => _ErrorView(
          message: e.toString(),
          onRetry: () => ref.invalidate(_contactsProvider),
        ),
        data: (contacts) => _ContactsBody(contacts: contacts),
      ),
    );
  }
}

// ── Body ──────────────────────────────────────────────────────────────────────

class _ContactsBody extends ConsumerWidget {
  final List<EmergencyContact> contacts;
  const _ContactsBody({required this.contacts});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // ── Info card ────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.primary.withOpacity(0.07),
            borderRadius: BorderRadius.circular(12),
            border:
                Border.all(color: AppTheme.primary.withOpacity(0.2)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 18, color: AppTheme.primary),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'These contacts receive an SMS with your live location '
                  'if you trigger SOS or don\'t respond to a route deviation alert.',
                  style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                      height: 1.4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // ── Contact list ─────────────────────────────────────────────────
        if (contacts.isEmpty)
          const _EmptyState()
        else
          ...contacts.map((c) => _ContactTile(
                contact: c,
                onDeleted: () => ref.invalidate(_contactsProvider),
              )),

        const SizedBox(height: 16),

        // ── Add button (max 3) ───────────────────────────────────────────
        if (contacts.length < 3)
          PrimaryButton(
            label: 'Add Emergency Contact',
            icon: Icons.person_add_outlined,
            onPressed: () async {
              final added = await showModalBottomSheet<bool>(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => const _AddContactSheet(),
              );
              if (added == true) ref.invalidate(_contactsProvider);
            },
          )
        else
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              children: [
                Icon(Icons.check_circle_outline,
                    size: 16, color: AppTheme.success),
                SizedBox(width: 8),
                Text(
                  'Maximum 3 contacts added.',
                  style: TextStyle(
                      fontSize: 13, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ── Contact tile ──────────────────────────────────────────────────────────────

class _ContactTile extends ConsumerWidget {
  final EmergencyContact contact;
  final VoidCallback onDeleted;

  const _ContactTile(
      {required this.contact, required this.onDeleted});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: contact.isPrimary
              ? AppTheme.primary.withOpacity(0.4)
              : AppTheme.divider,
        ),
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: contact.isPrimary
                  ? AppTheme.primaryLight.withOpacity(0.3)
                  : const Color(0xFFF0F0F0),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.person_outline,
                color: contact.isPrimary
                    ? AppTheme.primary
                    : AppTheme.textSecondary,
                size: 22),
          ),
          const SizedBox(width: 12),

          // Name + phone + relation
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      contact.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    if (contact.isPrimary) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Primary',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '+91 ${contact.phone}',
                  style: const TextStyle(
                      fontSize: 13, color: AppTheme.textSecondary),
                ),
                if (contact.relation != null)
                  Text(
                    contact.relation!,
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.textHint),
                  ),
              ],
            ),
          ),

          // Delete button
          IconButton(
            onPressed: () => _confirmDelete(context, ref),
            icon: const Icon(Icons.delete_outline,
                color: AppTheme.error, size: 20),
            tooltip: 'Remove',
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Contact?'),
        content: Text(
            '${contact.name} will no longer receive emergency alerts.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(safetyServiceProvider).deleteContact(contact.id);
      onDeleted();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString()),
          backgroundColor: AppTheme.error,
        ));
      }
    }
  }
}

// ── Add contact bottom sheet ──────────────────────────────────────────────────

class _AddContactSheet extends ConsumerStatefulWidget {
  const _AddContactSheet();

  @override
  ConsumerState<_AddContactSheet> createState() => _AddContactSheetState();
}

class _AddContactSheetState extends ConsumerState<_AddContactSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _relationCtrl = TextEditingController();
  bool _isPrimary = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _relationCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await ref.read(safetyServiceProvider).addContact(
            name: _nameCtrl.text.trim(),
            phone: _phoneCtrl.text.trim(),
            relation: _relationCtrl.text.trim().isEmpty
                ? null
                : _relationCtrl.text.trim(),
            isPrimary: _isPrimary,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 20, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                    color: AppTheme.divider,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const Text(
              'Add Emergency Contact',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 20),

            // Name
            TextFormField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                hintText: 'Full name',
                prefixIcon: Icon(Icons.person_outline,
                    color: AppTheme.textHint),
              ),
              validator: (v) => (v == null || v.trim().length < 2)
                  ? 'Enter a valid name'
                  : null,
            ),
            const SizedBox(height: 12),

            // Phone
            TextFormField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              maxLength: 10,
              decoration: const InputDecoration(
                hintText: '10-digit mobile number',
                prefixIcon:
                    Icon(Icons.phone_outlined, color: AppTheme.textHint),
                prefixText: '+91 ',
                counterText: '',
              ),
              validator: (v) {
                if (v == null || v.trim().length != 10) {
                  return 'Enter a valid 10-digit number';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),

            // Relation (optional)
            TextFormField(
              controller: _relationCtrl,
              decoration: const InputDecoration(
                hintText: 'Relation (optional) — e.g. Mother',
                prefixIcon:
                    Icon(Icons.people_outline, color: AppTheme.textHint),
              ),
            ),
            const SizedBox(height: 12),

            // Primary toggle
            Row(
              children: [
                Switch(
                  value: _isPrimary,
                  onChanged: (v) => setState(() => _isPrimary = v),
                  activeColor: AppTheme.primary,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Set as primary contact',
                    style: TextStyle(
                        fontSize: 14, color: AppTheme.textSecondary),
                  ),
                ),
              ],
            ),

            // Error
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: Text(_error!,
                    style: const TextStyle(
                        color: AppTheme.error, fontSize: 13)),
              ),

            const SizedBox(height: 16),
            PrimaryButton(
              label: 'Save Contact',
              isLoading: _saving,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Helper views ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(Icons.people_outline, size: 56, color: AppTheme.textHint),
          SizedBox(height: 12),
          Text(
            'No emergency contacts yet',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary),
          ),
          SizedBox(height: 6),
          Text(
            'Add up to 3 contacts who will be alerted\nin case of an emergency.',
            textAlign: TextAlign.center,
            style:
                TextStyle(fontSize: 13, color: AppTheme.textHint, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off_outlined,
                size: 64, color: AppTheme.textHint),
            const SizedBox(height: 16),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 14)),
            const SizedBox(height: 24),
            PrimaryButton(label: 'Try Again', onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}
