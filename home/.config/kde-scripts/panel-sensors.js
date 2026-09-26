// DP-8 パネルの System Monitor Sensor を設定する(冪等)。
// 実行: qdbus-qt6 org.kde.plasmashell /PlasmaShell evaluateScript "$(cat ~/.config/kde-scripts/panel-sensors.js)"
// appletsrc を直接編集しない(plasmashell が終了時に上書きする)。Plasma の scripting API 経由なら
// 即時反映と永続化を Plasma が面倒を見る。
// 対象パネル: 縦置きモニタ(スクリーン番号 SCREEN)の下端パネル。アプレットは [Appearance] title で
// 同定し、無ければ末尾に追加する(applet id に依存しない)。
// センサー ID は KDE 同梱プリセット(/usr/share/plasma/plasmoids/org.kde.plasma.systemmonitor.*/
// contents/config/faceproperties)と同じ。実在確認:
//   busctl --user call org.kde.ksystemstats1 /org/kde/ksystemstats1 org.kde.ksystemstats1 sensors as N <id>…
// 中央の数字 = total、ツールチップ = high+low 全部。
const SCREEN = 1;
const PIE = "org.kde.ksysguard.piechart", LINE = "org.kde.ksysguard.linechart";
const spec = [
  { title: "Disks",      face: PIE,  high: ["disk/all/used", "disk/all/free"],           total: ["disk/all/usedPercent"],       low: ["disk/all/total"] },
  { title: "メモリ",     face: PIE,  high: ["memory/physical/used", "memory/physical/free"], total: ["memory/physical/usedPercent"], low: ["memory/physical/total"] },
  { title: "CPU",        face: PIE,  high: ["cpu/all/usage"],                            total: ["cpu/all/usage"],              low: ["cpu/all/cpuCount", "cpu/all/coreCount"] },
  { title: "CPU温度",    face: PIE,  high: ["cpu/all/averageTemperature"],               total: ["cpu/all/averageTemperature"], low: ["lmsensors/thinkpad-isa-0000/fan1"],
    faceConfig: { rangeAuto: false, rangeFrom: 0, rangeTo: 100 } },  // ℃ を 0–100 の円で
  { title: "GPU",        face: PIE,  high: ["gpu/gpu0/usage"],                           total: ["gpu/gpu0/usage"],             low: ["gpu/gpu0/temperature"] },
  { title: "ディスクI/O", face: LINE, high: ["disk/all/read", "disk/all/write"],          total: [], low: [], faceConfig: { lineChartSmooth: true } },
  { title: "ネットワーク", face: LINE, high: ["network/all/download", "network/all/upload"], total: [], low: [], faceConfig: { lineChartSmooth: true } },
];
// 旧: title 未設定のまま置かれていたアプレット(id で同定)。初回のみ意味を持つ
const legacyIds = { 144: "Disks", 149: "メモリ", 150: "CPU", 151: "ネットワーク" };

function configure(w, s) {
  w.currentConfigGroup = ["Appearance"];
  w.writeConfig("chartFace", s.face);
  w.writeConfig("title", s.title);
  w.currentConfigGroup = ["Sensors"];
  w.writeConfig("highPrioritySensorIds", JSON.stringify(s.high));
  w.writeConfig("totalSensors", JSON.stringify(s.total));
  w.writeConfig("lowPrioritySensorIds", JSON.stringify(s.low));
  if (s.faceConfig) {
    w.currentConfigGroup = ["FaceConfig"];
    for (const k in s.faceConfig) w.writeConfig(k, s.faceConfig[k]);
  }
  w.reloadConfig();
}

let out = [];
for (const p of panels()) {
  if (p.screen != SCREEN) continue;
  const byTitle = {};
  for (const w of p.widgets()) {
    if (w.type != "org.kde.plasma.systemmonitor") continue;
    w.currentConfigGroup = ["Appearance"];
    byTitle[w.readConfig("title", legacyIds[w.id] || "")] = w;
  }
  for (const s of spec) {
    let w = byTitle[s.title], created = !w;
    if (!w) w = p.addWidget("org.kde.plasma.systemmonitor");
    configure(w, s);
    out.push((created ? "+" : "=") + s.title + "(" + w.id + ")");
  }
}
print("panel-sensors: " + (out.length ? out.join(" ") : "スクリーン " + SCREEN + " のパネルが見つかりません"));
