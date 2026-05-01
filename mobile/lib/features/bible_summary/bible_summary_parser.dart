/// Modelo de um livro (ou bloco introdutório) para o ecrã de resumos.
class BibleBookSummary {
  const BibleBookSummary({required this.title, required this.markdown});

  final String title;
  final String markdown;
}

int _prevNonEmptyIdx(List<String> lines, int start) {
  var i = start;
  while (i >= 0 && lines[i].trim().isEmpty) {
    i--;
  }
  return i;
}

/// Destaca referências entre parênteses que contêm capítulo:versículo.
String highlightBiblicalRefs(String text) {
  return text.replaceAllMapped(
    RegExp(r'\(([^)\n]{3,120})\)'),
    (m) {
      final inner = m[1]!;
      if (RegExp(r'\d+\s*:\s*\d').hasMatch(inner)) {
        return '**($inner)**';
      }
      return '($inner)';
    },
  );
}

String _structureHeadings(String raw) {
  final out = StringBuffer();
  for (final line in raw.split('\n')) {
    final t = line.trim();
    if (t == 'Resumo Executivo') {
      out.writeln('## Resumo Executivo');
    } else if (t.startsWith('Acontecimentos Principais')) {
      out.writeln('## $t');
    } else if (t.startsWith('Personagens de Destaque')) {
      out.writeln('## $t');
    } else if (t.startsWith('Acontecimentos Principais e Temas')) {
      out.writeln('## $t');
    } else if (t.startsWith('Acontecimentos Principais e Estrutura')) {
      out.writeln('## $t');
    } else {
      out.writeln(line);
    }
  }
  return out.toString();
}

/// Descobre o índice da primeira linha do bloco do livro cuja secção [resumoLineIdx] contém "Resumo Executivo".
int _bookBlockStart(List<String> lines, int resumoLineIdx) {
  final nameIdx = _prevNonEmptyIdx(lines, resumoLineIdx - 1);
  if (nameIdx < 0) return 0;
  final cur = lines[nameIdx].trim();
  if (nameIdx > 0) {
    final prev = lines[nameIdx - 1].trim();
    if (prev.isNotEmpty &&
        cur.startsWith(prev) &&
        cur != prev &&
        prev.length <= 24) {
      return nameIdx - 1;
    }
  }
  return nameIdx;
}

String _displayTitle(List<String> lines, int blockStart, int nameIdx) {
  final first = lines[blockStart].trim();
  final name = lines[nameIdx].trim();
  if (blockStart < nameIdx && name.startsWith(first) && name != first) {
    return first;
  }
  return name;
}

/// Remove linhas iniciais duplicadas do título já incluídas como `#` no markdown.
String _stripLeadingTitleLines(String raw, int titleLineCount) {
  final ls = raw.split('\n');
  if (titleLineCount <= 0 || ls.length <= titleLineCount) return raw;
  return ls.sublist(titleLineCount).join('\n').trimLeft();
}

/// Parse do ficheiro [resumobiblia.md] (texto integral).
List<BibleBookSummary> parseResumoBiblia(String raw) {
  final lines = raw.split(RegExp(r'\r?\n'));
  final resumoIdx = <int>[];
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].trim() == 'Resumo Executivo') {
      resumoIdx.add(i);
    }
  }
  if (resumoIdx.isEmpty) {
    return [
      BibleBookSummary(
        title: 'Resumo bíblico',
        markdown: '# Resumo\n\n${highlightBiblicalRefs(raw)}',
      ),
    ];
  }

  final out = <BibleBookSummary>[];

  final firstStart = _bookBlockStart(lines, resumoIdx.first);
  if (firstStart > 0) {
    final intro = lines.sublist(0, firstStart).join('\n').trim();
    if (intro.isNotEmpty) {
      final body = highlightBiblicalRefs(_structureHeadings(intro));
      out.add(
        BibleBookSummary(
          title: 'Introdução',
          markdown: '# Introdução\n\n$body',
        ),
      );
    }
  }

  for (var r = 0; r < resumoIdx.length; r++) {
    final resLine = resumoIdx[r];
    final blockStart = _bookBlockStart(lines, resLine);
    final nameIdx = _prevNonEmptyIdx(lines, resLine - 1);
    final title = _displayTitle(lines, blockStart, nameIdx);
    final nextStart =
        r + 1 < resumoIdx.length ? _bookBlockStart(lines, resumoIdx[r + 1]) : lines.length;

    var slice = lines.sublist(blockStart, nextStart).join('\n');
    final titleLines = nameIdx - blockStart + 1;
    slice = _stripLeadingTitleLines(slice, titleLines);

    final structured = _structureHeadings(slice);
    final md = '# $title\n\n${highlightBiblicalRefs(structured)}';
    out.add(BibleBookSummary(title: title, markdown: md));
  }

  return out;
}
