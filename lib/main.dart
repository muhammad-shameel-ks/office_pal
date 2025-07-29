import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'features/auth/presentation/pages/login_page.dart';
import 'features/superintendent/presentation/pages/superintendent_dashboard_page.dart';
import 'features/controller/presentation/pages/controller_dashboard_page.dart';
import 'features/superintendent/presentation/pages/seating_management_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  String? supabaseUrl = const String.fromEnvironment('SUPABASE_URL');
  String? supabaseAnonKey = const String.fromEnvironment('SUPABASE_ANON_KEY');

  // If not available from --dart-define (empty string), then use dotenv (for local dev)
  // This check is important for local development where secrets are loaded from .env
  if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
    // Load .env file only if running locally and dart-defines are not set
    await dotenv.load(fileName: ".env"); // The .env file is now at the root
    supabaseUrl = dotenv.env['SUPABASE_URL'];
    supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'];
  }

  if (supabaseUrl!.isEmpty || supabaseAnonKey!.isEmpty) {
    throw Exception(
        'ERROR: Supabase URL or Anon Key is null or empty. Ensure secrets are set for GitHub Actions and .env for local dev.');
  }

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );

  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // Simulate some initialization time
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Office Pal',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      // Define named routes
      routes: {
        '/': (context) =>
            _isLoading ? const LoadingScreen() : const AuthWrapper(),
        '/login': (context) => const LoginPage(),
        '/superintendent': (context) => const SuperintendentDashboardPage(),
        '/superintendent/dashboard': (context) =>
            const SuperintendentDashboardPage(),
        '/controller': (context) => const ControllerDashboardPage(),
        '/seating_management': (context) => const SeatingManagementPage(),
      },
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  late Future<Session?> _sessionFuture;

  @override
  void initState() {
    super.initState();
    _sessionFuture = Future.value(Supabase.instance.client.auth.currentSession);
  }

  Widget _handleAuthState(Session? session) {
    if (session == null) {
      return const LoginPage();
    }

    final userEmail = session.user.email?.toLowerCase() ?? '';

    if (userEmail.isEmpty) {
      return const LoginPage();
    }

    if (userEmail.contains('superintendent')) {
      return const SuperintendentDashboardPage();
    } else if (userEmail.contains('controller')) {
      return const ControllerDashboardPage();
    }

    return const LoginPage();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Session?>(
      future: _sessionFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingScreen();
        }

        // Once we have the initial state, start listening to auth changes
        return StreamBuilder<AuthState>(
          stream: Supabase.instance.client.auth.onAuthStateChange,
          builder: (context, streamSnapshot) {
            // For sign out, we want to use the stream data only
            final session = streamSnapshot.data?.session;
            return _handleAuthState(session);
          },
        );
      },
    );
  }
}

class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.blue.shade100,
              Colors.blue.shade50,
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              LoadingAnimationWidget.staggeredDotsWave(
                color: Colors.blue,
                size: 50,
              ),
              const SizedBox(height: 24),
              const Text(
                'Office Pal',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Loading...',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.blue.shade700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


// superintendent@examination.com