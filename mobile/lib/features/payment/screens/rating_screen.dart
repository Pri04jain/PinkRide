import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/app_error.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/widgets/primary_button.dart';
import '../payment_service.dart';

// Pending ratings provider — loads once per screen open
final _pendingRatingsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  return ref.watch(paymentServiceProvider).getPendingRatings();
});

/// RatingScreen — post-ride mutual rating.
///
/// Receives rideId via path parameter.
/// Loads pending ratings for this ride (who needs to be rated).
/// For each person: star selector (1–5) + tag chips + optional comment.
///
/// STAR SELECTOR:
/// Flutter has no built-in star rating widget. We build a Row of
/// GestureDetector-wrapped Icon widgets. Tapping a star sets _score
/// to that star's index. Stars at or below _score are filled (★),
/// stars above are outlined (☆).

class RatingScreen extends ConsumerStatefulWidget {
  final String rideId;
  const RatingScreen({super.key, required this.rideId});

  @override
  ConsumerState<RatingScreen> createState() => _RatingScreenState();
}

class _RatingScreenState extends ConsumerState<RatingScreen> {
  int _score = 5;
  final Set<String> _selectedTags = {};
  final _commentCtrl = TextEditingController();
  bool _submitting = false;
  String? _error;

  // Backend-valid tags (matches VALID_TAGS in rating.service.js)
  static const _driverTags = [
    ('safe_driver', '🚗 Safe Driver'),
    ('punctual', '⏰ Punctual'),
    ('clean_vehicle', '✨ Clean Vehicle'),
    ('polite', '😊 Polite'),
    ('good_route', '🗺️ Good Route'),
    ('smooth_ride', '🛣️ Smooth Ride'),
  ];

  static const _passengerTags = [
    ('punctual', '⏰ Punctual'),
    ('polite', '😊 Polite'),
    ('clean', '✨ Clean'),
    ('safe', '🔒 Safe'),
    ('verified', '✅ Verified'),
  ];

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit(String ratedUserId, String ratedUserRole) async {
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await ref.read(paymentServiceProvider).submitRating(
            rideId: widget.rideId,
            ratedUserId: ratedUserId,
            score: _score,
            tags: _selectedTags.toList(),
            comment: _commentCtrl.text.trim().isEmpty
                ? null
                : _commentCtrl.text.trim(),
          );

      if (mounted) context.go(AppRoutes.passengerHome);
    } on AppError catch (e) {
      setState(() {
        _submitting = false;
        _error = e.message;
      });
    } catch (_) {
      setState(() {
        _submitting = false;
        _error = 'Failed to submit rating. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Load pending ratings — who needs to be rated after this ride
    final pendingAsync = ref.watch(_pendingRatingsProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Rate Your Ride'),
        backgroundColor: AppTheme.surface,
        elevation: 0,
        automaticallyImplyLeading: false, // don't allow back — must rate or skip
      ),
      body: pendingAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppTheme.primary)),
        error: (_, __) => _buildRatingBody(null, 'driver'),
        data: (pending) {
          // Find the rating for this specific ride
          final rideRating = pending
              .where((r) => r['rideId'] == widget.rideId)
              .toList();

          if (rideRating.isEmpty) {
            // Already rated or no pending — go home
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => context.go(AppRoutes.passengerHome),
            );
            return const SizedBox.shrink();
          }

          final toRate = rideRating.first;
          return _buildRatingBody(
            toRate['rateUserId'] as String?,
            toRate['rateUserRole'] as String? ?? 'driver',
            name: toRate['rateUserName'] as String?,
          );
        },
      ),
    );
  }

  Widget _buildRatingBody(String? ratedUserId, String ratedUserRole,
      {String? name}) {
    final isDriver = ratedUserRole == 'driver';
    final tags = isDriver ? _driverTags : _passengerTags;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Avatar + name ────────────────────────────────────────────
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppTheme.primaryLight.withOpacity(0.25),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isDriver ? Icons.drive_eta_rounded : Icons.person_rounded,
              color: AppTheme.primary,
              size: 40,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Rate your ${isDriver ? 'driver' : 'passenger'}',
            style: const TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
            ),
          ),
          if (name != null) ...[
            const SizedBox(height: 4),
            Text(
              name,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
          ],

          const SizedBox(height: 28),

          // ── Star selector ────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final starIndex = i + 1;
              return GestureDetector(
                onTap: () => setState(() => _score = starIndex),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(
                    starIndex <= _score
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: AppTheme.warning,
                    size: 44,
                  ),
                ),
              );
            }),
          ),

          const SizedBox(height: 8),
          Text(
            _scoreLabel(_score),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),

          const SizedBox(height: 24),

          // ── Tag chips ────────────────────────────────────────────────
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'What stood out?',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: tags.map((tag) {
              final (value, label) = tag;
              final selected = _selectedTags.contains(value);
              return GestureDetector(
                onTap: () => setState(() {
                  if (selected) {
                    _selectedTags.remove(value);
                  } else {
                    _selectedTags.add(value);
                  }
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppTheme.primary.withOpacity(0.12)
                        : const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selected
                          ? AppTheme.primary
                          : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: selected
                          ? AppTheme.primary
                          : AppTheme.textSecondary,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 20),

          // ── Comment field ────────────────────────────────────────────
          TextField(
            controller: _commentCtrl,
            maxLines: 3,
            maxLength: 300,
            decoration: const InputDecoration(
              hintText: 'Add a comment (optional)',
            ),
          ),

          const SizedBox(height: 20),

          // ── Error ────────────────────────────────────────────────────
          if (_error != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.error.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(_error!,
                  style: const TextStyle(
                      color: AppTheme.error, fontSize: 13)),
            ),

          // ── Submit ───────────────────────────────────────────────────
          PrimaryButton(
            label: 'Submit Rating',
            icon: Icons.star_rounded,
            isLoading: _submitting,
            onPressed: ratedUserId != null
                ? () => _submit(ratedUserId, ratedUserRole)
                : null,
          ),

          const SizedBox(height: 12),

          TextButton(
            onPressed: () => context.go(AppRoutes.passengerHome),
            child: const Text(
              'Skip',
              style: TextStyle(
                  color: AppTheme.textSecondary, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  String _scoreLabel(int score) {
    switch (score) {
      case 1:
        return 'Very Poor';
      case 2:
        return 'Poor';
      case 3:
        return 'Okay';
      case 4:
        return 'Good';
      case 5:
        return 'Excellent!';
      default:
        return '';
    }
  }
}
