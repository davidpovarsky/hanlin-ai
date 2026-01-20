<h1 align="center">
  <a href="https://github.com/CherryHQ/hanlin-ai">
    <img src="cherry_icon.png" width="90" height="90" alt="Cherry" style="margin-right: 25px; vertical-align: middle;" />
    <img src="logo_3_0.png" width="120" height="120" alt="AI Hanlin" style="vertical-align: middle;" /><br>
    <span style="color: #FF6B6B;">Cherry Studio</span> · <span style="color: #4A90E2;">Hylic.AI</span>
  </a>
</h1>

<p align="center">
  <strong>Next-generation AI mobile workstation for an intelligent lifestyle.</strong><br>
  <em>开启智能生活的次世代AI移动工作台</em>
</p>

<div align="center">

[![iOS](https://img.shields.io/badge/iOS-18.0+-blue.svg)](https://developer.apple.com/ios/) [![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org) [![Xcode](https://img.shields.io/badge/Xcode-15.0+-blue.svg)](https://developer.apple.com/xcode/) [![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

</div>

<div align="center">

[![SwiftData](https://img.shields.io/badge/SwiftData-Support-purple.svg)](https://developer.apple.com/xcode/swiftdata/) [![CloudKit](https://img.shields.io/badge/CloudKit-Sync-blue.svg)](https://developer.apple.com/icloud/cloudkit/)

</div>

<div align="center">

English | [中文](README_CN.md)

</div>

## ✨ Features

### 🤖 AI Model Integration

- **20+ AI providers**: Qwen, GLM, Doubao, DeepSeek, ERNIE, Hunyuan, Yi, Kimi, Step, Spark, MiniMax, SiliconCloud, OpenAI, Claude, Gemini, and more
- **Real-time streaming responses**: streaming chat and tool calling for ChatGPT-like interactions
- **Local model support**: integrate LLM.swift for on-device inference and deployment

### 🔧 Intelligent Tools Ecosystem

- **🔍 Smart search engines**: Zhipu, Bocha, EXA, Tavily, LangSearch, Brave, Perplexity
- **🌐 Web content extraction**: SwiftSoup parsing for titles, body text, and icons, with batch URL support
- **🗺️ Mapping and location services**: CoreLocation and MapKit for live positioning, geocoding, and navigation
- **🌤️ Multi-source weather services**: QWeather and OpenWeather APIs for live weather and forecasts
- **📅 System calendar integration**: EventKit for events, reminders, and intelligent time filtering
- **💪 Health data analytics**: HealthKit integration for steps, distance, calories, and nutrition
- **💻 Code execution service**: Piston API for Python 3.10 with Jupyter-style outputs
- **🎨 Smart canvas system**: multi-type canvases, version history, SwiftData persistence, and collaboration
- **🔊 Multi-mode voice synthesis**: system TTS and external APIs with multi-language, multi-voice playback
- **🧠 Long-term memory system**: intelligent storage, retrieval, and personalized context

### 📚 Knowledge Base Management

- **Advanced RAG retrieval**: vector similarity search with multiple embedding models
- **Full-format document parsing**: PDF, Word/PPT, Excel, Markdown, and plain text extraction
- **Intelligent knowledge chunking**: semantic segmentation for long documents
- **Vector data management**: 1024-dimension embeddings with batch processing and retrieval optimization

### 👁️ Vision Analysis

- **Professional camera system**: AVCaptureSession engine with adaptive multi-camera support and smart zoom
- **Multimodal AI image understanding**: 20+ vision models for OCR, scene understanding, and analysis
- **Intelligent image processing**: camera, photo library, multi-select, preprocessing, and optimization
- **Streaming vision interaction**: real-time visual Q&A with contextual memory
- **Cross-device image sync**: SwiftData metadata for multi-device history

<a id="voice"></a>
## 🔊 Voice

- Multi-language text-to-speech with system voices and external providers
- Real-time playback control and streaming synthesis
- Voice output integrated across chat and tool workflows

## 🛠️ Tech Stack

- **Language**: Swift 5.9+
- **UI framework**: SwiftUI
- **Storage**: SwiftData + CloudKit
- **Networking**: URLSession + Async/Await
- **Dependency management**: Swift Package Manager

### Key Packages

```swift
// Local AI
.package(url: "https://github.com/otabuzzman/LLM.swift", from: "1.8.0")

// Document and chat rendering
.package(url: "https://github.com/CoreOffice/CoreXLSX", from: "0.14.2")
.package(url: "https://github.com/blackhole89/LaTeXSwiftUI", from: "1.5.0")
.package(url: "https://github.com/gonzalezreal/MarkdownUI", from: "2.0.0")

// Text and UI
.package(url: "https://github.com/RichTextFormat/RichTextKit", from: "0.9.0")
.package(url: "https://github.com/scinfu/SwiftSoup", from: "2.6.0")

// Utilities
.package(url: "https://github.com/weichsel/ZIPFoundation", from: "0.9.0")
```

## 🚀 Quick Start

### Requirements

- iOS 18.0+
- Xcode 15.0+
- Swift 5.9+
- macOS 14.0+ (for development)

### Installation Steps

1. **Clone the repository**
   ```bash
   git clone https://github.com/CherryHQ/hanlin-ai.git
   cd AI_HLY
   ```

2. **Open the project**
   ```bash
   open AI_HLY.xcodeproj
   ```

3. **Configure signing**
   - Select your development team in Xcode
   - Update the bundle identifier to a unique value

4. **Run the app**
   - Choose a target device or simulator
   - Press `Cmd + R`

### API Configuration

1. Launch the app and open Settings
2. Configure the required API keys in "API Key Management"
   - OpenAI API key
   - Claude API key
   - Google Gemini API key
   - Other provider keys
3. Configure external services in "Tool Settings"
   - Search engine API keys
   - Map service keys
   - Weather service keys

## 📖 Usage Guide

### Basic Conversations

1. Tap the list tab
2. Create a new chat with the plus button
3. Choose an AI model and parameters
4. Start chatting

### Vision Analysis

1. Tap the vision tab
2. Capture an image that includes text
3. Review the extracted text
4. Continue with AI analysis

### Knowledge Base Management

1. Tap the knowledge base tab
2. Create a new library
3. Upload documents or enter knowledge manually
4. Reference the library in chat

## 🏗️ Project Architecture

### Directory Layout

```
AI_HLY/
├── AI_HLY/                    # Main app
│   ├── Views/                 # UI components
│   │   ├── MainTabView.swift
│   │   ├── ChatView.swift
│   │   ├── VisionView.swift
│   │   └── ...
│   ├── Models/                # Data models
│   │   ├── ChatRecords.swift
│   │   ├── AllModels.swift
│   │   └── ...
│   ├── Services/              # Service layer
│   │   ├── APIServices/
│   │   ├── ChatServices/
│   │   └── ...
│   └── Resources/             # Assets
├── AI_HLY.xcodeproj/          # Xcode project
└── README.md
```

### Core Components

1. **App entry** (`AI_HLY.swift`)
   - SwiftData model container initialization
   - CloudKit configuration
   - Deep link handling

2. **Main UI** (`MainTabView.swift`)
   - Five-tab navigation
   - Deep link routing

3. **Data layer** (`Models/`)
   - SwiftData model definitions
   - CloudKit integration
   - Data persistence

4. **Service layer** (`Services/`)
   - API communication management
   - Tool system integration
   - External service adapters

## 📄 License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.

## 🙏 Acknowledgements

- Thanks to all AI model providers for their support
- Thanks to the open-source community for the libraries and tools
- Thanks to every contributor

---

<div align="center">

**If this project helps you, please give it a ⭐️!**

Made with ❤️ by the Hylic.AI team

</div>
