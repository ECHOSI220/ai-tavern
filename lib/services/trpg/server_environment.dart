class ServerEnvironment {
  const ServerEnvironment._();

  static const gameServerUrl = String.fromEnvironment(
    'GAME_SERVER_URL',
    defaultValue: 'https://ai-tavern-game-server.example.workers.dev',
  );
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const environment = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'development',
  );

  static bool get hasProductionServer =>
      !gameServerUrl.contains('.example.') &&
      gameServerUrl.startsWith('https://');
  static bool get hasSupabase =>
      supabaseUrl.startsWith('https://') && supabaseAnonKey.isNotEmpty;
}
