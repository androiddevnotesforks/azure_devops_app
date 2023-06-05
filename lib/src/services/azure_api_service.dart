// ignore_for_file: long-parameter-list

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:azure_devops/src/extensions/commit_extension.dart';
import 'package:azure_devops/src/extensions/reponse_extension.dart';
import 'package:azure_devops/src/models/commit.dart';
import 'package:azure_devops/src/models/commit_detail.dart';
import 'package:azure_devops/src/models/file_diff.dart';
import 'package:azure_devops/src/models/organization.dart';
import 'package:azure_devops/src/models/pipeline.dart';
import 'package:azure_devops/src/models/processes.dart';
import 'package:azure_devops/src/models/project.dart';
import 'package:azure_devops/src/models/project_languages.dart';
import 'package:azure_devops/src/models/pull_request.dart';
import 'package:azure_devops/src/models/repository.dart';
import 'package:azure_devops/src/models/repository_branches.dart';
import 'package:azure_devops/src/models/repository_items.dart';
import 'package:azure_devops/src/models/team.dart';
import 'package:azure_devops/src/models/team_member.dart';
import 'package:azure_devops/src/models/timeline.dart';
import 'package:azure_devops/src/models/user.dart';
import 'package:azure_devops/src/models/user_entitlements.dart';
import 'package:azure_devops/src/models/work_item_updates.dart';
import 'package:azure_devops/src/models/work_items.dart';
import 'package:azure_devops/src/services/storage_service.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/src/widgets/framework.dart';
import 'package:http/http.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

abstract class AzureApiService {
  const AzureApiService();

  String get organization;

  String get accessToken;

  UserMe? get user;

  Map<String, String>? get headers;

  String get basePath;

  List<GraphUser> get allUsers;

  Map<String, List<WorkItemType>> get workItemTypes;

  /// Work item states for each work item type for each project
  Map<String, Map<String, List<WorkItemState>>> get workItemStates;

  String getUserAvatarUrl(String userDescriptor);

  Future<LoginStatus> login(String accessToken);

  Future<void> setOrganization(String org);

  Future<ApiResponse<List<Organization>>> getOrganizations();

  void setChosenProjects(List<Project> chosenProjects);

  Future<ApiResponse<List<Project>>> getProjects();

  Future<ApiResponse<Project>> getProject({required String projectName});

  Future<ApiResponse<List<WorkItem>>> getWorkItems({
    Project? project,
    WorkItemType? type,
    WorkItemState? status,
    GraphUser? assignedTo,
  });

  Future<ApiResponse<Map<String, List<WorkItemType>>>> getWorkItemTypes({bool force = false});

  Future<ApiResponse<WorkItem>> getWorkItemDetail({
    required String projectName,
    required int workItemId,
  });

  Future<ApiResponse<List<WorkItemUpdate>>> getWorkItemUpdates({
    required String projectName,
    required int workItemId,
  });

  Future<ApiResponse<Uint8List>> getWorkItemAttachment({
    required String projectName,
    required String attachmentId,
    required String fileName,
  });

  Future<ApiResponse<WorkItem>> createWorkItem({
    required String projectName,
    required WorkItemType type,
    required GraphUser? assignedTo,
    required String title,
    required String description,
  });

  Future<ApiResponse<WorkItem>> editWorkItem({
    required String projectName,
    required int id,
    WorkItemType? type,
    GraphUser? assignedTo,
    String? title,
    String? description,
    String? status,
  });

  Future<ApiResponse<bool>> deleteWorkItem({required String projectName, required int id});

  Future<ApiResponse<List<PullRequest>>> getPullRequests({
    required PullRequestState filter,
    GraphUser? creator,
    Project? project,
  });

  Future<ApiResponse<List<GitRepository>>> getProjectRepositories({required String projectName});

  Future<ApiResponse<List<LanguageBreakdown>>> getProjectLanguages({required String projectName});

  Future<ApiResponse<List<RepoItem>>> getRepositoryItems({
    required String projectName,
    required String repoName,
    required String path,
    String? branch,
  });

  Future<ApiResponse<List<Branch>>> getRepositoryBranches({
    required String projectName,
    required String repoName,
  });

  Future<ApiResponse<FileDetailResponse>> getFileDetail({
    required String projectName,
    required String repoName,
    required String path,
    String? branch,
    String? commitId,
    bool previousChange,
  });

  Future<ApiResponse<List<Commit>>> getRecentCommits({Project? project, String? author, int? maxCount});

  Future<ApiResponse<Commit>> getCommitDetail({
    required String projectId,
    required String repositoryId,
    required String commitId,
  });

  Future<ApiResponse<CommitChanges>> getCommitChanges({
    required String projectId,
    required String repositoryId,
    required String commitId,
  });

  Future<ApiResponse<Diff>> getCommitDiff({
    required Commit commit,
    required String filePath,
    required bool isAdded,
    required bool isDeleted,
  });

  Future<ApiResponse<List<Pipeline>>> getRecentPipelines({
    Project? project,
    PipelineResult result,
    PipelineStatus status,
    String? triggeredBy,
  });

  Future<ApiResponse<Pipeline>> getPipeline({required String projectName, required int id});

  Future<ApiResponse<List<Record>>> getPipelineTimeline({required String projectName, required int id});

  Future<ApiResponse<String>> getPipelineTaskLogs({
    required String projectName,
    required int pipelineId,
    required int logId,
  });

  Future<ApiResponse<Pipeline>> cancelPipeline({required int buildId, required String projectId});

  Future<ApiResponse<Pipeline>> rerunPipeline({
    required int definitionId,
    required String projectId,
    required String branch,
  });

  Future<ApiResponse<GraphUser>> getUserFromEmail({required String email});

  Future<ApiResponse<GraphUser>> getUserFromDescriptor({required String descriptor});

  Future<ApiResponse<GraphUser>> getUserFromDisplayName({required String name});

  Future<ApiResponse<List<TeamMember>>> getProjectTeams({required String projectId});

  Future<ApiResponse<PullRequest>> getPullRequest({required String projectName, required int id});

  Future<void> logout();

  bool get isImageUnauthorized;
}

class AzureApiServiceImpl implements AzureApiService {
  factory AzureApiServiceImpl() {
    return instance ??= AzureApiServiceImpl._();
  }

  AzureApiServiceImpl._();

  static AzureApiServiceImpl? instance;

  final _client = Client();

  String _accessToken = '';

  String _organization = '';

  UserMe? _user;

  @override
  String get organization => _organization;

  @override
  String get accessToken => _accessToken;

  @override
  UserMe? get user => _user;

  @override
  String get basePath => _basePath;
  String get _basePath => 'https://dev.azure.com/$_organization';

  String get _usersBasePath => 'https://vssps.dev.azure.com';

  String get _apiVersion => 'api-version=7.0';

  @override
  List<GraphUser> get allUsers => _allUsers;
  List<GraphUser> _allUsers = [];

  @override
  bool get isImageUnauthorized => _isImageUnauthorized;
  bool _isImageUnauthorized = false;

  @override
  Map<String, String>? get headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Basic ${base64.encode(utf8.encode(':$_accessToken'))}',
      };

  List<Project> _projects = [];
  Iterable<Project>? _chosenProjects;

  @override
  Map<String, List<WorkItemType>> get workItemTypes => _workItemTypes;
  final Map<String, List<WorkItemType>> _workItemTypes = {};

  @override
  Map<String, Map<String, List<WorkItemState>>> get workItemStates => _workItemStates;
  final Map<String, Map<String, List<WorkItemState>>> _workItemStates = {};

  void dispose() {
    instance = null;
  }

  @override
  String getUserAvatarUrl(String userDescriptor) {
    return '$_basePath/_apis/GraphProfile/MemberAvatars/$userDescriptor?size=large';
  }

  Future<Response> _get(String url) async {
    print('GET $url');
    final res = await _client.get(
      Uri.parse(url),
      headers: headers,
    );

    _addSentryBreadcrumb(url, 'GET', res, '');

    return res;
  }

  Future<Response> _patch(String url, {Map<String, String>? body}) async {
    print('PATCH $url');
    final res = await _client.patch(
      Uri.parse(url),
      headers: headers,
      body: jsonEncode(body),
    );

    _addSentryBreadcrumb(url, 'PATCH', res, body);

    return res;
  }

  Future<Response> _patchList(String url, {List<Map<String, dynamic>>? body, String? contentType}) async {
    print('PATCH $url');
    final realHeaders = contentType != null ? ({...headers!, 'Content-Type': contentType}) : headers!;

    final res = await _client.patch(
      Uri.parse(url),
      headers: realHeaders,
      body: jsonEncode(body),
    );

    _addSentryBreadcrumb(url, 'PATCH', res, body);

    return res;
  }

  Future<Response> _post(String url, {Map<String, dynamic>? body}) async {
    print('POST $url');
    final res = await _client.post(
      Uri.parse(url),
      headers: headers,
      body: jsonEncode(body),
    );

    _addSentryBreadcrumb(url, 'POST', res, body);

    return res;
  }

  Future<Response> _postList(String url, {List<Map<String, dynamic>>? body, String? contentType}) async {
    print('POST $url');
    final realHeaders = contentType != null ? ({...headers!, 'Content-Type': contentType}) : headers!;

    final res = await _client.post(
      Uri.parse(url),
      headers: realHeaders,
      body: jsonEncode(body),
    );

    _addSentryBreadcrumb(url, 'POST', res, body);

    return res;
  }

  Future<Response> _delete(String url) async {
    print('DELETE $url');
    final res = await _client.delete(
      Uri.parse(url),
      headers: headers,
    );

    _addSentryBreadcrumb(url, 'DELETE', res, '');

    return res;
  }

  // error debouncer
  static bool _isLoggingError = false;

  void _addSentryBreadcrumb(String url, String method, Response res, Object? body) {
    if (kDebugMode) {
      print('$method $url ${res.statusCode} ${res.reasonPhrase}');
      return;
    }

    final breadcrumb = Breadcrumb.http(
      url: Uri.parse(url),
      method: method,
      reason: res.reasonPhrase,
      statusCode: res.statusCode,
    );

    Sentry.addBreadcrumb(breadcrumb);

    if (res.isError && _user != null && ![401, 403].contains(res.statusCode)) {
      if (_isLoggingError) return;

      _isLoggingError = true;
      Timer(Duration(seconds: 2), () => _isLoggingError = false);

      final title = '${res.statusCode} ${res.reasonPhrase}';

      Sentry.captureEvent(
        SentryEvent(
          level: SentryLevel.warning,
          breadcrumbs: [breadcrumb],
          message: SentryMessage(
            title,
            template: 'Response body: %s, \n Request body: %s',
            params: [if (res.body.isNotEmpty) res.body, if (body != null && body != '') body],
          ),
        ),
      );
    }
  }

  @override
  Future<LoginStatus> login(String accessToken) async {
    if (accessToken.isEmpty) return LoginStatus.unauthorized;

    final oldToken = _accessToken;

    _accessToken = accessToken;

    var profileEndpoint = '$_usersBasePath/_apis/profile/profiles/me?$_apiVersion-preview';

    _organization = StorageServiceCore().getOrganization();

    if (_organization.isNotEmpty) {
      profileEndpoint = '$_usersBasePath/$_organization/_apis/profile/profiles/me?$_apiVersion-preview';
    }

    final accountsRes = await _get(profileEndpoint);

    if (accountsRes.statusCode == HttpStatus.unauthorized) {
      _accessToken = oldToken;
      await setOrganization('');
      return LoginStatus.unauthorized;
    }

    if (accountsRes.statusCode != HttpStatus.ok) {
      _accessToken = oldToken;
      await setOrganization('');
      return LoginStatus.failed;
    }

    StorageServiceCore.instance!.setToken(accessToken);

    final user = UserMe.fromJson(jsonDecode(accountsRes.body) as Map<String, dynamic>);
    _user = user;

    _organization = StorageServiceCore().getOrganization();

    if (_organization.isEmpty) {
      return LoginStatus.orgNotSet;
    }

    unawaited(_getUsers());

    _chosenProjects = StorageServiceCore().getChosenProjects();

    if (_chosenProjects!.isEmpty) {
      return LoginStatus.projectsNotSet;
    }

    return LoginStatus.ok;
  }

  @override
  Future<void> setOrganization(String org) async {
    _organization = org.endsWith('/') ? org.substring(0, org.length - 1) : org;

    StorageServiceCore.instance!.setOrganization(_organization);

    if (user != null) unawaited(_getUsers());
  }

  @override
  Future<ApiResponse<List<Organization>>> getOrganizations() async {
    final orgsRes =
        await _get('https://app.vssps.visualstudio.com/_apis/accounts?memberId=${user!.publicAlias}&$_apiVersion');

    if (orgsRes.isError) return ApiResponse.error(orgsRes);

    return ApiResponse.ok(
      GetOrganizationsResponse.fromJson(jsonDecode(orgsRes.body) as Map<String, dynamic>).organizations,
    );
  }

  @override
  void setChosenProjects(List<Project> chosenProjects) {
    _chosenProjects = chosenProjects.toList();

    StorageServiceCore().setChosenProjects(_chosenProjects!);
  }

  @override
  Future<ApiResponse<List<Project>>> getProjects() async {
    _chosenProjects = StorageServiceCore().getChosenProjects();

    final projectsRes = await _get('$_basePath/_apis/projects?$_apiVersion&getDefaultTeamImageUrl=true');
    if (projectsRes.isError) return ApiResponse.error(projectsRes);

    final res = GetProjectsResponse.fromJson(jsonDecode(projectsRes.body) as Map<String, dynamic>);
    _projects = res.projects;

    // check if user is authorized to get images. This is done to avoid throwing many exceptions
    if (_projects.isNotEmpty) {
      final url = _projects.firstWhereOrNull((p) => p.defaultTeamImageUrl != null);
      if (url != null) {
        final imageRes = await _get(url.defaultTeamImageUrl!);
        if (imageRes.isError) _isImageUnauthorized = true;
      }
    }

    return ApiResponse.ok(_projects);
  }

  @override
  Future<ApiResponse<Project>> getProject({required String projectName}) async {
    final projectRes = await _get('$_basePath/_apis/projects/$projectName?$_apiVersion');
    if (projectRes.isError) return ApiResponse.error(projectRes);

    final project = Project.fromJson(jsonDecode(projectRes.body) as Map<String, dynamic>);

    return ApiResponse.ok(project);
  }

  @override
  Future<ApiResponse<List<WorkItem>>> getWorkItems({
    Project? project,
    WorkItemType? type,
    WorkItemState? status,
    GraphUser? assignedTo,
  }) async {
    final query = <String>[];
    if (project != null) {
      query.add(" [System.TeamProject] = '${project.name}' ");
    } else {
      final projectsToSearch = (_chosenProjects ?? _projects).toList();

      if (projectsToSearch.length == 1) {
        query.add(" [System.TeamProject] = '${projectsToSearch.first.name}' ");
      } else {
        var projectsQuery = '';

        for (var i = 0; i < projectsToSearch.length; i++) {
          if (i == 0) {
            projectsQuery += " ( [System.TeamProject] = '${projectsToSearch[i].name}' OR ";
          } else if (i == projectsToSearch.length - 1) {
            projectsQuery += " [System.TeamProject] = '${projectsToSearch[i].name}' ) ";
          } else {
            projectsQuery += " [System.TeamProject] = '${projectsToSearch[i].name}' OR ";
          }
        }

        query.add(projectsQuery);
      }
    }

    if (type != null) query.add(" [System.WorkItemType] = '${type.name}' ");

    if (status != null) query.add(" [System.State] = '${status.name}' ");

    if (assignedTo != null) query.add(" [System.AssignedTo] = '${assignedTo.mailAddress}' ");

    var queryStr = '';
    if (query.isNotEmpty) {
      queryStr = query.join(' and ');
      queryStr = ' Where $queryStr ';
    }

    final workItemIdsRes = await _post(
      '$_basePath/_apis/wit/wiql?\$top=200&$_apiVersion',
      body: {'query': 'Select [System.Id] From WorkItems $queryStr Order By [System.ChangedDate] desc'},
    );

    if (workItemIdsRes.isError) return ApiResponse.error(workItemIdsRes);

    final workItemIds = GetWorkItemIds.fromJson(jsonDecode(workItemIdsRes.body) as Map<String, dynamic>).workItems;
    if (workItemIds.isEmpty) return ApiResponse.ok([]);

    final ids = workItemIds.map((e) => e.id).join(',');

    final allWorkItemsRes = await _get('$_basePath/_apis/wit/workitems?ids=$ids&$_apiVersion');

    if (allWorkItemsRes.isError) return ApiResponse.error(allWorkItemsRes);

    return ApiResponse.ok(
      GetWorkItemsResponse.fromJson(jsonDecode(allWorkItemsRes.body) as Map<String, dynamic>).items,
    );
  }

  @override
  Future<ApiResponse<Map<String, List<WorkItemType>>>> getWorkItemTypes({bool force = false}) async {
    if (_workItemTypes.isNotEmpty && !force) {
      // return cached types to avoid too many api calls
      return ApiResponse.ok(_workItemTypes);
    }

    final processesRes = await _get('$_basePath/_apis/work/processes?\$expand=projects&$_apiVersion');
    if (processesRes.isError) return ApiResponse.error(processesRes);

    final processes = GetProcessesResponse.fromJson(jsonDecode(processesRes.body) as Map<String, dynamic>)
        .processes
        .where((p) => p.projects.isNotEmpty)
        .toList();

    final processWorkItems = <WorkProcess, List<WorkItemType>>{};

    await Future.wait([
      for (final proc in processes)
        _get('$_basePath/_apis/work/processes/${proc.typeId}/workItemTypes?$_apiVersion').then(
          (res) {
            if (res.isError) return;

            final types = GetWorkItemTypesResponse.fromJson(jsonDecode(res.body) as Map<String, dynamic>)
                .types
                .where((t) => !t.isDisabled)
                .toList();

            final projectsToSearch = proc.projects.where((p) => (_chosenProjects ?? _projects).contains(p));

            for (final proj in projectsToSearch) {
              _workItemTypes.putIfAbsent(proj.name!, () => types);
              processWorkItems.putIfAbsent(proc, () => types);
            }
          },
        ),
    ]);

    await Future.wait([
      for (final procEntry in processWorkItems.entries)
        for (final wt in procEntry.value)
          _get('$_basePath/_apis/work/processes/${procEntry.key.typeId}/workItemTypes/${wt.referenceName}/states?$_apiVersion')
              .then(
            (res) {
              if (res.isError) return;

              final states = GetWorkItemStatesResponse.fromJson(jsonDecode(res.body) as Map<String, dynamic>).states;
              final projectsToSearch = procEntry.key.projects.where((p) => (_chosenProjects ?? _projects).contains(p));
              for (final proj in projectsToSearch) {
                _workItemStates.putIfAbsent(proj.name!, () => {wt.name: states});
                _workItemStates[proj.name]!.putIfAbsent(wt.name, () => states);
              }
            },
          ),
    ]);

    return ApiResponse.ok(_workItemTypes);
  }

  @override
  Future<ApiResponse<WorkItem>> getWorkItemDetail({
    required String projectName,
    required int workItemId,
  }) async {
    final workItemRes = await _get('$_basePath/$projectName/_apis/wit/workitems/$workItemId?$_apiVersion');
    if (workItemRes.isError) return ApiResponse.error(workItemRes);

    return ApiResponse.ok(WorkItem.fromJson(jsonDecode(workItemRes.body) as Map<String, dynamic>));
  }

  @override
  Future<ApiResponse<List<WorkItemUpdate>>> getWorkItemUpdates({
    required String projectName,
    required int workItemId,
  }) async {
    final workItemUpdatesRes =
        await _get('$_basePath/$projectName/_apis/wit/workitems/$workItemId/updates?$_apiVersion');
    if (workItemUpdatesRes.isError) return ApiResponse.error(workItemUpdatesRes);

    return ApiResponse.ok(
      WorkItemUpdatesResponse.fromJson(jsonDecode(workItemUpdatesRes.body) as Map<String, dynamic>).updates,
    );
  }

  @override
  Future<ApiResponse<Uint8List>> getWorkItemAttachment({
    required String projectName,
    required String attachmentId,
    required String fileName,
  }) async {
    final attachmentRes =
        await _get('$_basePath/$projectName/_apis/wit/attachments/$attachmentId?fileName=$fileName&$_apiVersion');
    if (attachmentRes.isError) return ApiResponse.error(attachmentRes);

    return ApiResponse.ok(attachmentRes.bodyBytes);
  }

  @override
  Future<ApiResponse<WorkItem>> createWorkItem({
    required String projectName,
    required WorkItemType type,
    required GraphUser? assignedTo,
    required String title,
    required String description,
  }) async {
    final createRes = await _postList(
      '$_basePath/$projectName/_apis/wit/workitems/\$${type.name}?$_apiVersion-preview',
      body: [
        {
          'op': 'add',
          'value': title,
          'path': '/fields/System.Title',
        },
        {
          'op': 'add',
          'value': description,
          'path': '/fields/System.Description',
        },
        if (assignedTo != null)
          {
            'op': 'add',
            'value': assignedTo.mailAddress,
            'path': '/fields/System.AssignedTo',
          },
      ],
      contentType: 'application/json-patch+json',
    );

    if (createRes.isError) return ApiResponse.error(createRes);

    return ApiResponse.ok(WorkItem.fromJson(jsonDecode(createRes.body) as Map<String, dynamic>));
  }

  @override
  Future<ApiResponse<WorkItem>> editWorkItem({
    required String projectName,
    required int id,
    WorkItemType? type,
    GraphUser? assignedTo,
    String? title,
    String? description,
    String? status,
  }) async {
    final editRes = await _patchList(
      '$_basePath/$projectName/_apis/wit/workitems/$id?$_apiVersion-preview',
      body: [
        if (title != null)
          {
            'op': 'replace',
            'value': title,
            'path': '/fields/System.Title',
          },
        if (description != null)
          {
            'op': 'replace',
            'value': description,
            'path': '/fields/System.Description',
          },
        if (assignedTo != null)
          {
            'op': 'replace',
            'value': assignedTo.mailAddress,
            'path': '/fields/System.AssignedTo',
          },
        if (type != null)
          {
            'op': 'replace',
            'value': type.name,
            'path': '/fields/System.WorkItemType',
          },
        if (status != null)
          {
            'op': 'replace',
            'value': status,
            'path': '/fields/System.State',
          },
      ],
      contentType: 'application/json-patch+json',
    );

    if (editRes.isError) return ApiResponse.error(editRes);

    return ApiResponse.ok(WorkItem.fromJson(jsonDecode(editRes.body) as Map<String, dynamic>));
  }

  @override
  Future<ApiResponse<bool>> deleteWorkItem({required String projectName, required int id}) async {
    final deleteRes = await _delete('$_basePath/$projectName/_apis/wit/workitems/$id?$_apiVersion');
    if (deleteRes.isError) return ApiResponse.error(deleteRes);

    return ApiResponse.ok(true);
  }

  @override
  Future<ApiResponse<List<PullRequest>>> getPullRequests({
    required PullRequestState filter,
    GraphUser? creator,
    Project? project,
  }) async {
    var creatorFilter = '';
    if (creator != null) {
      final creatorSearch = "&\$filter=name eq '${creator.mailAddress}'";
      final entitlementRes =
          await _get('https://vsaex.dev.azure.com/$_organization/_apis/userentitlements?$_apiVersion$creatorSearch');
      if (entitlementRes.isError) return ApiResponse.error(entitlementRes);

      final member = GetUserEntitlementsResponse.fromJson(jsonDecode(entitlementRes.body) as Map<String, dynamic>)
          .members
          .firstOrNull;
      if (member == null) return ApiResponse.error(null);

      creatorFilter = '&searchCriteria.creatorId=${member.id}';
    }

    final projectsToSearch = project != null ? [project] : (_chosenProjects ?? _projects);

    final allProjectPrs = await Future.wait([
      for (final project in projectsToSearch)
        _get(
          '$_basePath/${project.name}/_apis/git/pullrequests?$_apiVersion&searchCriteria.status=${filter.name}$creatorFilter',
        ),
    ]);

    var isAllError = true;

    for (final res in allProjectPrs) {
      isAllError &= res.isError;
    }

    if (isAllError) return ApiResponse.error(allProjectPrs.firstOrNull);

    return ApiResponse.ok(
      allProjectPrs
          .where((r) => !r.isError)
          .map((r) => GetPullRequestsResponse.fromJson(jsonDecode(r.body) as Map<String, dynamic>).pullRequests)
          .expand((b) => b)
          .toList(),
    );
  }

  @override
  Future<ApiResponse<List<GitRepository>>> getProjectRepositories({required String projectName}) async {
    final repositoriesRes = await _get('$_basePath/$projectName/_apis/git/repositories?$_apiVersion');
    if (repositoriesRes.isError) return ApiResponse.error(repositoriesRes);

    return ApiResponse.ok(
      GetRepositoriesResponse.fromJson(jsonDecode(repositoriesRes.body) as Map<String, dynamic>).repositories,
    );
  }

  @override
  Future<ApiResponse<List<TeamMember>>> getProjectTeams({required String projectId}) async {
    final teamsRes = await _get('$_basePath/_apis/teams?$_apiVersion-preview');
    if (teamsRes.isError) return ApiResponse.error(teamsRes);

    final teams = GetTeamsResponse.fromJson(jsonDecode(teamsRes.body) as Map<String, dynamic>).teams!;
    final team = teams.firstWhereOrNull((t) => t!.projectId == projectId || t.projectName == projectId);

    if (team == null) {
      return ApiResponse.error(teamsRes);
    }

    final membersRes = await _get('$_basePath/_apis/projects/$projectId/teams/${team.id}/members?$_apiVersion');
    if (membersRes.isError) return ApiResponse.error(membersRes);

    return ApiResponse.ok(
      GetTeamMembersResponse.fromJson(jsonDecode(membersRes.body) as Map<String, dynamic>).members,
    );
  }

  @override
  Future<ApiResponse<PullRequest>> getPullRequest({required String projectName, required int id}) async {
    final prRes = await _get('$_basePath/$projectName/_apis/git/pullrequests/$id?$_apiVersion');
    if (prRes.isError) return ApiResponse.error(prRes);

    return ApiResponse.ok(PullRequest.fromJson(jsonDecode(prRes.body) as Map<String, dynamic>));
  }

  @override
  Future<ApiResponse<List<RepoItem>>> getRepositoryItems({
    required String projectName,
    required String repoName,
    required String path,
    String? branch,
  }) async {
    var branchQuery = '';

    if (branch != null) {
      final escapedBranch = Uri.encodeQueryComponent(branch);
      branchQuery = 'versionDescriptor.version=$escapedBranch&versionDescriptor.versionType=branch&';
    }

    final itemsRes = await _get(
      '$_basePath/$projectName/_apis/git/repositories/$repoName/items?scopePath=$path&recursionLevel=oneLevel&includeContentMetadata=true&includeContent=true&$branchQuery$_apiVersion',
    );
    if (itemsRes.isError) return ApiResponse.error(itemsRes);

    return ApiResponse.ok(GetRepoItemsResponse.fromRawJson(itemsRes.body).repoItems);
  }

  @override
  Future<ApiResponse<List<Branch>>> getRepositoryBranches({
    required String projectName,
    required String repoName,
  }) async {
    final branchesRes = await _get(
      '$_basePath/$projectName/_apis/git/repositories/$repoName/stats/branches?$_apiVersion',
    );
    if (branchesRes.isError) return ApiResponse.error(branchesRes);

    return ApiResponse.ok(RepositoryBranchesResponse.fromRawJson(branchesRes.body).branches);
  }

  @override
  Future<ApiResponse<FileDetailResponse>> getFileDetail({
    required String projectName,
    required String repoName,
    required String path,
    String? branch,
    String? commitId,
    bool previousChange = false,
  }) async {
    var versionQuery = '';

    if (commitId != null) {
      versionQuery = 'versionDescriptor.version=$commitId&versionDescriptor.versionType=commit&';
    } else if (branch != null) {
      final escapedBranch = Uri.encodeQueryComponent(branch);
      versionQuery = 'versionDescriptor.version=$escapedBranch&versionDescriptor.versionType=branch&';
    }

    if (previousChange) {
      versionQuery += 'versionDescriptor.versionOptions=previousChange&';
    }

    final res = await _get(
      '$_basePath/$projectName/_apis/git/repositories/$repoName/items?path=$path&includeContentMetadata=true&includeContent=true&$versionQuery$_apiVersion',
    );
    if (res.isError) return ApiResponse.error(res);

    final isBinary = res.body.contains('\u0000');

    return ApiResponse.ok(FileDetailResponse(content: res.body, isBinary: isBinary));
  }

  @override
  Future<ApiResponse<List<LanguageBreakdown>>> getProjectLanguages({required String projectName}) async {
    final langsRes = await _get(
      '$_basePath/$projectName/_apis/projectanalysis/languagemetrics',
    );

    if (langsRes.isError) return ApiResponse.error(langsRes);

    return ApiResponse.ok(
      GetProjectLanguagesResponse.fromJson(jsonDecode(langsRes.body) as Map<String, dynamic>)
          .languageBreakdown
          .toList(),
    );
  }

  @override
  Future<ApiResponse<List<Pipeline>>> getRecentPipelines({
    Project? project,
    PipelineResult result = PipelineResult.all,
    PipelineStatus status = PipelineStatus.all,
    String? triggeredBy,
  }) async {
    final orderSearch = '&queryOrder=queueTimeDescending';
    final resultSearch = '&resultFilter=${result.stringValue}';
    final statusSearch = result != PipelineResult.all ? '' : '&statusFilter=${status.stringValue}';
    final triggeredBySearch = triggeredBy == null ? '' : '&requestedFor=$triggeredBy';

    final queryParams = '$_apiVersion$orderSearch$resultSearch$statusSearch$triggeredBySearch';

    final projectsToSearch = project != null ? [project] : (_chosenProjects ?? _projects);

    final allProjectPipelines = await Future.wait([
      for (final project in projectsToSearch) _get('$_basePath/${project.name}/_apis/build/builds?$queryParams'),
    ]);

    var isAllError = true;

    for (final res in allProjectPipelines) {
      isAllError &= res.isError;
    }

    if (isAllError) return ApiResponse.error(allProjectPipelines.firstOrNull);

    final res = allProjectPipelines
        .where((r) => !r.isError)
        .map((r) => GetPipelineResponse.fromJson(jsonDecode(r.body) as Map<String, dynamic>).pipelines)
        .expand((b) => b)
        .toList();

    return ApiResponse.ok(res);
  }

  @override
  Future<ApiResponse<Pipeline>> getPipeline({required String projectName, required int id}) async {
    final pipelineRes = await _get('$_basePath/$projectName/_apis/build/builds/$id?$_apiVersion');

    if (pipelineRes.isError) return ApiResponse.error(pipelineRes);

    final pipeline = Pipeline.fromJson(jsonDecode(pipelineRes.body) as Map<String, dynamic>);

    return ApiResponse.ok(pipeline);
  }

  @override
  Future<ApiResponse<List<Record>>> getPipelineTimeline({required String projectName, required int id}) async {
    final timelineRes = await _get('$_basePath/$projectName/_apis/build/builds/$id/timeline?$_apiVersion');
    if (timelineRes.isError) return ApiResponse.error(timelineRes);

    return ApiResponse.ok(GetTimelineResponse.fromRawJson(timelineRes.body).records);
  }

  @override
  Future<ApiResponse<String>> getPipelineTaskLogs({
    required String projectName,
    required int pipelineId,
    required int logId,
  }) async {
    final logsRes = await _get('$_basePath/$projectName/_apis/build/builds/$pipelineId/logs/$logId?$_apiVersion');
    if (logsRes.isError) return ApiResponse.error(logsRes);

    return ApiResponse.ok(logsRes.body);
  }

  @override
  Future<ApiResponse<List<Commit>>> getRecentCommits({Project? project, String? author, int? maxCount}) async {
    final projectsToSearch = project != null ? [project] : (_chosenProjects ?? _projects);

    final allProjectRepos = await Future.wait([
      for (final project in projectsToSearch) _get('$_basePath/${project.name}/_apis/git/repositories?$_apiVersion'),
    ]);

    var isAllError = true;

    for (final res in allProjectRepos) {
      isAllError &= res.isError;
    }

    if (isAllError) return ApiResponse.error(allProjectRepos.firstOrNull);

    final repos = allProjectRepos
        .where((r) => !r.isError)
        .map((r) => GetRepositoriesResponse.fromJson(jsonDecode(r.body) as Map<String, dynamic>).repositories)
        .expand((r) => r)
        .toList();

    final authorSearch = author != null ? '&searchCriteria.author=$author' : '';
    final topSearch = maxCount != null ? '&searchCriteria.\$top=$maxCount' : '';

    final allProjectCommits = await Future.wait([
      for (final repo in repos)
        _get(
          '$_basePath/${repo.project!.name}/_apis/git/repositories/${repo.name}/commits?$_apiVersion$authorSearch$topSearch',
        ),
    ]);

    var isAllCommitsError = true;

    for (final res in allProjectCommits) {
      isAllCommitsError &= res.isError;
    }

    if (isAllCommitsError) return ApiResponse.error(allProjectCommits.firstOrNull);

    final res = allProjectCommits
        .map((res) => GetCommitsResponse.fromJson(jsonDecode(res.body) as Map<String, dynamic>).commits)
        .expand((c) => c)
        .toList();

    return ApiResponse.ok(res);
  }

  @override
  Future<ApiResponse<CommitChanges>> getCommitChanges({
    required String projectId,
    required String repositoryId,
    required String commitId,
  }) async {
    final changesRes =
        await _get('$_basePath/$projectId/_apis/git/repositories/$repositoryId/commits/$commitId/changes?$_apiVersion');
    if (changesRes.isError) return ApiResponse.error(changesRes);

    return ApiResponse.ok(CommitChanges.fromJson(jsonDecode(changesRes.body) as Map<String, dynamic>));
  }

  @override
  Future<ApiResponse<Commit>> getCommitDetail({
    required String projectId,
    required String repositoryId,
    required String commitId,
  }) async {
    final detailRes =
        await _get('$_basePath/$projectId/_apis/git/repositories/$repositoryId/commits/$commitId?$_apiVersion');
    if (detailRes.isError) return ApiResponse.error(detailRes);

    return ApiResponse.ok(Commit.fromJson(jsonDecode(detailRes.body) as Map<String, dynamic>));
  }

  @override
  Future<ApiResponse<Diff>> getCommitDiff({
    required Commit commit,
    required String filePath,
    required bool isAdded,
    required bool isDeleted,
  }) async {
    final hasParent = commit.parents?.isNotEmpty ?? false;
    final repoId = commit.repositoryId;
    final diffRes = await _post(
      '$_basePath/_apis/contribution/hierarchyQuery/project/${commit.projectId}?$_apiVersion-preview',
      body: {
        'contributionIds': ['ms.vss-code-web.file-diff-data-provider'],
        'dataProviderContext': {
          'properties': {
            'repositoryId': repoId,
            'diffParameters': {
              'includeCharDiffs': true,
              if (!isDeleted) 'modifiedPath': filePath,
              if (!isDeleted) 'modifiedVersion': 'GC${commit.commitId}',
              if (!isAdded) 'originalPath': filePath,
              if (!isAdded && hasParent) 'originalVersion': 'GC${commit.parents!.first}',
              'partialDiff': true,
              'forceLoad': false,
            },
          },
        },
      },
    );
    if (diffRes.isError) return ApiResponse.error(diffRes);

    return ApiResponse.ok(GetFileDiffResponse.fromRawJson(diffRes.body).data.diff);
  }

  @override
  Future<ApiResponse<Pipeline>> cancelPipeline({required int buildId, required String projectId}) async {
    final cancelRes = await _patch(
      '$_basePath/$projectId/_apis/build/builds/$buildId?$_apiVersion',
      body: {'status': PipelineStatus.cancelling.stringValue},
    );
    if (cancelRes.isError) return ApiResponse.error(cancelRes);

    final res = Pipeline.fromJson(jsonDecode(cancelRes.body) as Map<String, dynamic>);
    return ApiResponse.ok(res);
  }

  @override
  Future<ApiResponse<Pipeline>> rerunPipeline({
    required int definitionId,
    required String projectId,
    required String branch,
  }) async {
    final rerunRes = await _post(
      '$_basePath/$projectId/_apis/build/builds?$_apiVersion',
      body: {
        'sourceBranch': branch,
        'definition': {'id': definitionId},
      },
    );

    if (rerunRes.isError) return ApiResponse.error(rerunRes);

    final res = Pipeline.fromJson(jsonDecode(rerunRes.body) as Map<String, dynamic>);
    return ApiResponse.ok(res);
  }

  @override
  Future<ApiResponse<GraphUser>> getUserFromEmail({
    required String email,
  }) async {
    if (_allUsers.isEmpty) {
      await _getUsers();
    }

    return ApiResponse.ok(_allUsers.firstWhereOrNull((u) => u.mailAddress == email));
  }

  @override
  Future<ApiResponse<GraphUser>> getUserFromDescriptor({
    required String descriptor,
  }) async {
    if (_allUsers.isEmpty) {
      await _getUsers();
    }

    final user = _allUsers.firstWhereOrNull((u) => u.descriptor == descriptor);
    if (user == null) {
      return ApiResponse.error(Response('', 404, reasonPhrase: 'User not found'));
    }

    return ApiResponse.ok(user);
  }

  @override
  Future<ApiResponse<GraphUser>> getUserFromDisplayName({
    required String name,
  }) async {
    if (_allUsers.isEmpty) {
      await _getUsers();
    }

    final user = _allUsers.firstWhereOrNull((u) => u.displayName == name);
    if (user == null) {
      return ApiResponse.error(null);
    }

    return ApiResponse.ok(user);
  }

  Future<ApiResponse> _getUsers() async {
    final usersRes = await _get('$_usersBasePath/$_organization/_apis/graph/users?$_apiVersion-preview');
    if (usersRes.isError) return ApiResponse.error(usersRes);

    _allUsers = GetUsersResponse.fromJson(jsonDecode(usersRes.body) as Map<String, dynamic>).users!;
    return ApiResponse.ok(_allUsers);
  }

  @override
  Future<void> logout() async {
    StorageServiceCore().clear();
    _organization = '';
    _chosenProjects = null;
    _allUsers.clear();
    _user = null;
    dispose();
  }
}

class AzureApiServiceInherited extends InheritedWidget {
  const AzureApiServiceInherited({
    super.key,
    required super.child,
    required this.apiService,
  });

  final AzureApiService apiService;

  static AzureApiServiceInherited of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AzureApiServiceInherited>()!;
  }

  @override
  bool updateShouldNotify(covariant InheritedWidget oldWidget) {
    return false;
  }
}

enum LoginStatus {
  ok,
  failed,
  orgNotSet,
  projectsNotSet,
  unauthorized,
}

class ApiResponse<T extends Object?> {
  ApiResponse({
    required this.isError,
    required this.data,
    required this.errorResponse,
  });

  ApiResponse.ok(this.data)
      : isError = false,
        errorResponse = null;

  ApiResponse.error(this.errorResponse)
      : isError = true,
        data = null;

  final bool isError;
  final T? data;
  final Response? errorResponse;

  ApiResponse<T> copyWith({
    bool? isError,
    T? data,
    Response? errorResponse,
  }) {
    return ApiResponse<T>(
      isError: isError ?? this.isError,
      data: data ?? this.data,
      errorResponse: errorResponse ?? this.errorResponse,
    );
  }
}

class FileDetailResponse {
  FileDetailResponse({
    required this.content,
    required this.isBinary,
  });

  final String content;
  final bool isBinary;
}
