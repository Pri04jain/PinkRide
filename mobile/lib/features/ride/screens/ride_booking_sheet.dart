import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../auth/widgets/primary_button.dart';
import '../providers/ride_provider.dart';

/// RideBookingSheet — slides up as a modal bottom sheet to confirm the booking.
///
/// WHY A SEPARATE SHEET AND NOT INLINE ON THE HOME SCREEN?
/// The home screen is already dense (map + inputs + fare card).
/// The booking confirmation step needs space for:
///   - Full fare summary
///   - Payment method selector (cash vs UPI)
///   - Schedule time picker (now vs later)
///   - Wallet balance warning (shared rides need ₹50 minimum)
///   - Confirm button
///
/// A bottom sheet gives this space without navigating away from the map.
/// The user can swipe down to cancel without losing their locations.
///
/// HOW showModalBottomSheet WORKS:
///   - Shows a panel that slides up from the bottom
///   - The screen behind is dimmed (scrim) but still visible
///   - User can swipe down or tap the scrim to dismiss
///   - isScrollControlled: true → lets the sheet grow taller than 60% of screen
///   - The sheet is a ConsumerWidget so it can watch Riverpod providers

class RideBookingSheet extends ConsumerStatefulWidget {
  const RideBookingSheet({super.key});

  @override
  ConsumerState<RideBookingSheet> createState() => _RideBookingSheetState();
}

class _RideBookingSheetState extends ConsumerState<RideBookingSheet> {
  // Track whether the user wants to schedule for later
  bool _scheduleForLater = false;

  @override
  Widget build(BuildContext context) {
    final form = ref.watch(bookingFormProvider);
    final bookingState = ref.watch(bookingProvider);
    final isBooking = bookingState is BookingInProgress;

    // Close sheet automatically when booking succeeds
    // The home screen's ref.listen handles the actual navigation
    ref.listen<BookingState>(bookingProvider, (_, next) {
      if (next is BookingSuccess || next is BookingError) {
        if (next is BookingSuccess) Navigator.of(context).pop();
      }
    });

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        // Extra bottom padding so content isn't hidden behind keyboard
        MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).padding.bottom +
            24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Drag handle ──────────────────────────────────────────────
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 20),
                decoration: BoxDecoration(
                  color: AppTheme.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // ── Title ────────────────────────────────────────────────────
            const Text(
              'Confirm Booking',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 20),

            // ── Trip summary ─────────────────────────────────────────────
            _TripSummaryCard(form: form),
            const SizedBox(height: 20),

            // ── Payment method ───────────────────────────────────────────
            const _SectionLabel('Payment method'),
            const SizedBox(height: 10),
            _PaymentSelector(
              selected: form.paymentMethod,
              onChanged: (method) =>
                  ref.read(bookingProvider.notifier).setPaymentMethod(method),
            ),
            const SizedBox(height: 20),

            // ── Schedule time ────────────────────────────────────────────
            const _SectionLabel('When'),
            const SizedBox(height: 10),
            _ScheduleSelector(
              scheduleForLater: _scheduleForLater,
              scheduledAt: form.scheduledAt,
              onToggle: (later) {
                setState(() => _scheduleForLater = later);
                if (!later) {
                  // Reset to immediate ride
                  ref.read(bookingProvider.notifier).setScheduledAt(
                        DateTime.now().add(const Duration(minutes: 2)),
                      );
                }
              },
              onTimePicked: (time) =>
                  ref.read(bookingProvider.notifier).setScheduledAt(time),
            ),
            const SizedBox(height: 20),

            // ── Wallet warning for shared rides ──────────────────────────
            if (form.rideType != 'private') ...[
              _WalletWarning(rideType: form.rideType),
              const SizedBox(height: 16),
            ],

            // ── Error message ────────────────────────────────────────────
            if (bookingState is BookingError) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.error.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline,
                        size: 16, color: AppTheme.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        bookingState.message,
                        style: const TextStyle(
                            color: AppTheme.error, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ── Confirm button ───────────────────────────────────────────
            PrimaryButton(
              label: 'Confirm — ${form.estimate?.formattedFare ?? ''}',
              isLoading: isBooking,
              onPressed: () =>
                  ref.read(bookingProvider.notifier).confirmBooking(),
            ),
            const SizedBox(height: 12),

            // ── Cancel link ──────────────────────────────────────────────
            Center(
              child: TextButton(
                onPressed: isBooking ? null : () => Navigator.of(context).pop(),
                child: const Text(
                  'Cancel',
                  style: TextStyle(
                      color: AppTheme.textSecondary, fontSize: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Trip summary card ─────────────────────────────────────────────────────────

class _TripSummaryCard extends StatelessWidget {
  final BookingFormState form;
  const _TripSummaryCard({required this.form});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7F7),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          // Pickup row
          _LocationRow(
            icon: Icons.radio_button_checked,
            iconColor: AppTheme.success,
            label: 'From',
            address: form.pickup?.address ?? '',
          ),

          // Connector line
          Padding(
            padding: const EdgeInsets.only(left: 10, top: 4, bottom: 4),
            child: Column(
              children: List.generate(
                3,
                (_) => Container(
                  width: 1.5,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 1),
                  color: AppTheme.divider,
                ),
              ),
            ),
          ),

          // Drop row
          _LocationRow(
            icon: Icons.location_on,
            iconColor: AppTheme.primary,
            label: 'To',
            address: form.drop?.address ?? '',
          ),

          const SizedBox(height: 12),
          const Divider(color: AppTheme.divider, height: 1),
          const SizedBox(height: 12),

          // Fare + ride type row
          Row(
            children: [
              // Ride type badge
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _rideTypeLabel(form.rideType),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),

              // Total fare
              if (form.estimate != null) ...[
                Text(
                  form.estimate!.formattedFare,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '(${form.estimate!.formattedDistance})',
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textSecondary),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _rideTypeLabel(String type) {
    switch (type) {
      case 'shared':            return 'Shared';
      case 'women_only_shared': return 'Women Only';
      default:                  return 'Private';
    }
  }
}

class _LocationRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String address;

  const _LocationRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.address,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 18, color: iconColor),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                    fontSize: 11, color: AppTheme.textSecondary),
              ),
              Text(
                address,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Payment method selector ───────────────────────────────────────────────────

class _PaymentSelector extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const _PaymentSelector({
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _PaymentOption(
            value: 'cash',
            label: 'Cash',
            icon: Icons.payments_outlined,
            subtitle: 'Pay driver directly',
            selected: selected == 'cash',
            onTap: () => onChanged('cash'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _PaymentOption(
            value: 'upi',
            label: 'UPI',
            icon: Icons.phone_android_rounded,
            subtitle: 'PhonePe / GPay',
            selected: selected == 'upi',
            onTap: () => onChanged('upi'),
          ),
        ),
      ],
    );
  }
}

class _PaymentOption extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _PaymentOption({
    required this.value,
    required this.label,
    required this.icon,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primaryLight.withOpacity(0.2)
              : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppTheme.primary : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: selected ? AppTheme.primary : AppTheme.textSecondary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? AppTheme.primary
                          : AppTheme.textPrimary,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                        fontSize: 11, color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle,
                  size: 16, color: AppTheme.primary),
          ],
        ),
      ),
    );
  }
}

// ── Schedule selector ─────────────────────────────────────────────────────────

class _ScheduleSelector extends StatelessWidget {
  final bool scheduleForLater;
  final DateTime scheduledAt;
  final ValueChanged<bool> onToggle;
  final ValueChanged<DateTime> onTimePicked;

  const _ScheduleSelector({
    required this.scheduleForLater,
    required this.scheduledAt,
    required this.onToggle,
    required this.onTimePicked,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Toggle row
        Row(
          children: [
            Expanded(
              child: _ScheduleOption(
                label: 'Now',
                icon: Icons.flash_on_rounded,
                subtitle: 'Immediate pickup',
                selected: !scheduleForLater,
                onTap: () => onToggle(false),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ScheduleOption(
                label: 'Later',
                icon: Icons.schedule_rounded,
                subtitle: 'Schedule a time',
                selected: scheduleForLater,
                onTap: () => onToggle(true),
              ),
            ),
          ],
        ),

        // Date/time picker — shown when "Later" is selected
        if (scheduleForLater) ...[
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => _pickDateTime(context),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.07),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: AppTheme.primary.withOpacity(0.25)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_outlined,
                      size: 16, color: AppTheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    DateFormat('EEE, d MMM • h:mm a').format(scheduledAt),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primary,
                    ),
                  ),
                  const Spacer(),
                  const Icon(Icons.edit_outlined,
                      size: 14, color: AppTheme.primary),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _pickDateTime(BuildContext context) async {
    // Step 1: pick date
    final date = await showDatePicker(
      context: context,
      initialDate: scheduledAt,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 7)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: AppTheme.primary),
        ),
        child: child!,
      ),
    );
    if (date == null || !context.mounted) return;

    // Step 2: pick time
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(scheduledAt),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: AppTheme.primary),
        ),
        child: child!,
      ),
    );
    if (time == null) return;

    onTimePicked(DateTime(
      date.year, date.month, date.day,
      time.hour, time.minute,
    ));
  }
}

class _ScheduleOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _ScheduleOption({
    required this.label,
    required this.icon,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primaryLight.withOpacity(0.2)
              : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppTheme.primary : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? AppTheme.primary : AppTheme.textSecondary,
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? AppTheme.primary
                        : AppTheme.textPrimary,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                      fontSize: 11, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Wallet warning for shared rides ──────────────────────────────────────────

class _WalletWarning extends StatelessWidget {
  final String rideType;
  const _WalletWarning({required this.rideType});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.warning.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.warning.withOpacity(0.3)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.account_balance_wallet_outlined,
              size: 16, color: AppTheme.warning),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Shared rides require a minimum wallet balance of ₹50 '
              'to cover potential cancellation fees.',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary,
                  height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Section label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppTheme.textSecondary,
        letterSpacing: 0.3,
      ),
    );
  }
}
