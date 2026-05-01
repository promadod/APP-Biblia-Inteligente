import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bible_summary_parser.dart';

final bibleSummaryListProvider = FutureProvider<List<BibleBookSummary>>((ref) async {
  final raw = await rootBundle.loadString('resumobiblia.md');
  return parseResumoBiblia(raw);
});
