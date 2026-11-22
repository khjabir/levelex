import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:path_provider/path_provider.dart';

/// Runs ML Kit pose detection (stream mode, like the app) over every frame
/// sequence pushed to `files/frames/SEQUENCE/f_*.png` and writes
/// `SEQUENCE/pose_MODEL.jsonl`, one line per frame.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: ProbePage()));
}

class ProbePage extends StatefulWidget {
  const ProbePage({super.key});

  @override
  State<ProbePage> createState() => _ProbePageState();
}

class _ProbePageState extends State<ProbePage> {
  String _status = 'starting';

  @override
  void initState() {
    super.initState();
    _run();
  }

  void _say(String s) {
    // ignore: avoid_print
    print('[probe] $s');
    if (mounted) setState(() => _status = s);
  }

  Future<void> _run() async {
    final root = Directory('${(await getApplicationSupportDirectory()).path}/frames');
    final done = File('${root.path}/done.txt');
    if (done.existsSync()) done.deleteSync();
    var models = ['base'];
    final config = File('${root.path}/config.json');
    if (config.existsSync()) {
      models = (jsonDecode(config.readAsStringSync())['models'] as List).cast<String>();
    }
    final seqs = root.listSync().whereType<Directory>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final model in models) {
      for (final seq in seqs) {
        final out = File('${seq.path}/pose_$model.jsonl');
        if (out.existsSync()) continue;
        final frames = seq.listSync().whereType<File>()
            .where((f) => f.path.endsWith('.png')).toList()
          ..sort((a, b) => a.path.compareTo(b.path));
        final detector = PoseDetector(
          options: PoseDetectorOptions(
            mode: PoseDetectionMode.stream,
            model: model == 'accurate'
                ? PoseDetectionModel.accurate
                : PoseDetectionModel.base,
          ),
        );
        final sink = StringBuffer();
        final sw = Stopwatch()..start();
        var found = 0;
        for (final f in frames) {
          final poses = await detector.processImage(InputImage.fromFilePath(f.path));
          if (poses.isEmpty) {
            sink.writeln('{}');
            continue;
          }
          found++;
          final lm = <String, List<double>>{};
          poses.first.landmarks.forEach((type, l) {
            lm[type.name] = [l.x, l.y, l.z, l.likelihood];
          });
          sink.writeln(jsonEncode(lm));
        }
        await detector.close();
        out.writeAsStringSync(sink.toString());
        _say('${seq.path.split('/').last} [$model]: $found/${frames.length} '
            'frames with a pose, ${sw.elapsedMilliseconds ~/ frames.length} ms/frame');
      }
    }
    done.writeAsStringSync('ok');
    _say('done');
  }

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text(_status)));
}
