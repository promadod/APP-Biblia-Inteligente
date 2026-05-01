/// Utilizador autenticado localmente (cadastro no dispositivo).
class UserProfile {
  const UserProfile({
    required this.username,
    required this.fullName,
    required this.age,
    this.apiToken,
    this.learningGroupSlug,
  });

  final String username;
  final String fullName;
  final int age;

  /// Token devolvido pelo backend (`POST /api/auth/login|register`); necessário para estudos coletivos.
  final String? apiToken;

  /// Ex.: `alunos`, `professores`.
  final String? learningGroupSlug;

  bool get isProfessor => learningGroupSlug == 'professores';
}
