# 01: 漫步半徑模型與偏好持久化

**What to build:** 漫步半徑成為可保存的使用者偏好：範圍 0.1–100 km，預設 5 km，App 重開後保留。存取方式沿用移動速度偏好（共用同步模組的模式），提供給 UI 與選點邏輯讀寫。

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] 半徑小於 0.1 km 或大於 100 km 時自動夾限；非有限值回到預設 5 km
- [ ] 首次啟動預設 5 km；修改後重開 App 仍為修改值
- [ ] 單元測試涵蓋邊界值 0.1 / 100、預設值、持久化讀回
