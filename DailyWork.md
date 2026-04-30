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
