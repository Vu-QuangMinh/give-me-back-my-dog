# DailyWork

**Ngày tháng**: 2026-05-01
**Người chỉnh sửa**: Banana

## Công việc đã làm

### Tile và logic gameplay
- Đánh số thứ tự cho từng ô hex theo định dạng chữ-số (A,0; B,0;... L,7) để dễ chỉ định vị trí khi giao việc.
- Quy ước mới: ô có cây thành obstacle (không đi qua được), ô có lửa cho phép đi qua nhưng mất 1 máu, áp dụng cho cả nhân vật lẫn enemy.

### Trang trí map
- Bỏ căn nhà và cây đặt cố định ở map ban đầu, chỉ giữ lại các cây và đám lửa rải ngẫu nhiên.
- Thêm hàng cỏ ở rìa trên và rìa dưới của map (texture cỏ procedural, không cần tải asset).
- Trồng hàng cây cố định dọc rìa: 6 cây ở rìa trên và 4 cây ở rìa dưới, kích thước đồng bộ với cây random.

### Mô hình căn nhà
- Thay model nhà cũ bằng model mới ở thư mục Level 1.
- Đặt nhà phía sau map, lùi ra sau hàng cỏ rìa dưới để không che khuất khu vực chiến đấu.
- Phóng to căn nhà lên 5 lần để cân đối với scale của map.

### Thêm enemy mới
- **Squirrel** (sóc): nhanh, máu thấp, di chuyển 3 ô — phù hợp vai trò skirmisher.
- **Bulldozer**: máu trâu, di chuyển chậm, đánh mạnh — vai trò tank.
- Mỗi enemy spawn 1 con ngẫu nhiên ở Level 1 cùng với crab.

### Sửa lỗi animation
- Squirrel không đổi sang model walk khi di chuyển: thực ra model có chuyển nhưng cả 2 trạng thái đều đứng yên ở tư thế T-pose nên trông giống hệt nhau.
- Đã fix: cho animation tự chạy ngay khi enemy spawn, vừa giải quyết squirrel vừa làm crab và bulldozer trông sống động hơn.
- Tinh chỉnh kích thước: Squirrel còn 80%, Crab còn 90% so với trước.

### Dọn dẹp project
- Xóa các model và texture không còn dùng (~95 MB): các phiên bản nhà cũ, model cỏ test, sample placeholder.
- Xóa các script orphan và file UID rác từ thời 2D.
- Cập nhật `.gitignore` để loại trừ thêm vài thứ phát sinh khi build.
- Project gọn, chạy không lỗi, sẵn sàng push lên GitHub.

---

**Ngày tháng**: 2026-05-02
**Người chỉnh sửa**: Banana

## Công việc đã làm

### Thay model enemy bằng phiên bản low-poly
- Thay 3 model gốc (Crab, Squirrel, Bull) bằng phiên bản LP nhẹ hơn nhiều, mỗi model chỉ còn 1 file thay cho cặp Base/Walk như cũ.
- Cập nhật cơ chế auto-fit để hiểu được model có scale thật (model cũ bị AABB micro nên scale tới 337×, model LP chỉ scale ~0.6–1.2× là vừa).
- Tinh chỉnh kích thước hiển thị nhiều vòng theo cảm giác visual: Crab nhỏ (~0.6m), Squirrel ~0.8m, Bull ~1.2m.

### Thêm 2 enemy mới
- **Dasher**: model dài như thú 4 chân, di chuyển 4 ô/turn, máu mỏng — vai trò skirmisher tốc độ. Scale tăng 50% sau khi visual quá bé.
- **Gunner**: behaviour Ranger giữ khoảng cách, đánh tầm xa 5 ô, máu thấp — vai trò sniper. Cùng phong cách model LP.

### Logic spawn enemy mới
- Đảo thứ tự khởi tạo: rải cây + lửa **trước**, spawn enemy **sau** → enemy tự né tile đã có cây/lửa.
- Mở rộng phạm vi spawn: trước đây chỉ cho phép trên ô NORMAL (làm enemy clump trên 1 hàng), giờ cho cả vỉa hè (CEMENT) và đường nhựa (ASPHALT). Map đa dạng hơn, enemy phân tán đều.
- Tất cả enemy tự động xoay mặt về player gần nhất ngay khi spawn và sau mỗi nước đi.

### Layout map texture
- Hàng cỏ: row 0 và row 7 (như cũ)
- Vỉa hè xi măng: row 1 và row 6 — texture procedural value-noise màu xám sáng.
- Mặt đường nhựa: row 3, 4, 5 — texture procedural perlin-noise màu xám đậm.
- Layout cuối: cỏ → vỉa hè → đất → 3 làn đường → vỉa hè → cỏ. Map giờ trông như con đường thật.

### Căn nhà
- Vị trí cuối: X=-5, Z=-11, Y=0.2, scale 1.0. Nền nhà ngang bằng mặt hex tile, lùi xa khỏi grid để không che view chiến đấu.
- Trước đó user thay model mới (low poly hơn), giảm từ scale 5.0 còn 1.0 (= 20%) cho vừa cảnh.

### Lửa: đi qua cũng mất máu
- Trước đây chỉ damage khi đứng dừng trên ô lửa. Giờ tính cả các ô lửa entity đi qua trên đường đi (mỗi ô = -1 HP, đa-fire thì cộng dồn).
- Áp dụng cho cả player, enemy, grapple pull, push.

### Chu kỳ ngày-đêm + slider giờ
- Thanh trượt giờ ở góc dưới trái màn hình (dưới HUD), kéo từ 0 đến 12.
- Có nút toggle Ngày/Đêm; mặc định Ngày.
- Day: 06:00 → 18:00 (slider 0..12 = sáng → trưa → chiều).
- Night: 18:00 → 06:00 hôm sau (qua 23:59 → 00:00 → 06:00).
- Mặt trời/trăng arc theo slider: mọc đông → đỉnh trời → lặn tây.
- Ngày: ánh sáng cam ấm ở chân trời, trắng-vàng ở đỉnh.
- Đêm: ánh trăng trắng-xanh lạnh, năng lượng thấp.
- Chạng vạng (18:00–21:00 đêm): ánh nắng hoàng hôn nhạt dần thành ánh trăng — smooth transition để không bị nhảy đột ngột khi toggle.

### Phân tích dung lượng build
- File .exe export ra ~243 MB. Phân tích cho thấy:
  - House.glb đơn 68 MB (model nhiều polygon + texture embedded)
  - Mike idle.glb 18 MB (high-poly Mixamo)
  - ~52 MB orphan textures trong `Map/Level Asset/Level 1/` và `CharacterAsset/Mike|Sonny/` (đã embed trong .glb nhưng cũng tồn tại như file rời, Godot import vào pck → trùng dữ liệu).
- Đề xuất: xóa orphan textures + thay Mike/Sonny bằng low-poly version (giống cách đã làm với enemy) sẽ giảm build xuống ~150 MB.
