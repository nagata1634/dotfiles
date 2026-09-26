/*
 * Span Image — 1枚の画像を複数モニタにまたがって表示する Plasma 壁紙プラグイン。
 *
 * Plasma には壁紙のスパン機能が無い（KDE Bug 393781、2018年からの未実装要望）。
 * ImageMagick で出力ごとに切り出す必要は無く、QML だけで完結する:
 *   壁紙インスタンスは画面ごとに1つ生成されるので、各インスタンスが
 *   「仮想デスクトップ全体のサイズに引き伸ばした画像」を自分の画面位置ぶん
 *   マイナス方向へずらして描き、親で clip すれば、結果としてスパンになる。
 *
 * 解像度・拡大率・回転・オフセットはすべて Qt の仮想デスクトップ座標（論理px）に
 * 反映済みなので追加の計算は要らない。出力構成を変えると Screen.virtualX/Y と
 * width/height が変わり、自動で追従する。
 *
 * MediaProxy を挟む理由:
 *   KDE 標準の壁紙（Altai、Autumn 5.5 など）は単なる画像ファイルではなく
 *   ディレクトリ形式の KPackage（例 file:///usr/share/wallpapers/Autumn/）で、
 *   Image 要素には直接読めない。MediaProxy が targetSize に応じた実ファイルへ
 *   解決してくれる（ライト/ダーク変種の選択も含む）。
 */
import QtQuick
import org.kde.plasma.wallpapers.image as Wallpaper
import org.kde.plasma.plasmoid

WallpaperItem {
    id: root

    // --- 仮想デスクトップ全体の矩形（論理px）------------------------------
    property real bx: 0
    property real by: 0
    property real bw: width
    property real bh: height

    function recomputeBbox() {
        const ss = Qt.application.screens;
        if (!ss || ss.length === 0)
            return;
        let x1 = Infinity, y1 = Infinity, x2 = -Infinity, y2 = -Infinity;
        for (let i = 0; i < ss.length; ++i) {
            const s = ss[i];
            x1 = Math.min(x1, s.virtualX);
            y1 = Math.min(y1, s.virtualY);
            x2 = Math.max(x2, s.virtualX + s.width);
            y2 = Math.max(y2, s.virtualY + s.height);
        }
        if (x2 > x1 && y2 > y1) {
            bx = x1; by = y1; bw = x2 - x1; bh = y2 - y1;
        }
    }

    // このインスタンスが載っている画面の、bbox 内での位置
    readonly property real offX: Screen.virtualX - bx
    readonly property real offY: Screen.virtualY - by

    onWidthChanged: recomputeBbox()
    onHeightChanged: recomputeBbox()
    Screen.onVirtualXChanged: recomputeBbox()
    Screen.onVirtualYChanged: recomputeBbox()

    // 設定ダイアログでサムネイルを選んだ瞬間に反映させるため PreviewImage を優先する。
    // ダイアログを閉じ損ねると古い値が残るので、生成時に必ず null へ戻す（下の onCompleted）。
    readonly property string rawSource: {
        const p = String(configuration.PreviewImage || "null");
        if (p !== "null" && p.length > 0)
            return p;
        return String(configuration.Image || "");
    }

    Component.onCompleted: {
        recomputeBbox();
        // 設定ダイアログ表示中に plasmashell や systemsettings が落ちた場合の残骸を消す
        configuration.PreviewImage = "null";
        root.loading = true;
    }

    // システム設定の「すべての画面に適用」経由だと Image だけが書き換わり、
    // config.qml の saveConfig()/onDestruction を経由しないため PreviewImage が
    // 古い値のまま残り続け、rawSource がそちらを優先してしまう
    // (「選び直しても反映されない」の直接原因)。Image が変わった時点で
    // PreviewImage の役目は終わっているので、経路によらず即座に消す。
    Connections {
        target: configuration
        function onImageChanged() {
            if (configuration.PreviewImage !== "null")
                configuration.PreviewImage = "null";
        }
    }

    Wallpaper.MediaProxy {
        id: proxy
        source: root.rawSource
        // bbox 全体を1枚で覆うので、要求解像度も bbox 基準にする
        targetSize: Qt.size(root.bw * Screen.devicePixelRatio,
                            root.bh * Screen.devicePixelRatio)
        customColor: root.configuration.Color
    }

    Rectangle {
        anchors.fill: parent
        color: root.configuration.Color
        clip: true

        Image {
            x: -root.offX
            y: -root.offY
            width: root.bw
            height: root.bh
            source: proxy.modelImage
            fillMode: Image.PreserveAspectCrop   // bbox 全体を覆い、はみ出しは切る
            asynchronous: true
            retainWhileLoading: true
            cache: false
            onStatusChanged: {
                // retainWhileLoading のため読み込みに失敗すると前の画像が残り、
                // 「切り替えたのに変わらない」という紛らわしい見え方になる。失敗だけ記録する。
                if (status === Image.Error)
                    console.warn("SPANIMAGE: 画像を読み込めません:", source);
                if (status !== Image.Loading)
                    root.loading = false;
            }
        }
    }
}
