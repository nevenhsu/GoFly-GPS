# 升版規則

## iOS

- `MARKETING_VERSION` 為對外版本號，對應 `CFBundleShortVersionString`。
- `CURRENT_PROJECT_VERSION` 為建置編號（build），對應 `CFBundleVersion`。
- 升到新的 `MARKETING_VERSION` 時，build 可以重新從 **1** 開始；同一版本內，每次交付新的測試或發行建置都應遞增 build。

編號範例（非目前套件紀錄）：

- `1.0.5（36）`
- `1.0.6（1）` → `1.0.6（2）`
- `1.0.7（1）`

版本設定位置：`app/GoFly/GoFly.xcconfig`。已交付的 `1.0.6（37）` 保留原編號，後續 2 pt 線寬試用版為 `1.0.6（38）`；同版後續交付使用更大的 build，不回退為 1。下一個新的對外版本可以從 1 開始。

## Mac

- `CFBundleShortVersionString` 為對外版本號，`CFBundleVersion` 為建置編號。
- 每次交付新的建置都持續遞增 build，**不隨對外版本升版歸零或重設為 1**。
- iOS 與 Mac 的 build 分別管理，不要求相同數值。

版本設定位置：`app/GoFlyMac/build-app.sh` 產生的 Info.plist 欄位。
