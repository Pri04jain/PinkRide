import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/app_error.dart';
import '../driver_service.dart';
import '../models/driver_model.dart';
import '../models/ride_request_model.dart';

// ── DriverHomeState ───────────────────────────────────────────────────────────
//
// Sealed class covering every possible state of the driver home screen.
//
// WHY SEALED?
// The screen has 5 meaningfully different states — loading, no profile yet,
// awaiting approval, live dashboard, and error. Tracking these with booleans
// leads to impossible combinations. A sealed class makes each state explicit
// and the UI switches exhaustively over them.

sealed class DriverHomeState {
  const DriverHomeState();
}

/// Initial load — fetching driver profile from backend.
class DriverHomeLoading extends DriverHomeState {
  const DriverHomeLoading();
}

/// Driver has no profile yet — show registration CTA.
class DriverHomeNoProfile extends DriverHomeState {
  const DriverHomeNoProfile();
}

/// Profile exists but not yet approved — show status screen.
class DriverHomePendingApproval extends DriverHomeState {
  final DriverModel driver;
  const DriverHomePendingApproval(this.driver);
}

/// Approved driver — main dashboard with online toggle + ride requests.
class DriverHomeReady extends DriverHomeState {
  final DriverModel driver;
  final List<RideRequestModel> rideRequests;
  final bool isLoadingRequests;
  final bool isTogglingAvailability;

  const DriverHomeReady({
    required this.driver,
    required this.rideRequests,
    this.isLoadingRequests = false,
    this.isTogglingAvailability = false,
  });

  DriverHomeReady copyWith({
    DriverModel? driver,
    List<RideRequestModel>? rideRequests,
    bool? isLoadingRequests,
    bool? isTogglingAvailability,
  }) {
    return DriverHomeReady(
      driver: driver ?? this.driver,
      rideRequests: rideRequests ?? this.rideRequests,
      isLoadingRequests: isLoadingRequests ?? this.isLoadingRequests,
      isTogglingAvailability:
          isTogglingAvailability ?? this.isTogglingAvailability,
    );
  }
}

/// Something went wrong — show error with retry.
class DriverHomeError extends DriverHomeState {
  final String message;
  const DriverHomeError(this.message);
}

// ── DriverHomeNotifier ────────────────────────────────────────────────────────

class DriverHomeNotifier extends StateNotifier<DriverHomeState> {
  final DriverService _service;

  DriverHomeNotifier(this._service) : super(const DriverHomeLoading()) {
    loadProfile();
  }

  // ── Load profile ──────────────────────────────────────────────────────────
  // Called on mount and after registration. Determines which sub-screen to show
  // by inspecting the driver's approval_status.

  Future<void> loadProfile() async {
    state = const DriverHomeLoading();

    try {
      final driver = await _service.getProfile();

      if (driver.isApproved) {
        // Approved — land on the live dashboard
        state = DriverHomeReady(driver: driver, rideRequests: const []);
        // Eagerly fetch ride requests if driver is already online
        if (driver.isAvailable) {
          await refreshRideRequests();
        }
      } else {
        // pending | under_review | rejected | suspended
        state = DriverHomePendingApproval(driver);
      }
    } on AppError catch (e) {
      if (e.statusCode == 404) {
        // No driver profile exists yet — new driver
        state = const DriverHomeNoProfile();
      } else {
        state = DriverHomeError(e.message);
      }
    } catch (_) {
      state = const DriverHomeError(
          'Could not load your driver profile. Please try again.');
    }
  }

  // ── Toggle availability ───────────────────────────────────────────────────
  // Optimistic update: flip the toggle immediately, then confirm with server.
  // On failure, revert to previous value and surface the error via a brief
  // error state that the screen can listen to.

  Future<void> toggleAvailability() async {
    final current = state;
    if (current is! DriverHomeReady) return;
    if (current.isTogglingAvailability) return; // prevent double-tap

    final wasAvailable = current.driver.isAvailable;
    final targetAvailability = !wasAvailable;

    // Optimistic flip
    state = current.copyWith(
      driver: current.driver.copyWith(isAvailable: targetAvailability),
      isTogglingAvailability: true,
    );

    try {
      final confirmed =
          await _service.setAvailability(isAvailable: targetAvailability);

      final readyState = state;
      if (readyState is! DriverHomeReady) return;

      state = readyState.copyWith(
        driver: readyState.driver.copyWith(isAvailable: confirmed),
        isTogglingAvailability: false,
      );

      // If just went online, immediately fetch nearby rides
      if (confirmed) await refreshRideRequests();
    } on AppError catch (e) {
      // Revert and surface error
      final readyState = state;
      if (readyState is! DriverHomeReady) return;
      state = readyState.copyWith(
        driver: readyState.driver.copyWith(isAvailable: wasAvailable),
        isTogglingAvailability: false,
      );
      // Re-emit as error so screen can show a snackbar
      _emitTransientError(e.message);
    } catch (_) {
      final readyState = state;
      if (readyState is! DriverHomeReady) return;
      state = readyState.copyWith(
        driver: readyState.driver.copyWith(isAvailable: wasAvailable),
        isTogglingAvailability: false,
      );
      _emitTransientError('Failed to update availability. Try again.');
    }
  }

  // ── Refresh ride requests ─────────────────────────────────────────────────
  // Fetches the latest nearby open rides from the backend.
  // Called when driver goes online, on pull-to-refresh, or on a timer.

  Future<void> refreshRideRequests() async {
    final current = state;
    if (current is! DriverHomeReady) return;

    state = current.copyWith(isLoadingRequests: true);

    try {
      final result = await _service.getNearbyRideRequests();

      final readyState = state;
      if (readyState is! DriverHomeReady) return;

      state = readyState.copyWith(
        rideRequests: result.requests,
        isLoadingRequests: false,
      );
    } on AppError catch (e) {
      final readyState = state;
      if (readyState is! DriverHomeReady) return;
      state = readyState.copyWith(isLoadingRequests: false);
      _emitTransientError(e.message);
    } catch (_) {
      final readyState = state;
      if (readyState is! DriverHomeReady) return;
      state = readyState.copyWith(isLoadingRequests: false);
    }
  }

  // ── Accept ride ───────────────────────────────────────────────────────────
  // Removes the accepted ride from the local list immediately (optimistic),
  // then calls the backend. On success, driver goes offline (backend sets
  // is_available=false after acceptance). On failure, reloads the list.

  Future<void> acceptRide(String rideId) async {
    final current = state;
    if (current is! DriverHomeReady) return;

    // Optimistically remove from list
    final updatedList =
        current.rideRequests.where((r) => r.id != rideId).toList();
    state = current.copyWith(rideRequests: updatedList);

    try {
      await _service.acceptRide(rideId);
      // Backend sets driver offline after accepting — reflect that locally
      final readyState = state;
      if (readyState is! DriverHomeReady) return;
      state = readyState.copyWith(
        driver: readyState.driver.copyWith(isAvailable: false),
        rideRequests: const [],
      );
    } on AppError catch (e) {
      _emitTransientError(e.message);
      await refreshRideRequests(); // reload real state from server
    } catch (_) {
      _emitTransientError('Failed to accept ride. Please try again.');
      await refreshRideRequests();
    }
  }

  // ── Called after registration completes ───────────────────────────────────
  // The register screen pops back and calls this to reload the newly
  // created profile and advance to PendingApproval state.

  Future<void> onRegistrationComplete() => loadProfile();

  // ── Internal helpers ──────────────────────────────────────────────────────

  /// Temporarily replaces state with DriverHomeError, then restores.
  /// Used to surface transient errors (toggle fail, accept fail) as a
  /// one-shot event that the screen listens to with ref.listen.
  void _emitTransientError(String message) {
    // Screen uses ref.listen to catch these; after one frame it reloads.
    state = DriverHomeError(message);
    // Restore the profile so the screen isn't stuck on the error state.
    loadProfile();
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

final driverHomeProvider =
    StateNotifierProvider<DriverHomeNotifier, DriverHomeState>((ref) {
  return DriverHomeNotifier(ref.watch(driverServiceProvider));
});

// ── DriverRegisterState ───────────────────────────────────────────────────────
// Separate notifier for the registration form — keeps form state isolated
// from the home screen so a failed submit doesn't affect the home state.

sealed class DriverRegisterState {
  const DriverRegisterState();
}

class DriverRegisterIdle extends DriverRegisterState {
  const DriverRegisterIdle();
}

class DriverRegisterSubmitting extends DriverRegisterState {
  const DriverRegisterSubmitting();
}

class DriverRegisterSuccess extends DriverRegisterState {
  const DriverRegisterSuccess();
}

class DriverRegisterError extends DriverRegisterState {
  final String message;
  const DriverRegisterError(this.message);
}

class DriverRegisterNotifier extends StateNotifier<DriverRegisterState> {
  final DriverService _service;

  DriverRegisterNotifier(this._service) : super(const DriverRegisterIdle());

  Future<void> submit({
    required String licenseNumber,
    required String licenseExpiry,
    required String vehicleNumber,
    required String vehicleType,
    required String vehicleMake,
    required String vehicleModel,
    required String vehicleColor,
    required int vehicleYear,
  }) async {
    if (state is DriverRegisterSubmitting) return;
    state = const DriverRegisterSubmitting();

    try {
      await _service.registerDriver(
        licenseNumber: licenseNumber,
        licenseExpiry: licenseExpiry,
        vehicleNumber: vehicleNumber,
        vehicleType: vehicleType,
        vehicleMake: vehicleMake,
        vehicleModel: vehicleModel,
        vehicleColor: vehicleColor,
        vehicleYear: vehicleYear,
      );
      state = const DriverRegisterSuccess();
    } on AppError catch (e) {
      state = DriverRegisterError(e.message);
    } catch (_) {
      state = const DriverRegisterError(
          'Registration failed. Please check your details and try again.');
    }
  }

  void clearError() {
    if (state is DriverRegisterError) state = const DriverRegisterIdle();
  }
}

final driverRegisterProvider =
    StateNotifierProvider.autoDispose<DriverRegisterNotifier, DriverRegisterState>(
        (ref) {
  return DriverRegisterNotifier(ref.watch(driverServiceProvider));
});

// ── DocUploadState ────────────────────────────────────────────────────────────
// Tracks the upload state for a single document type (license / rc / insurance).

sealed class DocUploadState {
  const DocUploadState();
}

class DocUploadIdle extends DocUploadState {
  const DocUploadIdle();
}

class DocUploading extends DocUploadState {
  const DocUploading();
}

class DocUploadSuccess extends DocUploadState {
  const DocUploadSuccess();
}

class DocUploadError extends DocUploadState {
  final String message;
  const DocUploadError(this.message);
}

class DocUploadNotifier extends StateNotifier<DocUploadState> {
  final DriverService _service;
  final String docType;

  DocUploadNotifier(this._service, this.docType)
      : super(const DocUploadIdle());

  Future<void> upload(String filePath) async {
    if (state is DocUploading) return;
    state = const DocUploading();

    try {
      await _service.uploadDocument(docType: docType, filePath: filePath);
      state = const DocUploadSuccess();
    } on AppError catch (e) {
      state = DocUploadError(e.message);
    } catch (_) {
      state = const DocUploadError('Upload failed. Please try again.');
    }
  }

  void reset() => state = const DocUploadIdle();
}

// Family provider keyed by docType string so each document has its own notifier.
final docUploadProvider = StateNotifierProvider.autoDispose
    .family<DocUploadNotifier, DocUploadState, String>((ref, docType) {
  return DocUploadNotifier(ref.watch(driverServiceProvider), docType);
});
