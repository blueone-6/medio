import 'package:dio/dio.dart';

import '../../config/app_config.dart';
import 'api_interceptor.dart';

/// Factory for configured [Dio] instances.
Dio createDio({
  String? baseUrl,
  Map<String, dynamic>? defaultHeaders,
  List<Interceptor>? extraInterceptors,
}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl ?? '',
      connectTimeout: AppConfig.connectTimeout,
      receiveTimeout: AppConfig.receiveTimeout,
      headers: {
        'Accept': 'application/json',
        ...?defaultHeaders,
      },
    ),
  );
  dio.interceptors.add(LoggingInterceptor());
  dio.interceptors.add(RetryInterceptor(dio));
  if (extraInterceptors != null) {
    dio.interceptors.addAll(extraInterceptors);
  }
  return dio;
}
