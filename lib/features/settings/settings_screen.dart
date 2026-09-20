import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/l10n/gen/app_localizations.dart';
import '../../core/l10n/locale_controller.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/soft_card.dart';
import '../../shared/widgets/brand_logo.dart';
import '../auth/auth_controller.dart';

/// S23 — Settings: language, server URL, versions, refresh, logout.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _baseUrl =
      TextEditingController(text: ref.read(appConfigProvider).baseUrl);
  bool? _connectionOk;
  bool _testing = false;

  @override
  void dispose() {
    _baseUrl.dispose();
    super.dispose();
  }

  /// Persist as the address is typed.
  ///
  /// It used to be written only by "Test connection", so an address typed and
  /// then left — by tapping back, or by pressing the button that needs the
  /// address to already be right — was silently thrown away on the next
  /// launch. A preference write per keystroke is cheap; losing the server the
  /// phone is meant to talk to is not.
  void _rememberBaseUrl(String value) {
    unawaited(ref.read(appConfigProvider).setBaseUrl(value));
  }

  /// Spec S23: "Test connection → GET /config". Saving first is deliberate —
  /// the client reads the URL per request, so the test exercises the address
  /// that will actually be used.
  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _connectionOk = null;
    });

    await ref.read(appConfigProvider).setBaseUrl(_baseUrl.text);
    try {
      await ref.read(apiProvider).reference.config();
      if (mounted) setState(() => _connectionOk = true);
    } on Object {
      if (mounted) setState(() => _connectionOk = false);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  /// Tier 2 pre-demo check.
  ///
  /// The only honest way to find out whether *this* phone will show a medicine
  /// reminder is to make it show one, and finding out in the room is too late.
  /// Thirty seconds is long enough to put the phone down and short enough to
  /// wait for.
  Future<void> _testReminder() async {
    final l10n = L.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final notifications = ref.read(medicineNotificationsProvider);

    final granted = await notifications.requestPermission();
    if (!mounted) return;
    if (!granted) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.medicineRemindersRefused)),
      );
      return;
    }

    final ok = await notifications.scheduleSmokeTest(
      patientId: '',
      drugName: 'Metformin 500 mg',
      instructionsNp: 'खाना पछि',
    );
    if (!mounted) return;

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok ? l10n.settingsTestReminderQueued : l10n.settingsTestReminderFailed,
        ),
      ),
    );
  }

  Future<void> _refreshLists() async {
    final repo = ref.read(referenceRepoProvider);
    // An empty version is never equal to the server's, so this always refetches.
    final refreshed = await repo.refreshCodelistsIfStale('');
    if (refreshed) ref.invalidate(configFlagsProvider);
    if (!mounted) return;

    final l10n = L.of(context);
    final String rulesVersion =
        ref.read(rulesProvider).valueOrNull?.version ?? l10n.commonUnknown;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          refreshed
              ? l10n.settingsConnectionOk(rulesVersion)
              : l10n.settingsConnectionFailed(l10n.commonNoConnection),
        ),
      ),
    );
  }

  Future<void> _logout() async {
    final l10n = L.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.settingsLogoutConfirmTitle),
        content: Text(l10n.settingsLogoutConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.triageRed,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.settingsLogout),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false)) return;

    await ref.read(authProvider.notifier).signOut();
    if (mounted) context.go('/auth/phone');
  }

  /// Persists the choice and rebuilds the transport.
  ///
  /// Everything downstream — the API, the repositories, the sync engine — hangs
  /// off `apiTransportProvider`, so flipping the flag is enough; nothing has to
  /// be torn down by hand.
  Future<void> _switchTransport(bool useMock) async {
    await ref.read(appConfigProvider).setUseMockServer(useMock);
    if (!mounted) return;

    ref.read(useMockServerProvider.notifier).state = useMock;
    // The flags are cached per transport, and a failed fetch caches an empty
    // set. Without this the versions card kept showing whatever the *previous*
    // transport answered — blank, after a reach for a server that is not
    // there — for the rest of the session.
    ref.invalidate(configFlagsProvider);
    setState(() => _connectionOk = null);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);
    final locale = Localizations.localeOf(context);
    final useMock = ref.watch(useMockServerProvider);
    final flags = ref.watch(configFlagsProvider).valueOrNull;
    final rules = ref.watch(rulesProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          AppSpacing.md,
          AppSpacing.gutter,
          40,
        ),
        children: [
          FormSection(
            title: l10n.settingsLanguage,
            children: [
              SegmentedControl<String>(
                values: const ['ne', 'en'],
                selected: locale.languageCode,
                labelOf: (code) => code == 'ne'
                    ? l10n.settingsLanguageNepali
                    : l10n.settingsLanguageEnglish,
                onChanged: (code) => ref
                    .read(localeControllerProvider.notifier)
                    .setLocale(Locale(code)),
              ),
            ],
          ),

          FormSection(
            title: l10n.settingsServerUrl,
            children: [
          // Spec Session 3 step 9: one APK, switchable at runtime. The demo
          // runs on the mock; when the backend is up the switch goes off and
          // the same build talks to it, with no rebuild and no reinstall.
          SwitchListTile(
            value: useMock,
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.science_outlined),
            title: Text(
              l10n.settingsMockMode,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            subtitle: Text(
              useMock ? l10n.settingsMockModeOn : l10n.settingsMockModeOff,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            onChanged: _switchTransport,
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _baseUrl,
            keyboardType: TextInputType.url,
            autocorrect: false,
            onChanged: _rememberBaseUrl,
            // The address is meaningless while the mock is serving, so it is
            // visibly inert rather than quietly ignored.
            enabled: !useMock,
            decoration: InputDecoration(
              labelText: l10n.settingsServerUrl,
              suffixIcon: _connectionOk == null
                  ? null
                  : Icon(
                      _connectionOk!
                          ? Icons.check_circle_outline
                          : Icons.error_outline,
                      color: _connectionOk!
                          ? AppColors.successInkOf(context)
                          : AppColors.triageRed,
                    ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: _testing ? null : _testConnection,
            icon: _testing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.network_check, size: 18),
            label: Text(l10n.settingsTestConnection),
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: _testReminder,
            icon: const Icon(Icons.notifications_active_outlined, size: 18),
            label: Text(l10n.settingsTestReminder),
          ),
            ],
          ),

          FormSection(
            title: l10n.settingsRulesVersion,
            children: [
              _VersionRow(
                label: l10n.settingsRulesVersion,
                value: rules?.version ?? l10n.commonUnknown,
              ),
              const SizedBox(height: AppSpacing.sm),
              _VersionRow(
                label: l10n.settingsCodelistVersion,
                // The model defaults this to an empty string, which drew an
                // empty row rather than saying it did not know.
                value: (flags?.codelistVersion.isNotEmpty ?? false)
                    ? flags!.codelistVersion
                    : l10n.commonUnknown,
              ),
              const SizedBox(height: AppSpacing.lg),
              OutlinedButton.icon(
                onPressed: _refreshLists,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(l10n.settingsRefreshLists),
              ),
            ],
          ),

          SectionHeader(l10n.integrationsTitle),
          _IntegrationRow(
            icon: Icons.badge_outlined,
            title: l10n.integrationNidTitle,
            body: l10n.integrationNidBody,
            enabled: flags?.nidEnabled ?? false,
          ),
          _IntegrationRow(
            icon: Icons.insert_chart_outlined,
            title: l10n.integrationHmisTitle,
            body: l10n.integrationHmisBody,
            enabled: flags?.hmisExportEnabled ?? false,
          ),
          _IntegrationRow(
            icon: Icons.verified_user_outlined,
            title: l10n.integrationCouncilTitle,
            body: l10n.integrationCouncilBody,
            enabled: flags?.councilVerifyEnabled ?? false,
          ),
          SizedBox(height: AppSpacing.xl),

          OutlinedButton.icon(
            onPressed: _logout,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.dangerInkOf(context),
              side: BorderSide(
                color: AppColors.triageRed.withValues(alpha: 0.4),
              ),
            ),
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: Text(l10n.settingsLogout),
          ),
          const SizedBox(height: AppSpacing.xl),
          Center(
            child: Column(
              children: [
                const BrandLogo.mark(size: 40),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  l10n.settingsAbout,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A label on the left, a version string on the right.
class _VersionRow extends StatelessWidget {
  const _VersionRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondaryOf(context),
                ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
      ],
    );
  }
}

/// One integration that does not exist yet, described honestly.
///
/// The rule this screen follows: **no mock success states**. A row that showed
/// a green tick for "National ID verified" would be a lie told to the one
/// audience — a ministry evaluator — most likely to check. So the row says what
/// the integration would do, what it needs, and what the app does instead in
/// the meantime, and the button is disabled.
///
/// [enabled] comes from `GET /config`, so the day somebody does have the API
/// access the rows light up without an app change.
class _IntegrationRow extends StatelessWidget {
  const _IntegrationRow({
    required this.icon,
    required this.title,
    required this.body,
    required this.enabled,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);

    return SoftCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: AppColors.textSecondaryOf(context)),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ],
          ),
          if (!enabled) ...[
            const SizedBox(height: AppSpacing.sm),
            SoftPill(
              label: l10n.integrationsNotConnected,
              foreground: AppColors.onTriageAmber,
              background: AppColors.triageAmberTint,
              dense: true,
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Text(body, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: AppSpacing.lg),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              // Deliberately inert. There is nothing to connect to, and a
              // button that pretended otherwise would be the dishonest part.
              onPressed: null,
              child: Text(l10n.integrationsConnect),
            ),
          ),
        ],
      ),
    );
  }
}
