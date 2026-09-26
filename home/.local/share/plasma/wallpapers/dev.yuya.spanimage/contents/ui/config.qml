/*
 * Span Image の設定ページ。
 * サムネイル一覧は org.kde.image の ThumbnailsComponent / WallpaperDelegate /
 * AddFileDialog をプラグイン ID だけ置換して流用している。
 * それらは同一スコープに imageWallpaper / configDialog / cfg_* が居ることを
 * 前提にしているので、ここで同じ名前を用意する。
 */
import QtQuick
import QtQuick.Controls as QtControls2
import QtQuick.Layouts
import org.kde.plasma.wallpapers.image as PlasmaWallpaper
import org.kde.kquickcontrols as KQuickControls
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: root

    // Plasma が初期プロパティとして注入する。宣言しないと設定ページ全体が壊れる。
    property var configDialog
    property var wallpaperConfiguration: wallpaper.configuration
    property var parentLayout
    property var screenSize: Qt.size(Screen.width, Screen.height)

    property string cfg_Image
    property string cfg_ImageDefault
    property alias cfg_Color: colorButton.color
    property color cfg_ColorDefault
    property int cfg_FillMode: 2
    property int cfg_FillModeDefault: 2
    property bool cfg_Blur: false
    property bool cfg_BlurDefault: false

    signal configurationChanged()
    signal wallpaperBrowseCompleted()

    onScreenSizeChanged: {
        if (thumbnailsLoader.item) {
            thumbnailsLoader.item.screenSize = root.screenSize;
        }
    }

    // KCM(システム設定)から開いた場合 wallpaperConfiguration が null になりうる。
    // 本家 org.kde.image は未ガードで TypeError を吐き続けるので、こちらでは守る。
    function saveConfig() {
        if (imageWallpaper.wallpaperModel) {
            imageWallpaper.wallpaperModel.commitAddition();
            imageWallpaper.wallpaperModel.commitDeletion();
        }
        if (wallpaperConfiguration) {
            // cfg_Image 経由の保存が KCM 文脈で効かないことがあるため明示的に書く
            wallpaperConfiguration.Image = cfg_Image;
            wallpaperConfiguration.PreviewImage = "null";
            wallpaperConfiguration.writeConfig();
        }
    }

    function openChooserDialog() {
        const c = Qt.createComponent("AddFileDialog.qml");
        c.createObject(root);
        c.destroy();
    }

    function selectWallpaper(wallpaper: string, selectors: list<string>): void {
        cfg_Image = imageWallpaper.makeWallpaperUrl(wallpaper, selectors);
        if (wallpaperConfiguration)
            wallpaperConfiguration.PreviewImage = cfg_Image;
    }

    PlasmaWallpaper.ImageBackend {
        id: imageWallpaper
        renderingMode: PlasmaWallpaper.ImageBackend.SingleImage
        targetSize: Qt.size(root.screenSize.width * Screen.devicePixelRatio,
                            root.screenSize.height * Screen.devicePixelRatio)
        onSettingsChanged: root.configurationChanged()
    }

    spacing: 0

    Kirigami.FormLayout {
        id: formLayout
        Layout.bottomMargin: Kirigami.Units.largeSpacing

        Component.onCompleted: {
            if (typeof appearanceRoot !== "undefined") {
                twinFormLayouts.push(appearanceRoot.parentLayout);
            }
        }

        KQuickControls.ColorButton {
            id: colorButton
            Kirigami.FormData.label: "余白の色:"
            dialogTitle: "余白の色を選択"
            KCM.SettingHighlighter {
                highlight: root.cfg_Color != root.cfg_ColorDefault
            }
        }

        QtControls2.Label {
            Kirigami.FormData.label: "表示:"
            text: "画像は全画面を覆う1枚として配置され、各画面はその一部を表示します。\n両方の画面で同じ画像を選んでください。"
            wrapMode: Text.WordWrap
            opacity: 0.7
        }
    }

    DropArea {
        Layout.fillWidth: true
        Layout.fillHeight: true

        onEntered: drag => { if (drag.hasUrls) drag.accept(); }
        onDropped: drop => {
            drop.urls.forEach(url => imageWallpaper.addUsersWallpaper(url));
            thumbnailsLoader.item.view.positionViewAtIndex(0, GridView.Beginning);
        }

        Loader {
            id: thumbnailsLoader
            anchors.fill: parent
            Component.onCompleted: setSource("ThumbnailsComponent.qml",
                                             { screenSize: root.screenSize })
        }
    }

    Component.onDestruction: {
        if (wallpaperConfiguration)
            wallpaperConfiguration.PreviewImage = "null";
    }
}
