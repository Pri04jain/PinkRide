import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../features/auth/widgets/primary_button.dart';
import '../providers/driver_provider.dart';

/// DriverRegisterScreen — two-step form to create a driver profile.
///
/// Step 1: License details (number + expiry)
/// Step 2: Vehicle details (type, make, model, year, color, number plate)
///
/// On success: pops back to DriverHomeScreen and calls
/// driverHomeProvider.onRegistrationComplete() to reload the profile
/// and advance to PendingApproval state.

class DriverRegisterScreen extends ConsumerStatefulWidget {
  const DriverRegisterScreen({super.key});

  @override
  ConsumerState<DriverRegisterScreen> createState() =>
      _DriverRegisterScreenState();
}

class _DriverRegisterScreenState extends ConsumerState<DriverRegisterScreen> {
  final _pageController = PageController();
  int _currentStep = 0;

  // Step 1 — License
  final _licenseController = TextEditingController();
  DateTime? _licenseExpiry;

  // Step 2 — Vehicle
  String _vehicleType = 'Sedan';
  final _vehicleMakeController = TextEditingController();
  final _vehicleModelController = TextEditingController();
  final _vehicleColorController = TextEditingController();
  final _vehicleNumberController = TextEditingController();
  int _vehicleYear = DateTime.now().year - 2;

  final _step1Key = GlobalKey<FormState>();
  final _step2Key = GlobalKey<FormState>();

  static const _vehicleTypes = [
    'Hatchback',
    'Sedan',
    'SUV',
    'MUV',
    'Van',
  ];

  @override
  void dispose() {
    _pageController.dispose();
    _licenseController.dispose();
    _vehicleMakeController.dispose();
    _vehicleModelController.dispose();
    _vehicleColorController.dispose();
    _vehicleNumberController.dispose();
    super.dispose();
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  void _nextStep() {
    if (_currentStep == 0) {
      if (!_step1Key.currentState!.validate()) return;
      if (_licenseExpiry == null) {
        _showError('Please select your license expiry date.');
        return;
      }
    }
    setState(() => _currentStep = 1);
    _pageController.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _prevStep() {
    setState(() => _currentStep = 0);
    _pageController.previousPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  // ── Submit ────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (!_step2Key.currentState!.validate()) return;

    final expiry = _licenseExpiry!;
    final expiryStr =
        '${expiry.year}-${expiry.month.toString().padLeft(2, '0')}-${expiry.day.toString().padLeft(2, '0')}';

    await ref.read(driverRegisterProvider.notifier).submit(
          licenseNumber: _licenseController.text.trim().toUpperCase(),
          licenseExpiry: expiryStr,
          vehicleNumber:
              _vehicleNumberController.text.trim().toUpperCase(),
          vehicleType: _vehicleType,
          vehicleMake: _vehicleMakeController.text.trim(),
          vehicleModel: _vehicleModelController.text.trim(),
          vehicleColor: _vehicleColorController.text.trim(),
          vehicleYear: _vehicleYear,
        );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppTheme.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ── Expiry date picker ────────────────────────────────────────────────────

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _licenseExpiry ?? now.add(const Duration(days: 365)),
      firstDate: now, // must be in the future
      lastDate: now.add(const Duration(days: 365 * 20)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: AppTheme.primary),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _licenseExpiry = picked);
  }

  @override
  Widget build(BuildContext context) {
    final regState = ref.watch(driverRegisterProvider);

    // Listen for success → pop and reload home
    ref.listen<DriverRegisterState>(driverRegisterProvider, (_, next) {
      if (next is DriverRegisterSuccess) {
        ref.read(driverHomeProvider.notifier).onRegistrationComplete();
        Navigator.of(context).pop();
      } else if (next is DriverRegisterError) {
        _showError(next.message);
        ref.read(driverRegisterProvider.notifier).clearError();
      }
    });

    final isSubmitting = regState is DriverRegisterSubmitting;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Driver Registration'),
        leading: _currentStep == 1
            ? BackButton(onPressed: _prevStep)
            : null,
      ),
      body: Column(
        children: [
          // Progress indicator
          _StepProgress(current: _currentStep),

          // Form pages
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _Step1License(
                  formKey: _step1Key,
                  licenseController: _licenseController,
                  licenseExpiry: _licenseExpiry,
                  onPickExpiry: _pickExpiry,
                  onNext: _nextStep,
                ),
                _Step2Vehicle(
                  formKey: _step2Key,
                  vehicleType: _vehicleType,
                  vehicleTypes: _vehicleTypes,
                  onVehicleTypeChanged: (v) =>
                      setState(() => _vehicleType = v!),
                  makeCtr: _vehicleMakeController,
                  modelCtr: _vehicleModelController,
                  colorCtr: _vehicleColorController,
                  numberCtr: _vehicleNumberController,
                  vehicleYear: _vehicleYear,
                  onYearChanged: (y) => setState(() => _vehicleYear = y),
                  isSubmitting: isSubmitting,
                  onSubmit: _submit,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Step progress ─────────────────────────────────────────────────────────────

class _StepProgress extends StatelessWidget {
  final int current;
  const _StepProgress({required this.current});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: [
          _StepDot(index: 0, current: current, label: 'License'),
          Expanded(
            child: Container(
              height: 2,
              color:
                  current >= 1 ? AppTheme.primary : AppTheme.divider,
            ),
          ),
          _StepDot(index: 1, current: current, label: 'Vehicle'),
        ],
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  final int index;
  final int current;
  final String label;
  const _StepDot(
      {required this.index,
      required this.current,
      required this.label});

  @override
  Widget build(BuildContext context) {
    final done = current > index;
    final active = current == index;
    final color = (done || active) ? AppTheme.primary : AppTheme.textHint;

    return Column(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: done ? AppTheme.primary : Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
          ),
          child: done
              ? const Icon(Icons.check, size: 14, color: Colors.white)
              : Center(
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: color),
                  ),
                ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(fontSize: 10, color: color),
        ),
      ],
    );
  }
}

// ── Step 1: License ───────────────────────────────────────────────────────────

class _Step1License extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController licenseController;
  final DateTime? licenseExpiry;
  final VoidCallback onPickExpiry;
  final VoidCallback onNext;

  const _Step1License({
    required this.formKey,
    required this.licenseController,
    required this.licenseExpiry,
    required this.onPickExpiry,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final expiryLabel = licenseExpiry != null
        ? '${licenseExpiry!.day.toString().padLeft(2, '0')}/'
            '${licenseExpiry!.month.toString().padLeft(2, '0')}/'
            '${licenseExpiry!.year}'
        : 'Select expiry date';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Driving License',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Enter your Indian driving license details exactly as printed.',
              style:
                  TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 24),

            // License number
            TextFormField(
              controller: licenseController,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Z0-9]')),
                LengthLimitingTextInputFormatter(15),
              ],
              decoration: const InputDecoration(
                labelText: 'License Number',
                hintText: 'RJ14 2020 1234567',
                prefixIcon:
                    Icon(Icons.credit_card_outlined, color: AppTheme.primary),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'License number is required';
                final clean = v.replaceAll(' ', '');
                final dlRegex =
                    RegExp(r'^[A-Z]{2}[0-9]{2}[0-9]{4}[0-9]{7}$');
                if (!dlRegex.hasMatch(clean)) {
                  return 'Invalid format. Example: RJ14202012345678';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Expiry date picker
            GestureDetector(
              onTap: onPickExpiry,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined,
                        color: AppTheme.primary, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        expiryLabel,
                        style: TextStyle(
                          fontSize: 15,
                          color: licenseExpiry != null
                              ? AppTheme.textPrimary
                              : AppTheme.textHint,
                        ),
                      ),
                    ),
                    const Icon(Icons.chevron_right,
                        color: AppTheme.textHint),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'License must be valid (not expired).',
              style: TextStyle(fontSize: 11, color: AppTheme.textHint),
            ),

            const SizedBox(height: 32),
            PrimaryButton(
              label: 'Next: Vehicle Details',
              onPressed: onNext,
              icon: Icons.arrow_forward,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Step 2: Vehicle ───────────────────────────────────────────────────────────

class _Step2Vehicle extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final String vehicleType;
  final List<String> vehicleTypes;
  final ValueChanged<String?> onVehicleTypeChanged;
  final TextEditingController makeCtr;
  final TextEditingController modelCtr;
  final TextEditingController colorCtr;
  final TextEditingController numberCtr;
  final int vehicleYear;
  final ValueChanged<int> onYearChanged;
  final bool isSubmitting;
  final VoidCallback onSubmit;

  const _Step2Vehicle({
    required this.formKey,
    required this.vehicleType,
    required this.vehicleTypes,
    required this.onVehicleTypeChanged,
    required this.makeCtr,
    required this.modelCtr,
    required this.colorCtr,
    required this.numberCtr,
    required this.vehicleYear,
    required this.onYearChanged,
    required this.isSubmitting,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final currentYear = DateTime.now().year;
    final years = List.generate(
      currentYear - 2004,
      (i) => currentYear - i,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Vehicle Details',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Your vehicle must be 2005 or newer.',
              style:
                  TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 24),

            // Vehicle type dropdown
            DropdownButtonFormField<String>(
              value: vehicleType,
              decoration: const InputDecoration(
                labelText: 'Vehicle Type',
                prefixIcon: Icon(Icons.directions_car_outlined,
                    color: AppTheme.primary),
              ),
              items: vehicleTypes
                  .map((t) =>
                      DropdownMenuItem(value: t, child: Text(t)))
                  .toList(),
              onChanged: onVehicleTypeChanged,
            ),
            const SizedBox(height: 14),

            // Make
            TextFormField(
              controller: makeCtr,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Make (Brand)',
                hintText: 'e.g. Maruti Suzuki, Hyundai',
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Vehicle make is required'
                  : null,
            ),
            const SizedBox(height: 14),

            // Model
            TextFormField(
              controller: modelCtr,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Model',
                hintText: 'e.g. Swift Dzire, i20',
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Vehicle model is required'
                  : null,
            ),
            const SizedBox(height: 14),

            // Color
            TextFormField(
              controller: colorCtr,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Color',
                hintText: 'e.g. White, Silver',
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Vehicle color is required'
                  : null,
            ),
            const SizedBox(height: 14),

            // Vehicle number
            TextFormField(
              controller: numberCtr,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Z0-9]')),
                LengthLimitingTextInputFormatter(10),
              ],
              decoration: const InputDecoration(
                labelText: 'Vehicle Number Plate',
                hintText: 'RJ14AB1234',
                prefixIcon: Icon(Icons.pin_outlined,
                    color: AppTheme.primary),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Vehicle number is required';
                }
                if (v.length < 6) return 'Enter a valid number plate';
                return null;
              },
            ),
            const SizedBox(height: 14),

            // Year dropdown
            DropdownButtonFormField<int>(
              value: vehicleYear,
              decoration: const InputDecoration(
                labelText: 'Year of Manufacture',
                prefixIcon: Icon(Icons.date_range_outlined,
                    color: AppTheme.primary),
              ),
              items: years
                  .map((y) => DropdownMenuItem(
                      value: y, child: Text('$y')))
                  .toList(),
              onChanged: (y) {
                if (y != null) onYearChanged(y);
              },
            ),

            const SizedBox(height: 32),
            PrimaryButton(
              label: 'Submit Application',
              onPressed: isSubmitting ? null : onSubmit,
              isLoading: isSubmitting,
              icon: Icons.check_circle_outline,
            ),
          ],
        ),
      ),
    );
  }
}
