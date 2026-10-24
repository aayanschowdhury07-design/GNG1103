import 'package:clinicflow_core/clinicflow_core.dart';
import 'package:flutter/material.dart';

import 'session.dart';

/// Hands the backend and the session to every screen below it.
class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.backend, required this.session, required super.child});
  final ClinicFlowBackend backend;
  final PatientSession session;

  static AppScope of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!;

  @override
  bool updateShouldNotify(AppScope old) => backend != old.backend || session != old.session;
}

extension AppContext on BuildContext {
  ClinicFlowBackend get backend => AppScope.of(this).backend;
  PatientSession get session => AppScope.of(this).session;
  BookingDraft get draft => AppScope.of(this).session.draft;
  Strings get s => AppScope.of(this).session.s;
  String get lang => AppScope.of(this).session.lang;
  CfColors get colors => CfColors.of(this);
  TextTheme get text => Theme.of(this).textTheme;
}

/// Rebuilds [builder] whenever the backend data, the session or the booking draft changes,
/// the way a screen subscribed to Firestore would.
class Watch extends StatelessWidget {
  const Watch({super.key, required this.builder});
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([scope.backend, scope.session, scope.session.draft]),
      builder: (context, _) => builder(context),
    );
  }
}
