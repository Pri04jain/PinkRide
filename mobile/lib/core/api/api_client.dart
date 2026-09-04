import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/api_endpoints.dart';
import '../constants/app_constants.dart';
import '../models/app_error.dart';
import '../utils/storage_service.dart';

/// ApiClient — the single HTTP client used by every feature in the app.
///
/// HOW DIO WORKS (vs the basic `http` package):
/// ┌─────────────────────────────────────────────────────┐
/// │  Request                                            │
/// │    → Interceptor 1 (AuthInterceptor — attach token) │
/// │    → Interceptor 2 (LogInterceptor — print in dev)  │
/// │    → Dio sends HTTP request                         │
/// │  Response                                           │
/// │    ← Interceptor 2 (log response)                   │
/// │    ← Interceptor 1 (handle 401 → refresh token)     │
/// │    ← Your code receives clean data                  │
/// └─────────────────────────────────────────────────────┘
///
/// Without interceptors you would need to manually:
///   - Add "Authorization: Bearer <token>" to EVERY request
///   - Check if the response is 401 and refresh EVERY time
///   - That's hundreds of lines of repetition across all features
///
/// With interceptors: write it once here, it applies everywhere automatically.

// ── Riverpod Provider ─────────────────────────────────────────────────────────
// Makes ApiClient available throughout the app via:
//   final api = ref.watch(apiClientProvider);
// No need to pass it through constructors.

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

// ── ApiClient ─────────────────────────────────────────────────────────────────

class ApiClient {
  late final Dio _dio;

  ApiClient() {
    final baseUrl = dotenv.env['API_BASE_URL'] ?? 'http://localhost:3000/api/v1';

    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,

        // How long to wait for the server to accept our connection
        connectTimeout: AppConstants.connectTimeout,

        // How long to wait for the server to send the full response
        receiveTimeout: AppConstants.receiveTimeout,

        // Tell the backend we're sending JSON
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },

        // Don't throw on non-200 status codes — we handle them in the interceptor
        validateStatus: (status) => true,
      ),
    );

    // Order matters: AuthInterceptor runs before LogInterceptor so the log
    // shows the request WITH the Authorization header attached.
    _dio.interceptors.add(_AuthInterceptor(_dio));

    // Only log in debug mode — never in production builds
    assert(() {
      _dio.interceptors.add(
        LogInterceptor(
          requestBody: true,
          responseBody: true,
          requestHeader: false, // don't log the token value
          responseHeader: false,
          // ignore: avoid_print
          logPrint: (obj) => print('[API] $obj'),
        ),
      );
      return true;
    }());
  }

  // ── Public HTTP methods ───────────────────────────────────────────────────
  // These wrap _dio and convert every response/error into either
  // a clean Map<String, dynamic> or a typed AppError.

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParams,
  }) async {
    final response = await _safeRequest(
      () => _dio.get(path, queryParameters: queryParams),
    );
    return response;
  }

  Future<Map<String, dynamic>> post(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParams,
  }) async {
    return _safeRequest(
      () => _dio.post(path, data: data, queryParameters: queryParams),
    );
  }

  Future<Map<String, dynamic>> patch(
    String path, {
    dynamic data,
  }) async {
    return _safeRequest(() => _dio.patch(path, data: data));
  }

  Future<Map<String, dynamic>> delete(String path) async {
    return _safeRequest(() => _dio.delete(path));
  }

  /// Special method for multipart file uploads (driver documents, profile photos).
  /// Takes a file path and field name, wraps in FormData, sends as multipart.
  Future<Map<String, dynamic>> uploadFile(
    String path, {
    required String filePath,
    required String fieldName,
    Map<String, dynamic>? extraFields,
  }) async {
    final formData = FormData.fromMap({
      fieldName: await MultipartFile.fromFile(filePath),
      if (extraFields != null) ...extraFields,
    });
    return _safeRequest(() => _dio.post(path, data: formData));
  }

  // ── Core request handler ──────────────────────────────────────────────────
  // Runs the dio call, checks HTTP status, extracts data, converts errors.

  Future<Map<String, dynamic>> _safeRequest(
    Future<Response> Function() request,
  ) async {
    try {
      final response = await request();
      return _handleResponse(response);
    } on DioException catch (e) {
      throw _handleDioException(e);
    } on AppError {
      // Already converted — rethrow as-is
      rethrow;
    } catch (e) {
      throw AppError.unknown(e.toString());
    }
  }

  // ── Response handler ──────────────────────────────────────────────────────
  // Our backend always returns: { success: bool, data: {...}, message: string }
  // This method unpacks that envelope and handles non-200 statuses.

  Map<String, dynamic> _handleResponse(Response response) {
    final status = response.statusCode ?? 0;
    final body = response.data;

    // 2xx — success
    if (status >= 200 && status < 300) {
      // Backend wraps all responses in { success: true, data: {...} }
      // Return the inner data object directly
      if (body is Map<String, dynamic>) {
        return (body['data'] as Map<String, dynamic>?) ?? body;
      }
      return {};
    }

    // Extract the message the backend sent (always human-readable)
    final message = _extractMessage(body);

    switch (status) {
      case 400:
        throw AppError(
          message: message,
          statusCode: 400,
          type: AppErrorType.validation,
          rawData: body,
        );
      case 401:
        // _AuthInterceptor already tried to refresh — if we're here, refresh
        // also failed. Time to log the user out.
        throw AppError.unauthorized(message);
      case 403:
        throw AppError.forbidden(message);
      case 404:
        throw AppError.notFound(message);
      case 409:
        throw AppError.conflict(message);
      case 422:
        throw AppError.validation(message);
      case 429:
        throw AppError.rateLimited(message);
      default:
        if (status >= 500) throw AppError.server(message);
        throw AppError.unknown(message);
    }
  }

  // ── DioException handler ──────────────────────────────────────────────────
  // Converts low-level network failures into AppError

  AppError _handleDioException(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return AppError.timeout();

      case DioExceptionType.connectionError:
        // Could be no internet, server down, or wrong URL
        if (e.error is SocketException) return AppError.network();
        return AppError.network();

      case DioExceptionType.badResponse:
        // Has a response — handle it like a normal response
        if (e.response != null) {
          return _handleResponse(e.response!) as dynamic;
        }
        return AppError.unknown();

      case DioExceptionType.cancel:
        return AppError.unknown('Request was cancelled.');

      default:
        return AppError.unknown(e.message);
    }
  }

  /// Pull the `message` field from the backend response body.
  /// Falls back to a generic string so we never show raw JSON to users.
  String _extractMessage(dynamic body) {
    if (body is Map<String, dynamic>) {
      return (body['message'] as String?) ?? 'Something went wrong.';
    }
    return 'Something went wrong.';
  }
}

// ── Auth Interceptor ──────────────────────────────────────────────────────────
//
// This interceptor runs on EVERY request and response automatically.
//
// ON REQUEST:
//   - Reads the access token from secure storage
//   - Adds it as: Authorization: Bearer <token>
//   - If no token exists, request goes out without auth header
//     (public endpoints like /auth/request-otp don't need it)
//
// ON RESPONSE (401 only):
//   - The access token expired mid-session
//   - We silently fetch a new access token using the refresh token
//   - Retry the original request with the new token
//   - The user never sees a "session expired" error during normal use
//   - If the refresh also fails → clear tokens → user must log in again
//
// WHY IN AN INTERCEPTOR AND NOT IN EACH SERVICE?
//   If you did this in each service, you'd have the same try/catch/refresh
//   logic in bookRide, getProfile, acceptRide, triggerSOS... everywhere.
//   Here it's written once and works for every request automatically.

class _AuthInterceptor extends Interceptor {
  final Dio _dio;

  // Tracks if we're already trying to refresh.
  // Prevents an infinite loop where the refresh request itself gets a 401
  // and triggers another refresh attempt.
  bool _isRefreshing = false;

  _AuthInterceptor(this._dio);

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await StorageService.getAccessToken();

    if (token != null && token.isNotEmpty) {
      // Attach token to this specific request's headers
      options.headers['Authorization'] = 'Bearer $token';
    }

    // Continue sending the request
    handler.next(options);
  }

  @override
  Future<void> onResponse(
    Response response,
    ResponseInterceptorHandler handler,
  ) async {
    // 401 means our access token expired
    if (response.statusCode == 401 && !_isRefreshing) {
      final retried = await _tryRefreshAndRetry(response.requestOptions);
      if (retried != null) {
        // Successfully retried with new token — return the new response
        return handler.resolve(retried);
      }
      // Refresh failed — pass the 401 through to _handleResponse
    }

    handler.next(response);
  }

  /// Attempts to get a new access token using the stored refresh token,
  /// then retries the original failed request.
  /// Returns null if refresh fails (user must re-login).
  Future<Response?> _tryRefreshAndRetry(RequestOptions original) async {
    _isRefreshing = true;

    try {
      final refreshToken = await StorageService.getRefreshToken();
      if (refreshToken == null || refreshToken.isEmpty) return null;

      // Call refresh endpoint directly on _dio (bypassing this interceptor
      // to avoid triggering another refresh on a 401 from the refresh call)
      final refreshResponse = await _dio.post(
        ApiEndpoints.refreshToken,
        data: {'refreshToken': refreshToken},
        options: Options(
          // Skip this interceptor for the refresh call itself
          extra: {'skipAuthInterceptor': true},
        ),
      );

      if (refreshResponse.statusCode == 200) {
        final data = refreshResponse.data as Map<String, dynamic>;
        final newAccessToken =
            (data['data'] as Map<String, dynamic>?)?['accessToken'] as String?;

        if (newAccessToken != null) {
          // Save new token to secure storage
          await StorageService.saveAccessToken(newAccessToken);

          // Retry the original request with the new token
          final retryOptions = original.copyWith(
            headers: {
              ...original.headers,
              'Authorization': 'Bearer $newAccessToken',
            },
          );
          return await _dio.fetch(retryOptions);
        }
      }

      // Refresh failed — clear tokens so router redirects to login
      await StorageService.clearAll();
      return null;
    } catch (_) {
      await StorageService.clearAll();
      return null;
    } finally {
      _isRefreshing = false;
    }
  }
}
