# 03: km chip 與「設定漫步範圍」sheet

**What to build:** E1 待命與 E2 執行面板的漫步列在時速膠囊左側出現 km chip（`icon/radius`＋數值，不顯示單位）。點擊開啟 E2.b「設定漫步範圍」半開 sheet：「漫步半徑」數值、快選 0.5／5／20／100 km、滑桿 0.1–100 km、完成設定。E1 與 E2 共用同一 sheet 與偏好，三語系字串同步。依 Figma 04 E1／E2／E2.b Light／Dark。

**Blocked by:** 01 (漫步半徑模型與偏好持久化)

**Status:** ready-for-agent

- [ ] E1、E2 Light／Dark 的 chip 位置、尺寸、間距與 Figma 一致，且與時速膠囊並排不重疊（含大字級）
- [ ] 點 chip 開 sheet；快選、滑桿、完成設定即時更新並寫入偏好，chip 數值同步
- [ ] 滑桿範圍 0.1–100 km，快選第一檔是否改為 0.1 km 待設計確認
- [ ] en／zh-Hans／zh-Hant 字串齊全
- [ ] Simulator 截圖 Light／Dark 各一組
