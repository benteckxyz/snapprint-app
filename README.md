# SnapPrint 📸🖨️

**Native iOS app (iPhone + iPad)** – Photo capture → Thermal receipt printing via Square API validation.

Built with Swift + SwiftUI, targeting iOS 16.0+.  
Printer: **Star Micronics mC-Print3** (Ethernet LAN / TCP).  
Bundle ID: `xyz.benteck.snapprint`

---

## Flow

```
[Receipt Entry] → [Square API Check via Backend] → [Camera 3-2-1 Countdown]
     → [Photo Preview] → [Thermal Optimize + Print] → [Mark as Printed]
```

---

## Setup

### 1. Prerequisites
- Xcode 15+
- CocoaPods (`sudo gem install cocoapods`)
- Star mC-Print3 printer on same LAN
- Your backend API running

### 2. Add StarIO SDK via Swift Package Manager

> ⚠️ **CocoaPods is deprecated** for StarIO as of v2.12.3+. Use Swift Package Manager.

1. Open **`SnapPrint.xcodeproj`** in Xcode
2. Go to **File → Add Package Dependencies...**
3. Add the first package:
   ```
   https://github.com/star-micronics/stario-ios
   ```
   → Select latest version → Add to target **SnapPrint**

4. Add the second package:
   ```
   https://github.com/star-micronics/stario-extension-ios
   ```
   → Select latest version → Add to target **SnapPrint**

5. Wait for Xcode to resolve and download packages (~30 sec)

### 3. Configure the app

Edit `SnapPrint/App/AppConfig.swift`:

```swift
// Your backend URL
static let backendBaseURL = "https://api.yourserver.com"

// Printer IP address (find in printer settings or network scan)
static let printerPortName = "TCP:192.168.1.100"   // ← Change this!
```

### 3. Enable StarIO in PrinterService

After Xcode resolves the SPM packages, open:  
`SnapPrint/Services/PrinterService.swift`

1. Uncomment the two import lines at top:
   ```swift
   import StarIO
   import StarIO_Extension
   ```
2. Uncomment the StarIO SDK calls inside `performPrint()` 
3. Remove the `#if DEBUG` mock block

### 5. Backend API

Your backend needs two endpoints:

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/receipt/{code}` | Check if receipt exists and printed status |
| `POST` | `/receipt/mark-printed` | Mark receipt as printed after success |

**GET Response:**
```json
{
  "exists": true,
  "printed": false,
  "receiptId": "abc123",
  "message": null
}
```

**POST Body:**
```json
{ "receiptId": "abc123" }
```

### 6. Printer IP Discovery

To find your mC-Print3's IP:
1. Print a self-test page: hold Feed button for 3s while powering on
2. IP address is printed on the test page
3. Alternatively: check your router's DHCP client list

---

## Project Structure

```
SnapPrint/
├── App/
│   ├── SnapPrintApp.swift          ← App entry point
│   └── AppConfig.swift             ← ⭐ CONFIGURE THIS FIRST
├── Models/
│   └── ReceiptModel.swift          ← Data models & enums
├── Services/
│   ├── SquareAPIService.swift      ← Backend API calls
│   ├── ImageProcessor.swift        ← Thermal image optimization
│   └── PrinterService.swift        ← StarPRNT SDK wrapper ⭐ UNCOMMENT SDK CALLS
├── Views/
│   ├── ReceiptEntryView.swift      ← Screen 1: Enter receipt code
│   ├── CameraView.swift            ← Screen 2: Camera + countdown
│   ├── PhotoPreviewView.swift      ← Screen 3: Preview + Print/Cancel
│   └── Components/
│       └── CountdownOverlay.swift  ← 3-2-1 animated countdown
└── Resources/
    └── Info.plist                  ← Permissions & config
```

---

## Image Processing Pipeline

For clean thermal prints on the mC-Print3 (80mm / 203 DPI):

1. **Resize** → 576px width (72mm × 203dpi / 25.4)
2. **Grayscale** → via vImage
3. **Enhance** → Contrast ×1.4, brightness +0.05 via Core Image
4. **Dither** → Floyd-Steinberg error diffusion (prevents solid black areas)

Tune in `AppConfig.swift`:
- `thermalContrastBoost` – higher = darker print
- `ditherThreshold` – 0.4–0.6 recommended
- `thermalBrightnessShift` – positive = brighter base

---

## Permissions (Info.plist)

| Key | Purpose |
|-----|---------|
| `NSCameraUsageDescription` | Camera for photo capture |
| `NSLocalNetworkUsageDescription` | Printer discovery on LAN |
| `NSBonjourServices` | Bonjour printer search |

---

## SDK Reference

- [StarPRNT SDK iOS Swift](https://github.com/star-micronics/StarPRNT-SDK-iOS-Swift)
- [mC-Print3 Product Page](https://www.starmicronics.com/mcp3/)
- [Square Payments API](https://developer.squareup.com/reference/square/payments-api)

---

## Testing Without Printer

In `DEBUG` mode, `PrinterService` simulates a print with a 1.5s delay.  
Build for `Release` to use the real StarIO SDK.

```swift
// AppConfig.swift – no changes needed for debug
// PrinterService.swift – mock is active in #if DEBUG block
```
