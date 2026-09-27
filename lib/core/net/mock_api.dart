import 'dart:async';

import '../../domain/models/models.dart';
import '../../domain/rules/rules.dart' as domain;
import '../../domain/rules/triage.dart' as domain;
import '../errors/app_error.dart';
import '../ids/ids.dart';
import 'api_transport.dart';

/// Spec §15 — every endpoint in Part A against in-memory maps.
///
/// It exists so the app can be built and demoed before the backend does, and it
/// is the fallback if the backend is down during the demo. Switch it on with
/// `--dart-define=MOCK_API=true`.
///
/// It sits at the [ApiTransport] seam, which means it answers with the same
/// unwrapped `data` object the envelope interceptor produces — the endpoint
/// classes above it cannot tell the difference, so mock mode cannot drift out
/// of shape with the contract.
///
/// Behaviour the spec pins down: OTP is always `123456`; any four-digit PIN is
/// accepted; grants expire after ten minutes; redeem returns the whole bundle;
/// sync push answers `applied` with `version + 1`; pull returns nothing new.
class MockApi implements ApiTransport {
  /// [rules] makes the mock's triage the *real* triage. Leave it null and the
  /// mock falls back to a crude stand-in — enough to drive a red banner in a
  /// widget test, but the app should pass the loaded rule table in mock mode so
  /// the demo exercises the same code the backend will.
  MockApi({
    DateTime Function()? clock,
    this.latency = Duration.zero,
    this.rules,
    String? activatedRole,
    String? activatedName,
    this.onActivated,
    this.onNamed,
  })  : _clock = clock ?? DateTime.now {
    _seed();
    // A real server remembers that this account became a health worker; an
    // in-memory mock forgets on every launch, and `GET /me` then overwrites
    // the role the device had already stored. So the composition root hands
    // the last activation back in.
    if (activatedRole != null) _applyRole(activatedRole);
    // The display name is forgotten the same way, and shows up in the same
    // place: `GET /me` handed back the seeded account's name, so the provider
    // phone's lock screen and greeting read "Sita Chaudhary" instead of the
    // health worker who set the PIN.
    if (activatedName != null && activatedName.isNotEmpty) {
      _user = {..._user, 'name': activatedName};
    }
  }

  /// Demo constants from spec §15 and A.4.
  static const String demoOtp = '123456';
  static const String providerInviteCode = 'HA-GHORAHI-01';
  static const String fchvInviteCode = 'FCHV-W5-01';
  static const String qrPrefix = 'SWC1:';

  /// Spec A.7: a printed fallback card is a `ttlMinutes: 525600` grant, and
  /// redeeming a long-lived token additionally requires the patient's PIN.
  /// Anything a day or longer counts — a card that outlives the consultation
  /// is a card that can be photographed off a wall.
  static const int longLivedTtlMinutes = 1440;

  /// The PIN the seeded owner is assumed to have set, for the case where the
  /// demo starts from a pull rather than from `POST /auth/pin/set`.
  static const String demoPatientPin = '1234';

  final DateTime Function() _clock;

  /// Settable so the composition root can hand the mock the loaded rule table
  /// without the transport provider having to depend on the provider that
  /// loads it — that would be a cycle, since loading can go over the wire.
  domain.Rules? rules;

  /// A touch of delay makes loading states visible when demoing.
  final Duration latency;

  /// Called when S18 activates a role, so it can outlive this instance.
  final void Function(String role)? onActivated;

  /// Called when S05 sets the account name, for the same reason.
  final void Function(String name)? onNamed;

  final Map<String, Map<String, dynamic>> _patients = {};
  final Map<String, Map<String, dynamic>> _visits = {};
  final Map<String, Map<String, dynamic>> _documents = {};
  final Map<String, Map<String, dynamic>> _pregnancies = {};
  final Map<String, Map<String, dynamic>> _ancContacts = {};
  final Map<String, Map<String, dynamic>> _deliveries = {};

  /// Tier 3, additive (docs/CONTRACT_ADDENDUM.md).
  final Map<String, Map<String, dynamic>> _immunisations = {};
  final Map<String, Map<String, dynamic>> _growth = {};
  final Map<String, Map<String, dynamic>> _reminders = {};
  final Map<String, Map<String, dynamic>> _auditEntries = {};
  final Map<String, Map<String, dynamic>> _grants = {};
  final List<Map<String, dynamic>> _facilities = [];
  final List<Map<String, dynamic>> _codelists = [];
  final List<Map<String, dynamic>> _demoSms = [];

  /// Op ids already applied, so a replayed push answers `duplicate` rather than
  /// writing twice — the same idempotency the real server provides (A.4).
  final Set<String> _appliedOpIds = {};

  /// Phones that have completed `POST /auth/pin/set`.
  ///
  /// Without this the mock answered `hasPin: true` to the very first OTP
  /// verification, so S03 routed a brand-new install to the unlock screen and
  /// S05 "Set PIN + name" could never be reached — which is step 2 of the §17
  /// acceptance checklist.
  final Set<String> _phonesWithPin = {};

  /// The PIN each user id last set, so a long-lived (printed-card) grant can
  /// be checked against the *patient's own* PIN rather than any four digits.
  /// The real backend holds a hash; the mock holds the digits because there is
  /// nothing here to protect.
  final Map<String, String> _pinsByUserId = {};

  late Map<String, dynamic> _user;

  String get _now => _clock().toUtc().toIso8601String();

  /// The last `updatedAt` this mock handed out.
  DateTime? _lastWriteAt;

  /// A write timestamp that is strictly later than every previous one.
  ///
  /// `updatedAt` is the pull cursor, and the cursor advances past rows it has
  /// already returned — so two rows sharing a timestamp means one of them can
  /// never be pulled. A real server has sub-millisecond resolution and a
  /// monotonic clock; an injected test clock has neither, so this supplies both
  /// rather than letting the boundary bug hide behind a frozen clock.
  String _touch() {
    var at = _clock().toUtc();
    final last = _lastWriteAt;
    if (last != null && !at.isAfter(last)) {
      at = last.add(const Duration(milliseconds: 1));
    }
    _lastWriteAt = at;
    return at.toIso8601String();
  }

  // ---------------------------------------------------------------------------
  // ApiTransport
  // ---------------------------------------------------------------------------

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
    String? bearer,
  }) =>
      _route('GET', path, null, query ?? const {});

  @override
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
    String? bearer,
  }) =>
      _route('POST', path, body ?? const {}, const {});

  @override
  Future<Map<String, dynamic>> put(
    String path, {
    Map<String, dynamic>? body,
    String? bearer,
  }) =>
      _route('PUT', path, body ?? const {}, const {});

  @override
  Future<Map<String, dynamic>> patch(
    String path, {
    Map<String, dynamic>? body,
    String? bearer,
  }) =>
      _route('PATCH', path, body ?? const {}, const {});

  /// There is no storage to PUT to; the handshake still has three steps so the
  /// upload worker's retry and attempt counting get exercised.
  @override
  Future<void> uploadBytes(
    String url, {
    required List<int> bytes,
    required Map<String, String> headers,
    String method = 'PUT',
  }) async {
    await Future<void>.delayed(latency);
  }

  // ---------------------------------------------------------------------------
  // Routing
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> _route(
    String method,
    String path,
    Map<String, dynamic>? body,
    Map<String, dynamic> query,
  ) async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);

    final b = body ?? const <String, dynamic>{};

    Map<String, String>? p;
    switch ('$method $path') {
      case 'POST /auth/otp/request':
        return {
          'otpSentTo': b['phone'],
          'expiresInSec': 300,
          'demoOtp': demoOtp,
        };
      case 'POST /auth/otp/verify':
        if (b['otp'] != demoOtp) {
          throw const AppError(
            code: AppError.validationError,
            message: 'Wrong code',
            details: {'otp': 'Wrong code'},
            httpStatus: 400,
          );
        }
        final phone = '${b['phone']}';
        final known = _phonesWithPin.contains(phone);
        return {
          'tempToken': 'mock_temp',
          'hasPin': known,
          'isNewUser': !known,
        };
      case 'POST /auth/pin/set':
        _user = {..._user, 'name': b['name'] ?? _user['name']};
        onNamed?.call('${_user['name']}');
        _phonesWithPin.add('${_user['phone']}');
        // Remembered so a long-lived printed-card grant can be checked against
        // this account's PIN rather than against any four digits (A.7).
        _pinsByUserId['${_user['id']}'] = '${b['pin'] ?? demoPatientPin}';
        return _session();
      case 'POST /auth/pin/login':
        _phonesWithPin.add('${b['phone']}');
        final pin = '${b['pin'] ?? ''}';
        if (pin.length != 4) {
          throw const AppError(
            code: AppError.validationError,
            message: 'PIN must be 4 digits',
            details: {'pin': 'PIN must be 4 digits'},
            httpStatus: 400,
          );
        }
        _pinsByUserId['${_user['id']}'] = pin;
        return _session();
      case 'POST /auth/refresh':
        return {
          'accessToken': 'mock_access',
          'refreshToken': 'mock_refresh',
        };
      case 'POST /auth/provider/activate':
        return {'user': _activate('${b['inviteCode']}')};
      case 'GET /me':
        return {'user': _user};

      case 'GET /patients':
        // S06's family list: the records this account *owns*, not every record
        // it may see. Granted patients reach the device through `/sync/pull`
        // and surface under "Recent patients" on S19 instead — returning them
        // here puts other people's households in somebody's family screen.
        return {
          'items': _patients.values
              .where((p) => _alive(p) && p['ownerUserId'] == _user['id'])
              .toList(),
        };
      case 'POST /patients':
        return {'patient': _createPatient(b)};

      case 'POST /grants':
        return _createGrant(b);
      case 'POST /grants/redeem':
        return _redeemGrant(
          '${b['qrPayload']}',
          b['pin'] == null ? null : '${b['pin']}',
        );

      case 'POST /documents/presign':
        return _presign(b);

      case 'GET /codelists':
        return {
          'version': configVersion,
          'items': query['kind'] == null
              ? _codelists
              : _codelists.where((c) => c['kind'] == query['kind']).toList(),
        };
      case 'GET /rules':
        return rulesDocument;
      case 'GET /config':
        return {
          'smsMode': 'mock',
          'aiSummaryEnabled': true,
          // Tier 3. False, and honestly so: none of these has an API to talk
          // to. The Settings rows say what each one would do and stay
          // disabled. See docs/CONTRACT_ADDENDUM.md.
          'nidEnabled': false,
          'hmisExportEnabled': false,
          'councilVerifyEnabled': false,
          'otpDemo': true,
          'rulesVersion': configVersion,
          'codelistVersion': configVersion,
        };
      case 'GET /demo/sms':
        return {'items': _demoSms};
      case 'GET /facilities/nearby':
        return {'items': _nearby(query)};

      case 'POST /sync/push':
        return _push(b);
      case 'GET /sync/pull':
        return _pull('${query['since'] ?? ''}');
    }

    if ((p = _match('PATCH /patients/:id', method, path)) != null) {
      return {'patient': _updatePatient(p!['id']!, b)};
    }
    if ((p = _match('GET /patients/:id', method, path)) != null) {
      return _patientDetail(p!['id']!);
    }
    if ((p = _match('GET /patients/:id/timeline', method, path)) != null) {
      return {'items': _timeline(p!['id']!), 'nextBefore': null};
    }
    if ((p = _match('GET /patients/:id/audit', method, path)) != null) {
      return {'items': _forPatient(_auditEntries, p!['id']!)};
    }
    if ((p = _match('GET /patients/:id/visits', method, path)) != null) {
      return {'items': _forPatient(_visits, p!['id']!)};
    }
    if ((p = _match('POST /patients/:id/visits', method, path)) != null) {
      return {'visit': _addVisit(p!['id']!, b)};
    }
    if ((p = _match('GET /patients/:id/reminders', method, path)) != null) {
      return {'items': _forPatient(_reminders, p!['id']!)};
    }
    if ((p = _match('POST /patients/:id/pregnancies', method, path)) != null) {
      return _registerPregnancy(p!['id']!, b);
    }
    if ((p = _match('POST /grants/:id/revoke', method, path)) != null) {
      return {'grant': _revokeGrant(p!['id']!)};
    }
    if ((p = _match('POST /documents/:id/complete', method, path)) != null) {
      return {'document': _completeDocument(p!['id']!)};
    }
    if ((p = _match('POST /documents/:id/summarize', method, path)) != null) {
      return {'document': _summarize(p!['id']!)};
    }
    if ((p = _match('GET /documents/:id', method, path)) != null) {
      return {'document': _readDocument(p!['id']!)};
    }
    if ((p = _match('GET /pregnancies/:id', method, path)) != null) {
      return _pregnancyBundle(p!['id']!);
    }
    if ((p = _match('PATCH /pregnancies/:id', method, path)) != null) {
      return {'pregnancy': _updatePregnancy(p!['id']!, b)};
    }
    if ((p = _match('POST /pregnancies/:id/delivery', method, path)) != null) {
      return _recordDelivery(p!['id']!, b);
    }
    if ((p = _match(
          'PUT /pregnancies/:id/contacts/:contactNo',
          method,
          path,
        )) !=
        null) {
      return _recordContact(p!['id']!, int.parse(p['contactNo']!), b);
    }

    throw AppError(
      code: AppError.notFound,
      message: 'Mock API has no route for $method $path',
      httpStatus: 404,
    );
  }

  /// Matches `'GET /patients/:id/visits'` against a live method and path,
  /// returning the captured parameters or null.
  Map<String, String>? _match(String pattern, String method, String path) {
    final parts = pattern.split(' ');
    if (parts.first != method) return null;

    final expected = parts.last.split('/');
    final actual = path.split('/');
    if (expected.length != actual.length) return null;

    final params = <String, String>{};
    for (var i = 0; i < expected.length; i++) {
      final segment = expected[i];
      if (segment.startsWith(':')) {
        params[segment.substring(1)] = actual[i];
      } else if (segment != actual[i]) {
        return null;
      }
    }
    return params;
  }

  // ---------------------------------------------------------------------------
  // Handlers
  // ---------------------------------------------------------------------------

  Map<String, dynamic> _session() => {
        'accessToken': 'mock_access',
        'refreshToken': 'mock_refresh',
        'user': _user,
      };

  Map<String, dynamic> _activate(String inviteCode) {
    final role = switch (inviteCode) {
      providerInviteCode => 'provider',
      fchvInviteCode => 'fchv',
      _ => null,
    };
    if (role == null) {
      throw const AppError(
        code: AppError.validationError,
        message: 'Unknown invite code',
        details: {'inviteCode': 'Unknown invite code'},
        httpStatus: 400,
      );
    }

    _applyRole(role);
    onActivated?.call(role);
    return _user;
  }

  /// The role half of an activation, without the invite-code check — the
  /// constructor replays a stored role that was already validated once.
  void _applyRole(String role) {
    _user = {
      ..._user,
      'role': role,
      'facilityId': 'f_0001',
      'facilityName': 'Ghorahi Health Post',
    };
  }

  bool _alive(Map<String, dynamic> row) => row['deleted'] != true;

  List<Map<String, dynamic>> _forPatient(
    Map<String, Map<String, dynamic>> table,
    String patientId,
  ) =>
      table.values
          .where((r) => r['patientId'] == patientId && _alive(r))
          .toList();

  Map<String, dynamic> _require(
    Map<String, Map<String, dynamic>> table,
    String id,
  ) {
    final row = table[id];
    if (row == null) {
      throw AppError(
        code: AppError.notFound,
        message: 'No row with id $id',
        httpStatus: 404,
      );
    }
    return row;
  }

  Map<String, dynamic> _createPatient(Map<String, dynamic> body) {
    final id = '${body['id'] ?? newId()}';
    // Idempotent by id, exactly as the contract promises.
    final existing = _patients[id];
    if (existing != null) return existing;

    return _patients[id] = {
      'id': id,
      'ownerUserId': _user['id'],
      'name': body['name'],
      'sex': body['sex'],
      'dob': body['dob'],
      'bloodGroup': body['bloodGroup'],
      'ward': body['ward'],
      'municipality': body['municipality'],
      'allergies': body['allergies'] ?? <String>[],
      'chronicConditions': body['chronicConditions'] ?? <String>[],
      'emergencyContactPhone': body['emergencyContactPhone'],
      'version': 1,
      'updatedAt': _touch(),
      'deleted': false,
    };
  }

  Map<String, dynamic> _updatePatient(String id, Map<String, dynamic> body) {
    final current = _require(_patients, id);
    return _patients[id] = {
      ...current,
      ...body,
      'id': id,
      'version': (current['version'] as int) + 1,
      'updatedAt': _touch(),
    };
  }

  Map<String, dynamic> _patientDetail(String id) {
    final patient = _require(_patients, id);
    final visits = _forPatient(_visits, id);

    return {
      'patient': patient,
      'summary': {
        'allergies': patient['allergies'],
        'activeProblems': [
          for (final code in (patient['chronicConditions'] as List))
            {'code': code, 'labelEn': '$code', 'labelNp': '$code'},
        ],
        'lastVitals': visits.isEmpty
            ? null
            : {
                'at': visits.first['visitAt'],
                ...?(visits.first['vitals'] as Map?)?.cast<String, dynamic>(),
              },
        'lastVisitAt': visits.isEmpty ? null : visits.first['visitAt'],
        'pregnancyActive': _pregnancies.values.any(
          (p) => p['patientId'] == id && p['status'] == 'active',
        ),
      },
    };
  }

  /// "BP 132/84 · J45 · 1 Rx" — the same line the offline timeline builds.
  String? _visitSubtitle(Map<String, dynamic> v) {
    final vitals = (v['vitals'] as Map?)?.cast<String, dynamic>();
    final codes = (v['diagnosisCodes'] as List?)?.cast<String>() ?? const [];
    final rx = (v['prescriptions'] as List?)?.length ?? 0;
    final parts = <String>[
      if (vitals?['bpSys'] != null && vitals?['bpDia'] != null)
        'BP ${vitals!['bpSys']}/${vitals['bpDia']}',
      ...codes,
      if (rx > 0) '$rx Rx',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  List<Map<String, dynamic>> _timeline(String patientId) {
    final items = <Map<String, dynamic>>[
      for (final v in _forPatient(_visits, patientId))
        {
          'kind': 'visit',
          'at': v['visitAt'],
          // The same shape the offline formatter builds, so a row does not
          // change its wording the moment it syncs. "Visit" on its own, with
          // the raw complaint code underneath, told the health worker neither
          // where the patient was seen nor what for.
          'title': [
            'Visit',
            if ('${v['facilityName'] ?? ''}'.isNotEmpty) v['facilityName'],
            if ((v['diagnosisCodes'] as List?)?.isNotEmpty ?? false)
              (v['diagnosisCodes'] as List).join(', ')
            else
              v['chiefComplaintCode'],
          ].join(' — '),
          'subtitle': _visitSubtitle(v),
          'refId': v['id'],
          'payload': v,
        },
      for (final d in _forPatient(_documents, patientId))
        {
          'kind': 'document',
          'at': d['takenAt'],
          'title': d['title'],
          'refId': d['id'],
          'payload': d,
        },
      for (final p in _pregnancies.values.where(
        (p) => p['patientId'] == patientId,
      ))
        {
          'kind': 'pregnancy_registered',
          'at': p['updatedAt'],
          'title': 'Pregnancy registered',
          'refId': p['id'],
          'payload': p,
        },
      // Tier 3. Only doses actually given reach the timeline: the timeline is a
      // record of what happened, and a schedule row nobody has acted on has
      // not happened yet. The child-health screen is where the plan lives.
      for (final i in _forPatient(_immunisations, patientId))
        if (i['givenAt'] != null)
          {
            'kind': 'immunisation',
            'at': i['givenAt'],
            'title': '${i['vaccineCode']} dose ${i['doseNo']}',
            'subtitle': i['batchNo'] == null ? null : 'Batch ${i['batchNo']}',
            'refId': i['id'],
            'payload': i,
          },
      for (final g in _forPatient(_growth, patientId))
        {
          'kind': 'growth',
          'at': g['measuredAt'],
          'title': 'Weight ${g['weightKg']} kg',
          'refId': g['id'],
          'payload': g,
        },
    ];

    items.sort((a, b) => '${b['at']}'.compareTo('${a['at']}'));
    return items;
  }

  Map<String, dynamic> _addVisit(String patientId, Map<String, dynamic> body) {
    final id = '${body['id'] ?? newId()}';
    final existing = _visits[id];
    if (existing != null) return existing;

    final visit = _visits[id] = {
      'id': id,
      'patientId': patientId,
      'providerUserId': _user['id'],
      'providerName': _user['name'],
      'facilityId': _user['facilityId'],
      'facilityName': _user['facilityName'],
      'visitAt': body['visitAt'] ?? _now,
      'chiefComplaintCode': body['chiefComplaintCode'],
      'vitals': body['vitals'],
      'diagnosisCodes': body['diagnosisCodes'] ?? <String>[],
      'notes': body['notes'],
      'advice': body['advice'],
      'followUpAt': body['followUpAt'],
      'referral': body['referral'],
      'prescriptions': body['prescriptions'] ?? <Map<String, dynamic>>[],
      'supersedesId': body['supersedesId'],
      'version': 1,
      'updatedAt': _touch(),
      'deleted': false,
    };

    _audit(patientId, 'visit_added');
    return visit;
  }

  // -------------------------------------------------------------------------
  // Grants
  // -------------------------------------------------------------------------

  Map<String, dynamic> _createGrant(Map<String, dynamic> body) {
    final id = newId();
    final token = 'mock_grant_$id';
    final ttl = (body['ttlMinutes'] as int?) ?? 10;

    final grant = _grants[id] = {
      'id': id,
      'patientId': body['patientId'],
      'scope': body['scope'] ?? 'append',
      'token': token,
      'expiresAt':
          _clock().toUtc().add(Duration(minutes: ttl)).toIso8601String(),
      'redeemedByUserId': null,
      'redeemedAt': null,
      'revokedAt': null,
      'accessUntil': null,
      // A.7's printed fallback card. The flag travels with the grant so the
      // provider's app knows, before it has anything else to go on, that this
      // token needs the patient's PIN beside it.
      'longLived': ttl >= longLivedTtlMinutes,
      // Tier 3 fine-grained consent, additive. Absent or empty means the whole
      // record — the behaviour of every grant before this existed.
      'sections': (body['sections'] as List?)?.cast<String>() ?? <String>[],
    };

    _audit('${body['patientId']}', 'grant_created');
    return {'grant': grant, 'token': token, 'qrPayload': '$qrPrefix$token'};
  }

  /// The PIN the patient's owning account last set, or the demo default when
  /// this install reached the record by a pull rather than by setting one.
  String _ownerPin(String patientId) {
    final owner = '${_require(_patients, patientId)['ownerUserId']}';
    return _pinsByUserId[owner] ?? demoPatientPin;
  }

  /// DEMO: mock only — the real backend validates the JWT.
  ///
  /// True when [payload] carries the SWC1 prefix and [token] is exactly the
  /// shape [_createGrant] mints: `mock_grant_` followed by a UUID. Anything
  /// else — "HELLO", a bare token with no prefix, a truncated paste — is not
  /// a grant and is left to fail.
  static final RegExp _mockGrantToken = RegExp(
    r'^mock_grant_[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}'
    r'-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  bool _looksLikeForeignGrant(String payload, String token) =>
      payload.startsWith(qrPrefix) && _mockGrantToken.hasMatch(token);

  /// DEMO: mock only — the real backend validates the JWT.
  ///
  /// Records the other phone's code as a grant on the seeded Sita so the rest
  /// of [_redeemGrant] can run unchanged: one redeem path, one bundle, one
  /// audit trail.
  Map<String, dynamic> _adoptForeignGrant(String token) {
    final id = token.substring('mock_grant_'.length);
    _audit(sitaId, 'grant_created');
    return _grants[id] = {
      'id': id,
      'patientId': sitaId,
      'scope': 'append',
      'token': token,
      // Ten minutes from now rather than from whenever the other phone drew
      // it: the two clocks are not the same clock, and an adopted code that
      // arrives already expired would be worse than no leniency at all.
      'expiresAt': _clock().toUtc().add(const Duration(minutes: 10))
          .toIso8601String(),
      'redeemedByUserId': null,
      'redeemedAt': null,
      'revokedAt': null,
      'accessUntil': null,
      'longLived': false,
      'sections': <String>[],
    };
  }

  Map<String, dynamic> _redeemGrant(String qrPayload, [String? pin]) {
    final token = qrPayload.startsWith(qrPrefix)
        ? qrPayload.substring(qrPrefix.length)
        : qrPayload;

    var grant = _grants.values.cast<Map<String, dynamic>?>().firstWhere(
          (g) => g!['token'] == token,
          orElse: () => null,
        );

    // DEMO: mock only — the real backend validates the JWT.
    //
    // Two phones running the mock each hold their own `_grants` map, so a code
    // the patient's phone just drew is a code this instance has never heard of
    // and the scan dies on "Unknown QR code". That kills the one moment the
    // demo exists to show. When the payload is shaped like a code this mock
    // would itself have issued — the SWC1 prefix and a `mock_grant_<uuid>`
    // token — it is adopted and pointed at the seeded Sita, which is the
    // record both phones are seeded with anyway.
    //
    // Nothing else is relaxed: a code this instance *did* issue still goes
    // through the expiry, revoke and already-redeemed checks below, and a bad
    // prefix or a payload that is not a grant token is still rejected.
    if (grant == null && _looksLikeForeignGrant(qrPayload, token)) {
      grant = _adoptForeignGrant(token);
    }

    if (grant == null) {
      throw const AppError(
        code: AppError.notFound,
        message: 'Unknown QR code',
        httpStatus: 404,
      );
    }
    if (grant['revokedAt'] != null ||
        _clock().toUtc().isAfter(DateTime.parse('${grant['expiresAt']}'))) {
      throw const AppError(
        code: AppError.grantExpired,
        message: 'QR expired, ask for a new one',
        httpStatus: 403,
      );
    }
    if (grant['redeemedByUserId'] != null &&
        grant['redeemedByUserId'] != _user['id']) {
      throw const AppError(
        code: AppError.alreadyRedeemed,
        message: 'Already used',
        httpStatus: 409,
      );
    }

    // A.7: a printed card is readable by anyone who can see the wall it hangs
    // on, so the second factor is the patient standing there to say four
    // digits. `details.pin` tells the app which of the two it is looking at —
    // a challenge it has not answered yet, or an answer that was wrong —
    // without adding a code to the A.3 table.
    if (grant['longLived'] == true) {
      final expected = _ownerPin('${grant['patientId']}');
      if (pin == null || pin.isEmpty) {
        throw const AppError(
          code: AppError.forbidden,
          message: 'This card needs the patient PIN',
          details: {'pin': 'required'},
          httpStatus: 403,
        );
      }
      if (pin != expected) {
        throw const AppError(
          code: AppError.forbidden,
          message: 'Wrong PIN',
          details: {'pin': 'invalid'},
          httpStatus: 403,
        );
      }
    }

    grant
      ..['redeemedByUserId'] = _user['id']
      ..['redeemedAt'] = _now
      ..['accessUntil'] =
          _clock().toUtc().add(const Duration(hours: 24)).toIso8601String();

    final patientId = '${grant['patientId']}';
    _audit(patientId, 'grant_redeemed');

    final pregnancy = _pregnancies.values
        .cast<Map<String, dynamic>?>()
        .firstWhere(
          (p) => p!['patientId'] == patientId && p['status'] == 'active',
          orElse: () => null,
        );

    // Tier 3: the bundle carries only what the patient agreed to share. The
    // filtering happens here, on the server side of the seam, because consent
    // the client enforces is not consent — a provider with a debugger would
    // still have the whole record.
    final sections = (grant['sections'] as List?)?.cast<String>() ?? const [];
    bool shares(String section) =>
        sections.isEmpty || sections.contains(section);

    final timeline = _timeline(patientId).where((item) {
      final kind = '${item['kind']}';
      return switch (kind) {
        'visit' => shares('visits'),
        'document' => shares('documents'),
        'pregnancy_registered' || 'anc_contact' || 'delivery' =>
          shares('pregnancy'),
        'immunisation' || 'growth' => shares('child'),
        _ => true,
      };
    }).toList();

    return {
      'grant': grant,
      // The patient row itself is always included: a summary with no name on
      // it is not a record, it is a puzzle. What `sections` controls is the
      // clinical content.
      'patient': _require(_patients, patientId),
      // An *empty* summary rather than a null one: A.4 types `summary` as
      // required, and withholding a section must not change the shape of the
      // envelope. Note that the patient row above still carries `allergies`,
      // so the one genuinely safety-critical field is never hidden by a
      // consent choice — see the note in docs/CONTRACT_ADDENDUM.md.
      'summary': shares('summary')
          ? _patientDetail(patientId)['summary']
          : _emptySummary(),
      'timeline': timeline,
      'pregnancy': shares('pregnancy') ? pregnancy : null,
      'ancContacts': pregnancy == null || !shares('pregnancy')
          ? <Map<String, dynamic>>[]
          : _ancContacts.values
              .where((c) => c['pregnancyId'] == pregnancy['id'])
              .toList(),
    };
  }

  /// The shape of a summary that was not shared: present, valid, and empty.
  static Map<String, dynamic> _emptySummary() => {
        'activeProblems': <Map<String, dynamic>>[],
        'currentMedicines': <Map<String, dynamic>>[],
        'allergies': <String>[],
        'lastVitals': null,
        'activePregnancy': null,
        'lastVisitAt': null,
        'visitCount': 0,
      };

  Map<String, dynamic> _revokeGrant(String id) {
    final grant = _require(_grants, id);
    return _grants[id] = {...grant, 'revokedAt': _now, 'accessUntil': null};
  }

  // -------------------------------------------------------------------------
  // Documents
  // -------------------------------------------------------------------------

  Map<String, dynamic> _presign(Map<String, dynamic> body) {
    final id = '${body['id'] ?? newId()}';
    final document = _documents[id] = {
      'id': id,
      'patientId': body['patientId'],
      'uploadedByUserId': _user['id'],
      'type': body['type'],
      'title': body['title'],
      'takenAt': body['takenAt'],
      'status': 'pending_upload',
      'downloadUrl': null,
      'aiSummary': null,
      'aiSummaryStatus': 'none',
      'version': 1,
      'updatedAt': _touch(),
      'deleted': false,
    };

    return {
      'document': document,
      'uploadUrl': 'https://mock.storage.invalid/put/$id',
      'uploadMethod': 'PUT',
      'uploadHeaders': {'Content-Type': '${body['contentType']}'},
      'expiresInSec': 900,
    };
  }

  Map<String, dynamic> _completeDocument(String id) {
    final current = _require(_documents, id);
    final document = _documents[id] = {
      ...current,
      'status': 'uploaded',
      'downloadUrl': 'https://mock.storage.invalid/get/$id',
      'version': (current['version'] as int) + 1,
      'updatedAt': _touch(),
    };

    _audit('${current['patientId']}', 'document_added');
    return document;
  }

  /// How long the mock pretends the model takes. Long enough that S10's queued
  /// state is visible on a projector, short enough that nobody in the room
  /// stops watching.
  static const Duration summaryDelay = Duration(seconds: 4);

  /// When each queued summary becomes available.
  final Map<String, DateTime> _summaryReadyAt = {};

  /// `POST /documents/:id/summarize` (A.4). Answers `queued` immediately; the
  /// work "happens" between polls, which is the shape the app has to cope with
  /// against a real queue.
  Map<String, dynamic> _summarize(String id) {
    final current = _require(_documents, id);
    _summaryReadyAt[id] = _clock().toUtc().add(summaryDelay);
    return _documents[id] = {
      ...current,
      'aiSummary': null,
      'aiSummaryStatus': 'queued',
      'version': (current['version'] as int) + 1,
      'updatedAt': _touch(),
    };
  }

  /// `GET /documents/:id`, which is also where a queued job finishes.
  ///
  /// The mock has no worker, so the transition happens on the read that comes
  /// after the deadline — from the app's point of view that is indistinguishable
  /// from a job that completed while it was waiting.
  Map<String, dynamic> _readDocument(String id) {
    final current = _require(_documents, id);
    final readyAt = _summaryReadyAt[id];

    if (readyAt == null || _clock().toUtc().isBefore(readyAt)) return current;

    _summaryReadyAt.remove(id);
    return _documents[id] = {
      ...current,
      'aiSummary': cannedSummary,
      'aiSummaryStatus': 'done',
      'version': (current['version'] as int) + 1,
      'updatedAt': _touch(),
    };
  }

  /// The one draft the mock knows how to write.
  ///
  /// Both languages in one string, because A.2 says `aiSummary` is "Nepali +
  /// English summary" — one field, not two — and the label above it in S10 says
  /// in both languages that a human still has to check it.
  static const String cannedSummary = '''
भरतपुर अस्पताल — डिस्चार्ज सारांश (मस्यौदा)
भर्ना: निमोनिया। ५ दिन उपचार पछि सुधार भई डिस्चार्ज।
औषधि:
• एमोक्सिसिलिन ५०० मि.ग्रा. — १ ट्याब्लेट दिनको ३ पटक, ५ दिन
• प्यारासिटामोल ५०० मि.ग्रा. — १ ट्याब्लेट ज्वरो आएमा, दिनको ३ पटकसम्म
फलोअप: १ हप्तामा नजिकको स्वास्थ्य चौकीमा।

Bharatpur Hospital - discharge summary (draft)
Admitted with pneumonia. Improved after 5 days of treatment and discharged.
Medicines:
• Amoxicillin 500 mg - 1 tablet three times a day for 5 days
• Paracetamol 500 mg - 1 tablet when feverish, up to three times a day
Follow-up: at the nearest health post within 1 week.''';

  // -------------------------------------------------------------------------
  // Maternal
  // -------------------------------------------------------------------------

  Map<String, dynamic> _registerPregnancy(
    String patientId,
    Map<String, dynamic> body,
  ) {
    final patient = _require(_patients, patientId);
    if (patient['sex'] != 'female') {
      throw const AppError(
        code: AppError.ruleViolation,
        message: 'Pregnancy can only be registered for a female patient',
        httpStatus: 422,
      );
    }

    final id = '${body['id'] ?? newId()}';
    final lmp = body['lmp'] as String?;
    final edd = body['edd'] as String? ??
        (lmp == null
            ? null
            : DateTime.parse(lmp)
                .add(const Duration(days: 280))
                .toIso8601String()
                .substring(0, 10));

    final pregnancy = _pregnancies[id] = {
      'id': id,
      'patientId': patientId,
      'lmp': lmp,
      'edd': edd,
      'gravida': body['gravida'] ?? 1,
      'para': body['para'] ?? 0,
      'riskFactors': body['riskFactors'] ?? <String>[],
      'riskLevel':
          ((body['riskFactors'] as List?) ?? const []).isEmpty ? 'normal' : 'high',
      'status': 'active',
      'birthPlan': body['birthPlan'],
      'registeredByUserId': _user['id'],
      'version': 1,
      'updatedAt': _touch(),
      'deleted': false,
    };

    // The same eight-contact schedule and the same deterministic ids the app
    // derives locally, so the two sets converge instead of duplicating.
    // The schedule from spec A.5 / assets/rules.json — not an invented one.
    final weeks = rules?.ancSchedule.map((e) => e.weekTarget).toList() ??
        ancScheduleWeeks;
    final contacts = <Map<String, dynamic>>[];
    for (var i = 0; i < weeks.length; i++) {
      final contactNo = i + 1;
      final contactId = ancContactId(id, contactNo);
      contacts.add(
        _ancContacts[contactId] = {
          'id': contactId,
          'pregnancyId': id,
          'contactNo': contactNo,
          'weekTarget': weeks[i],
          // A.2: AncContact.dueAt is a calendar date, not a timestamp.
          'dueAt': lmp == null
              ? _now.substring(0, 10)
              : DateTime.parse(lmp)
                  .add(Duration(days: weeks[i] * 7))
                  .toIso8601String()
                  .substring(0, 10),
          'doneAt': null,
          'providerUserId': null,
          'findings': null,
          'dangerSigns': <String>[],
          'triageLevel': null,
          'triageReasons': <String>[],
          'referral': null,
          'version': 1,
          'updatedAt': _touch(),
          'deleted': false,
        },
      );
    }

    return {'pregnancy': pregnancy, 'ancContacts': contacts};
  }

  Map<String, dynamic> _pregnancyBundle(String id) {
    final pregnancy = _require(_pregnancies, id);
    return {
      'pregnancy': pregnancy,
      'ancContacts': _ancContacts.values
          .where((c) => c['pregnancyId'] == id)
          .toList()
        ..sort((a, b) => (a['contactNo'] as int).compareTo(b['contactNo'] as int)),
      'delivery': _deliveries.values.cast<Map<String, dynamic>?>().firstWhere(
            (d) => d!['pregnancyId'] == id,
            orElse: () => null,
          ),
      'reminders':
          _reminders.values.where((r) => r['pregnancyId'] == id).toList(),
    };
  }

  Map<String, dynamic> _updatePregnancy(String id, Map<String, dynamic> body) {
    final current = _require(_pregnancies, id);
    final changes = {...body}..remove('version');

    return _pregnancies[id] = {
      ...current,
      ...changes,
      'id': id,
      'version': (current['version'] as int) + 1,
      'updatedAt': _touch(),
    };
  }

  Map<String, dynamic> _recordContact(
    String pregnancyId,
    int contactNo,
    Map<String, dynamic> body,
  ) {
    if (contactNo < 1 || contactNo > 8) {
      throw const AppError(
        code: AppError.ruleViolation,
        message: 'contactNo must be between 1 and 8',
        httpStatus: 422,
      );
    }

    final id = ancContactId(pregnancyId, contactNo);
    final current = _require(_ancContacts, id);
    final findings = (body['findings'] as Map?)?.cast<String, dynamic>();
    final dangerSigns =
        ((body['dangerSigns'] as List?) ?? const []).map((e) => '$e').toList();

    final (level, reasons) = _triage(pregnancyId, findings, dangerSigns);

    final contact = _ancContacts[id] = {
      ...current,
      'doneAt': body['doneAt'] ?? _now,
      'providerUserId': _user['id'],
      'findings': findings,
      'dangerSigns': dangerSigns,
      'triageLevel': level,
      'triageReasons': reasons,
      'referral': body['referral'],
      'version': (current['version'] as int) + 1,
      'updatedAt': _touch(),
    };

    final pregnancy = _pregnancies[pregnancyId];
    if (pregnancy != null) _audit('${pregnancy['patientId']}', 'contact_recorded');

    return {
      'ancContact': contact,
      'nearestReferral': reasons.isEmpty ? null : _facilities.first,
    };
  }

  /// Runs the real rule engine when one was injected, and a crude stand-in
  /// otherwise. Either way the *shape* is what Part A specifies: a level plus
  /// human-readable English reasons.
  (String, List<String>) _triage(
    String pregnancyId,
    Map<String, dynamic>? findings,
    List<String> dangerSigns,
  ) {
    final rules = this.rules;
    if (rules != null) {
      final row = _pregnancies[pregnancyId];
      final result = domain.triage(
        findings: findings == null ? null : Findings.fromJson(findings),
        dangerSigns: dangerSigns,
        pregnancy: row == null
            ? const Pregnancy(id: '', patientId: '', edd: '')
            : Pregnancy.fromJson(row),
        gestationalAgeDays: 210,
        rules: rules,
      );
      return (result.level.wire, result.reasonsEn);
    }

    final reasons = <String>[
      if (dangerSigns.isNotEmpty) 'danger_sign',
      if ((findings?['bpSys'] as num? ?? 0) >= 140 ||
          (findings?['bpDia'] as num? ?? 0) >= 90)
        'bp_high',
      if ((findings?['hbGdl'] as num? ?? 99) < 7) 'severe_anaemia',
    ];
    return (reasons.isEmpty ? 'green' : 'red', reasons);
  }

  Map<String, dynamic> _recordDelivery(
    String pregnancyId,
    Map<String, dynamic> body,
  ) {
    final pregnancy = _require(_pregnancies, pregnancyId);
    if (pregnancy['status'] != 'active') {
      throw const AppError(
        code: AppError.ruleViolation,
        message: 'This pregnancy is already closed',
        httpStatus: 422,
      );
    }

    final id = '${body['id'] ?? newId()}';
    final delivery = _deliveries[id] = {
      'id': id,
      'pregnancyId': pregnancyId,
      'deliveredAt': body['deliveredAt'] ?? _now,
      'place': body['place'],
      'mode': body['mode'],
      'outcome': body['outcome'],
      'babyWeightKg': body['babyWeightKg'],
      'babySex': body['babySex'],
      'complications': body['complications'] ?? <String>[],
      'version': 1,
      'updatedAt': _touch(),
      'deleted': false,
    };

    final closed = _pregnancies[pregnancyId] = {
      ...pregnancy,
      'status': 'delivered',
      'version': (pregnancy['version'] as int) + 1,
      'updatedAt': _touch(),
    };

    return {'delivery': delivery, 'pregnancy': closed};
  }

  // -------------------------------------------------------------------------
  // Sync
  // -------------------------------------------------------------------------

  Map<String, dynamic> _push(Map<String, dynamic> body) {
    final changes = (body['changes'] as List?) ?? const [];
    final results = <Map<String, dynamic>>[];

    for (final raw in changes) {
      final change = (raw as Map).cast<String, dynamic>();
      final opId = '${change['opId']}';
      final table = '${change['table']}';
      final rowId = '${change['rowId']}';
      final baseVersion = change['baseVersion'] as int? ?? 0;
      final payload = (change['payload'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{};

      final store = _tableFor(table);
      if (store == null) {
        results.add({
          'opId': opId,
          'status': 'rejected',
          'error': {
            'code': AppError.validationError,
            'message': 'Unknown table $table',
          },
        });
        continue;
      }

      if (!_appliedOpIds.add(opId)) {
        results.add({
          'opId': opId,
          'status': 'duplicate',
          'row': store[rowId],
        });
        continue;
      }

      final current = store[rowId];
      final currentVersion = (current?['version'] as int?) ?? 0;
      if (current != null && currentVersion != baseVersion) {
        results.add({'opId': opId, 'status': 'conflict', 'current': current});
        continue;
      }

      final row = store[rowId] = {
        ...?current,
        ...payload,
        'id': rowId,
        'version': currentVersion + 1,
        'updatedAt': _touch(),
        'deleted': payload['deleted'] ?? current?['deleted'] ?? false,
      };
      results.add({'opId': opId, 'status': 'applied', 'row': row});
    }

    return {'results': results, 'serverTime': _now};
  }

  /// Spec A.4 `GET /sync/pull`: "All rows changed since cursor for the patients
  /// this user may see (owned, or active grant)", ordered by `updatedAt` asc.
  ///
  /// This is what makes a fresh install usable. Without it a device that signs
  /// in to an existing account sees the patient list (from `GET /patients`) and
  /// nothing else — no pregnancy, no visits, no documents. Found on the phone.
  Map<String, dynamic> _pull(String since) {
    final visible = _visiblePatientIds();
    final pregnancyIds = _pregnancies.values
        .where((p) => visible.contains(p['patientId']))
        .map((p) => '${p['id']}')
        .toSet();

    bool changed(Map<String, dynamic> row) {
      final updatedAt = '${row['updatedAt'] ?? ''}';
      // A lexical compare is right here: both sides are ISO-8601 UTC.
      return since.isEmpty || updatedAt.compareTo(since) > 0;
    }

    final changes = <Map<String, dynamic>>[
      for (final row in _patients.values)
        if (visible.contains(row['id']) && changed(row))
          {'table': 'patients', 'row': row},
      for (final row in _pregnancies.values)
        if (visible.contains(row['patientId']) && changed(row))
          {'table': 'pregnancies', 'row': row},
      for (final row in _ancContacts.values)
        if (pregnancyIds.contains(row['pregnancyId']) && changed(row))
          {'table': 'anc_contacts', 'row': row},
      for (final row in _visits.values)
        if (visible.contains(row['patientId']) && changed(row))
          {'table': 'visits', 'row': row},
      for (final row in _documents.values)
        if (visible.contains(row['patientId']) && changed(row))
          {'table': 'documents', 'row': row},
      for (final row in _deliveries.values)
        if (pregnancyIds.contains(row['pregnancyId']) && changed(row))
          {'table': 'deliveries', 'row': row},
      for (final row in _immunisations.values)
        if (visible.contains(row['patientId']) && changed(row))
          {'table': 'immunisations', 'row': row},
      for (final row in _growth.values)
        if (visible.contains(row['patientId']) && changed(row))
          {'table': 'growth_measurements', 'row': row},
    ]..sort((a, b) {
        final left = '${(a['row'] as Map)['updatedAt'] ?? ''}';
        final right = '${(b['row'] as Map)['updatedAt'] ?? ''}';
        return left.compareTo(right);
      });

    // A.4 pages at 200. Paging is exercised rather than assumed, so the engine's
    // hasMore loop is covered by the mock as well as by its own tests.
    const pageSize = 200;
    final page = changes.take(pageSize).toList();
    final cursor = page.isEmpty
        ? (since.isEmpty ? _now : since)
        : '${(page.last['row'] as Map)['updatedAt']}';

    return {
      'changes': page,
      'cursor': cursor,
      'hasMore': changes.length > pageSize,
    };
  }

  /// Patients the signed-in user may see: the ones they own, plus any they hold
  /// an unexpired grant for (A.4).
  Set<String> _visiblePatientIds() {
    final owned = _patients.values
        .where((p) => p['ownerUserId'] == _user['id'])
        .map((p) => '${p['id']}')
        .toSet();

    for (final grant in _grants.values) {
      if (grant['redeemedByUserId'] != _user['id']) continue;
      if (grant['revokedAt'] != null) continue;
      final until = DateTime.tryParse('${grant['accessUntil']}');
      if (until != null && until.isAfter(_clock().toUtc())) {
        owned.add('${grant['patientId']}');
      }
    }
    return owned;
  }

  Map<String, Map<String, dynamic>>? _tableFor(String table) =>
      switch (table) {
        'patients' => _patients,
        'visits' => _visits,
        'documents' => _documents,
        'pregnancies' => _pregnancies,
        'anc_contacts' => _ancContacts,
        'deliveries' => _deliveries,
        'immunisations' => _immunisations,
        'growth_measurements' => _growth,
        _ => null,
      };

  List<Map<String, dynamic>> _nearby(Map<String, dynamic> query) {
    final onlyBirthing = query['birthing'] == true || query['birthing'] == 'true';
    final limit = query['limit'] is int
        ? query['limit'] as int
        : int.tryParse('${query['limit']}') ?? 5;

    return _facilities
        .where((f) => !onlyBirthing || f['hasBirthingCentre'] == true)
        .take(limit)
        .map((f) => {...f, 'distanceKm': 2.4})
        .toList();
  }

  void _audit(String patientId, String action) {
    final id = newId();
    _auditEntries[id] = {
      'id': id,
      'patientId': patientId,
      'actorUserId': _user['id'],
      'actorName': _user['name'],
      'actorFacilityName': _user['facilityName'],
      'action': action,
      'at': _now,
    };
  }

  // ---------------------------------------------------------------------------
  // Seed data (spec A.2 examples)
  // ---------------------------------------------------------------------------

  static const String configVersion = '2026-09-18.1';

  /// Spec A.5. Kept here so the mock and `assets/rules.json` cannot drift.
  static const List<int> ancScheduleWeeks = [12, 20, 26, 30, 34, 36, 38, 40];

  /// A trimmed RULES object. The app ships the full copy in `assets/rules.json`
  /// and only overrides it when `/rules` reports a newer version, so the mock
  /// deliberately reports the same version and changes nothing.
  static const Map<String, dynamic> rulesDocument = {
    'version': configVersion,
    'ancSchedule': ancScheduleWeeks,
  };

  static const String sitaId = 'p_a1a1a1a1-0000-4000-8000-000000000001';
  static const String ramId = 'p_a1a1a1a1-0000-4000-8000-000000000002';
  static const String pregnancyId = 'pg_b2b2b2b2-0000-4000-8000-000000000001';
  static const String ramVisitId = 'v_c3c3c3c3-0000-4000-8000-000000000001';
  static const String ramDocumentId = 'd_e5e5e5e5-0000-4000-8000-000000000001';

  /// Tier 3 — the under-five whose immunisation card and growth chart the
  /// child-health module is demonstrated on.
  static const String aaravId = 'p_a1a1a1a1-0000-4000-8000-000000000006';

  /// The paper the AI draft summary is demonstrated on (Tier 2, S10).
  static const String ramDischargeId = 'd_e5e5e5e5-0000-4000-8000-000000000002';

  /// Three women the health post is already following (Tier 2, the S19
  /// dashboard). They belong to other households, and this account reaches
  /// them through grants it has already redeemed — which is exactly how a real
  /// health worker's phone comes to hold them.
  static const List<String> dashboardPatientIds = [
    'p_a1a1a1a1-0000-4000-8000-000000000003',
    'p_a1a1a1a1-0000-4000-8000-000000000004',
    'p_a1a1a1a1-0000-4000-8000-000000000005',
  ];

  /// Tier 3: Aarav, three years old, so the child-health module has a real
  /// card to show — six doses given, one overdue, three weights.
  ///
  /// Owned by the demo account, so he appears in My family beside Sita and Ram
  /// rather than needing a grant. A real backend seeds him the same way; see
  /// `docs/CONTRACT_ADDENDUM.md`.
  void _seedAarav() {
    final now = _clock().toUtc();
    // Three years and two months old: past every infant dose, and two months
    // past the 15-month MR booster he has not had.
    final dob = DateTime.utc(now.year - 3, now.month - 2 <= 0 ? 12 : now.month - 2, 14);

    _patients[aaravId] = {
      'id': aaravId,
      'ownerUserId': 'u_0001',
      'name': 'Aarav Chaudhary',
      'sex': 'male',
      'dob': dob.toIso8601String().substring(0, 10),
      'bloodGroup': 'B+',
      'ward': 5,
      'municipality': 'Ghorahi',
      'allergies': <String>[],
      'chronicConditions': <String>[],
      'emergencyContactPhone': '+9779801000009',
      'version': 1,
      'updatedAt': _touch(),
      'deleted': false,
    };

    // The schedule the app would generate from the same date of birth, with the
    // same deterministic ids — this is exactly what the backend must derive.
    for (final (code, doseNo, weeks, months) in _epiRows) {
      final due = months == null
          ? dob.add(Duration(days: weeks! * 7))
          : DateTime.utc(dob.year + (dob.month - 1 + months) ~/ 12,
              (dob.month - 1 + months) % 12 + 1, dob.day);

      // Everything up to and including the 12-month JE was given on time; the
      // 15-month MR booster and TCV were not, which is the row the card is
      // meant to make impossible to miss.
      final given = !((code == 'MR' && doseNo == 2) || code == 'TCV');

      final id = immunisationId(aaravId, code, doseNo);
      _immunisations[id] = {
        'id': id,
        'patientId': aaravId,
        'vaccineCode': code,
        'doseNo': doseNo,
        'dueAt': due.toIso8601String().substring(0, 10),
        'givenAt': given
            ? due.add(const Duration(days: 2)).toIso8601String()
            : null,
        'givenByUserId': given ? 'u_0002' : null,
        'batchNo': given ? 'B${due.year}-$doseNo' : null,
        'version': 1,
        'updatedAt': _touch(),
        'deleted': false,
      };
    }

    for (final (monthsAgo, kg) in [(18, 10.4), (9, 11.8), (2, 13.1)]) {
      final at = now.subtract(Duration(days: monthsAgo * 30));
      final id = 'gm_aarav_$monthsAgo';
      _growth[id] = {
        'id': id,
        'patientId': aaravId,
        'measuredAt': at.toIso8601String(),
        'weightKg': kg,
        'heightCm': null,
        'muacCm': null,
        'version': 1,
        'updatedAt': _touch(),
        'deleted': false,
      };
    }
  }

  /// The EPI rows the mock seeds from, mirroring `assets/epi_schedule.json`.
  ///
  /// Duplicated here rather than read from the asset because the mock has no
  /// asset bundle in a unit test, and because a mock that quietly diverged from
  /// the shipped schedule is exactly the drift these two copies make visible.
  static const List<(String, int, int?, int?)> _epiRows = [
    ('BCG', 1, 0, null),
    ('OPV', 1, 6, null),
    ('OPV', 2, 10, null),
    ('OPV', 3, 14, null),
    ('PENTA', 1, 6, null),
    ('PENTA', 2, 10, null),
    ('PENTA', 3, 14, null),
    ('PCV', 1, 6, null),
    ('PCV', 2, 10, null),
    ('PCV', 3, null, 9),
    ('ROTA', 1, 6, null),
    ('ROTA', 2, 10, null),
    // 14 weeks and 9 months, not 6 and 14 weeks — corrected 2026-09-19 along
    // with the asset. `epiScheduleMatchesAsset` in the tests exists so these
    // two copies cannot drift apart again.
    ('FIPV', 1, 14, null),
    ('FIPV', 2, null, 9),
    ('MR', 1, null, 9),
    ('MR', 2, null, 15),
    ('JE', 1, null, 12),
    ('TCV', 1, null, 15),
  ];

  /// Tier 2: three more women so the S19 dashboard has something to count.
  ///
  /// Mock-only. A real backend has no equivalent and needs none — the tiles are
  /// computed from whatever the device has cached, so against a live server
  /// they fill up as the health post scans people.
  void _seedDashboardPatients() {
    const names = ['Gita Tharu', 'Maya B.K.', 'Parbati Chaudhary'];
    // One in each trimester, so every tile on the dashboard has somebody in it
    // and none of them reads as a bug.
    const weeks = [10, 37, 22];

    for (var i = 0; i < dashboardPatientIds.length; i++) {
      final patientId = dashboardPatientIds[i];

      _patients[patientId] = {
        'id': patientId,
        'ownerUserId': 'u_0002',
        'name': names[i],
        'sex': 'female',
        'dob': '199${5 + i}-06-1${i + 1}',
        'bloodGroup': i == 1 ? 'A+' : 'O+',
        'ward': 5 + i,
        'municipality': 'Ghorahi',
        'allergies': <String>[],
        'chronicConditions': <String>[],
        'emergencyContactPhone': null,
        'version': 1,
        // `_touch()`, not a date in the past: `updatedAt` is the pull cursor,
        // and a phone that has synced before is already past any past
        // timestamp — a row seeded backwards would never arrive.
        'updatedAt': _touch(),
        'deleted': false,
      };

      // An already-redeemed grant is what makes the record visible to this
      // account, and what `/sync/pull` keys off.
      final grantId = 'g_dashboard_$i';
      _grants[grantId] = {
        'id': grantId,
        'patientId': patientId,
        'scope': 'append',
        'token': 'mock_grant_$grantId',
        'expiresAt':
            _clock().toUtc().add(const Duration(days: 365)).toIso8601String(),
        'redeemedByUserId': 'u_0001',
        'redeemedAt': _now,
        'revokedAt': null,
        'accessUntil':
            _clock().toUtc().add(const Duration(days: 30)).toIso8601String(),
        'longLived': false,
      };

      final lmp = _clock().toUtc().subtract(Duration(days: weeks[i] * 7));
      final pregnancy = _registerPregnancy(patientId, {
        'id': 'pg_dashboard_$i',
        'lmp': lmp.toIso8601String().substring(0, 10),
      });

      final pid = '${pregnancy['pregnancy']!['id']}';

      // Maya is at 37 weeks and has been followed all along. Without this she
      // arrives with six contacts nobody ever did, and "contacts overdue"
      // reads 8 — a number a health post would assume was broken rather than
      // act on.
      if (i == 1) {
        for (final (contactNo, weeksAgo) in [
          (1, 25),
          (2, 17),
          (3, 11),
          (4, 7),
          (5, 3),
          (6, 1),
        ]) {
          _completeContact(
            pid,
            contactNo,
            weeksAgo: weeksAgo,
            findings: {
              'weightKg': 50.0 + contactNo,
              'bpSys': 112,
              'bpDia': 74,
              'ifaGiven': true,
            },
          );
        }
      }

      // The third woman has missed her second contact: the overdue tile needs
      // somebody in it, and an empty "contacts overdue" tile is the one number
      // a health post would never believe.
      if (i == 2) {
        final contactId = ancContactId(pid, 2);
        final current = _ancContacts[contactId];
        if (current != null) {
          _ancContacts[contactId] = {
            ...current,
            'dueAt': _clock()
                .toUtc()
                .subtract(const Duration(days: 21))
                .toIso8601String()
                .substring(0, 10),
            'updatedAt': _touch(),
          };
        }

        // ...and her first contact was amber, so the triage tile is not empty
        // either.
        final firstId = ancContactId(pid, 1);
        final first = _ancContacts[firstId];
        if (first != null) {
          final at = _clock().toUtc().subtract(const Duration(days: 3));
          _ancContacts[firstId] = {
            ...first,
            'doneAt': at.toIso8601String(),
            'providerUserId': 'u_0002',
            'findings': {'bpSys': 145, 'bpDia': 92, 'weightKg': 49.0},
            'dangerSigns': <String>[],
            'triageLevel': 'amber',
            'triageReasons': <String>['bp_high'],
            'version': 2,
            'updatedAt': _touch(),
          };
        }
      }
    }
  }

  void _completeSeededContact(
    int contactNo, {
    required int weeksAgo,
    required Map<String, dynamic> findings,
  }) =>
      _completeContact(
        pregnancyId,
        contactNo,
        weeksAgo: weeksAgo,
        findings: findings,
      );

  /// Marks one seeded ANC contact as done, with findings that triage green
  /// unless they say otherwise — the red one is for the demo to produce live
  /// on S13.
  void _completeContact(
    String forPregnancyId,
    int contactNo, {
    required int weeksAgo,
    required Map<String, dynamic> findings,
  }) {
    final id = ancContactId(forPregnancyId, contactNo);
    final current = _ancContacts[id];
    if (current == null) return;

    final at = _clock().toUtc().subtract(Duration(days: weeksAgo * 7));
    final (level, reasons) = _triage(forPregnancyId, findings, const []);

    _ancContacts[id] = {
      ...current,
      'doneAt': at.toIso8601String(),
      'providerUserId': 'u_0002',
      'findings': findings,
      'dangerSigns': <String>[],
      'triageLevel': level,
      'triageReasons': reasons,
      'version': 2,
      'updatedAt': at.toIso8601String(),
    };
  }

  void _seed() {
    _user = {
      'id': 'u_0001',
      'phone': '+9779801000001',
      'role': 'patient',
      'name': 'Sita Chaudhary',
      'facilityId': null,
      'facilityName': null,
      'createdAt': _now,
    };

    _facilities.addAll([
      {
        'id': 'f_0001',
        'name': 'Ghorahi Health Post',
        'type': 'health_post',
        'hasBirthingCentre': false,
        'phone': '+9779857000001',
        'lat': 28.03,
        'lng': 82.49,
        'municipality': 'Ghorahi',
      },
      {
        'id': 'f_0002',
        'name': 'Rapti Provincial Hospital',
        'type': 'hospital',
        'hasBirthingCentre': true,
        'phone': '+9779857000002',
        'lat': 28.05,
        'lng': 82.50,
        'municipality': 'Ghorahi',
      },
    ]);

    _codelists.addAll([
      {
        'kind': 'complaint',
        'code': 'FEVER',
        'labelEn': 'Fever',
        'labelNp': 'ज्वरो',
      },
      {
        'kind': 'diagnosis',
        'code': 'E11',
        'labelEn': 'Type 2 diabetes',
        'labelNp': 'मधुमेह',
      },
      {
        'kind': 'drug',
        'code': 'METFORMIN_500',
        'labelEn': 'Metformin 500 mg',
        'labelNp': 'मेटफर्मिन ५०० मि.ग्रा.',
      },
      {
        'kind': 'dangerSign',
        'code': 'SEVERE_HEADACHE_BLURRED_VISION',
        'labelEn': 'Severe headache or blurred vision',
        'labelNp': 'कडा टाउको दुख्ने वा धमिलो देखिने',
      },
    ]);

    // Sita — week-30 pregnancy.
    _patients[sitaId] = {
      'id': sitaId,
      'ownerUserId': 'u_0001',
      'name': 'Sita Chaudhary',
      'sex': 'female',
      'dob': '2002-04-11',
      'bloodGroup': 'B+',
      'ward': 5,
      'municipality': 'Ghorahi',
      'allergies': <String>['sulpha'],
      'chronicConditions': <String>[],
      'emergencyContactPhone': '+9779801000009',
      'version': 1,
      'updatedAt': _touch(),
      'deleted': false,
    };

    final lmp = _clock().toUtc().subtract(const Duration(days: 30 * 7));
    _registerPregnancy(sitaId, {
      'id': pregnancyId,
      'lmp': lmp.toIso8601String().substring(0, 10),
    });

    // Contacts 1-3 already happened: at week 30 a real record would not be
    // blank, and the demo needs a dashboard with history behind it rather than
    // eight empty rows.
    _completeSeededContact(1, weeksAgo: 18, findings: {
      'weightKg': 52.0,
      'bpSys': 110,
      'bpDia': 70,
      'hbGdl': 11.8,
      'urineProtein': 'neg',
      'ifaGiven': true,
      'tdDoseGiven': true,
    });
    _completeSeededContact(2, weeksAgo: 10, findings: {
      'weightKg': 55.5,
      'bpSys': 118,
      'bpDia': 76,
      'fundalHeightCm': 20.0,
      'ifaGiven': true,
      'calciumGiven': true,
      'dewormingGiven': true,
    });
    _completeSeededContact(3, weeksAgo: 4, findings: {
      'weightKg': 58.0,
      'bpSys': 124,
      'bpDia': 80,
      'fundalHeightCm': 26.0,
      'fhrBpm': 142,
      'ifaGiven': true,
      'calciumGiven': true,
      'fetalMovement': 'normal',
    });

    // Ram — diabetes and one visit.
    _patients[ramId] = {
      'id': ramId,
      'ownerUserId': 'u_0001',
      'name': 'Ram Bahadur Chaudhary',
      'sex': 'male',
      'dob': '1968-01-15',
      'bloodGroup': 'O+',
      'ward': 5,
      'municipality': 'Ghorahi',
      'allergies': <String>['penicillin'],
      'chronicConditions': <String>['E11'],
      'emergencyContactPhone': '+9779801000009',
      'version': 1,
      'updatedAt': _touch(),
      'deleted': false,
    };

    _addVisit(ramId, {
      'id': ramVisitId,
      'visitAt': _clock()
          .toUtc()
          .subtract(const Duration(days: 25))
          .toIso8601String(),
      'chiefComplaintCode': 'FOLLOW_UP',
      'vitals': {'bpSys': 138, 'bpDia': 86, 'weightKg': 71.5},
      'diagnosisCodes': ['E11'],
      'notes': 'Fasting sugar 168 mg/dl',
      'advice': 'Diet, walk 30 min daily',
      'prescriptions': [
        {
          'id': 'rx_0001',
          'drugCode': 'METFORMIN_500',
          'drugName': 'Metformin 500 mg',
          'dose': '1 tab',
          'frequency': 'BD',
          'durationDays': 30,
          'instructionsNp': 'खाना पछि',
        },
      ],
    });

    // A paper record for Ram, so the timeline shows more than visits and the
    // documents grid is not empty on a fresh install.
    _documents[ramDocumentId] = {
      'id': ramDocumentId,
      'patientId': ramId,
      'uploadedByUserId': 'u_0002',
      'type': 'lab',
      'title': 'Fasting blood sugar',
      'takenAt': _clock()
          .toUtc()
          .subtract(const Duration(days: 40))
          .toIso8601String()
          .substring(0, 10),
      'status': 'uploaded',
      'downloadUrl': 'https://mock.storage.invalid/get/$ramDocumentId',
      'aiSummary': null,
      'aiSummaryStatus': 'none',
      'version': 1,
      'updatedAt': _clock()
          .toUtc()
          .subtract(const Duration(days: 40))
          .toIso8601String(),
      'deleted': false,
    };

    // A discharge sheet for Ram, which is what the Tier-2 "Draft summary (AI)"
    // demo is run against: a dense two-page hospital printout is exactly the
    // document somebody would want read back to them in Nepali.
    _documents[ramDischargeId] = {
      'id': ramDischargeId,
      'patientId': ramId,
      'uploadedByUserId': 'u_0002',
      'type': 'discharge',
      'title': 'Bharatpur Hospital discharge sheet',
      'takenAt': _clock()
          .toUtc()
          .subtract(const Duration(days: 12))
          .toIso8601String()
          .substring(0, 10),
      'status': 'uploaded',
      'downloadUrl': 'https://mock.storage.invalid/get/$ramDischargeId',
      'aiSummary': null,
      'aiSummaryStatus': 'none',
      'version': 1,
      // `takenAt` is twelve days ago because that is when the paper was
      // printed, but `updatedAt` is now: it is the pull cursor, and a phone
      // that has synced before is already past any timestamp in the past. A
      // row seeded into the past would never reach an install that is not
      // brand new — which is every phone the demo will actually run on.
      'updatedAt': _touch(),
      'deleted': false,
    };

    _seedDashboardPatients();
    _seedAarav();

    // Two seeded reminders, which are also what `/demo/sms` shows.
    for (var i = 0; i < 2; i++) {
      final id = 'rem_000${i + 1}';
      _reminders[id] = {
        'id': id,
        'patientId': sitaId,
        'pregnancyId': pregnancyId,
        'kind': 'anc_due',
        'dueAt': _clock().toUtc().add(Duration(days: 7 * (i + 1)))
            .toIso8601String(),
        'channel': 'sms',
        'recipientPhone': '+9779801000009',
        'recipientRole': 'family',
        'messageNp': 'सीता चौधरीको गर्भ जाँच नजिकिँदै छ।',
        'messageEn': "Sita Chaudhary's antenatal check-up is due soon.",
        'status': 'pending',
        'sentAt': null,
      };
      _demoSms.add({
        'to': '+9779801000009',
        'text': 'सीता चौधरीको गर्भ जाँच नजिकिँदै छ।',
        'sentAt': _now,
      });
    }
  }
}
