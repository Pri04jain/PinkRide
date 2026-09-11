import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/constants/api_endpoints.dart';

// ── Data models ───────────────────────────────────────────────────────────────

class UpiOrderResult {
  final String orderId;
  final int amountPaise; // Razorpay uses paise (₹1 = 100 paise)
  final String currency;
  final String keyId;
  final bool isMock; // true in dev mode

  const UpiOrderResult({
    required this.orderId,
    required this.amountPaise,
    required this.currency,
    required this.keyId,
    this.isMock = false,
  });

  factory UpiOrderResult.fromJson(Map<String, dynamic> json) {
    return UpiOrderResult(
      orderId: json['orderId'] as String? ?? '',
      amountPaise: (json['amount'] as num?)?.toInt() ?? 0,
      currency: json['currency'] as String? ?? 'INR',
      keyId: json['keyId'] as String? ?? '',
      isMock: json['dev'] as bool? ?? false,
    );
  }

  double get amountRupees => amountPaise / 100;
}

class WalletInfo {
  final double balance;
  final List<WalletTransaction> transactions;

  const WalletInfo({required this.balance, required this.transactions});
}

class WalletTransaction {
  final String id;
  final double amount;
  final String type;
  final String notes;
  final double balanceAfter;
  final DateTime createdAt;

  const WalletTransaction({
    required this.id,
    required this.amount,
    required this.type,
    required this.notes,
    required this.balanceAfter,
    required this.createdAt,
  });

  factory WalletTransaction.fromJson(Map<String, dynamic> json) {
    return WalletTransaction(
      id: json['id'] as String? ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      type: json['type'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
      balanceAfter: (json['balance_after'] as num?)?.toDouble() ?? 0,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  bool get isCredit => amount > 0;
  String get formattedAmount =>
      '${isCredit ? '+' : ''}₹${amount.abs().toStringAsFixed(0)}';
}

// ── PaymentService ────────────────────────────────────────────────────────────

class PaymentService {
  final ApiClient _api;
  const PaymentService(this._api);

  // ── UPI: create order ────────────────────────────────────────────────────
  Future<UpiOrderResult> createUpiOrder(String rideId) async {
    final data = await _api.post(
      ApiEndpoints.createUpiOrder(rideId),
    );
    return UpiOrderResult.fromJson(data);
  }

  // ── UPI: verify payment ──────────────────────────────────────────────────
  Future<void> verifyUpiPayment(
      String rideId, Map<String, String> paymentData) async {
    await _api.post(
      ApiEndpoints.verifyUpiPayment(rideId),
      data: paymentData,
    );
  }

  // ── Cash: driver confirms receipt ────────────────────────────────────────
  Future<void> confirmCashPayment(String rideId) async {
    await _api.post(ApiEndpoints.confirmCash(rideId));
  }

  // ── Ratings ───────────────────────────────────────────────────────────────
  Future<void> submitRating({
    required String rideId,
    required String ratedUserId,
    required int score,
    required List<String> tags,
    String? comment,
  }) async {
    await _api.post(
      '/payments/rides/$rideId/rate',
      data: {
        'ratedUserId': ratedUserId,
        'score': score,
        if (tags.isNotEmpty) 'tags': tags,
        if (comment != null && comment.isNotEmpty) 'comment': comment,
      },
    );
  }

  Future<List<Map<String, dynamic>>> getPendingRatings() async {
    final data = await _api.get('/payments/ratings/pending');
    final list = data['pending'] as List<dynamic>? ?? [];
    return list.cast<Map<String, dynamic>>();
  }

  // ── Wallet top-up (for WalletScreen) ─────────────────────────────────────
  Future<Map<String, dynamic>> createTopupOrder(int amount) async {
    return _api.post('/users/wallet/topup/order', data: {'amount': amount});
  }

  Future<void> verifyTopupPayment(Map<String, dynamic> body) async {
    await _api.post('/users/wallet/topup/verify', data: body);
  }

  // ── Wallet ───────────────────────────────────────────────────────────────
  Future<WalletInfo> getWallet() async {
    final data = await _api.get(ApiEndpoints.wallet);
    final txList = data['transactions'] as List<dynamic>? ?? [];
    return WalletInfo(
      balance: (data['balance'] as num?)?.toDouble() ?? 0,
      transactions: txList
          .map((e) =>
              WalletTransaction.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

final paymentServiceProvider = Provider<PaymentService>((ref) {
  return PaymentService(ref.watch(apiClientProvider));
});
