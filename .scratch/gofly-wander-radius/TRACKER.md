# 漫步半徑（km chip／範圍設定）

日期：2026-11-01。Figma 04 E1／E2／E2.b 已新增設計（Light／Dark）；以下票單尚未實作。規則：半徑 0.1–100 km、預設 5 km；目標距離 = min(速度 × 10 分鐘, 半徑)；更換地點圓心固定為最初起點；半徑變更不影響進行中路線。

| 票 | 狀態 | 依賴 |
|---|---|---|
| 01 漫步半徑模型與偏好持久化 | ready-for-agent | — |
| 02 自動漫步終點受半徑約束 | ready-for-agent | 01 |
| 03 km chip 與設定漫步範圍 sheet | ready-for-agent | 01 |
| 04 地圖藍色虛線範圍圈 | ready-for-agent | 01, 03 |
| 05 收合面板與中斷恢復保留半徑 | ready-for-agent | 02, 03 |
| 06 驗收與文件 | ready-for-agent | 04, 05 |
