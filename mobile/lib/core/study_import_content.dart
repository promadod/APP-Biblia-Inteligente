/// Texto formatado para gravar um resultado da [Busca] como estudo.
String formatSearchStudyContent(String query, Map<String, dynamic> data) {
  final buf = StringBuffer();
  buf.writeln('Consulta: $query');
  buf.writeln();

  final narrative = data['narrative'] as String?;
  if (narrative != null && narrative.trim().isNotEmpty) {
    buf.writeln('Narrativa');
    buf.writeln(narrative.trim());
    buf.writeln();
  }

  final verses = (data['verses'] as List?) ?? [];
  if (verses.isNotEmpty) {
    buf.writeln('Versículos (${verses.length})');
    buf.writeln();
    for (final v in verses) {
      final m = v as Map<String, dynamic>;
      final ref = '${m['book'] ?? ''} ${m['chapter_number'] ?? ''}:${m['number'] ?? ''}'.trim();
      buf.writeln('• $ref');
      buf.writeln(m['text'] ?? '');
      buf.writeln();
    }
  }

  return buf.toString().trim();
}

/// Título curto para estudo importado da busca.
String titleForSearchStudy(String query) {
  final q = query.trim();
  if (q.length <= 48) return 'Busca: $q';
  return 'Busca: ${q.substring(0, 45)}…';
}
