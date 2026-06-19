import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_client/core/api/api_exception.dart';
import 'package:media_client/utils/user_facing_error.dart';

void main() {
  test('maps socket errors to friendly copy', () {
    const err = FormatException('SocketException: Connection refused');
    final info = userFacingErrorInfo(err);
    expect(info.kind, UserFacingErrorKind.network);
    expect(info.message, '无法连接服务器，请检查网络与服务器地址');
  });

  test('maps ApiException status codes', () {
    expect(
      userFacingMessage(ApiException('ApiException(401): unauthorized', statusCode: 401)),
      '登录已失效，请重新配置服务器',
    );
    expect(
      userFacingMessage(ApiException('ApiException(503): unavailable', statusCode: 503)),
      '服务器暂时不可用，请稍后重试',
    );
    expect(userFacingErrorInfo(ApiException('ApiException(503): unavailable', statusCode: 503)).suggestsSettings, isFalse);
    expect(userFacingErrorInfo(ApiException('unauthorized', statusCode: 401)).suggestsSettings, isTrue);
  });

  test('maps not configured ApiException', () {
    final info = userFacingErrorInfo(ApiException('Emby server URL not configured'));
    expect(info.kind, UserFacingErrorKind.notConfigured);
    expect(info.message, '尚未配置 Emby 服务器');
    expect(info.suggestsSettings, isTrue);
  });

  test('maps Dio timeout', () {
    final err = DioException(
      requestOptions: RequestOptions(path: '/'),
      type: DioExceptionType.connectionTimeout,
    );
    expect(userFacingMessage(err), '连接超时，请稍后重试');
    expect(userFacingErrorInfo(err).kind, UserFacingErrorKind.timeout);
  });

  test('home section error adds title and contextual hint', () {
    final info = homeSectionErrorInfo(
      ApiException('Emby server URL not configured'),
      HomeLoadSection.recommendations,
    );
    expect(info.title, '推荐内容加载失败');
    expect(info.hint, contains('设置'));
    expect(info.suggestsSettings, isTrue);
  });

  test('network resume hint mentions other section may work', () {
    final err = DioException(
      requestOptions: RequestOptions(path: '/'),
      type: DioExceptionType.connectionError,
    );
    final info = homeSectionErrorInfo(err, HomeLoadSection.resume);
    expect(info.title, '继续观看加载失败');
    expect(info.hint, contains('推荐'));
  });
}
