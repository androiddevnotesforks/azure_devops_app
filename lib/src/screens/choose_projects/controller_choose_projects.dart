part of choose_projects;

class _ChooseProjectsController {
  _ChooseProjectsController._(this.api, this.removeRoutes, this.storage);

  final AzureApiService api;
  final bool removeRoutes;
  final StorageService storage;

  final chosenProjects = ValueNotifier<ApiResponse<List<Project>?>?>(null);
  final visibleProjects = ValueNotifier<List<Project>>([]);
  List<Project> allProjects = <Project>[];

  final chooseAllVisible = ValueNotifier(false);

  final _initiallyChosenProjects = <Project>[];

  /// Projects already in local storage
  Iterable<Project> alreadyChosenProjects = [];

  Future<void> init() async {
    final org = storage.getOrganization();
    if (org.isEmpty) {
      await _chooseOrg();
    }

    allProjects = [];

    final projectsRes = await api.getProjects();
    final projects = projectsRes.data ?? <Project>[];

    alreadyChosenProjects = storage.getChosenProjects().where((p) => projects.map((p1) => p1.id!).contains(p.id));

    // sort projects by last change date, already chosen projects go first.
    if (alreadyChosenProjects.isNotEmpty) {
      allProjects
        ..addAll(
          alreadyChosenProjects.toList()..sort((a, b) => b.lastUpdateTime!.compareTo(a.lastUpdateTime!)),
        )
        ..addAll(
          projects.where((p) => !alreadyChosenProjects.contains(p)).toList()
            ..sort((a, b) => b.lastUpdateTime!.compareTo(a.lastUpdateTime!)),
        );
    } else {
      allProjects.addAll(projects..sort((a, b) => b.lastUpdateTime!.compareTo(a.lastUpdateTime!)));
      chooseAllVisible.value = true;
    }

    chosenProjects.value = ApiResponse(
      isError: projectsRes.isError,
      data: (alreadyChosenProjects.isNotEmpty ? alreadyChosenProjects : projects).toList(),
      errorResponse: projectsRes.errorResponse,
    );

    _initiallyChosenProjects.addAll(chosenProjects.value!.data!);
    visibleProjects.value = allProjects;
  }

  void toggleChooseAll() {
    chosenProjects.value = ApiResponse.ok(chooseAllVisible.value ? [] : [...visibleProjects.value]);

    chooseAllVisible.value = !chooseAllVisible.value;
  }

  void toggleChosenProject(Project p) {
    if (chosenProjects.value!.data!.contains(p)) {
      chosenProjects.value!.data!.remove(p);
    } else {
      chosenProjects.value!.data!.add(p);
    }

    chosenProjects.value = ApiResponse.ok(chosenProjects.value!.data);
  }

  Future<void> goToHome() async {
    if (chosenProjects.value!.data!.isEmpty) {
      return OverlayService.error(
        'No projects chosen',
        description: 'You have to choose at least one project',
      );
    }

    api.setChosenProjects(
      chosenProjects.value!.data!..sort((a, b) => b.lastUpdateTime!.compareTo(a.lastUpdateTime!)),
    );

    if (removeRoutes) {
      unawaited(AppRouter.goToTabs());
    } else {
      final hasChangedProjects = _initiallyChosenProjects != chosenProjects.value!.data!;
      if (hasChangedProjects) {
        // get new work item types to avoid errors in work items creation
        unawaited(api.getWorkItemTypes(force: true));
      }

      AppRouter.popRoute();
    }
  }

  Future<void> _chooseOrg() async {
    final orgsRes = await api.getOrganizations();
    if (orgsRes.isError) {
      return OverlayService.error(
        'Error trying to get your organizations',
        description: "Check that your token has 'All accessible organizations' option enabled",
      );
    }

    final orgs = orgsRes.data!;

    if (orgs.isEmpty) {
      await OverlayService.error(
        'No organizations found for your account',
        description: "Check that your token has 'All accessible organizations' option enabled",
      );
      await api.logout();
      await MsalService().logout();
      // Rebuild app to reset dependencies. This is needed to fix user null error after logout and login
      rebuildApp();
      unawaited(AppRouter.goToLogin());
      return;
    }

    if (orgs.length < 2) {
      await api.setOrganization(orgs.first.accountName!);
      return;
    }

    final selectedOrg = await _selectOrganization(orgs);

    if (selectedOrg == null) return;

    await api.setOrganization(selectedOrg.accountName!);
  }

  Future<Organization?> _selectOrganization(List<Organization> orgs) async {
    Organization? selectedOrg;

    await OverlayService.bottomsheet(
      isDismissible: false,
      title: 'Select your organization',
      isScrollControlled: true,
      heightPercentage: .7,
      builder: (context) => ListView(
        children: [
          ...orgs.map(
            (u) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: LoadingButton(
                onPressed: () {
                  selectedOrg = u;
                  AppRouter.popRoute();
                },
                text: u.accountName!,
              ),
            ),
          ),
        ],
      ),
    );
    return selectedOrg;
  }

  void setVisibleProjects(String filterName) {
    visibleProjects.value = allProjects.where((p) => p.name!.toLowerCase().contains(filterName.toLowerCase())).toList();
  }

  void resetSearch() {
    visibleProjects.value = allProjects;
  }

  /// Prevents user from going back without having selected any project after clear cache
  void onPopInvoked({required bool didPop}) {
    if (didPop) return;

    if (alreadyChosenProjects.isEmpty) return;

    final canPop = AppRouter.rootNavigator?.canPop() ?? false;

    if (canPop) {
      AppRouter.popRoute();
      return;
    }

    AppRouter.askBeforeClosingApp(didPop: didPop);
  }
}
