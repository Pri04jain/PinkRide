import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../auth/widgets/primary_button.dart';
import '../payment_service.dart';

// ── Provider ──────────────────────────────────────────────────────────────────

final _walletProvider = FutureProvider.autoDispose<WalletInfo>((ref) {
  return ref.watch(paymentServiceProvider).getWallet();
});

/// WalletScreen — shows current balance + transaction history.
///
/// Two sections:
///   1. Balance card — large balance display + top-up button
///   2. Transaction list — chronological history with credit/debit colour coding
///
/// Transaction types from the backend:
///   topup          → green (money added)
///   ride_payment   → red (fare deducted)
///   fine_deduction → red (cancellation fine)
///   refund         → green (fine waived or refund)

class WalletScreen extends ConsumerWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncWallet = ref.watch(_walletProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('My Wallet'),
        backgroundColor: AppTheme.surface,
        elevation: 0,
      ),
      body: asyncWallet.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppTheme.primary)),
        error: (e, _) => _ErrorView(
          message: e.toString(),
          onRetry: () => ref.invalidate(_walletProvider),
        ),
        data: (wallet) => _WalletBody(wallet: wallet),
      ),
    );
  }
}

// ── Body ──────────────────────────────────────────────────────────────────────

class _WalletBody extends ConsumerWidget {
  final WalletInfo wallet;
  const _WalletBody({required this.wallet});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      // Pull-to-refresh re-fetches wallet data
      color: AppTheme.primary,
      onRefresh: () async => ref.invalidate(_walletProvider),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(
                children: [
                  // ── Balance card ───────────────────────────────────────
                  _BalanceCard(balance: wallet.balance),
                  const SizedBox(height: 24),

                  // ── Section header ─────────────────────────────────────
                  const Row(
                    children: [
                      Text(
                        'Transaction History',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),

          // ── Transaction list ─────────────────────────────────────────
          wallet.transactions.isEmpty
              ? const SliverToBoxAdapter(child: _EmptyTransactions())
              : SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                      child:
                          _TransactionTile(tx: wallet.transactions[i]),
                    ),
                    childCount: wallet.transactions.length,
                  ),
                ),

          // Bottom padding
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}

// ── Balance card ──────────────────────────────────────────────────────────────

class _BalanceCard extends StatelessWidget {
  final double balance;
  const _BalanceCard({required this.balance});

  @override
  Widget build(BuildContext context) {
    final isLow = balance < 50; // warn if below shared-ride minimum

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.secondary, Color(0xFF1a1a3e)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppTheme.secondary.withOpacity(0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label row
          Row(
            children: [
              const Icon(Icons.account_balance_wallet_outlined,
                  color: Colors.white54, size: 18),
              const SizedBox(width: 6),
              const Text(
                'Wallet Balance',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const Spacer(),
              if (isLow)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.warning.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: AppTheme.warning.withOpacity(0.5)),
                  ),
                  child: const Text(
                    'Low',
                    style: TextStyle(
                        color: AppTheme.warning,
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 12),

          // Balance amount
          Text(
            '₹${balance.toStringAsFixed(2)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 40,
              fontWeight: FontWeight.bold,
              letterSpacing: -1,
            ),
          ),

          const SizedBox(height: 4),
          Text(
            isLow
                ? 'Add ₹50+ to use shared rides'
                : 'Available for fines & shared rides',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),

          const SizedBox(height: 20),

          // Top-up button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _showTopupSheet(context),
              icon: const Icon(Icons.add_rounded,
                  size: 18, color: Colors.white),
              label: const Text('Add Money',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                side:
                    const BorderSide(color: Colors.white38, width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showTopupSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _TopupSheet(),
    );
  }
}

// ── Transaction tile ──────────────────────────────────────────────────────────

class _TransactionTile extends StatelessWidget {
  final WalletTransaction tx;
  const _TransactionTile({required this.tx});

  @override
  Widget build(BuildContext context) {
    final dateStr =
        DateFormat('d MMM, h:mm a').format(tx.createdAt.toLocal());

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        children: [
          // Type icon circle
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: (tx.isCredit ? AppTheme.success : AppTheme.error)
                  .withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _iconForType(tx.type),
              color:
                  tx.isCredit ? AppTheme.success : AppTheme.error,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),

          // Description + date
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _labelForType(tx.type),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  tx.notes.isNotEmpty ? tx.notes : dateStr,
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (tx.notes.isNotEmpty)
                  Text(
                    dateStr,
                    style: const TextStyle(
                        fontSize: 11, color: AppTheme.textHint),
                  ),
              ],
            ),
          ),

          // Amount + balance after
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                tx.formattedAmount,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: tx.isCredit
                      ? AppTheme.success
                      : AppTheme.error,
                ),
              ),
              Text(
                '₹${tx.balanceAfter.toStringAsFixed(0)} left',
                style: const TextStyle(
                    fontSize: 11, color: AppTheme.textHint),
              ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'topup':
        return Icons.add_circle_outline;
      case 'ride_payment':
        return Icons.directions_car_outlined;
      case 'fine_deduction':
        return Icons.warning_amber_outlined;
      case 'refund':
        return Icons.undo_rounded;
      default:
        return Icons.swap_horiz_rounded;
    }
  }

  String _labelForType(String type) {
    switch (type) {
      case 'topup':
        return 'Wallet Top-up';
      case 'ride_payment':
        return 'Ride Payment';
      case 'fine_deduction':
        return 'Cancellation Fine';
      case 'refund':
        return 'Refund';
      default:
        return type.replaceAll('_', ' ');
    }
  }
}

// ── Top-up sheet ──────────────────────────────────────────────────────────────
// Quick amount selector + custom amount field.
// In dev/mock mode Razorpay is skipped and balance is credited directly.

class _TopupSheet extends ConsumerStatefulWidget {
  const _TopupSheet();

  @override
  ConsumerState<_TopupSheet> createState() => _TopupSheetState();
}

class _TopupSheetState extends ConsumerState<_TopupSheet> {
  final _customCtrl = TextEditingController();
  int? _selectedAmount;
  bool _loading = false;
  String? _error;

  static const _presets = [100, 200, 500, 1000];

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  Future<void> _topup() async {
    final raw = _selectedAmount ??
        int.tryParse(_customCtrl.text.trim());
    if (raw == null || raw < 100) {
      setState(() => _error = 'Minimum top-up is ₹100.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Step 1 — create order
      final data = await ref
          .read(paymentServiceProvider)
          .createTopupOrder(raw);

      final orderId = data['orderId'] as String?;
      final isMock = data['dev'] as bool? ?? false;

      if (isMock) {
        // Dev mode — verify directly with mock fields
        await ref.read(paymentServiceProvider).verifyTopupPayment({
          'amount': raw,
          'razorpay_order_id': orderId,
          'razorpay_payment_id':
              'pay_mock_${DateTime.now().millisecondsSinceEpoch}',
          'razorpay_signature': 'mock_signature',
        });
        if (mounted) {
          Navigator.of(context).pop();
          ref.invalidate(_walletProvider);
        }
      }
    } catch (e) {
      setState(() {
        _loading = false;
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
            'Add Money',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 20),

          // Preset amounts
          Row(
            children: _presets.map((amount) {
              final selected = _selectedAmount == amount;
              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedAmount = amount;
                      _customCtrl.clear();
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppTheme.primaryLight.withOpacity(0.2)
                          : const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selected
                            ? AppTheme.primary
                            : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: Text(
                      '₹$amount',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: selected
                            ? AppTheme.primary
                            : AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 12),

          // Custom amount
          TextField(
            controller: _customCtrl,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() => _selectedAmount = null),
            decoration: const InputDecoration(
              hintText: 'Custom amount (min ₹100)',
              prefixText: '₹ ',
            ),
          ),

          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!,
                  style: const TextStyle(
                      color: AppTheme.error, fontSize: 13)),
            ),

          const SizedBox(height: 16),
          PrimaryButton(
            label: 'Add Money',
            isLoading: _loading,
            onPressed: _topup,
          ),
        ],
      ),
    );
  }
}

// ── Helper views ──────────────────────────────────────────────────────────────

class _EmptyTransactions extends StatelessWidget {
  const _EmptyTransactions();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      child: Column(
        children: [
          Icon(Icons.receipt_long_outlined,
              size: 56, color: AppTheme.textHint),
          SizedBox(height: 12),
          Text(
            'No transactions yet',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary),
          ),
          SizedBox(height: 6),
          Text(
            'Your ride payments, fines, and top-ups\nwill appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 13, color: AppTheme.textHint, height: 1.4),
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
