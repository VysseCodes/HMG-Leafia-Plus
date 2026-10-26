# LeafiaPopupFix

Makes the **Settings** button of the head unit's phone projection popup work.

The popup ("Android Auto and Apple CarPlay are the supported Phone Projection options… Settings / Close", from the stock `Mobis_SystemPopup`) opens the page `com.daudio.app.deviceconnections/.ui.connectivitySettings.PhoneProjectionSettingsActivity`. Gen5W firmware has no app with that name, so the button crashed and nothing opened.

This app has exactly that package and page name. The page has no screen of its own: it opens the head unit's real **Device Connections** screen (`com.daudio.app.phoneprojection/.settings.ui.DeviceConnectionSettings`), passing on the popup's own extras (`from_micom_popup`, which Device Connections reads), and closes. No stock file changes.

It's installed by part `6_leafiabridge` as `/system/app/LeafiaPopupFix.apk`, and only where no app with that package name already exists. Uninstall removes it.

Build: `apps/build.sh popupfix <out.apk>` (see `apps/leafiabridge/README.md` for signing).
