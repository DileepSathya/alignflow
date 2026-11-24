import 'package:flutter/material.dart';
import 'api.dart';
import 'demo_style.dart';
import 'app_router.dart';

void main() => runApp(const AlignFlowApp());

class AlignFlowApp extends StatefulWidget {
  const AlignFlowApp({super.key});
  @override
  State<AlignFlowApp> createState() => _AlignFlowAppState();
}

class _AlignFlowAppState extends State<AlignFlowApp> {
  final api = Api();
  late final AppRouter router = AppRouter(api);

  @override
  void dispose() {
    router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: 'AlignFlow',
        debugShowCheckedModeBanner: false,
        theme: DemoStyle.theme(),
        routerDelegate: router,
        routeInformationParser: AppRouteParser(),
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
  bool showServer = false;
  String? error;

  @override
  void dispose() {
    server.dispose();
    username.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (username.text.trim().isEmpty || password.text.isEmpty) {
      setState(() => error = 'Enter your username and password.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.api.useServer(server.text);
      await widget.api.checkServer();
      widget
          .onLogin(await widget.api.login(username.text.trim(), password.text));
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
            child: SingleChildScrollView(
                child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Card(
              elevation: 0,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 26, vertical: 28),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Brand(),
                      const SizedBox(height: 22),
                      Text('Log in',
                          style: Theme.of(context).textTheme.headlineMedium),
                      const SizedBox(height: 4),
                      const Text(
                          'Sign in with the username and password given by your admin.',
                          style: TextStyle(color: DemoStyle.muted)),
                      const SizedBox(height: 20),
                      if (showServer) ...[
                        TextField(
                            controller: server,
                            decoration: const InputDecoration(
                              labelText: 'Server IP address',
                              hintText: '192.168.1.25:8000',
                              helperText:
                                  'Enter the PC IP and API port (usually 8000)',
                            ),
                            keyboardType: TextInputType.url,
                            textInputAction: TextInputAction.next),
                        const SizedBox(height: 14),
                      ],
                      const SizedBox(height: 14),
                      TextField(
                          controller: username,
                          decoration:
                              const InputDecoration(labelText: 'Username'),
                          textInputAction: TextInputAction.next),
                      const SizedBox(height: 14),
                      TextField(
                          controller: password,
                          decoration:
                              const InputDecoration(labelText: 'Password'),
                          obscureText: true,
                          onSubmitted: (_) => submit()),
                      if (error != null)
                        Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(error!,
                                style: const TextStyle(color: Colors.red))),
                      const SizedBox(height: 18),
                      FilledButton(
                          onPressed: busy ? null : submit,
                          child: Text(busy ? 'Signing in...' : 'Log in')),
                      TextButton(
                          onPressed: busy
                              ? null
                              : () async {
                                  await widget.api.useServer(server.text);
                                  if (context.mounted) {
                                    AppRouter.of(context).go('/signup');
                                  }
                                },
                          child: const Text('Register your clinic')),
                      const SizedBox(height: 14),
                      TextButton(
                          onPressed: () =>
                              setState(() => showServer = !showServer),
                          child: Text(showServer
                              ? 'Hide server settings'
                              : 'Server settings')),
                    ]),
              )),
        ))),
      );
}

class Brand extends StatelessWidget {
  const Brand({super.key});
  @override
  Widget build(BuildContext context) => Row(children: [
        const DemoBrandMark(),
        const SizedBox(width: 10),
        const Text('AlignFlow',
            style: TextStyle(
                fontFamily: 'Bricolage',
                fontSize: 22,
                fontWeight: FontWeight.bold)),
      ]);
}

class TeamLanding extends StatelessWidget {
  final Map<String, dynamic> user;
  final Api api;
  final VoidCallback onLogout;
  const TeamLanding(
      {super.key,
      required this.user,
      required this.api,
      required this.onLogout});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Brand(), actions: [
          TextButton(
              onPressed: () async {
                await api.logout();
                onLogout();
              },
              child: const Text('Log out'))
        ]),
        body: Center(
            child: Text(
                'Welcome, ${user['name']}. Your team workspace is coming in a later phase.')),
      );
}
