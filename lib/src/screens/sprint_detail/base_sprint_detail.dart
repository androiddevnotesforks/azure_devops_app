library sprint_detail;

import 'package:azure_devops/src/extensions/context_extension.dart';
import 'package:azure_devops/src/mixins/filter_mixin.dart';
import 'package:azure_devops/src/models/board.dart';
import 'package:azure_devops/src/models/processes.dart';
import 'package:azure_devops/src/models/sprint.dart';
import 'package:azure_devops/src/models/user.dart';
import 'package:azure_devops/src/models/work_items.dart';
import 'package:azure_devops/src/router/router.dart';
import 'package:azure_devops/src/services/azure_api_service.dart';
import 'package:azure_devops/src/theme/dev_ops_icons_icons.dart';
import 'package:azure_devops/src/widgets/app_base_page.dart';
import 'package:azure_devops/src/widgets/app_page.dart';
import 'package:azure_devops/src/widgets/board_widget.dart';
import 'package:azure_devops/src/widgets/filter_menu.dart';
import 'package:azure_devops/src/widgets/popup_menu.dart';
import 'package:azure_devops/src/widgets/search_field.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

part 'components_sprint_detail.dart';
part 'controller_sprint_detail.dart';
part 'screen_sprint_detail.dart';

typedef _SprintDetailParameters = ();

class SprintDetailPage extends StatelessWidget {
  const SprintDetailPage();

  static const _SprintDetailParameters _smartphoneParameters = ();
  static const _SprintDetailParameters _tabletParameters = ();

  @override
  Widget build(BuildContext context) {
    final args = AppRouter.getSprintDetailArgs(context);
    return AppBasePage(
      initState: () => _SprintDetailController._(context.api, args),
      smartphone: (ctrl) => _SprintDetailScreen(ctrl, _smartphoneParameters),
      tablet: (ctrl) => _SprintDetailScreen(ctrl, _tabletParameters),
    );
  }
}
