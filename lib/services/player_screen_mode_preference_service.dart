import 'package:shared_preferences/shared_preferences.dart';

import 'package:flick/models/player_screen_mode.dart';

class PlayerScreenModePreferenceService {
  static const _keyPlayerScreenMode = 'player_screen_mode';
  static const _keyErisinCoverDefault = 'erisin_cover_default_v2';

  Future<PlayerScreenMode> getMode() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_keyErisinCoverDefault) != true) {
      await prefs.setString(_keyPlayerScreenMode, PlayerScreenMode.artworkCard.storageValue);
      await prefs.setBool(_keyErisinCoverDefault, true);
      return PlayerScreenMode.artworkCard;
    }
    return PlayerScreenModeX.fromStorageValue(
      prefs.getString(_keyPlayerScreenMode),
    );
  }

  Future<void> setMode(PlayerScreenMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPlayerScreenMode, mode.storageValue);
    await prefs.setBool(_keyErisinCoverDefault, true);
  }
}
