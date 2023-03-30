part of login;

class _LoginController {
  factory _LoginController({required AzureApiService apiService}) {
    return instance ??= _LoginController._(apiService);
  }

  _LoginController._(this.apiService);

  static _LoginController? instance;

  final AzureApiService apiService;

  final formFieldKey = GlobalKey<FormFieldState<dynamic>>();

  String pat = '';

  void dispose() {
    instance = null;
  }

  Future<void> init() async {
    print('$_LoginController initialized');
  }

  void setPat(String value) {
    pat = value;
  }

  Future<void> login() async {
    final isValid = formFieldKey.currentState!.validate();
    if (!isValid) return;

    final isLogged = await apiService.login(pat);
    if (isLogged == LoginStatus.failed) {
      _showLoginErrorAlert();
      return;
    }

    if (isLogged == LoginStatus.unauthorized) {
      final hasSetOrg = await _setOrgManually();
      if (!hasSetOrg) return;

      final isLoggedManually = await apiService.login(pat);
      if (isLoggedManually == LoginStatus.failed) {
        _showLoginErrorAlert();
        return;
      } else if (isLoggedManually == LoginStatus.unauthorized) {
        _showLoginErrorAlert();
        return;
      }
    }

    await AppRouter.goToChooseProjects();
  }

  void showInfo() {
    OverlayService.error(
      'Info',
      description:
          'Your PAT is stored on your device and is only used as an http header to communicate with Azure API, '
          "it's not stored anywhere else.\n\n"
          "Check that your PAT has access to all the organizations, otherwise it won't work.",
    );
  }

  void _showLoginErrorAlert() {
    OverlayService.error(
      'Login error',
      description: 'Check that your PAT is correct and retry',
    );
  }

  Future<bool> _setOrgManually() async {
    var hasSetOrg = false;

    String? manualOrg;
    await OverlayService.bottomsheet(
      title: 'Insert your organization',
      isScrollControlled: true,
      builder: (context) => Container(
        height: context.height * .8,
        decoration: BoxDecoration(
          color: context.colorScheme.background,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            children: [
              Text('Insert your organization name'),
              const SizedBox(
                height: 20,
              ),
              DevOpsFormField(
                label: 'Organization',
                onChanged: (s) => manualOrg = s,
                onFieldSubmitted: () {
                  hasSetOrg = true;
                  AppRouter.pop();
                },
                maxLines: 1,
              ),
              const SizedBox(
                height: 40,
              ),
              LoadingButton(
                onPressed: () {
                  hasSetOrg = true;
                  AppRouter.pop();
                },
                text: 'Confirm',
              ),
            ],
          ),
        ),
      ),
    );

    if (!hasSetOrg) return false;
    if (manualOrg == null || manualOrg!.isEmpty) return false;

    await apiService.setOrganization(manualOrg!);

    return true;
  }
}
