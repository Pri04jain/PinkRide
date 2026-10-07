import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';

/// EmergencyContactsScreen — manage up to 3 emergency contacts.
class EmergencyContactsScreen extends StatefulWidget {
  const EmergencyContactsScreen({super.key});

  @override
  State<EmergencyContactsScreen> createState() =>
      _EmergencyContactsScreenState();
}

class _EmergencyContactsScreenState extends State<EmergencyContactsScreen> {
  // Placeholder contacts for UI demo
  final List<Map<String, String>> _contacts = [];

  void _addContact() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _AddContactSheet(
        onSave: (name, phone, relation) {
          setState(() {
            _contacts.add({
              'name': name,
              'phone': phone,
              'relation': relation,
            });
          });
          Navigator.pop(context);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Emergency Contacts')),
      floatingActionButton: _contacts.length < 3
          ? FloatingActionButton.extended(
              onPressed: _addContact,
              backgroundColor: AppTheme.primary,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text('Add Contact',
                  style: TextStyle(color: Colors.white)),
            )
          : null,
      body: _contacts.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.contact_phone_outlined,
                      size: 64, color: AppTheme.textHint),
                  const SizedBox(height: 16),
                  const Text(
                    'No emergency contacts yet',
                    style: TextStyle(
                        fontSize: 16, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Add up to 3 contacts. They\'ll be\nalerted if a route deviation is detected.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13, color: AppTheme.textHint),
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _contacts.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final contact = _contacts[index];
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
                      contact['name']!.substring(0, 1).toUpperCase(),
                      style: const TextStyle(
                          color: AppTheme.primary,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  title: Text(contact['name']!,
                      style:
                          const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                      '${contact['phone']} · ${contact['relation']}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline,
                        color: AppTheme.error),
                    onPressed: () =>
                        setState(() => _contacts.removeAt(index)),
                  ),
                );
              },
            ),
    );
  }
}

class _AddContactSheet extends StatefulWidget {
  final void Function(String name, String phone, String relation) onSave;
  const _AddContactSheet({required this.onSave});

  @override
  State<_AddContactSheet> createState() => _AddContactSheetState();
}

class _AddContactSheetState extends State<_AddContactSheet> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  String _relation = 'Family';

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Add Emergency Contact',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Full Name'),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneController,
            decoration: const InputDecoration(labelText: 'Phone Number'),
            keyboardType: TextInputType.phone,
            maxLength: 10,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _relation,
            decoration: const InputDecoration(labelText: 'Relation'),
            items: ['Family', 'Friend', 'Colleague', 'Other']
                .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                .toList(),
            onChanged: (v) => setState(() => _relation = v ?? 'Family'),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () {
                if (_nameController.text.isNotEmpty &&
                    _phoneController.text.length == 10) {
                  widget.onSave(
                    _nameController.text,
                    _phoneController.text,
                    _relation,
                  );
                }
              },
              child: const Text('Save Contact'),
            ),
          ),
        ],
      ),
    );
  }
}
