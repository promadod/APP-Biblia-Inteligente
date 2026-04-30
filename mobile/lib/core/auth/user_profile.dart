/// Utilizador autenticado localmente (cadastro no dispositivo).
class UserProfile {
  const UserProfile({
    required this.username,
    required this.fullName,
    required this.age,
  });

  final String username;
  final String fullName;
  final int age;
}
