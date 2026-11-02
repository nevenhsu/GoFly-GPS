# 升版規則

## 修改授權（優先規則）

- **不要自動升版號。** 只有使用者明確要求修改版本號或 build 時，才修改對應欄位。
- 重新建置、製作 IPA／DMG、合併 main 或發布 Release，本身不代表授權調整 `MARKETING_VERSION`、`CURRENT_PROJECT_VERSION`、`CFBundleShortVersionString` 或 `CFBundleVersion`。預設保留現有數值。
- 下列遞增與重設規則只規範「已獲使用者授權的升版」如何編號，不得據此自行遞增。若發行通道要求更大的版本或 build，先說明並取得使用者指示。

## iOS

- `MARKETING_VERSION` 為對外版本號，對應 `CFBundleShortVersionString`。
- `CURRENT_PROJECT_VERSION` 為建置編號（build），對應 `CFBundleVersion`。
- 升到新的 `MARKETING_VERSION` 時，build 可以重新從 **1** 開始；同一版本內，獲使用者授權遞增 build 時使用更大的編號。

編號範例（非目前套件紀錄）：

- `1.0.5（36）`
- `1.0.6（1）` → `1.0.6（2）`
- `1.0.7（1）`

版本設定位置：`app/GoFly/GoFly.xcconfig`。目前為 `1.0.7（1）`。已交付的 `1.0.6（37）` 保留原編號，後續 2 pt 線寬試用版為 `1.0.6（38）`；同版後續若獲授權遞增 build，使用更大的編號，不回退為 1。下一個新的對外版本可以從 1 開始。

## Mac

- `CFBundleShortVersionString` 為對外版本號，`CFBundleVersion` 為建置編號。
- 升到新的對外版本時，build 可以重新從 **1** 開始（2026-11-03 使用者決定，自 `1.0.7（1）` 起；之前為跨版本持續遞增）；同一版本內，獲使用者授權遞增 build 時使用更大的編號。
- iOS 與 Mac 的 build 分別管理，不要求相同數值。

版本設定位置：`app/GoFlyMac/build-app.sh` 產生的 Info.plist 欄位。目前為 `1.0.7（1）`，前一版為 `1.0.6（4）`。

## Release 說明

發布或更新 GitHub Release 時，依 [Release 說明撰寫規格](RELEASE-NOTES.md) 排列英文與繁體中文內容；不因此自動調整版本或 build。
