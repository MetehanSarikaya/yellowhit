# Akın — Prototip (Godot 4)

Mobil tower-defense prototipi. Grid tabanlı, gerçek zamanlı yeniden yönlenen
düşmanlar (AStarGrid2D ile flow-field benzeri pathfinding), katlanarak büyüyen
dalgalar ve dönen giriş noktaları.

## Açma

1. [Godot 4.3+](https://godotengine.org/download) indir (Standard sürüm yeterli).
2. Godot'u aç → "Import" → bu klasördeki `project.godot` dosyasını seç.
3. Üstte Play (▶) tuşuna bas. İlk açılışta varsayılan sahneyi `scenes/Main.tscn`
   olarak seçmen istenebilir (zaten `project.godot` içinde tanımlı).

## Kontroller

- **Kurulum:** Açılışta bir hücreye dokunarak kalenin yerini seç.
- **Kule koy:** Boş bir hücreye dokun (max 10 kule).
- **Kule kaldır:** Var olan bir kuleye tekrar dokun.
- Sarı yanıp sönen kare = sıradaki dalganın giriş noktası, önceden hazırlan.

## Mobilde test etme

- **Masaüstü önizleme:** Play tuşu, proje ayarlarındaki 480x960 pencerede çalışır.
- **Telefonda canlı test (Android):** Telefonu USB ile bağla, geliştirici modu +
  USB debugging aç, Godot'ta üstteki cihaz listesinden telefonu seçip "Play on
  Device" (uzak deploy) tuşuna bas. Titreşim ve dokunma gibi şeyler ancak
  gerçek cihazda doğru test edilir.

## Ses ekleme

`scenes/Main.tscn` içinde 4 boş `AudioStreamPlayer` node'u var:
`MusicPlayer`, `SfxShoot`, `SfxHit`, `SfxWave`.

`.ogg` veya `.wav` dosyalarını `assets/audio/` klasörüne koy, sonra Godot
editöründe ilgili node'u seçip Inspector'dan `Stream` alanına dosyayı sürükle.
Kod tarafında hiçbir değişiklik gerekmiyor — `play_sfx()` fonksiyonu stream
boşsa otomatik atlıyor.

## Önemli sabitler (scripts/main.gd üstünde)

Dengeyi buradan ayarlayabilirsiniz:

- `COLS`, `ROWS`, `CELL` — grid boyutu ve hücre piksel boyutu
- `RANGE` — kule menzili
- `FIRE_RATE` — kule ateş aralığı (frame)
- `SPEED_NORM`, `SPEED_SLOW` — asker hızları
- `MAX_TOWERS` — maksimum kule sayısı
- `EXPLORER_CHANCE` — kule menzilinden kaçınmaya çalışan "kaşif" asker oranı
- `COOLDOWN_LEN` — dalgalar arası inşa penceresi (frame, 60fps'te ~3sn)

## GitHub'a yükleme

```bash
git init
git remote add origin https://github.com/MetehanSarikaya/<repo-adi>.git
git add .
git commit -m "ilk prototip"
git branch -M main
git push -u origin main
```
