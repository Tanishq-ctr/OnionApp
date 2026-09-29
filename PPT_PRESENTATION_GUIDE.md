# 🧅 OnionGrader — Presentation & System Architecture Guide

> **Slide Deck Reference & Outline for PowerPoint (PPT) Generation**  
> *AI-Powered On-Device Mobile Quality Grading Application*

---

## 📌 Slide 1: Title & Project Overview

* **Project Title:** OnionGrader 🌱🧅
* **Subtitle:** Automated Mobile Quality Grading of Onions Using Dual-Model On-Device Machine Learning
* **Target Audience:** Agricultural Inspectors, Supply Chain Managers, Quality Control Teams, Consumers
* **Key Value Proposition:**
  * Fully **on-device** execution — zero cloud dependence, works offline in remote fields.
  * Real-time dual AI model inference + automated relative undersized heuristic.
  * Instant PDF quality reports with annotated bounding boxes and statistical breakdowns.

---

## 💡 Slide 2: Problem Statement & Solution

### The Problem
* **Manual Inspection:** Time-consuming, subjective, inconsistent across inspectors, and prone to error.
* **Lack of Standardized Records:** Quality reports are often paper-based or unverified.
* **Connectivity Challenges:** Agricultural packing sheds and farms often lack high-speed internet required by cloud-only AI solutions.

### The Solution: OnionGrader
* **Instant Computer Vision:** Captures image via camera/gallery, detects & classifies onions in seconds.
* **Dual-Model Edge AI:** Leverages two specialized YOLOv8 TFLite models running directly on the smartphone CPU/NPU.
* **Standardized Metric (Grade A vs. URS):** Automatically computes Grade A % and URS (Rejected) % based on standard rules.

---

## 🏗️ Slide 3: System Architecture & Workflow

```
┌─────────────────┐     ┌─────────────────────┐     ┌──────────────────────┐
│  Image Capture  │ ──> │ Dual TFLite Models  │ ──> │   Grading Engine     │
│ (Camera/Gallery)│     │ (veg + onion2)      │     │ (Heuristic Rules)    │
└─────────────────┘     └─────────────────────┘     └──────────────────────┘
                                                               │
                                                               ▼
┌─────────────────┐     ┌─────────────────────┐     ┌──────────────────────┐
│   PDF Report    │ <── │   Local History     │ <── │   Results Screen     │
│ (Preview/Share) │     │ (SharedPreferences) │     │ (Color Bounding Box) │
└─────────────────┘     └─────────────────────┘     └──────────────────────┘
```

1. **Input Stage:** Captures photo or selects image from device gallery (resizes for 640×640 tensor input).
2. **Inference Stage:** Parallel/sequential execution of dual quantized YOLOv8 TFLite models.
3. **Merging & NMS Stage:** Merges model bounding boxes and applies Non-Maximum Suppression (IoU threshold = 0.45).
4. **Grading Rule Engine:** Evaluates defect labels, size heuristics, and defect-crop overlap.
5. **UI & Export Stage:** Displays color-annotated preview, saves to scan history, and generates shareable PDF.

---

## 🤖 Slide 4: Dual AI Model Strategy

| Feature | Model 1 (`veg_model.tflite`) | Model 2 (`onion2_model.tflite`) |
| :--- | :--- | :--- |
| **Primary Focus** | Onion crop localization & primary condition | Specialized surface damage detection |
| **Target Classes** | `onion`, `rotten`, `sprout`, `double_split` | `damaged` |
| **Output Role** | Establishes total onion crop count & primary defect status | Overlays surface damage defect boxes |

### Dual-Model Merge & NMS Strategy
* **Rule 1:** Retain all bounding boxes from Model 1 (`veg`). Every Model 1 detection represents an individual onion crop.
* **Rule 2:** Filter Model 2 (`onion2`) to retain **only** `damaged` boxes. Discard duplicated onion/rotten boxes from Model 2.
* **Rule 3:** Perform per-class Non-Maximum Suppression (NMS) to eliminate duplicate overlapping boxes.

---

## 📏 Slide 5: Quality Grading Logic & Heuristics

### 1. Total Onions Calculation
$$\text{Total Onions} = \text{Model 1 Crops} + \text{Standalone Model 2 Damaged Crops}$$

### 2. Defect & URS (Rejected) Criteria
An onion is classified as **URS (Substandard / Rejected)** if it meets ANY of the following:
* **Primary Defect Label:** Detected as `rotten`, `sprout`, or `double_split`.
* **Surface Damage:** Overlapped by a Model 2 `damaged` box ($\text{IoU} > 0.3$).
* **Undersized Heuristic:** Its bounding box area is $< 50\%$ of the batch average area ($\text{Area} < 0.5 \times \text{Mean Area}$).

### 3. Grade A Criteria
An onion is **Grade A** if it is:
* Labeled as `onion`
* **NOT** defective (`rotten`/`sprout`/`double_split`/`damaged`)
* **NOT** undersized

$$\text{Grade A \%} = \left(\frac{\text{Grade A Count}}{\text{Total Onions}}\right) \times 100$$

---

## 📱 Slide 6: Key Features & User Interface

1. **Live Camera & Flash Control:** Custom full-screen camera preview with toggleable flash and status indicators.
2. **Interactive Bounding Box Painter:** Real-time canvas overlay color-coded by defect class:
   * 🟢 **Green:** Grade A Onion
   * 🔴 **Red / Red-Accent:** Rotten / Double Split
   * 🟠 **Orange / Deep-Orange:** Sprout / Damaged
   * 🟡 **Yellow:** Undersized Onion
3. **Scan History:** Persistent local log with stored thumbnails, timestamps, and metrics.
4. **PDF Preview & Export:** In-app PDF previewer (`PdfPreview`) allowing visual verification before sharing/printing.

---

## 🛠️ Slide 7: Technical Stack & Performance Optimization

* **Framework:** Flutter 3.x / Dart 3.x (Material 3 Design)
* **ML Engine:** `tflite_flutter` (TensorFlow Lite C++ API via FFI)
* **Native Architecture:** 64-bit Android Binary (`x86_64` / `arm64`)
* **PDF & Printing:** `pdf`, `printing`
* **Performance Enhancements:**
  * Quantized INT8/FP16 models for fast mobile execution (~300–800ms inference).
  * Auto-detecting tensor shapes & box coordinate normalization (handling both 0–1 normalized and 0–640 pixel coordinates).
  * Direct memory image decode and zero-network dependencies.

---

## 📊 Slide 8: Presentation Summary & Future Roadmap

### Summary
* **Fully Operational:** Complete end-to-end mobile grading workflow.
* **High Accuracy & Reliability:** Dual-model verification reduces false positives.
* **Field-Ready:** Operates without server infrastructure or cloud connectivity.

### Future Improvements
* **Isolate Optimization:** Offload model inference to background Dart isolates to eliminate UI main thread pauses.
* **Calibrated Measurement:** Integrate AR markers for absolute millimeter diameter measurement.
* **Cloud Sync:** Optional background synchronization with enterprise ERP / inventory systems when online.
