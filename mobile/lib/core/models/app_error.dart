
enum AppErrorType {
  /// 401 — not logged in, or token revoked
  unauthorized,

  /// 403 — logged in but not allowed (wrong role, face not verified, etc.)
  forbidden,

  /// 404 — resource not found (ride, driver, user)
  notFound,

  /// 409 — conflict (duplicate booking, already rated, etc.)
  conflict,

  /// 422 — validation failed (invalid phone, bad coordinates, etc.)
  validation,

  /// 429 — rate limited (too many OTP requests)
  rateLimited,

  /// 500 — server error
  server,

  /// No internet, DNS failure, connection refused
  network,

  /// Request timed out (server took too long)
  timeout,

  /// Something we didn't expect
  unknown,
}

class AppError implements Exception {
  /// Human-readable message — safe to show directly in the UI.
  /// Comes from the backend's `message` field, or a friendly fallback.
  final String message;

  /// HTTP status code (null for network/timeout errors)
  final int? statusCode;

  /// Category of the error — use this for programmatic handling
  final AppErrorType type;

  /// Raw backend error data (for debugging only — never show this to users)
  final dynamic rawData;

  const AppError({
    required this.message,
    this.statusCode,
    this.type = AppErrorType.unknown,
    this.rawData,
  });

  // ── Factory constructors — one per error category ─────────────────────────
  // These give us a clean call site:
  //   throw AppError.unauthorized();
  //   throw AppError.network();
  // instead of remembering all the enum values everywhere.

  factory AppError.unauthorized([String? message]) => AppError(
        message: message ?? 'Session expired. Please log in again.',
        statusCode: 401,
        type: AppErrorType.unauthorized,
      );

  factory AppError.forbidden([String? message]) => AppError(
        message: message ?? 'You don\'t have permission to do this.',
        statusCode: 403,
        type: AppErrorType.forbidden,
      );

  factory AppError.notFound([String? message]) => AppError(
        message: message ?? 'Not found.',
        statusCode: 404,
        type: AppErrorType.notFound,
      );

  factory AppError.conflict([String? message]) => AppError(
        message: message ?? 'This action conflicts with existing data.',
        statusCode: 409,
        type: AppErrorType.conflict,
      );

  factory AppError.validation(String message) => AppError(
        message: message,
        statusCode: 422,
        type: AppErrorType.validation,
      );

  factory AppError.rateLimited([String? message]) => AppError(
        message: message ?? 'Too many requests. Please wait a moment.',
        statusCode: 429,
        type: AppErrorType.rateLimited,
      );

  factory AppError.server([String? message]) => AppError(
        message: message ?? 'Something went wrong on our end. Try again shortly.',
        statusCode: 500,
        type: AppErrorType.server,
      );

  factory AppError.network() => const AppError(
        message: 'No internet connection. Check your network and try again.',
        type: AppErrorType.network,
      );

  factory AppError.timeout() => const AppError(
        message: 'The request took too long. Please try again.',
        type: AppErrorType.timeout,
      );

  factory AppError.unknown([String? message]) => AppError(
        message: message ?? 'Something unexpected happened. Please try again.',
        type: AppErrorType.unknown,
      );

  // ── Convenience getters ───────────────────────────────────────────────────

  /// True if the user needs to be sent to the login screen.
  bool get requiresLogin => type == AppErrorType.unauthorized;

  /// True if the error is something the user can retry.
  bool get isRetryable =>
      type == AppErrorType.network ||
      type == AppErrorType.timeout ||
      type == AppErrorType.server;

  @override
  String toString() => 'AppError[$statusCode/${type.name}]: $message';
}
