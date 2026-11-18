import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PageFrame extends StatelessWidget {
  const PageFrame({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 900),
      child: Padding(padding: padding, child: child),
    ),
  );
}

class AsyncPanel<T> extends StatelessWidget {
  const AsyncPanel({
    super.key,
    required this.value,
    required this.data,
    this.onRetry,
  });
  final AsyncValue<T> value;
  final Widget Function(T) data;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => value.when(
    data: data,
    loading: () => const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: CircularProgressIndicator(),
      ),
    ),
    error: (error, _) => Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 40),
            const SizedBox(height: 12),
            Text(
              'Could not load data. Check your connection and try again.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            if (onRetry != null)
              TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    ),
  );
}

void showError(BuildContext context, Object error) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        error
            .toString()
            .replaceFirst('PostgrestException(message: ', '')
            .split(', code:')
            .first,
      ),
    ),
  );
}

void showMessage(BuildContext context, String message) {
  if (context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class ConnectivityBanner extends StatefulWidget {
  const ConnectivityBanner({super.key});
  @override
  State<ConnectivityBanner> createState() => _ConnectivityBannerState();
}

class _ConnectivityBannerState extends State<ConnectivityBanner> {
  bool offline = false;
  late final StreamSubscription<List<ConnectivityResult>> subscription;
  @override
  void initState() {
    super.initState();
    Connectivity().checkConnectivity().then(_update);
    subscription = Connectivity().onConnectivityChanged.listen(_update);
  }

  void _update(List<ConnectivityResult> results) {
    if (mounted) {
      setState(() => offline = results.contains(ConnectivityResult.none));
    }
  }

  @override
  void dispose() {
    subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!offline) return const SizedBox.shrink();
    return MaterialBanner(
      content: const Text(
        'No network connection detected. Saved information may be out of date.',
      ),
      leading: const Icon(Icons.wifi_off_outlined),
      actions: [
        TextButton(
          onPressed: () async =>
              _update(await Connectivity().checkConnectivity()),
          child: const Text('Retry'),
        ),
      ],
    );
  }
}
