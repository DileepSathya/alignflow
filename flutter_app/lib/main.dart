import 'package:flutter/material.dart';
import 'api.dart';
import 'admin_page.dart';

void main() => runApp(const AlignFlowApp());

const ink = Color(0xFF10242B);
const teal = Color(0xFF0B7A75);
const bg = Color(0xFFF3F6F7);

class AlignFlowApp extends StatefulWidget {
  const AlignFlowApp({super.key});
  @override
  State<AlignFlowApp> createState() => _AlignFlowAppState();
}

class _AlignFlowAppState extends State<AlignFlowApp> {
  final api = Api();
  Map<String, dynamic>? user;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    await api.restore();
    if (api.token != null) {
      try { user = await api.me(); } catch (_) { await api.logout(); }
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'AlignFlow',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme.fromSeed(seedColor: teal, primary: teal, surface: Colors.white),
      textTheme: ThemeData.light().textTheme.apply(bodyColor: ink, displayColor: ink),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      ),
    ),
    home: loading
        ? const Scaffold(body: Center(child: CircularProgressIndicator()))
        : user == null
            ? LoginPage(api: api, onLogin: (value) => setState(() => user = value))
            : user!['role'] == 'admin'
                ? AdminPage(api: api, user: user!, onLogout: () => setState(() => user = null))
                : TeamLanding(user: user!, api: api, onLogout: () => setState(() => user = null)),
  );
}

class LoginPage extends StatefulWidget {
  final Api api;
  final ValueChanged<Map<String, dynamic>> onLogin;
  const LoginPage({super.key, required this.api, required this.onLogin});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  late final server = TextEditingController(text: widget.api.serverAddress);
  final username = TextEditingController();
  final password = TextEditingController();
  bool busy = false;
  String? error;

  @override
  void dispose() { server.dispose(); username.dispose(); password.dispose(); super.dispose(); }

  Future<void> submit() async {
    if (username.text.trim().isEmpty || password.text.isEmpty) {
      setState(() => error = 'Enter your username and password.'); return;
    }
    setState(() { busy = true; error = null; });
    try {
      await widget.api.useServer(server.text);
      await widget.api.checkServer();
      widget.onLogin(await widget.api.login(username.text.trim(), password.text));
    }
    catch (e) { if (mounted) setState(() => error = e.toString()); }
    finally { if (mounted) setState(() => busy = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(child: SingleChildScrollView(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Card(elevation: 4, child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          const Brand(), const SizedBox(height: 26),
          Text('Log in', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text('Sign in with the username and password given by your admin.'),
          const SizedBox(height: 22),
          TextField(controller: server, decoration: const InputDecoration(
            labelText: 'Server IP address', hintText: '192.168.1.25:8000',
            helperText: 'Enter the PC IP and API port (usually 8000)',
          ), keyboardType: TextInputType.url, textInputAction: TextInputAction.next),
          const SizedBox(height: 14),
          TextField(controller: username, decoration: const InputDecoration(labelText: 'Username'), textInputAction: TextInputAction.next),
          const SizedBox(height: 14),
          TextField(controller: password, decoration: const InputDecoration(labelText: 'Password'), obscureText: true, onSubmitted: (_) => submit()),
          if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, style: const TextStyle(color: Colors.red))),
          const SizedBox(height: 18),
          FilledButton(onPressed: busy ? null : submit, child: Text(busy ? 'Signing in...' : 'Log in')),
        ]),
      )),
    ))),
  );
}

class Brand extends StatelessWidget {
  const Brand({super.key});
  @override
  Widget build(BuildContext context) => Row(children: [
    Container(width: 38, height: 38, decoration: BoxDecoration(color: teal, borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.waves, color: Colors.white)),
    const SizedBox(width: 10), const Text('AlignFlow', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
  ]);
}

class TeamLanding extends StatelessWidget {
  final Map<String, dynamic> user;
  final Api api;
  final VoidCallback onLogout;
  const TeamLanding({super.key, required this.user, required this.api, required this.onLogout});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Brand(), actions: [TextButton(onPressed: () async { await api.logout(); onLogout(); }, child: const Text('Log out'))]),
    body: Center(child: Text('Welcome, ${user['name']}. Your team workspace is coming in a later phase.')),
  );
}
