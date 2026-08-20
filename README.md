# 📄 Smart PDF Compressor (Flutter & Android)

A high-performance, intelligent Flutter Android application designed to compress PDF documents to **exact target file sizes** (e.g. `500 KB`, `200 KB`, `100 KB`, `1 MB`) while maximizing image clarity and document DPI.

---

## ✨ Features

- **🎯 Exact Target Size Matching**: Uses a **2-dimensional Binary Search Optimization Engine** to dynamically calibrate DPI resolution and JPEG quality, reaching **95%–99% of requested size** (e.g., hitting `496 KB` for a `512 KB` limit) without unnecessary quality loss.
- **⚡ Lightning-Fast Performance**: Multi-threaded isolate processing with sub-second execution (< 0.4s per document).
- **🛡️ 100% Sanitized & Portal-Safe**: Strips unwanted metadata streams and outputs clean, standard PDF structures (`Microsoft Print to PDF`) compatible with government, university, and job portals.
- **💾 Save & Share**:
  - Direct 1-tap save to Android **Downloads** folder.
  - Native Android share sheet integration (WhatsApp, Gmail, Telegram, Google Drive, etc.).
  - Built-in PDF previewer.
- **🎨 Modern Material 3 UI**: Clean emerald teal theme, live step-by-step progress tracking, presets chips, and custom size inputs.

---

## 🏗️ Architecture & How It Works

```
[Selected PDF]
       │
       ▼
[Page Analysis & Resolution Scaling (Up to 3.5x / 250+ DPI)]
       │
       ▼
[Isolate Background Processing]
       │
  ┌────┴───────────────────────────┐
  ▼                                ▼
[Full-Res Integer Binary Search]  [Dynamic Scale Fallback]
  (Quality: 30% - 95%)              (Exact Target Budget Calculation)
  └────┬───────────────────────────┘
       ▼
[Clean PDF Reassembly (Zero Metadata Bloat)]
       │
       ▼
[Output PDF (~96-99% of Target Size)]
```

---

## 🚀 Getting Started

### Prerequisites

- Flutter SDK (v3.19+)
- Android SDK (API 21+)
- Java 17+

### Installation & Run

1. **Clone the repository:**
   ```bash
   git clone https://github.com/athrvvvv/pdf_compress.git
   cd pdf_compress
   ```

2. **Get Flutter dependencies:**
   ```bash
   flutter pub get
   ```

3. **Run on your connected Android device:**
   ```bash
   flutter run
   ```

4. **Build release APK:**
   ```bash
   flutter build apk --release --split-per-abi
   ```

---

## 📦 Tech Stack

- **Flutter / Dart**
- **`pdfx`**: High-performance PDF page rendering
- **`pdf`**: PDF document generation and structural assembly
- **`image`**: Fast image processing & JPEG quantization
- **`file_picker`**: Device storage file selection
- **`share_plus`**: Native Android share sheet
- **`open_filex`**: System PDF viewer integration

---

## 📄 License

MIT License. Open source and free to use!
