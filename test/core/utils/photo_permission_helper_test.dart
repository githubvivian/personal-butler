import 'package:flutter_test/flutter_test.dart';
import 'package:personal_butler/core/utils/photo_permission_helper.dart';
import 'package:photo_manager/photo_manager.dart';

void main() {
  const helper = PhotoPermissionHelper();

  tearDown(() {
    PhotoManager.withPlugin(PhotoManagerPlugin());
  });

  test('image request option excludes video and media location', () {
    final androidPermission =
        PhotoPermissionHelper.imagePermissionRequestOption.androidPermission;

    expect(androidPermission.type, RequestType.image);
    expect(androidPermission.mediaLocation, isFalse);
  });

  test('requestImagePermission forwards the image request option', () async {
    final plugin = _CapturingPhotoManagerPlugin();
    PhotoManager.withPlugin(plugin);

    final state = await helper.requestImagePermission();

    expect(state, PermissionState.authorized);
    expect(
      plugin.requestOption,
      PhotoPermissionHelper.imagePermissionRequestOption,
    );
  });

  test('authorized and limited states have image access', () {
    expect(helper.hasImageAccess(PermissionState.authorized), isTrue);
    expect(helper.hasImageAccess(PermissionState.limited), isTrue);
  });

  test('non-access states do not have image access', () {
    expect(helper.hasImageAccess(PermissionState.denied), isFalse);
    expect(helper.hasImageAccess(PermissionState.restricted), isFalse);
    expect(helper.hasImageAccess(PermissionState.notDetermined), isFalse);
  });
}

class _CapturingPhotoManagerPlugin extends PhotoManagerPlugin {
  PermissionRequestOption? requestOption;

  @override
  Future<PermissionState> requestPermissionExtend(
    PermissionRequestOption requestOption,
  ) async {
    this.requestOption = requestOption;
    return PermissionState.authorized;
  }
}
