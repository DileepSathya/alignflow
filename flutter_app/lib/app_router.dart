import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'admin_workspace.dart';
import 'cad_orders_page.dart';
import 'clinic_signup.dart';
import 'clinic_workspace.dart';
import 'lab_orders_page.dart';
import 'main.dart' show LoginPage;
import 'marketing_page.dart';
import 'orders_page.dart';
import 'qc_orders_page.dart';
import 'team_page.dart';

class AppRoutePath {
  final String path;
  const AppRoutePath(this.path);
}

class AppRouteParser extends RouteInformationParser<AppRoutePath> {
  @override
  Future<AppRoutePath> parseRouteInformation(
          RouteInformation information) async =>
      AppRoutePath(information.uri.toString());

  @override
  RouteInformation? restoreRouteInformation(AppRoutePath configuration) =>
      RouteInformation(uri: Uri.parse(configuration.path));
}

class AppRouter extends RouterDelegate<AppRoutePath>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<AppRoutePath> {
  AppRouter(this.api) {
    _restore();
  }

  final Api api;
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  Map<String, dynamic>? user;
  bool loading = true;
  String path = '/';
  Completer<void>? _detailClosed;

  static AppRouter of(BuildContext context) =>
      Router.of(context).routerDelegate as AppRouter;

  static String baseFor(String role) => switch (role) {
        'admin' => '/admin/orders',
        'marketing' => '/marketing/orders',
        'clinic_admin' || 'clinician' => '/clinic/dashboard',
        'planning' => '/planning/orders',
        'production' => '/production/orders',
        _ => '/scanner/orders',
      };

  Future<void> _restore() async {
    await api.restore();
    if (api.token != null) {
      try {
        user = await api.me();
      } catch (_) {
        await api.logout();
      }
    }
    if (user != null && (path == '/' || path == '/login')) {
      path = baseFor(user!['role'] as String);
    }
    loading = false;
    notifyListeners();
  }

  void login(Map<String, dynamic> value) {
    user = value;
    final role = value['role'] as String;
    final prefix =
        role == 'clinic_admin' || role == 'clinician' ? '/clinic/' : '/$role/';
    if (!path.startsWith(prefix)) path = baseFor(role);
    notifyListeners();
  }

  void logout() {
    user = null;
    path = '/login';
    notifyListeners();
  }

  void go(String newPath) {
    if (path == newPath) return;
    _finishDetail();
    path = newPath;
    notifyListeners();
  }

  Future<void> openOrder(String orderId, {bool qcMode = false}) {
    final role = user!['role'] as String;
    final prefix =
        role == 'clinic_admin' || role == 'clinician' ? '/clinic/' : '/$role/';
    final currentPath = Uri.parse(path).path;
    final section = currentPath.startsWith('/planning/qc')
        ? '/planning/qc'
        : currentPath.startsWith(prefix)
            ? currentPath
            : baseFor(role);
    _detailClosed = Completer<void>();
    path =
        '$section/order/${Uri.encodeComponent(orderId)}${qcMode ? '/qc' : ''}';
    notifyListeners();
    return _detailClosed!.future;
  }

  void _finishDetail() {
    if (_detailClosed != null && !_detailClosed!.isCompleted) {
      _detailClosed!.complete();
    }
    _detailClosed = null;
  }

  @override
  AppRoutePath get currentConfiguration => AppRoutePath(path);

  @override
  Future<void> setNewRoutePath(AppRoutePath configuration) async {
    _finishDetail();
    path = configuration.path;
    notifyListeners();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Navigator(
          key: navigatorKey,
          pages: const [
            MaterialPage<void>(
                child:
                    Scaffold(body: Center(child: CircularProgressIndicator())))
          ],
          onDidRemovePage: (_) {});
    }
    if (user == null) {
      return Navigator(
          key: navigatorKey,
          pages: [
            MaterialPage<void>(
                key: const ValueKey('login'),
                child: LoginPage(api: api, onLogin: login)),
            if (path == '/signup')
              MaterialPage<void>(
                  key: const ValueKey('signup'),
                  child: ClinicSignupPage(api: api))
          ],
          onDidRemovePage: (page) {
            if (page.key == const ValueKey('signup') && path == '/signup') {
              path = '/login';
              notifyListeners();
            }
          });
    }

    final role = user!['role'] as String;
    final allowedPrefix = switch (role) {
      'clinic_admin' || 'clinician' => '/clinic/',
      _ => '/$role/',
    };
    final routeUri = Uri.parse(path);
    var effectivePath = routeUri.path;
    if (!effectivePath.startsWith(allowedPrefix)) effectivePath = baseFor(role);
    final parts = effectivePath.split('/');
    final orderIndex = parts.indexOf('order');
    final sectionPath = orderIndex >= 0
        ? '/${parts.sublist(1, orderIndex).join('/')}'
        : effectivePath;
    final validSections = switch (role) {
      'admin' => [
          '/admin/orders',
          '/admin/planning',
          '/admin/users',
          '/admin/clinics',
          '/admin/performance'
        ],
      'marketing' => ['/marketing/orders', '/marketing/clinics'],
      'clinic_admin' => [
          '/clinic/dashboard',
          '/clinic/orders',
          '/clinic/clinicians'
        ],
      'clinician' => ['/clinic/dashboard', '/clinic/orders'],
      'planning' => ['/planning/orders', '/planning/qc'],
      'production' => ['/production/orders'],
      _ => ['/scanner/orders'],
    };
    final safeSection =
        validSections.contains(sectionPath) ? sectionPath : baseFor(role);
    final orderId = orderIndex >= 0 &&
            orderIndex + 1 < parts.length &&
            validSections.contains(sectionPath)
        ? Uri.decodeComponent(parts[orderIndex + 1])
        : null;
    final workspace = switch (role) {
      'admin' => AdminWorkspace(
          api: api,
          user: user!,
          onLogout: logout,
          initialSection: const {
            '/admin/orders': 'All orders',
            '/admin/planning': 'Planning',
            '/admin/users': 'Users',
            '/admin/clinics': 'Clinics',
            '/admin/performance': 'Performance'
          }[safeSection]!),
      'marketing' => MarketingPage(
          api: api,
          user: user!,
          onLogout: logout,
          initialSection:
              safeSection == '/marketing/clinics' ? 'Clinics' : 'Orders'),
      'clinic_admin' || 'clinician' => ClinicWorkspace(
          api: api,
          user: user!,
          onLogout: logout,
          initialFilters: safeSection == '/clinic/orders'
              ? routeUri.queryParameters : const {},
          initialSection: const {
            '/clinic/dashboard': 'Dashboard',
            '/clinic/orders': 'Orders',
            '/clinic/clinicians': 'Clinicians'
          }[safeSection]!),
      'planning' when safeSection == '/planning/qc' =>
        QcOrdersPage(api: api, user: user!, onLogout: logout),
      'planning' => CadOrdersPage(api: api, user: user!, onLogout: logout),
      'production' => LabOrdersPage(api: api, user: user!, onLogout: logout),
      _ => TeamPage(api: api, user: user!, onLogout: logout),
    };
    return Navigator(
      key: navigatorKey,
      pages: [
        MaterialPage<void>(key: ValueKey(safeSection), child: workspace),
        if (orderId != null)
          MaterialPage<void>(
              key: ValueKey('order:$orderId'),
              child: OrderDetailPage(
                  api: api,
                  orderId: orderId,
                  role: role,
                  userId: role == 'admin' ||
                          (role == 'planning' && safeSection != '/planning/qc')
                      ? user!['id'] as int
                      : null,
                  qcMode: parts.last == 'qc')),
      ],
      onDidRemovePage: (page) {
        if (orderId != null &&
            page.key == ValueKey('order:$orderId') &&
            path.contains('/order/')) {
          _finishDetail();
          path = safeSection;
          notifyListeners();
        }
      },
    );
  }
}
