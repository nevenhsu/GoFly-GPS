# 05: 收合面板與中斷恢復保留半徑

**What to build:** 漫步中斷再恢復後仍沿用原任務起點與半徑。E1.a、E2.a 收合面板同樣顯示 km chip、範圍按鈕與範圍圈（2026-11-01 使用者指示，Figma Light／Dark 已補，App 已實作）。

**Blocked by:** 02 (自動漫步終點受半徑約束), 03 (km chip 與設定漫步範圍 sheet)

**Status:** ready-for-agent

- [ ] 恢復流程（E5）的 checkpoint 含範圍錨點與半徑，恢復後更換地點仍受同一圓限制
- [x] Figma 已補 E1.a／E2.a（Light／Dark）並記錄在規格；App 收合時顯示 chip、按鈕與圈
- [ ] 軟體驗證測試涵蓋中斷→恢復後半徑與圓心不變
