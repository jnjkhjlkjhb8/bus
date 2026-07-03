part of '../view/search_screen.dart';

class _SearchResultRow extends StatelessWidget {
  const _SearchResultRow({
    required this.result,
    required this.transportType,
    required this.onTap,
  });

  final SearchResult result;
  final TransportType transportType;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget leadingWidget;
    if (result.type == SearchResultType.busRoute) {
      leadingWidget = Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: cs.onSurface,
          borderRadius: BorderRadius.circular(4),
        ),
        alignment: Alignment.center,
        child: Text(
          result.uid,
          style: TextStyle(
            color: cs.surface,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    } else if (result.type == SearchResultType.mrtStation) {
      final code = result.uid;
      final mrtColor = mrtLineColor(code, cs);
      final lineName = mrtLineLabel(code);

      leadingWidget = Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: mrtColor,
          borderRadius: BorderRadius.circular(4),
        ),
        alignment: Alignment.center,
        child: Text(
          lineName,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    } else {
      leadingWidget = SizedBox(
        width: 36,
        child: Center(
          child: TransportIcon(type: transportType, size: 22),
        ),
      );
    }

    return Pressable(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 62),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: cs.brightness == Brightness.light
              ? Colors.white
              : cs.surfaceContainerLow,
        ),
        child: Row(
          children: [
            leadingWidget,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                      height: 1.3,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    result.subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: cs.onSurfaceVariant,
                      height: 1.3,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              size: 24,
              color: cs.outline,
            ),
          ],
        ),
      ),
    );
  }
}
