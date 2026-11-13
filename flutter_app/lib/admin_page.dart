import 'package:flutter/material.dart';
import 'api.dart';

const roles = {
  'marketing': 'Marketing',
  'cad': 'Clinical CAD',
  'lab': 'Lab / Manufacturing',
  'qc': 'QC',
};

class AdminPage extends StatefulWidget {
  final Api api;
  final Map<String, dynamic> user;
  final VoidCallback onLogout;
  final bool embedded;
  const AdminPage({super.key, required this.api, required this.user, required this.onLogout, this.embedded = false});
  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  List<Map<String, dynamic>> users = [];
  bool loading = true;
  String? error;

  @override
  void initState() { super.initState(); refresh(); }

  Future<void> refresh() async {
    try {
      final data = await widget.api.request('GET', '/api/users');
      if (mounted) setState(() { users = (data['users'] as List).cast<Map<String, dynamic>>(); error = null; });
    } catch (e) { if (mounted) setState(() => error = e.toString()); }
    finally { if (mounted) setState(() => loading = false); }
  }

  Future<void> create() async {
    final created = await showDialog<bool>(context: context, builder: (context) => CreateUserDialog(api: widget.api));
    if (created == true) refresh();
  }

  Future<void> edit(Map<String, dynamic> user) async {
    final updated = await showDialog<bool>(context: context, builder: (context) => CreateUserDialog(api: widget.api, user: user));
    if (updated == true) refresh();
  }

  Future<void> delete(Map<String, dynamic> user) async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Delete user?'),
      content: Text('Delete ${user['name']} (${user['username']})?'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete'))],
    ));
    if (confirmed != true) return;
    try { await widget.api.request('DELETE', '/api/users/${user['id']}'); await refresh(); }
    catch (e) { if (mounted) setState(() => error = e.toString()); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: widget.embedded ? null : AppBar(
      title: const Text('AlignFlow Admin'), backgroundColor: Colors.white,
      actions: [TextButton.icon(onPressed: () async { await widget.api.logout(); widget.onLogout(); }, icon: const Icon(Icons.logout), label: const Text('Log out'))],
    ),
    body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1100), child: Padding(
      padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Users', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
            const Text('Create logins for each team.'),
          ])),
          FilledButton.icon(onPressed: create, icon: const Icon(Icons.add), label: const Text('Create user')),
        ]),
        const SizedBox(height: 20),
        if (error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(error!, style: const TextStyle(color: Colors.red))),
        Expanded(child: Card(child: loading
          ? const Center(child: CircularProgressIndicator())
          : users.isEmpty
            ? const Center(child: Text('No users yet.'))
            : ListView.separated(
                itemCount: users.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final user = users[index];
                  return ListTile(
                    leading: CircleAvatar(child: Text((user['name'] as String).substring(0, 1).toUpperCase())),
                    title: Text(user['name'] as String),
                    subtitle: Text('${user['username']}  •  ${roles[user['role']] ?? 'Admin'}'),
                    trailing: user['role'] == 'admin' ? const Text('Built-in') : Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(tooltip: 'Edit user', icon: const Icon(Icons.edit_outlined), onPressed: () => edit(user)),
                      IconButton(tooltip: 'Delete user', icon: const Icon(Icons.delete_outline), onPressed: () => delete(user)),
                    ]),
                  );
                },
              ))),
      ]),
    ))),
  );
}

class CreateUserDialog extends StatefulWidget {
  final Api api;
  final Map<String, dynamic>? user;
  const CreateUserDialog({super.key, required this.api, this.user});
  @override
  State<CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends State<CreateUserDialog> {
  final name = TextEditingController();
  final username = TextEditingController();
  final password = TextEditingController();
  String? role;
  String? error;
  bool saving = false;

  bool get editing => widget.user != null;

  @override
  void initState() {
    super.initState();
    if (editing) {
      name.text = widget.user!['name'] as String;
      username.text = widget.user!['username'] as String;
      role = widget.user!['role'] as String;
    }
  }

  @override
  void dispose() { name.dispose(); username.dispose(); password.dispose(); super.dispose(); }

  Future<void> save() async {
    if (name.text.trim().isEmpty || username.text.trim().isEmpty || (!editing && password.text.isEmpty) || role == null) {
      setState(() => error = 'Complete all fields.'); return;
    }
    setState(() { saving = true; error = null; });
    try {
      await widget.api.request(editing ? 'PATCH' : 'POST',
        editing ? '/api/users/${widget.user!['id']}' : '/api/users', {
        'name': name.text.trim(), 'username': username.text.trim(), 'role': role,
        if (!editing || password.text.isNotEmpty) 'password': password.text,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) { if (mounted) setState(() => error = e.toString()); }
    finally { if (mounted) setState(() => saving = false); }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(editing ? 'Edit user' : 'Create user'),
    content: SizedBox(width: 420, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: name, decoration: const InputDecoration(labelText: 'Full name')),
      const SizedBox(height: 12),
      TextField(controller: username, decoration: const InputDecoration(labelText: 'Username')),
      const SizedBox(height: 12),
      TextField(controller: password, decoration: InputDecoration(labelText: editing ? 'New password (optional)' : 'Password'), obscureText: true),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(initialValue: role, decoration: const InputDecoration(labelText: 'Team role'),
        items: roles.entries.map((entry) => DropdownMenuItem(value: entry.key, child: Text(entry.value))).toList(),
        onChanged: (value) => setState(() => role = value)),
      if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, style: const TextStyle(color: Colors.red))),
    ]))),
    actions: [TextButton(onPressed: saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: saving ? null : save, child: Text(saving ? 'Saving...' : editing ? 'Save changes' : 'Create user'))],
  );
}
