# Dilenci (çalışma adı)

Godot 4 ile 3D insan büyütme / yaşam simülasyonu (Android hedefli).
Karakter çocukken başlar; beslenir, uyur, büyür, çalışır, aile kurar, yaşlanır.
Ölünce çocuklarından biri mirası devralıp oyuna devam eder.

## Çalıştırma
Godot 4.3+ ile `project.godot` dosyasını açın ve F5'e basın.

## Yapı
- `scripts/game_state.gd` — zaman, ihtiyaçlar, yaş, para, kayıt, miras (autoload)
- `scripts/character.gd` — geçici 3D karakter (ileride Sketchfab modeli)
- `scripts/main.gd` — 3D oda ve arayüz

## Test
- Mantık testi: `godot --headless -s tools/test_life.gd`
- Ekran görüntüsü: `xvfb-run godot --rendering-method gl_compatibility --resolution 720x1280 -s tools/screenshot.gd -- cikti.png [jobs]`
- Denge botu (bütün bir hayatı oynar, kilometre taşlarını yazar): `godot --headless -s tools/balance_bot.gd -- <tohum> <nesil>`
- Ses testi: `godot --headless -s tools/test_audio.gd`
