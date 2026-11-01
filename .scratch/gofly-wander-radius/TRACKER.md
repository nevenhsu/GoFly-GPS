# 漫步半徑（km chip／範圍設定）

日期：2026-11-01。Figma 04 E1／E2／E2.b 已新增設計（Light／Dark）；以下票單尚未實作。規則：半徑 0.1–100 km、預設 5 km；目標距離 = min(速度 × 10 分鐘, 半徑)；更換地點圓心固定為最初起點；使用者 Pin 指定的目的地可在圈外，只有自動選的終點限制在圈內；範圍錨點只在停止自動漫步後以地圖 Pin 瞬移改位置時更新；半徑變更不影響進行中路線。

| 票 | 狀態 | 依賴 |
|---|---|---|
| 01 漫步半徑模型與偏好持久化 | implemented; software-verified | — |
| 02 自動漫步終點受半徑約束 | implemented; software-verified（Core 單元測試＋協調器整合測試）；Simulator E2 目視：半徑 0.5 km 時終點距離被限制為 0.5 km 路線 | 01 |
| 03 km chip 與設定漫步範圍 sheet | implemented; Simulator 目視（E1 fixture，zh-Hant／en） | 01 |
| 04 地圖藍色虛線範圍圈 | implemented; Simulator 目視（E1 fixture）：藍色虛線圈＋半透明藍填色、範圍按鈕開關正常；無位置時圓心取自動漫步會用的起點（目前搖桿起點，否則地圖上三分之一處）；E2 執行中畫面與實機待驗證 | 01, 03 |
| 05 收合面板與中斷恢復保留半徑 | implemented 範圍：圓心／半徑／顯示存偏好，Simulator 驗證重開後半徑 0.5 與隱藏狀態保留；E1.a／E2.a 已補設計並實作（收合也顯示 chip／按鈕／圈，Simulator 目視 E1.a）；中斷恢復流程另無專屬測試 | 02, 03 |
| 06 驗收與文件 | 文件同步；Simulator 驗證 E1／E2 Light；Dark 全畫面截圖、實機、大字級未做 | 04, 05 |

未驗證：實機、動態字級、地圖 Pin 瞬移後圓心移動（只有 Core 邏輯測試，App 內未實際走過）、Dark 畫面。
