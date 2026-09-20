import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../../domain/models/models.dart';
import '../../domain/rules/medicine_schedule.dart';

/// Tier 2 — local notifications for a prescription's doses.
///
/// Deliberately the only place in the app that touches the plugin. Everything
/// about *when* lives in `medicine_schedule.dart` as a pure function, so this
/// class is the thin, untestable half: permissions, time zones and ids.
///
/// Nothing here throws at the caller. A phone that refuses the permission, has
/// no exact-alarm right, or has an Android version the plugin dislikes should
/// leave the rest of the consultation working — the reminder is a convenience,
/// and the prescription is already in the record either way.
class MedicineNotifications {
  MedicineNotifications({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const String channelId = 'medicine_reminders';
  static const String channelName = 'Medicine reminders';

  /// The patient whose timeline a tapped notification opens, carried as the
  /// notification payload.
  static const String payloadPrefix = 'patient:';

  final FlutterLocalNotificationsPlugin _plugin;

  bool _ready = false;

  /// Set once by `main()`; the router reads it after the first frame so a
  /// notification that launched the app still lands on the right timeline.
  static String? pendingPatientId;

  /// Prepare the plugin and the time-zone database.
  ///
  /// [onSelectPatient] is called when a notification is tapped while the app is
  /// running.
  Future<void> init({void Function(String patientId)? onSelectPatient}) async {
    if (_ready) return;

    tz.initializeTimeZones();
    // Nepal is UTC+05:45 and no device outside it will be running this demo;
    // asking the platform for its zone needs another package, and guessing UTC
    // would put every reminder five and three-quarter hours out.
    tz.setLocalLocation(tz.getLocation('Asia/Kathmandu'));

    void handle(NotificationResponse response) {
      final payload = response.payload;
      if (payload == null || !payload.startsWith(payloadPrefix)) return;
      final patientId = payload.substring(payloadPrefix.length);
      pendingPatientId = patientId;
      onSelectPatient?.call(patientId);
    }

    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
        onDidReceiveNotificationResponse: handle,
      );

      // The app may have been launched *by* a notification, in which case the
      // callback above never fires.
      final launch = await _plugin.getNotificationAppLaunchDetails();
      final payload = launch?.notificationResponse?.payload;
      if (launch?.didNotificationLaunchApp ?? false) {
        if (payload != null && payload.startsWith(payloadPrefix)) {
          pendingPatientId = payload.substring(payloadPrefix.length);
        }
      }

      _ready = true;
    } on Object catch (error) {
      debugPrint('Notifications unavailable: $error');
    }
  }

  /// Android 13+ will not show anything until the user agrees. Returns false if
  /// they said no, or if there is no implementation to ask.
  Future<bool> requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return false;

    try {
      return await android.requestNotificationsPermission() ?? false;
    } on Object catch (error) {
      debugPrint('Notification permission request failed: $error');
      return false;
    }
  }

  /// Schedule every dose in [prescriptions] for the next seven days.
  ///
  /// Returns how many alarms were actually set, which is what the UI reports —
  /// "12 reminders set" is checkable; "done" is not.
  Future<int> scheduleForVisit({
    required String patientId,
    required List<Prescription> prescriptions,
    DateTime? from,
  }) async {
    final doses = scheduleForPrescriptions(
      prescriptions,
      from: from ?? DateTime.now(),
    );

    var scheduled = 0;
    for (final dose in doses) {
      if (await _schedule(patientId: patientId, dose: dose)) scheduled++;
    }
    return scheduled;
  }

  /// One alarm. Used by [scheduleForVisit] and by the demo's 30-second check.
  Future<bool> _schedule({
    required String patientId,
    required ScheduledDose dose,
  }) async {
    if (!_ready) return false;

    final body = [
      if (dose.instructionsNp != null && dose.instructionsNp!.isNotEmpty)
        dose.instructionsNp!,
    ].join(' · ');

    try {
      await _plugin.zonedSchedule(
        id: notificationIdFor(dose.prescriptionId, dose.at),
        title: dose.drugName,
        body: body.isEmpty ? null : body,
        scheduledDate: tz.TZDateTime.from(dose.at, tz.local),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.reminder,
          ),
        ),
        // Exact where the phone allows it, because "take it at eight" is the
        // whole instruction. A phone that refuses falls back below rather than
        // dropping the reminder.
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: '$payloadPrefix$patientId',
      );
      return true;
    } on Object catch (error) {
      debugPrint('Exact alarm refused, retrying inexact: $error');
      try {
        await _plugin.zonedSchedule(
          id: notificationIdFor(dose.prescriptionId, dose.at),
          title: dose.drugName,
          body: body.isEmpty ? null : body,
          scheduledDate: tz.TZDateTime.from(dose.at, tz.local),
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              channelId,
              channelName,
              importance: Importance.high,
              priority: Priority.high,
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: '$payloadPrefix$patientId',
        );
        return true;
      } on Object catch (inner) {
        debugPrint('Could not schedule reminder: $inner');
        return false;
      }
    }
  }

  /// Schedules one notification a short way ahead.
  ///
  /// This exists for the pre-demo check in `docs/DEMO_SCRIPT.md`: it is the
  /// only way to find out whether this particular phone will actually show a
  /// reminder before the room is watching.
  Future<bool> scheduleSmokeTest({
    required String patientId,
    required String drugName,
    String? instructionsNp,
    Duration after = const Duration(seconds: 30),
  }) {
    return _schedule(
      patientId: patientId,
      dose: ScheduledDose(
        prescriptionId: 'smoke-test',
        at: DateTime.now().add(after),
        drugName: drugName,
        instructionsNp: instructionsNp,
      ),
    );
  }

  Future<void> cancelAll() async {
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
    } on Object catch (error) {
      debugPrint('Could not cancel reminders: $error');
    }
  }

  /// How many alarms are currently waiting, for the "n reminders set" line.
  Future<int> pendingCount() async {
    if (!_ready) return 0;
    try {
      return (await _plugin.pendingNotificationRequests()).length;
    } on Object {
      return 0;
    }
  }
}
