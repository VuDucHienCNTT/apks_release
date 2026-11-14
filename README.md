# apks_release

Bản phát hành các app Android TV của mình. Các app tự đọc `<app>/version.json` ở đây khi mở. Có bản mới thì hỏi, tải APK từ GitHub Releases, kiểm tra SHA-256 rồi mở trình cài, nên không phải cắm USB nữa.

| App | Thư mục | Project |
|---|---|---|
| Nova TV (launcher) | `novatv/` | NovaTV |
| THTV | `thtv/` | VietTV |
| Đọc Báo | `docbao/` | DocBao |
| Bóng đá TV | `bongdatv/` | BongDaTV |
| YouTube Lite | `youtubelite/` | YoutubeLite |
| Castly | `castly/` | Castly |

## Phát hành bản mới

1. Tăng `versionCode` / `versionName` trong project của app (YoutubeLite: `ytlite.versionName` trong `gradle.properties`).
2. Chạy trong PowerShell:

   ```powershell
   cd C:\Users\HienVD\AndroidStudioProjects\apks_release
   .\release.ps1 novatv -Notes "Sửa lỗi ..."   # build, kiểm tra, upload, cập nhật version.json, push
   .\release.ps1 -List                          # xem bản đang phát hành của từng app
   .\release.ps1 thtv -DryRun                   # chỉ kiểm tra, không upload
   ```

Script tự dừng nếu APK ký sai khóa, sai package, hoặc versionCode không lớn hơn bản đang phát hành.

Lần đầu cần cài GitHub CLI: `winget install GitHub.cli`, rồi chạy `gh auth login`.

## version.json

```json
{
  "versionCode": 7,
  "versionName": "1.6",
  "apkUrl": "https://github.com/VuDucHienCNTT/apks_release/releases/download/novatv-v1.6/novatv_1.6.apk",
  "sha256": "<sha256 của APK, chữ thường>",
  "sizeBytes": 225935,
  "notes": "Hiện trong hộp thoại cập nhật"
}
```

APK nằm ở **Releases** (tag `<app>-v<version>`), không commit vào repo.

## Khóa ký (quan trọng)

Mọi app ký bằng **cùng một khóa**: `C:\Users\HienVD\.android\hien-release.keystore`, khai báo trong `~/.gradle/gradle.properties` (`RELEASE_*`). SHA-256 chứng chỉ: `80654e1a…84baa2`.
Đây là bản sao khóa debug cũ, nên các box đã cài từ trước vẫn cập nhật đè được.

**Sao lưu file keystore này ra chỗ khác (USB, Drive riêng).** Mất khóa thì không phát hành được bản cập nhật nữa, phải gỡ app rồi cài lại bằng USB trên từng box.
