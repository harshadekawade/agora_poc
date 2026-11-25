import 'package:flutter/material.dart';

import 'chat_sheet.dart';
import 'event_log_sheet.dart';
import 'more_actions_sheet.dart';
import 'participants_sheet.dart';
import 'quality_sheet.dart';

/// Entry points for every call bottom sheet, so screens don't repeat the
/// sheet setup.
Future<void> _showSheet(
  BuildContext context,
  Widget child, {
  bool isTall = false,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: isTall,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => child,
);

Future<void> showMoreActionsSheet(BuildContext context) =>
    _showSheet(context, const MoreActionsSheet(), isTall: true);

Future<void> showParticipantsSheet(BuildContext context) =>
    _showSheet(context, const ParticipantsSheet(), isTall: true);

Future<void> showChatSheet(BuildContext context) =>
    _showSheet(context, const ChatSheet(), isTall: true);

Future<void> showEventLogSheet(BuildContext context) =>
    _showSheet(context, const EventLogSheet(), isTall: true);

Future<void> showQualitySheet(BuildContext context) =>
    _showSheet(context, const QualitySheet());
