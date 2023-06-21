part of settings;

class _SettingsController with ShareMixin {
  factory _SettingsController({required AzureApiService apiService, required StorageService storageService}) {
    return instance ??= _SettingsController._(apiService, storageService);
  }

  _SettingsController._(this.apiService, this.storageService);

  static _SettingsController? instance;

  final AzureApiService apiService;
  final StorageService storageService;

  late String gitUsername = apiService.user!.emailAddress!;
  late String pat = apiService.accessToken;

  String appVersion = '';

  late final patTextFieldController = TextEditingController(text: pat);

  final isEditing = ValueNotifier(false);

  final organizations = ValueNotifier<ApiResponse<List<Organization>>?>(null);

  bool get hasMultiOrgs => (organizations.value?.data?.length ?? 0) > 1;

  void dispose() {
    instance = null;
  }

  Future<void> init() async {
    final info = await PackageInfo.fromPlatform();
    appVersion = info.version;

    final orgs = await apiService.getOrganizations();
    organizations.value = orgs;
  }

  void shareApp() {
    final appUrl = Platform.isAndroid
        ? 'https://play.google.com/store/apps/details?id=io.purplesoft.azuredevops'
        : 'https://apps.apple.com/app/apple-store/id1666994628?pt=120276127&ct=app&mt=8';

    shareUrl(appUrl);
  }

  Future<void> logout() async {
    final confirm = await OverlayService.confirm(
      'Do you really want to logout?',
      description: 'You will have to insert your PAT again',
    );
    if (!confirm) return;

    await apiService.logout();
    unawaited(AppRouter.goToLogin());
  }

  void seeChosenProjects() {
    AppRouter.goToChooseProjects(removeRoutes: false);
  }

  void changeThemeMode(String mode) {
    PurpleTheme.of(AppRouter.rootNavigator!.context).changeTheme(mode);
    storageService.setThemeMode(mode);
  }

  void clearLocalStorage() {
    storageService.clearNoToken();

    OverlayService.snackbar('Cache cleared!');

    AppRouter.goToChooseProjects(removeRoutes: false);
  }

  Future<void> setNewToken(String token) async {
    if (token.isEmpty) return;

    final res = await apiService.login(token);

    if (res == LoginStatus.failed || res == LoginStatus.unauthorized) {
      patTextFieldController.text = pat;
      return OverlayService.error(
        'Login failed',
        description: 'Check that the Personal Access Token is valid and retry',
      );
    }

    storageService.clearNoToken();
    unawaited(AppRouter.goToSplash());
  }

  void toggleIsEditingToken() {
    isEditing.value = !isEditing.value;

    if (!isEditing.value && patTextFieldController.text != pat) {
      setNewToken(patTextFieldController.text);
    }
  }

  void openPurplesoftWebsite(FollowLink? link) {
    if (kReleaseMode) Sentry.captureMessage('Open Purplesoft website');

    link?.call();
  }

  void openAppStore() {
    InAppReview.instance.openStoreListing(appStoreId: '1666994628');
  }

  Future<void> switchOrganization() async {
    final selectedOrg = await _selectOrganization(organizations.value!.data!);
    if (selectedOrg == null) return;

    storageService.setOrganization(selectedOrg.accountName!);
    apiService.setChosenProjects([]);
    unawaited(AppRouter.goToSplash());
  }

  Future<Organization?> _selectOrganization(List<Organization> organizations) async {
    final currentOrg = storageService.getOrganization();

    Organization? selectedOrg;

    await OverlayService.bottomsheet(
      title: 'Select your organization',
      isScrollControlled: true,
      heightPercentage: .7,
      builder: (context) => ListView(
        children: organizations
            .map(
              (org) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: LoadingButton(
                  onPressed: () {
                    selectedOrg = org;
                    AppRouter.popRoute();
                  },
                  text: org.accountName == currentOrg ? '${org.accountName!} (current)' : org.accountName!,
                ),
              ),
            )
            .toList(),
      ),
    );

    if (selectedOrg?.accountName == currentOrg) return null;

    return selectedOrg;
  }
}
