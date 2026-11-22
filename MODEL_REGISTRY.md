# Model registry

Last verified: **2026-11-22** against the Hugging Face API (`/api/models/ggerganov/whisper.cpp/tree/main`). Sizes are exact byte counts and SHA-256 values are the Git LFS object IDs reported by Hugging Face. The pinned download URL returns `x-linked-etag` equal to the SHA-256 (checked for `ggml-small-q8_0.bin`).

**No model has been downloaded yet.** Nothing here has been benchmarked. RAM figures are the whisper.cpp README's published numbers for **f16** models. Quantised RAM is **to be measured** in Phase 4.

## Source

| Field | Value |
|---|---|
| Repository | `huggingface.co/ggerganov/whisper.cpp` (official ggml conversions by the whisper.cpp maintainers) |
| Pinned revision | `5359861c739e955e79d9a303bcbc70fb988958b1` (repo last modified 2024-10-29) |
| URL pattern | `https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/<file>` |
| Format | whisper.cpp **GGML binary** (`.bin`, magic `ggml`), not GGUF |
| Runtime | whisper.cpp ≥ v1.7 (target: v1.9.5) |
| Repo licence (HF card) | MIT |
| Original weights | OpenAI Whisper. GitHub `openai/whisper` (code and weights) is MIT. The HF Transformers cards state Apache-2.0 for `whisper-base`/`whisper-small` and MIT for `whisper-large-v3-turbo`. Both are permissive and allow commercial redistribution with notice. See `LICENCES.md`. |
| Languages | 99 (multilingual checkpoints, per HF model cards). **Quality varies widely by language and must be measured.** Hindi and Marathi are tested in Phase 4. |

## Candidate files (exact)

| ID | File | Quant | Bytes | MB (10⁶) | SHA-256 |
|---|---|---|---|---|---|
| base-f16 | `ggml-base.bin` | f16 | 147,951,465 | 148.0 | `60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe` |
| **base-q8** | `ggml-base-q8_0.bin` | Q8_0 | 81,768,585 | 81.8 | `c577b9a86e7e048a0b7eada054f4dd79a56bbfa911fbdacf900ac5b567cbb7d9` |
| base-q5 | `ggml-base-q5_1.bin` | Q5_1 | 59,707,625 | 59.7 | `422f1ae452ade6f30a004d7e5c6a43195e4433bc370bf23fac9cc591f01a8898` |
| small-f16 | `ggml-small.bin` | f16 | 487,601,967 | 487.6 | `1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b` |
| **small-q8** | `ggml-small-q8_0.bin` | Q8_0 | 264,464,607 | 264.5 | `49c8fb02b65e6049d5fa6c04f81f53b867b5ec9540406812c643f177317f779f` |
| small-q5 | `ggml-small-q5_1.bin` | Q5_1 | 190,085,487 | 190.1 | `ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb` |
| turbo-f16 | `ggml-large-v3-turbo.bin` | f16 | 1,624,555,275 | 1,624.6 | `1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69` |
| **turbo-q8** | `ggml-large-v3-turbo-q8_0.bin` | Q8_0 | 874,188,075 | 874.2 | `317eb69c11673c9de1e1f0d459b253999804ec71ac4c23c17ecf5fbe24e259a1` |
| **turbo-q5** | `ggml-large-v3-turbo-q5_0.bin` | Q5_0 | 574,041,195 | 574.0 | `394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2` |

Optional Core ML encoders (Apple Silicon only, separate download, **not in MVP**):

| File | Bytes | SHA-256 |
|---|---|---|
| `ggml-base-encoder.mlmodelc.zip` | 37,922,638 | `7e6ab77041942572f239b5b602f8aaa1c3ed29d73e3d8f20abea03a773541089` |
| `ggml-small-encoder.mlmodelc.zip` | 163,083,239 | `de43fb9fed471e95c19e60ae67575c2bf09e8fb607016da171b06ddad313988b` |
| `ggml-large-v3-turbo-encoder.mlmodelc.zip` | 1,173,393,014 | `84bedfe895bd7b5de6e8e89a0803dfc5addf8c0c5bc4c937451716bf7cf7988a` |

Optional VAD model (`huggingface.co/ggml-org/whisper-vad`, rev `9ffd54a1e1ee413ddf265af9913beaf518d1639b`, MIT):

| File | Bytes | SHA-256 |
|---|---|---|
| `ggml-silero-v6.2.0.bin` | 885,098 | `2aa269b785eeb53a82983a20501ddf7c1d9c48e33ab63a41391ac6c9f7fb6987` |

The VAD model is under 1 MB and could be **bundled in the app** (MIT) to trim silence before decoding.

## Proposed default variants (pending Phase 4 benchmarks)

| Tier | Proposed file | Why | Status |
|---|---|---|---|
| Base | `base-q8` (81.8 MB) | Q8_0 is usually near-lossless versus f16 at about half the size. Q5 on an already-small model risks more quality loss. | To be validated: WER vs f16 on the test set |
| Small | `small-q8` (264.5 MB) | Same reasoning. The default for your M4/16 GB. | To be validated |
| Turbo | `turbo-q5` (574 MB) **or** `turbo-q8` (874 MB) | Choose after measuring quality, speed and RAM on the M4. | Benchmark required before Turbo is ever recommended by default |

The registry also keeps the f16 files as manual "Maximum quality" options if benchmarks show a meaningful quality gap.

## Measured on the M4 / 16 GB (Phase 4, 2026-11-22)

Peak process memory while transcribing an 11 s English clip (Metal on): Base Q8_0 250 MB, Small Q8_0 504 MB, Turbo Q5_0 809 MB, Turbo Q8_0 1,131 MB. Warm RTF: 0.015, 0.045, 0.205, 0.197. Full table and method: `TESTING.md`, Phase 4.

## Memory (published, f16, whisper.cpp README v1.9.5)

| Model | Disk | Mem |
|---|---|---|
| base | 142 MiB | ~388 MB |
| small | 466 MiB | ~852 MB |
| large (v3, not turbo) | 2.9 GiB | ~3.9 GB |

Large-v3-turbo has the large-v3 encoder (32 layers) with 4 decoder layers. Its RAM is **expected below large-v3**, but no figure is published in the README. **Measure in Phase 4.** Quantised models are expected to use less RAM than f16 (to be measured).

## Storage rule (for the downloader)

```
required = file_bytes + safety_reserve
safety_reserve = max(1 GB, 10 % of file_bytes)
```

The download streams to `<ModelsDir>/.partial/<file>.part` on the **same volume** and is atomically renamed after SHA-256 verification, so no extra copy space is needed. No extraction step applies (GGML `.bin` is used as-is). The Core ML `.zip` would need its unzipped size too, but it's not in the MVP.

Models directory: `~/Library/Application Support/EsyType/Models/` with `registry.json` (installed files, verified hashes, install date).

## Hardware recommendation (initial rules, to be tuned by benchmarks)

| Condition | Recommendation |
|---|---|
| Apple Silicon, RAM ≤ 8 GB | Base (Q8) |
| Apple Silicon, 16 GB | **Small (Q8)**. Turbo offered manually after benchmarking. |
| Apple Silicon, 24 GB | Small, or Turbo if the M-series benchmark shows RTF ≤ 0.3 at an acceptable first-token latency |
| Apple Silicon, ≥ 32 GB | Turbo (once validated) |
| Intel, any RAM | Base by default. Small only if an on-device micro-benchmark (5 s sample) shows RTF ≤ 0.5. Turbo not recommended. |
| Free disk < required | Model shown as unavailable with the exact shortfall |
| Rosetta-translated process | Warn. The app ships universal, so this should not occur. |

RTF = processing time ÷ audio duration.

As implemented (Phase 2, `Recommender.swift`): "validated" for Turbo means a benchmark on this Mac with RTF ≤ 0.3, for both the 24 GB and ≥ 32 GB rows (first-token latency is added in Phase 4). Turbo Q8_0 is preferred over Q5_0 when both pass. Memory tiers: ≤ 8 GB → Base, otherwise Small, ≥ 24 GB → Turbo if validated. When the pick doesn't fit on disk, the largest smaller model that fits is offered instead.
