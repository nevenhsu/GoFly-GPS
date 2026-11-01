# 05: 收合面板與中斷恢復保留半徑

**What to build:** 漫步中斷再恢復後仍沿用原任務起點與半徑。E1.a、E2.a 收合面板是否顯示 km chip 與範圍圈，先在 Figma 補設計（目前未設計），再依設計實作。

**Blocked by:** 02 (自動漫步終點受半徑約束), 03 (km chip 與設定漫步範圍 sheet)

**Status:** ready-for-agent

- [ ] 恢復流程（E5）的 checkpoint 含範圍錨點與半徑，恢復後更換地點仍受同一圓限制
- [ ] Figma 補 E1.a／E2.a（Light／Dark）設計並記錄在規格；未設計前不實作
- [ ] 軟體驗證測試涵蓋中斷→恢復後半徑與圓心不變
