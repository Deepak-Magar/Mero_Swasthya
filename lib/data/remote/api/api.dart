import '../../../core/net/api_transport.dart';
import 'auth_api.dart';
import 'documents_api.dart';
import 'grants_api.dart';
import 'patients_api.dart';
import 'pregnancies_api.dart';
import 'reference_api.dart';
import 'sync_api.dart';

export 'auth_api.dart';
export 'documents_api.dart';
export 'grants_api.dart';
export 'json.dart';
export 'patients_api.dart';
export 'pregnancies_api.dart';
export 'reference_api.dart';
export 'sync_api.dart';

/// One handle for every endpoint group, so a repository takes `Api` rather than
/// six constructor arguments.
///
/// Swapping the whole networking layer for the in-memory mock (spec §15) is
/// `Api(MockApi())` instead of `Api(ApiClient(...))` — nothing else changes.
class Api {
  Api(ApiTransport transport)
      : auth = AuthApi(transport),
        patients = PatientsApi(transport),
        grants = GrantsApi(transport),
        documents = DocumentsApi(transport),
        pregnancies = PregnanciesApi(transport),
        reference = ReferenceApi(transport),
        sync = SyncApi(transport);

  final AuthApi auth;
  final PatientsApi patients;
  final GrantsApi grants;
  final DocumentsApi documents;
  final PregnanciesApi pregnancies;
  final ReferenceApi reference;
  final SyncApi sync;
}
