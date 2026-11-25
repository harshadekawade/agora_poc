import 'package:agora_poc/features/call/presentation/layout/call_layout_planner.dart';
import 'package:agora_poc/features/call/presentation/widgets/video_view_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stands in for the native video view: counts how often it is created.
class _FakeVideo extends StatefulWidget {
  const _FakeVideo();

  static int created = 0;

  @override
  State<_FakeVideo> createState() => _FakeVideoState();
}

class _FakeVideoState extends State<_FakeVideo> {
  @override
  void initState() {
    super.initState();
    _FakeVideo.created++;
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

class _KeyedVideo extends StatelessWidget {
  const _KeyedVideo();

  static const tile = CallTile.remote(5);

  @override
  Widget build(BuildContext context) => KeyedSubtree(
    key: VideoViewKeys.of(context, tile),
    child: const _FakeVideo(),
  );
}

void main() {
  setUp(() => _FakeVideo.created = 0);

  Widget app(Widget layout) => Directionality(
    textDirection: TextDirection.ltr,
    child: VideoViewKeys(child: layout),
  );

  testWidgets('a video keeps its view when the layout changes', (tester) async {
    // Grid-like layout…
    await tester.pumpWidget(
      app(const Column(children: [Expanded(child: _KeyedVideo())])),
    );
    // …then a full-bleed one with a different tree.
    await tester.pumpWidget(
      app(
        const Stack(
          children: [
            Positioned.fill(
              child: Padding(padding: EdgeInsets.all(4), child: _KeyedVideo()),
            ),
          ],
        ),
      ),
    );

    expect(_FakeVideo.created, 1);
  });

  testWidgets('outside the call screen there is no key', (tester) async {
    late GlobalKey? key;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          key = VideoViewKeys.of(context, _KeyedVideo.tile);
          return const SizedBox();
        },
      ),
    );

    expect(key, isNull);
  });
}
