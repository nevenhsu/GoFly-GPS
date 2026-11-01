---
status: accepted
---

# 事件驅動的 session 存活與自動重連，不做定時檢查

GoFly iOS 的 device session 存活由 `GoFlyCore` 的 `DeviceSessionKeeper` 單獨負責。它放在 `ServiceController` FIFO 之下：送點前重建與送點後同座標恢復都在同一個 FIFO 位置內完成，上層只看到 ACK、notSent、unconfirmed。觸發點只有四個：送點或心跳 ACK 失敗、網路路徑變化、回到前景、使用者重試。不做定時 TCP 探測，因為探測走的是另一條連線，不能證明 location channel 還活著，而且探測期間會鎖住搖桿與漫步操作；任務中的 ACK 本身就是更準的心跳。

裝置上有模擬位置時（瞬移後、路線進行或暫停、搖桿、漫步，以及取消路線、取消漫步後轉成的維持），session 一律不因閒置而關閉，改以每 15 秒重送同一座標作為心跳。只有使用者在設定按「停止」或「恢復原定位」才關閉 session、回到真實 GPS。自動重連在同一任務內每 60 秒最多一次，超過就顯示連線中斷，等使用者重試。既有的安全不變量不變：只有真實 ACK 才算成功、恢復只重送同一絕對座標、身分或配對錯誤不重試、watchdog 到期判定為未知、背景恢復需要有效授權。

## Considered Options

- **每 5 秒定時探測 VPN 通道**（舊做法）：被拒絕，原因如上。
- **在 FIFO 之上另外排入 repair 工作並暫停各 controller**（舊做法）：被拒絕。重連規則會散在三個 module，而且送點層和外層各自重試，實際上限不明確。
- **每個任務一生只自動重連一次**：被拒絕。12 小時的維持只要遇到第二次 Wi-Fi 閃斷就救不回來。

## Consequences

- 瞬移維持的背景進度缺口上限改為 45 秒（心跳間隔的 3 倍）。路線與漫步仍是 15 秒。
- 12 小時背景進度到期只結束系統背景任務，不 clear、不關 session。
- 「channel 開著時 iOS 會維持最後座標」是推論，要以實機驗證 15 秒心跳版本來確認（2026-10-25）。
- 2026-11-01 修正：自動重連的 60 秒預算由 `ConnectionRecoveryController` 執行，重建本身經 `ServiceController.repairConnection` 排在同一 FIFO。`DeviceSessionKeeper` 每筆寫入只嘗試一次、不自行重試，因為重連前必須先暫停路線、搖桿或瞬移維持的 writer，keeper 位於 FIFO 之下看不到它們。規則本身（每 60 秒最多一次、明確重試不計入）不變；先前程式在成功重連後立即重置預算，已改回依 ADR 間隔。
