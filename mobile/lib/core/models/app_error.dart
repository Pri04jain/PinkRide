/// Typed error thrown by ApiClient and caught by every provider.
/// Replaces raw exceptions with structured, UI-friendly error objects.
///
/// HOW IT FLOWS:
///   Backend returns non-200 → ApiClient throws AppError
///   Provider catches AppError → reads e.message for the snackbar/banner
///   UI watches state → shows the message to the user

enum AppErrorType {
  network,     // no internet / server unreachable
  timeout,     // request timed out
  validation,  // 400 / 422 — bad input
  unauthorized, // 401 — not logged in / token expired
  forbidden,   // 403 — not allowed
  notFound,    // 404
  conflict,    // 409 — duplicate entry
  rateLimited, // 429
  server,      // 5xx
  unknown,
}

class AppError implements Exception {
  final String message;
  final int? statusCode;
  final AppErrorType type;
  final dynamic rawData; // full backend body for debugging

  const AppError({
    required this.message,
    this.statusCode,
    this.type = AppErrorType.unknown,
    this.rawData,
  });

  // ── Named constructors for common cases ───────────────────────────────────
  factory AppError.network([String? msg]) => AppError(
        message: msg ?? 'No internet connection. Please check your network.',
        type: AppErrorType.network,
      );

  factory AppError.timeout() => const AppError(
        message: 'Request timed out. Please try again.',
        type: AppErrorType.timeout,
      );

  factory AppError.unauthorized([String? msg]) => AppError(
        message: msg ?? 'Session expired. Please log in again.',
        statusCode: 401,
        type: AppErrorType.unauthorized,
      );

  factory AppError.forbidden([String? msg]) => AppError(
        message: msg ?? 'You don\'t have permission to do that.',
        statusCode: 403,
        type: AppErrorType.forbidden,
      );

  factory AppError.notFound([String? msg]) => AppError(
        message: msg ?? 'The requested resource was not found.',
        statusCode: 404,
        type: AppErrorType.notFound,
      );

  factory AppError.conflict([String? msg]) => AppError(
        message: msg ?? 'This entry already exists.',
        statusCode: 409,
        type: AppErrorType.conflict,
      );

  factory AppError.validation([String? msg]) => AppError(
        message: msg ?? 'Please check your input and try again.',
        statusCode: 422,
        type: AppErrorType.validation,
      );

  factory AppError.rateLimited([String? msg]) => AppError(
        message: msg ?? 'Too many requests. Please wait a moment.',
        statusCode: 429,
        type: AppErrorType.rateLimited,
      );

  factory AppError.server([String? msg]) => AppError(
        message: msg ?? 'Server error. Please try again later.',
        type: AppErrorType.server,
      );

  factory AppError.unknown([String? msg]) => AppError(
        message: msg ?? 'Something went wrong. Please try again.',
        type: AppErrorType.unknown,
      );

  @override
  String toString() => 'AppError(type: $type, status: $statusCode, message: $message)';
}
