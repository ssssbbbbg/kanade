import 'package:flutter/material.dart';

import '../l10n/l10n_ext.dart';
import '../src/rust/api/types.dart';
import 'mv_page.dart';
import 'widgets.dart';

class VideoTile extends StatelessWidget {
  const VideoTile(this.video, {super.key});

  final VideoBrief video;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ListTile(
      leading: SizedBox(
        width: 96,
        height: 54,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Cover(video.coverUrl, radius: 8),
            if (video.durationSecs > 0)
              Positioned(
                right: 4,
                bottom: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    formatDuration(Duration(seconds: video.durationSecs)),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      title: Text(
        video.name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Row(
          children: [
            if (!video.uploaded) const QualityBadge('MV'),
            Expanded(
              child: Text(
                [
                  if (video.creator.isNotEmpty) video.creator,
                  if (video.playCount > BigInt.zero)
                    '▶ ${formatCount(l, video.playCount.toInt())}',
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      onTap: () =>
          Navigator.of(context).push(MvPage.route(video.vid, video.name)),
    );
  }
}
