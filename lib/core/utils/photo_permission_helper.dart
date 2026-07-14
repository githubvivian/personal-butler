import 'package:photo_manager/photo_manager.dart';

class PhotoPermissionHelper {
  const PhotoPermissionHelper();

  static const imagePermissionRequestOption = PermissionRequestOption(
    androidPermission: AndroidPermission(
      type: RequestType.image,
      mediaLocation: false,
    ),
  );

  Future<PermissionState> requestImagePermission() {
    return PhotoManager.requestPermissionExtend(
      requestOption: imagePermissionRequestOption,
    );
  }

  bool hasImageAccess(PermissionState state) => state.hasAccess;
}
