# 🧅 OnionGrader — Technical Documentation & Content Guide

---

## 1. Problem Statement & Background

### The Challenge
* **Manual Inspection Limitations:** Quality grading of agricultural produce (onions) in farms, mandis, and packing sheds is predominantly manual, subjective, slow, and labor-intensive.
* **Inconsistent Quality Grading:** Lack of standardized grading leads to disputes between farmers and buyers regarding Grade A yield vs. Rejected/Substandard (URS) produce.
* **Lack of Connectivity in Remote Areas:** Cloud-dependent AI applications fail in rural packing stations and fields with poor or non-existent internet connectivity.

### The Objective
To build a portable, fully **offline, on-device AI-powered mobile application** that automates onion detection, defect classification, size estimation, and quality report generation in seconds.

---

## 2. Proposed Solution & Innovation

**OnionGrader** is a Flutter-based mobile application powered by on-device TensorFlow Lite dual-model machine learning.

* **On-Device Machine Learning:** Executes inference locally using optimized C++ binaries via `tflite_flutter`, requiring zero internet connectivity.
* **Dual-Model Computer Vision Pipeline:** Uses two lightweight, quantized YOLOv8 object detection models to simultaneously identify crops, defect types, and surface damage.
* **Batch-Relative Undersized Heuristic:** Automatically calculates the average crop area per scan and flags undersized onions (< 50% of batch average area) without requiring physical calibration markers.
* **Automated PDF Quality Reporting:** Generates shareable PDF reports complete with annotated bounding boxes, timestamps, and statistical breakdowns.
* **Scan History Management:** Stores past inspection results locally for record-keeping and audit trails.

---

## 3. Technical Architecture & System Flow

```
┌─────────────────────────────────────────────────────────┐
│                     USER INTERFACE                      │
│      (Camera Preview / Gallery Picker / Results Screen) │
└────────────────────────────┬────────────────────────────┘
                             │ Raw Image Bytes
                             ▼
┌─────────────────────────────────────────────────────────┐
│                INFERENCE SERVICE ENGINE                 │
│  • Resizes & converts image to [1, 640, 640, 3] Float32 │
│  • Runs Model 1 (veg_model.tflite)                      │
│  • Runs Model 2 (onion2_model.tflite)                   │
│  • Merges detections & applies Per-Class NMS (IoU 0.45) │
└────────────────────────────┬────────────────────────────┘
                             │ Parsed Bounding Boxes & Confidence Scores
                             ▼
┌─────────────────────────────────────────────────────────┐
│                 GRADING SERVICE ENGINE                  │
│  • Separates Model 1 crops vs Model 2 damage boxes      │
│  • Computes Mean Area & flags Undersized crops (< 0.5x) │
│  • Evaluates Defect Labels & Damage Overlaps (IoU 0.3)  │
│  • Calculates Total Onions, Grade A Count & URS Count   │
└────────────────────────────┬────────────────────────────┘
                             │ GradingResult Data Object
                             ▼
┌─────────────────────────────────────────────────────────┐
│                 OUTPUT & LOCAL STORAGE                  │
│  • Annotated Bounding-Box Overlay                       │
│  • PDF Report Generation & In-App Interactive Preview   │
│  • Local Storage in SharedPreferences & Disk Thumbnail  │
└─────────────────────────────────────────────────────────┘
```

---

## 4. AI / ML Methodology & Dual-Model Strategy

### Dual-Model Breakdown

| Component | Model 1 (`veg_model.tflite`) | Model 2 (`onion2_model.tflite`) |
| :--- | :--- | :--- |
| **Model Type** | Quantized YOLOv8 Nano/Small | Quantized YOLOv8 Nano/Small |
| **Labels** | `onion`, `double_split`, `rotten`, `sprout` | `damaged` |
| **Role** | Locates onion crops & primary condition | Detects mechanical/surface damage |

### Merge & Non-Maximum Suppression (NMS) Logic
1. **Model 1 Execution:** All bounding boxes from `veg_model` are preserved as primary onion crop entries.
2. **Model 2 Execution:** Only boxes labeled `damaged` from `onion2_model` are retained; all other redundant classes are discarded.
3. **NMS Filtering:** Greedy per-class Non-Maximum Suppression is applied using an IoU threshold of 0.45:
$$\text{IoU}(A, B) = \frac{\text{Area}(A \cap B)}{\text{Area}(A \cup B)}$$

---

## 5. Quality Grading Rules & Mathematical Model

### A. Total Onion Count
$$\text{Total Onions} = N_{\text{Model 1}} + N_{\text{Standalone Damaged}}$$

### B. Defect Classification Criteria
An onion crop is classified under **URS (Undersized / Rejected / Substandard)** if ANY of the following conditions are met:
1. **Primary Defect Label:** Model 1 assigns a label of `rotten`, `sprout`, or `double_split`.
2. **Surface Damage:** A Model 2 `damaged` bounding box overlaps the crop with $\text{IoU} > 0.3$.
3. **Relative Undersizing:** Crop area is less than 50% of the mean crop area in the scan:
$$\text{Undersized} \iff \text{Area}_{\text{crop}} < 0.5 \times \left( \frac{1}{M} \sum_{i=1}^{M} \text{Area}_i \right) \quad (\text{for } M \ge 2)$$

### C. Grade A Criteria
An onion crop is classified as **Grade A** if:
* Labeled as `onion`
* Has NO defect labels (`rotten`, `sprout`, `double_split`, `damaged`)
* Is NOT undersized

$$\text{Grade A \%} = \frac{\text{Grade A Count}}{\text{Total Onions}} \times 100$$
$$\text{URS \%} = \frac{\text{URS Count}}{\text{Total Onions}} \times 100$$

---

## 6. Color-Coded Visual Annotation Scheme

* 🟢 **Green:** Grade A Onion (Healthy, standard size)
* 🔴 **Red:** Rotten Onion
* 🔴 **Red-Accent:** Double Split Onion
* 🟠 **Orange:** Sprout Defect
* 🟠 **Deep-Orange:** Surface Damaged Onion
* 🟡 **Yellow:** Undersized Onion

---

## 7. Technology Stack & Key Dependencies

* **Frontend & Mobile Framework:** Flutter 3.x / Dart 3.x (Material 3 Design)
* **ML Runtime Engine:** `tflite_flutter` (TensorFlow Lite C++ API via Dart FFI)
* **Native Architecture:** 64-bit Android Binary Support (`x86_64` / `arm64`)
* **Camera & Hardware Interfacing:** `camera`, `image_picker`
* **Image Processing:** `image` library (pixel decoding, resizing to 640×640 Float32 tensor)
* **PDF & Report Rendering:** `pdf`, `printing`
* **Local Persistence:** `shared_preferences`, `path_provider`

---

## 8. Feasibility, Impact & Scalability

* **Feasibility:** 100% functional, on-device execution with low latency (~300ms–800ms per image).
* **Cost Efficiency:** Zero cloud infrastructure cost or recurring API fees.
* **Impact:** Empowers farmers, traders, and quality auditors with instant, transparent, and verifiable grading data.
* **Scalability:** Easily extendable to other crops (potatoes, tomatoes, garlic) by swapping or adding TFLite model weights.
