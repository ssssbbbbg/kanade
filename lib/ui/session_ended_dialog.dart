import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../src/rust/api/types.dart';
import 'kanade_dialog.dart';
import 'sheet.dart';

/// 登录凭证失效、已自动退出时的提示。返回 true 表示用户要去重新登录。
Future<bool> showSessionEndedDialog(
  BuildContext context,
  SessionEndReason reason,
) async {
  final relogin = await showKanadeDialog<bool>(
    context,
    builder: (context) {
      final l = AppLocalizations.of(context);
      final causes = switch (reason) {
        SessionEndReason.expired => const <(IconData, String)>[],
        SessionEndReason.revoked => [
          (Icons.devices_rounded, l.sessionCauseOtherDevice),
          (Icons.phonelink_erase_rounded, l.sessionCauseDeviceRemoved),
          (Icons.key_rounded, l.sessionCausePassword),
        ],
        SessionEndReason.unknown => [
          (Icons.schedule_rounded, l.sessionCauseExpired),
          (Icons.devices_rounded, l.sessionCauseOtherDevice),
          (Icons.phonelink_erase_rounded, l.sessionCauseDeviceRemoved),
        ],
      };
      return KanadeDialog(
        icon: reason == SessionEndReason.expired
            ? Icons.schedule_rounded
            : Icons.link_off_rounded,
        title: l.sessionEndedTitle,
        message: switch (reason) {
          SessionEndReason.expired => l.sessionExpired,
          SessionEndReason.revoked => l.sessionRevoked,
          SessionEndReason.unknown => l.sessionRejected,
        },
        content: causes.isEmpty ? null : _Causes(causes),
        actions: [
          KanadeDialogAction(
            label: l.loginAgain,
            primary: true,
            onPressed: () => Navigator.of(context).pop(true),
          ),
          KanadeDialogAction(
            label: l.later,
            onPressed: () => Navigator.of(context).pop(false),
          ),
        ],
      );
    },
  );
  return relogin ?? false;
}

/// 服务器不说明原因，只能列出可能的情况。
class _Causes extends StatelessWidget {
  const _Causes(this.causes);

  final List<(IconData, String)> causes;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final (_, fill) = sheetColors(scheme);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.sessionCausesTitle,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          for (final (icon, text) in causes)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 18, color: scheme.onSurface),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      text,
                      style: const TextStyle(fontSize: 13.5, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
