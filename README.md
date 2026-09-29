# OnionGrader 🌱🧅

An AI-powered mobile application built with Flutter that automates the quality grading of onions using on-device machine learning.

## Features
* **Dual AI Models:** Uses two quantized YOLOv8 TensorFlow Lite models running entirely on-device:
  1. **Detection Model:** Locates onions within the frame and calculates their bounding box dimensions to detect undersized crops.
  2. **Classification Model:** Identifies surface defects such as rot, sprouting, mechanical damage, and double-splits.
* **Automated Grading:** Instantly calculates the total count, Grade A percentage, and URS (Rejected) percentage based on the AI detections.
* **Scan History:** Automatically saves a local history of all past scans, including thumbnails, timestamps, and quality metrics, inspired by document scanning apps.
* **Gallery & Live Camera:** Supports capturing images directly from the camera or importing existing photos from the device gallery.
* **PDF Reports:** Generates and exports detailed PDF quality reports with annotated bounding-box images and statistical breakdowns.

## Tech Stack
* **Framework:** Flutter / Dart (Material 3 UI)
* **Machine Learning:** `tflite_flutter` (TensorFlow Lite C API)
* **Local Storage:** `shared_preferences`, `path_provider`
* **Media:** `camera`, `image_picker`, `image` (for pixel manipulation)
* **Reporting:** `pdf`, `printing`

## Installation & Setup
1. Clone the repository and navigate into the project directory:
   ```bash
   cd OnionApp
   ```
2. Install dependencies:
   ```bash
   flutter pub get
   ```
3. Ensure the AI model files are present in the `assets/` folder:
   * `veg_model.tflite` & `veg_model.txt`
   * `onion2_model.tflite` & `onion2_model.txt`
4. Run the app:
   ```bash
   flutter run
   ```

### ⚠️ Important Note for Emulators
If you are testing this app on an Android Emulator, the emulator **MUST** use a 64-bit System Image (`x86_64` or `arm64`). The TensorFlow Lite C++ binaries included in this project do not support 32-bit `x86` system images. Installing on an `x86` emulator will result in an `INSTALL_FAILED_NO_MATCHING_ABIS` error.

## Usage
1. Open the app to view your **Scan History** on the home screen.
2. Tap the **Camera** floating action button to start a new scan.
3. Align the onions in the frame and tap the shutter button, OR tap the **Gallery** icon to pick a pre-captured photo.
4. The app will process the image and display an annotated preview with bounding boxes and a statistical breakdown.
5. Tap **Generate PDF Report** to save or share the official grading document.
6. The scan is automatically saved to your history for future reference.

## License
MIT License
