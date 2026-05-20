# Submodules Catalogue — `vasic-digital` + `HelixDevelopment`

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-05-20 |
| Last modified | 2026-05-20 |
| Status | active |
| Status summary | Initial catalogue. Enumerates every owned-by-us submodule under the two canonical organisations per Universal §11.4.74 (submodule-catalogue-first discovery). 142 repos total (122 + 20). Categorised by capability so consuming projects can locate "is there already a Submodule for X?" in one glance. Re-generate via `gh repo list` + the script in §3 below. |
| Issues | none |
| Issues summary | — |
| Fixed | initial catalogue creation |
| Fixed summary | per user mandate 2026-05-20 follow-up to §11.4.76. |
| Continuation | Re-enumerate quarterly (or after any non-trivial repo creation/rename in either org). |

## Table of contents

- [§1. Why this file exists](#1-why-this-file-exists)
- [§2. How to consume the catalogue](#2-how-to-consume-the-catalogue)
- [§3. Regeneration](#3-regeneration)
- [§4. vasic-digital catalogue (122 repos)](#4-vasic-digital-catalogue-122-repos)
- [§5. HelixDevelopment catalogue (20 repos)](#5-helixdevelopment-catalogue-20-repos)

## §1. Why this file exists

Per Universal §11.4.74 (Submodule-catalogue-first discovery + extend-don't-reimplement), every consuming project MUST survey these two organisations BEFORE scaffolding a new module. Without a single canonical inventory the survey becomes "open the GitHub page and skim 142 repos" — slow, easy to miss, error-prone.

This file is that inventory. It is the **first stop** for any "do we already have something that does X?" question. The full discipline is defined in [`Constitution.md`](Constitution.md) §11.4.74; this file is the operational companion.

Per Universal §11.4.76, the `vasic-digital/containers` Submodule is the canonical container-orchestration substrate — every containerised workload across every consuming project goes through it.

## §2. How to consume the catalogue

When scaffolding a new feature in any consuming project:

1. Find the closest capability match in §4 or §5 below.
2. If a match exists, add the submodule to the consuming project at the parent-root path (`<root>/<name>/` or `<root>/submodules/<name>/`) per Universal §11.4.28 (Submodules-As-Equal-Codebase).
3. Record the verdict in the tracker row: `Catalogue-Check: reuse <org/repo>@<sha>` or `Catalogue-Check: extend <org/repo>@<sha>`.
4. If extending: open a PR against the upstream Submodule (never duplicate in-project per §11.4.74).
5. If no match: record `Catalogue-Check: no-match <YYYY-MM-DD>` and justify in the PR description — operator-side validation re-checks the catalogue before approval.

The `no-match` path is rare — most "I need a small utility" needs are already covered by `digital.vasic.commons`-shaped modules below.

## §3. Regeneration

Re-generate the lists in §4 / §5 by running:

```bash
gh repo list vasic-digital --limit 200 --json name,description,updatedAt > /tmp/v.json
gh repo list HelixDevelopment --limit 200 --json name,description,updatedAt > /tmp/h.json
```

then categorise via the python helper kept inline in this commit (`scripts/build_catalogue.py` is the planned canonical tool — currently inline-built per the §11.4.74 launch commit). Update mtime in the metadata table on every regen.


## §4. vasic-digital catalogue (122 repos)

### Container + lifecycle

- **[`AgentWrapper`](https://github.com/vasic-digital/AgentWrapper)** — Wrap AI CLI Coding Agents in Docker containers
- **[`Agentic`](https://github.com/vasic-digital/Agentic)** — Graph-based agentic workflow orchestration
- **[`AutoTemp`](https://github.com/vasic-digital/AutoTemp)** — SCAFFOLD / WIP -- Benchmark-driven temperature auto-tuning orchestration
- **[`BackgroundTasks`](https://github.com/vasic-digital/BackgroundTasks)** — Background Tasks module
- **[`HelixQA`](https://github.com/vasic-digital/HelixQA)** — AI-driven QA orchestration for multi-platform testing
- **[`HyperTune`](https://github.com/vasic-digital/HyperTune)** — SCAFFOLD / WIP -- Hyperparameter tuning orchestration
- **[`LLMOrchestrator`](https://github.com/vasic-digital/LLMOrchestrator)** — Headless CLI agent management for LLM orchestration
- **[`tmux`](https://github.com/vasic-digital/tmux)** — Optimized + verified containerized tmux build — reproducible across hosts, jemalloc-aware, OOM-protected, 8-test verification gate. Reusable on any Linux system.

### AI / LLM provider + agent

- **[`Android-Toolkit`](https://github.com/vasic-digital/Android-Toolkit)** — Commonly used set of abstractions and implementations.
- **[`Benchmark`](https://github.com/vasic-digital/Benchmark)** — LLM benchmarking: SWE-bench, HumanEval, MMLU, leaderboard
- **[`Chutes-Toolkit`](https://github.com/vasic-digital/Chutes-Toolkit)** — Chutes Toolkit
- **[`Embeddings`](https://github.com/vasic-digital/Embeddings)** — Generic reusable Go module: digital.vasic.embeddings
- **[`I-LLM`](https://github.com/vasic-digital/I-LLM)** — SCAFFOLD / WIP -- Introspection layer for LLM providers
- **[`JVM-Toolkit`](https://github.com/vasic-digital/JVM-Toolkit)** — Commonly used set of abstractions and implementations.
- **[`LLMGateway`](https://github.com/vasic-digital/LLMGateway)** — (no description)
- **[`LLMOps`](https://github.com/vasic-digital/LLMOps)** — LLM operations: evaluation, experiments, datasets, prompt versioning
- **[`LLMProvider`](https://github.com/vasic-digital/LLMProvider)** — Shared LLM provider interface, 40+ provider adapters, retry, circuit breaker, health monitoring
- **[`LLMsVerifier`](https://github.com/vasic-digital/LLMsVerifier)** — Benchmark and verify LLMs
- **[`Memory`](https://github.com/vasic-digital/Memory)** — Generic reusable Go module: digital.vasic.memory
- **[`Normalize`](https://github.com/vasic-digital/Normalize)** — Adversarial-input canonicalisation library for defensive LLM guardrail pipelines
- **[`Open-Rag-Material-Android`](https://github.com/vasic-digital/Open-Rag-Material-Android)** — Material for RAG for Android development
- **[`Optimization`](https://github.com/vasic-digital/Optimization)** — Generic reusable Go module: digital.vasic.optimization
- **[`Planning`](https://github.com/vasic-digital/Planning)** — AI planning algorithms: HiPlan, MCTS, Tree of Thoughts
- **[`RAG`](https://github.com/vasic-digital/RAG)** — Generic reusable Go module: digital.vasic.rag
- **[`RedTeam`](https://github.com/vasic-digital/RedTeam)** — YAML-driven adversarial prompt fixture harness for defensive LLM guardrail regression testing
- **[`SelfImprove`](https://github.com/vasic-digital/SelfImprove)** — AI self-improvement: reward modelling, RLHF, optimizer
- **[`SiliconFlow-Toolkit`](https://github.com/vasic-digital/SiliconFlow-Toolkit)** — SiliconFlow Toolkit
- **[`SkillRegistry`](https://github.com/vasic-digital/SkillRegistry)** — CLI agent skill registration and management for AI agent systems
- **[`Storage`](https://github.com/vasic-digital/Storage)** — Generic reusable Go module: digital.vasic.storage
- **[`TOON`](https://github.com/vasic-digital/TOON)** — Generic reusable Go module: digital.vasic.toon - Token-Oriented Object Notation wrapper
- **[`ToolSchema`](https://github.com/vasic-digital/ToolSchema)** — Generic tool schema definition, validation, and execution for AI agent tool systems
- **[`VectorDB`](https://github.com/vasic-digital/VectorDB)** — Generic reusable Go module: digital.vasic.vectordb
- **[`VisionEngine`](https://github.com/vasic-digital/VisionEngine)** — Computer vision and LLM Vision for UI analysis and navigation
- **[`conversation`](https://github.com/vasic-digital/conversation)** — Conversation context management, infinite context compression, and event sourcing for AI agents

### Messaging + observability + storage

- **[`Document`](https://github.com/vasic-digital/Document)** — Go document model with format detection and change tracking
- **[`EventBus`](https://github.com/vasic-digital/EventBus)** — Generic reusable Go module: digital.vasic.eventbus
- **[`Filesystem`](https://github.com/vasic-digital/Filesystem)** — digital.vasic.filesystem - Reusable Go module
- **[`Formatters`](https://github.com/vasic-digital/Formatters)** — Generic reusable Go module: digital.vasic.formatters
- **[`I18n`](https://github.com/vasic-digital/I18n)** — digital.vasic.i18n - Generic internationalization Go module
- **[`Lazy`](https://github.com/vasic-digital/Lazy)** — Generic reusable Go module: digital.vasic.lazy - Lazy loading with sync.Once generics
- **[`MCP_Module`](https://github.com/vasic-digital/MCP_Module)** — Generic reusable Go module: digital.vasic.mcp
- **[`Messaging`](https://github.com/vasic-digital/Messaging)** — Generic reusable Go module: digital.vasic.messaging
- **[`Plugins`](https://github.com/vasic-digital/Plugins)** — Generic reusable Go module: digital.vasic.plugins
- **[`Streaming`](https://github.com/vasic-digital/Streaming)** — Generic reusable Go module: digital.vasic.streaming
- **[`cache`](https://github.com/vasic-digital/cache)** — Generic reusable Go module: digital.vasic.cache
- **[`concurrency`](https://github.com/vasic-digital/concurrency)** — Generic reusable Go module: digital.vasic.concurrency
- **[`config`](https://github.com/vasic-digital/config)** — digital.vasic.config - Reusable Go module
- **[`database`](https://github.com/vasic-digital/database)** — Generic reusable Go module: digital.vasic.database
- **[`discovery`](https://github.com/vasic-digital/discovery)** — digital.vasic.discovery - Reusable Go module
- **[`http3`](https://github.com/vasic-digital/http3)** — Generic Go module wrapping quic-go/http3 for net/http.Handler servers — drop-in HTTP/3 support
- **[`mdns`](https://github.com/vasic-digital/mdns)** — Generic Go module for RFC 6762/6763 mDNS service announcement and discovery — drop-in LAN service registration
- **[`observability`](https://github.com/vasic-digital/observability)** — Generic reusable Go module: digital.vasic.observability
- **[`ratelimiter`](https://github.com/vasic-digital/ratelimiter)** — digital.vasic.ratelimiter - Reusable Go module
- **[`recovery`](https://github.com/vasic-digital/recovery)** — Generic reusable Go module: digital.vasic.recovery - Application-level fault tolerance
- **[`tracker_sdk`](https://github.com/vasic-digital/tracker_sdk)** — Generic, tracker-agnostic SDK primitives: mirror manager, plugin registry, testing harness. Used by the Lava project (https://github.com/milos85vasic/Lava) to support multiple torrent trackers.

### Auth + security + middleware

- **[`Claritas`](https://github.com/vasic-digital/Claritas)** — SCAFFOLD / WIP -- System-prompt extraction detection
- **[`GandalfSolutions`](https://github.com/vasic-digital/GandalfSolutions)** — SCAFFOLD / WIP -- Read-only solutions archive for prompt-leak-defense testing
- **[`LeakHub`](https://github.com/vasic-digital/LeakHub)** — SCAFFOLD / WIP -- Prompt-leak corpus / defensive-use fixtures (red-team training)
- **[`Ouroborous`](https://github.com/vasic-digital/Ouroborous)** — SCAFFOLD / WIP -- Recursive/self-referential safety patterns
- **[`Veritas`](https://github.com/vasic-digital/Veritas)** — SCAFFOLD / WIP -- Truth/verification auxiliary
- **[`auth`](https://github.com/vasic-digital/auth)** — Generic reusable Go module: digital.vasic.auth
- **[`middleware`](https://github.com/vasic-digital/middleware)** — digital.vasic.middleware - Reusable Go module
- **[`security`](https://github.com/vasic-digital/security)** — Generic reusable Go module: digital.vasic.security

### Cross-platform (KMP) modules

- **[`Auth-KMP`](https://github.com/vasic-digital/Auth-KMP)** — Kotlin Multiplatform OAuth2 authentication: flows, token management, secure storage interface
- **[`Concurrency-KMP`](https://github.com/vasic-digital/Concurrency-KMP)** — Kotlin Multiplatform concurrency utilities: lazy loading, platform synchronization, flow-based loaders
- **[`Config-KMP`](https://github.com/vasic-digital/Config-KMP)** — Kotlin Multiplatform storage configuration types for network protocols
- **[`Database-KMP`](https://github.com/vasic-digital/Database-KMP)** — digital.vasic.database - KMP network storage database interfaces and entity types
- **[`Document-KMP`](https://github.com/vasic-digital/Document-KMP)** — Kotlin Multiplatform document model with format detection and change tracking
- **[`Formatters-KMP`](https://github.com/vasic-digital/Formatters-KMP)** — Cross-platform KMP text format detection, parsing interfaces, and format registry
- **[`RateLimiter-KMP`](https://github.com/vasic-digital/RateLimiter-KMP)** — Kotlin Multiplatform rate limiting: semaphore, token bucket, adaptive, throttler
- **[`Security-KMP`](https://github.com/vasic-digital/Security-KMP)** — Kotlin Multiplatform secure storage: AES encryption, platform Keychain/KeyStore integration
- **[`Storage-KMP`](https://github.com/vasic-digital/Storage-KMP)** — digital.vasic.storage - KMP network storage service interfaces and abstractions
- **[`UI-Components-KMP`](https://github.com/vasic-digital/UI-Components-KMP)** — Kotlin Multiplatform UI components: theme system, animations, accessibility utilities for Compose

### TypeScript / React + Web

- **[`API-Client-TS`](https://github.com/vasic-digital/API-Client-TS)** — Generic REST API client for TypeScript
- **[`Auth-Context-React`](https://github.com/vasic-digital/Auth-Context-React)** — React AuthProvider and useAuth hook for Catalogizer authentication with React Query
- **[`Calling-Engine-TS`](https://github.com/vasic-digital/Calling-Engine-TS)** — Generic SIP.js + WebRTC calling engine
- **[`Catalogizer-API-Client-TS`](https://github.com/vasic-digital/Catalogizer-API-Client-TS)** — Type-safe TypeScript client for the Catalogizer API with axios, auth, retry, and per-domain services
- **[`Collection-Manager-React`](https://github.com/vasic-digital/Collection-Manager-React)** — React collection management components for Catalogizer
- **[`Dashboard-Analytics-React`](https://github.com/vasic-digital/Dashboard-Analytics-React)** — React dashboard and analytics components for Catalogizer
- **[`I18n-Client-TS`](https://github.com/vasic-digital/I18n-Client-TS)** — Generic client-side i18n wrapper around i18next
- **[`Media-Browser-React`](https://github.com/vasic-digital/Media-Browser-React)** — React entity browser components for Catalogizer media browsing
- **[`Media-Player-React`](https://github.com/vasic-digital/Media-Player-React)** — React media player component for Catalogizer entity playback
- **[`Media-Types-TS`](https://github.com/vasic-digital/Media-Types-TS)** — Shared TypeScript type definitions for Catalogizer media entities, auth, and API
- **[`State-Management-TS`](https://github.com/vasic-digital/State-Management-TS)** — Generic Redux Toolkit state management utilities
- **[`Testing-Utils-TS`](https://github.com/vasic-digital/Testing-Utils-TS)** — Generic React + Redux testing utilities
- **[`UI-Components-React`](https://github.com/vasic-digital/UI-Components-React)** — Reusable TypeScript/React module
- **[`WebSocket-Client-TS`](https://github.com/vasic-digital/WebSocket-Client-TS)** — Reusable TypeScript/React module

### Testing + QA + benchmarking

- **[`Panoptic`](https://github.com/vasic-digital/Panoptic)** — A comprehensive tool for automated testing, UI recording, and screenshot capture across web, desktop, and mobile applications.
- **[`ReplayBuffer`](https://github.com/vasic-digital/ReplayBuffer)** — Reusable ReplayBuffer module for visual testing and automation
- **[`ScreenDiff`](https://github.com/vasic-digital/ScreenDiff)** — Reusable ScreenDiff module for visual testing and automation
- **[`TrainingCollector`](https://github.com/vasic-digital/TrainingCollector)** — Reusable TrainingCollector module for visual testing and automation
- **[`VisualRegression`](https://github.com/vasic-digital/VisualRegression)** — Reusable VisualRegression module for visual testing and automation
- **[`challenges`](https://github.com/vasic-digital/challenges)** — (no description)

### Apps / tools / experimental

- **[`ATMOSphere-Android-15`](https://github.com/vasic-digital/ATMOSphere-Android-15)** — (no description)
- **[`ATMOSphere-Android-15-Main`](https://github.com/vasic-digital/ATMOSphere-Android-15-Main)** — Android 15 AOSP for Orange Pi 5 Max
- **[`Asinka`](https://github.com/vasic-digital/Asinka)** — Interprocess Objects Syncrhronization Library: Asinka (Асинка)
- **[`Assets`](https://github.com/vasic-digital/Assets)** — Generic, reusable Go module for lazy asset loading with strategy-based resolution
- **[`Catalogizer`](https://github.com/vasic-digital/Catalogizer)** — Advanced Multi-Protocol Media Collection Management System
- **[`Courses-Creator`](https://github.com/vasic-digital/Courses-Creator)** — Courses creator toolkit
- **[`DocProcessor`](https://github.com/vasic-digital/DocProcessor)** — Documentation processing and feature map extraction for QA automation
- **[`Entities`](https://github.com/vasic-digital/Entities)** — Generic media entity system: title parsing, media types, hierarchy detection, and aggregation primitives for Go
- **[`Games`](https://github.com/vasic-digital/Games)** — Vasic Digital Games
- **[`GrabTube`](https://github.com/vasic-digital/GrabTube)** — Tube services downloader
- **[`HelixAgent`](https://github.com/vasic-digital/HelixAgent)** — (no description)
- **[`Integrations`](https://github.com/vasic-digital/Integrations)** — Integrations
- **[`Media`](https://github.com/vasic-digital/Media)** — digital.vasic.media - Reusable Go module
- **[`Models`](https://github.com/vasic-digital/Models)** — (no description)
- **[`Network-Binder`](https://github.com/vasic-digital/Network-Binder)** — Bind multiple internet connection endpoints into single one using mptcp.
- **[`OOM-Protect`](https://github.com/vasic-digital/OOM-Protect)** — Workstation OOM hardening for systemd Linux
- **[`PliniusCommon`](https://github.com/vasic-digital/PliniusCommon)** — SCAFFOLD / WIP -- Common types/errors library (shared foundation for the 8 sibling modules)
- **[`Proxy`](https://github.com/vasic-digital/Proxy)** — Proxy server
- **[`Pure_v2_Firmware`](https://github.com/vasic-digital/Pure_v2_Firmware)** — Firmware for BeagleBone
- **[`SDK`](https://github.com/vasic-digital/SDK)** — SDK
- **[`ShareConnect`](https://github.com/vasic-digital/ShareConnect)** — Share the downloadable URLs to remote (or local) processing endpoints
- **[`TransmissionConnect`](https://github.com/vasic-digital/TransmissionConnect)** — Remote control for Transmission BitTorrent client and integration with ShareConnect
- **[`Watcher`](https://github.com/vasic-digital/Watcher)** — digital.vasic.watcher - Reusable Go module
- **[`Yole`](https://github.com/vasic-digital/Yole)** — Text editor, Notes & ToDo - Markdown, todo.txt, plaintext, math, and much more ...
- **[`ffmpeg-kit`](https://github.com/vasic-digital/ffmpeg-kit)** — FFmpeg Kit for applications. Supports Android, Flutter, iOS, Linux, macOS, React Native and tvOS. Supersedes MobileFFmpeg, flutter_ffmpeg and react-native-ffmpeg.
- **[`qBitConnect`](https://github.com/vasic-digital/qBitConnect)** — Control qBittorrent from any device and integrate with ShareConnect

### Misc / scaffolds

- **[`Herald`](https://github.com/vasic-digital/Herald)** — Ingesting system events and reliably fanning them out to multiple notification channels so every alert reaches the right destination without confusion
- **[`containers`](https://github.com/vasic-digital/containers)** — (no description)
- **[`vasic-digital.github.io`](https://github.com/vasic-digital/vasic-digital.github.io)** — (no description)


## §5. HelixDevelopment catalogue (20 repos)

- **[`DebateOrchestrator`](https://github.com/HelixDevelopment/DebateOrchestrator)** — Multi-agent debate orchestration library — Phase 1 reconstruction (7 real + 5 stub sub-packages; see RECONSTRUCTION_ROADMAP.md)
- **[`DocProcessor`](https://github.com/HelixDevelopment/DocProcessor)** — Documentation processing and feature map extraction for QA automation
- **[`Helix-Game-1`](https://github.com/HelixDevelopment/Helix-Game-1)** — First Stake game from HelixDevelopment
- **[`Helix-Game-Demo`](https://github.com/HelixDevelopment/Helix-Game-Demo)** — (no description)
- **[`HelixAgent`](https://github.com/HelixDevelopment/HelixAgent)** — LLMs Agent
- **[`HelixBuilder`](https://github.com/HelixDevelopment/HelixBuilder)** — AI powered application building pipeline
- **[`HelixCode`](https://github.com/HelixDevelopment/HelixCode)** — AI Coding Agent
- **[`HelixConstitution`](https://github.com/HelixDevelopment/HelixConstitution)** — Constitution, AGENTS.MD and CLAUDE.MD universal agent rules and constraints
- **[`HelixGitpx`](https://github.com/HelixDevelopment/HelixGitpx)** — Helix Git Proxy eXtended
- **[`HelixLLM`](https://github.com/HelixDevelopment/HelixLLM)** — Helix LLM - Local running super model
- **[`HelixMemory`](https://github.com/HelixDevelopment/HelixMemory)** — Super Memory Provider — Unified Cognitive Memory Engine fusing Mem0 + Cognee + Letta for HelixAgent
- **[`HelixPlay`](https://github.com/HelixDevelopment/HelixPlay)** — Ultimate gaming experience!
- **[`HelixSpecifier`](https://github.com/HelixDevelopment/HelixSpecifier)** — Spec-Driven Development Fusion Engine - Unified specification intelligence fusing SpecKit + Superpowers + GSD for HelixAgent AI debate ensemble
- **[`HelixTranslate`](https://github.com/HelixDevelopment/HelixTranslate)** — A high-performance, enterprise-grade universal ebook translation toolkit supporting any ebook format and any language pair, featuring multiple translation engines, REST API with HTTP/3 support, and real-time WebSocket events.
- **[`LLMOrchestrator`](https://github.com/HelixDevelopment/LLMOrchestrator)** — Headless CLI agent management for LLM orchestration
- **[`LLMProvider`](https://github.com/HelixDevelopment/LLMProvider)** — Shared LLM provider interface, 40+ provider adapters
- **[`Projects`](https://github.com/HelixDevelopment/Projects)** — Helix projects
- **[`Stake-Tetris`](https://github.com/HelixDevelopment/Stake-Tetris)** — Stake Tetris
- **[`VisionEngine`](https://github.com/HelixDevelopment/VisionEngine)** — Computer vision and LLM Vision for UI analysis and navigation
- **[`helixqa`](https://github.com/HelixDevelopment/helixqa)** — AI-driven QA orchestration for multi-platform testing
