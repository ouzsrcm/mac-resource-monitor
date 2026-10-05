# MenuMonitor

macOS menü barında yaşayan, hafif bir sistem kaynakları izleyicisi. CPU, bellek, ağ, disk, termal durum ve pil bilgisini ayrı menü bar öğelerinde gösterir; her öğeye tıklayınca ayrıntılı bir panel açılır. Dock'ta görünmez.

SwiftUI `MenuBarExtra` ile yazılmıştır; harici bağımlılığı yoktur.

## Özellikler

| Öğe | Menü barda | Panelde |
|---|---|---|
| İşlemci | Toplam CPU % | Kullanıcı/sistem dağılımı, geçmiş grafiği, P/E çekirdek çubukları, en çok CPU kullanan 5 süreç |
| Bellek | Kullanılan RAM % | Uygulama/kalıcı/sıkıştırılmış dağılımı, bellek baskısı, geçmiş grafiği, takas, en çok bellek kullanan 5 süreç |
| Ağ | ↓ indirme ↑ yükleme hızı | Hız grafiği, bağlantı türü, arayüz, IPv4, açılıştan beri toplam trafik |
| Disk | Boş alan % veya okuma/yazma hızı | Doluluk çubuğu, boş/toplam alan, okuma/yazma hızları ve grafiği |
| Sistem | Termal duruma göre termometre + pil % | Termal durum (Normal / Ilık / Sıcak / Kritik), pil yüzdesi, şarj durumu, tahmini kalan süre |

Ayrıca:

- **Akıllı uyarılar** (yerel bildirim, her tür için 10 dk bekleme süresi):
  - CPU 30 saniye boyunca kesintisiz %90'ın üzerinde (bildirimde en çok CPU kullanan süreç yazar)
  - Bellek baskısı kritik
  - Termal durum Sıcak veya Kritik
  - Disk boş alanı %10'un altında
  - Pil %15'in altında ve şarj olmuyor
- **Süreç listesi:** Satıra sağ tıklayıp PID kopyalanabilir. Uygulamalar ikon ve adlarıyla gösterilir.
- **Kendi tüketimi:** Her panelin altında MenuMonitor'ün kendi CPU ve bellek kullanımı görünür.
- **Ayarlar penceresi:** Dil, menü bar görünümü, görünür öğeler, örnekleme aralıkları, uyarılar ve disk etiketi biçimi.
- **Dil desteği:** Türkçe ve İngilizce. Varsayılan olarak sistem dilini izler; diğer sistem dillerinde İngilizce açılır.

## Gereksinimler

- macOS 14 Sonoma veya üstü
- Apple Silicon (M serisi) Mac

## Kurulum

1. [Releases](https://github.com/ouzsrcm/mac-resource-monitor/releases/latest) sayfasından `MenuMonitor-<sürüm>.zip` dosyasını indirin. İsterseniz önce aşağıdaki "İndirdiğin dosyayı doğrula" bölümündeki adımlarla dosyayı doğrulayın.
2. Zip'i açın ve `MenuMonitor.app`'i Applications klasörüne taşıyın.
3. Uygulamayı çalıştırın.

## İndirdiğin dosyayı doğrula

Release dosyaları kaynak koddan GitHub Actions üzerinde derlenir (`.github/workflows/release.yml`). İndirdiğiniz dosyayı iki şekilde doğrulayabilirsiniz.

**Checksum:** Zip ile aynı release'teki `SHA256SUMS.txt` dosyasını aynı klasöre indirip çalıştırın:

```sh
shasum -a 256 -c SHA256SUMS.txt
```

**Köken doğrulaması** ([GitHub CLI](https://cli.github.com) gerekir):

```sh
gh attestation verify MenuMonitor-<sürüm>.zip --repo ouzsrcm/mac-resource-monitor
```

Checksum tek başına yalnızca dosyanın indirme sırasında bozulmadığını gösterir; dosyayı değiştiren biri checksum'ı da değiştirebilir. Attestation ise zip'in bu repodaki belirli bir commit'ten, GitHub Actions'ta derlendiğini kriptografik olarak kanıtlar. Komut başarılı olursa çıktıda hangi commit ve workflow ile derlendiği görünür.

**Notarization** (isteğe bağlı). Uygulamayı Applications'a taşıdıktan sonra:

```sh
spctl --assess --verbose=4 /Applications/MenuMonitor.app
```

Çıktıda `source=Notarized Developer ID` görünmesi, kopyanın Developer ID ile imzalanıp Apple noter onayından geçtiğini gösterir.

## Gizlilik

MenuMonitor internete bağlanmaz, telemetri toplamaz ve hiçbir veriyi dışarı göndermez. Tüm ölçümler yerel sistem API'lerinden okunur ve yalnızca bellekte tutulur; uygulama kapanınca silinir. Diskte saklanan tek şey ayarlarınızdır (`UserDefaults`). Uyarılar yerel bildirim olarak gösterilir.

Ağ panelindeki bağlantı türü bilgisi `NWPathMonitor` ile okunur. Bu API yalnızca sistemin mevcut bağlantı durumunu bildirir, ağ üzerinden veri göndermez.

## Neden App Sandbox kapalı

Süreç listesi için başka süreçlerin CPU ve bellek kullanımını okumak gerekir (`proc_pid_rusage`). App Sandbox içinde başka süreçlerin bilgilerine erişim engellendiği için sandbox kapalıdır.

MenuMonitor yalnızca okuma yapar: sistemde değişiklik yapmaz, süreç sonlandırmaz ve başka süreçlere müdahale etmez. Hardened runtime açıktır.

## Derleme ve çalıştırma

Kaynak koddan derlemek için:

- Xcode 16+ (Swift 6)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`

Xcode projesi depoda tutulmaz; `project.yml` dosyasından üretilir.

```sh
xcodegen generate
xcodebuild -project MenuMonitor.xcodeproj -scheme MenuMonitor -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/MenuMonitor.app
```

Gerçekçi performans ölçümü için `-configuration Release` ile derleyin. Uygulamadan çıkmak için herhangi bir paneldeki **Çıkış** butonunu kullanın.

## Ayarlar

Herhangi bir panelin altındaki **Ayarlar…** butonuyla açılır. Tüm ayarlar kalıcıdır (`UserDefaults`).

- **Dil:** Sistem dili, Türkçe veya English. Değişiklik uygulama yeniden başlatınca geçerli olur (ayarlardaki **Yeniden Başlat** butonu).
- **Menü bar:** Yalnızca ikon (varsayılan) veya ikon ve değer. Yalnızca ikon modunda da termometre termal duruma, pil ikonu doluluk ve şarj durumuna göre değişir.
- **Görünür öğeler:** Beş menü bar öğesinin her biri ayrı ayrı gizlenebilir. Uygulama Dock'ta görünmediği için en az bir öğe açık kalmak zorundadır.
- **Örnekleme:** Panel kapalıyken 1 / 2 / 3 / 5 sn, panel açıkken 0,5 / 1 / 2 sn.
- **Uyarılar:** Her kural ayrı ayrı açılıp kapatılabilir.
- **Disk etiketi:** "İkon ve değer" modunda menü barda boş alan yüzdesi veya `R 12 MB/s W 3 MB/s` biçiminde okuma/yazma hızı.

### Çeviriler

Metinler `Sources/Resources/Localizable.xcstrings` String Catalog'undadır. Kaynak dil Türkçedir: koddaki Türkçe metinler anahtar olarak kullanılır, katalogda yalnızca İngilizce karşılıklar tutulur. Yeni bir metin eklerken `Text("…")`, `String(localized: "…")` veya `LocalizedStringKey` parametresi kullanın ve İngilizce karşılığını kataloğa ekleyin.

## Mimari

```
Sources/
├── App/          Uygulama girişi, menü bar öğeleri ve Settings sahnesi
├── Core/         Örnekleme motoru, arka plan okuyucu, uyarılar, ayarlar, yardımcı tipler
├── Metrics/      Her metrik için ayrı bir okuyucu struct
└── Views/        Paneller, menü bar etiketleri, ayarlar penceresi
    └── Components/   Grafikler ve küçük yeniden kullanılabilir bileşenler
```

- **Tek örnekleme döngüsü:** Tüm ölçümler `SamplingEngine` içindeki tek bir async döngüden yapılır. Paneller ve etiketler kendi zamanlayıcısını kurmaz, yalnızca motorun yayınladığı değerleri (`@Observable`) okur.
- **Uyarlanabilir aralık:** Paneller açılıp kapandıkça motora bildirir. Hiç panel açık değilken örnekleme seyrekleşir, bir panel açıldığında sıklaşır.
- **Metrik okuyucular:** `Sources/Metrics` altındaki her okuyucu `mutating func read() -> X?` desenini izler. Fark gerektiren ölçümler (CPU, ağ, disk hızı) önceki örneği kendi içinde saklar.
- **Pahalı okumalar ana thread dışında:** Süreç taraması ve disk kapasitesi `BackgroundSampler` actor'ünde çalışır. Süreç taraması yalnızca CPU veya Bellek paneli açıkken yapılır; disk kapasitesi 30 saniyede bir okunur.
- **Geçmiş:** Grafikler için son 120 ölçüm sabit kapasiteli bir `RingBuffer`'da tutulur.
- **Swift 6 strict concurrency** altında uyarısız derlenir.

### Kullanılan sistem API'leri

| Metrik | API |
|---|---|
| CPU (toplam / çekirdek) | Mach `host_statistics`, `host_processor_info` |
| Bellek | Mach `host_statistics64`, `sysctl` (`kern.memorystatus_vm_pressure_level`, `vm.swapusage`) |
| Ağ | `getifaddrs` (`if_data` sayaçları), `NWPathMonitor` |
| Süreçler | libproc: `proc_listallpids`, `proc_pid_rusage`, `proc_name` |
| Disk hızı | IOKit `IOBlockStorageDriver` istatistikleri |
| Disk alanı | `URLResourceKey.volumeAvailableCapacityForImportantUsageKey` |
| Termal | `ProcessInfo.thermalState` |
| Pil | IOKit Power Sources (`IOPSCopyPowerSourcesInfo`) |
| Bildirimler | UserNotifications |

## Bilinen sınırlamalar

- **Süreç listesi:** Root veya başka bir kullanıcıya ait süreçler (`WindowServer`, `kernel_task` vb.) yetki gerektirdiği için listede görünmez. Activity Monitor bunları ayrıcalıklı bir yardımcı servisle okur.
- **Bildirimler:** Uygulama varsayılan olarak ad-hoc imzalıdır (`CODE_SIGN_IDENTITY: "-"`). Bildirimler gelmezse:
  1. Uygulamayı `/Applications` klasörüne taşıyıp oradan çalıştırın.
  2. Kalıcı çözüm için `project.yml` içinde `CODE_SIGN_STYLE: Automatic`, `CODE_SIGN_IDENTITY: "Apple Development"` ve `DEVELOPMENT_TEAM` ayarlayarak (ücretsiz Apple ID yeterli) gerçek bir imza kullanın.
- **Termal durum:** macOS yalnızca dört seviyeli bir durum bildirir; sıcaklık değeri (°C) gösterilmez.
