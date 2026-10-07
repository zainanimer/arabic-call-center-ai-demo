An AI tool that listens to Arabic phone calls, suggests what the agent should say, and scores how well the call went. All data is fictional. 
Watch the demo using the link below
https://github.com/user-attachments/assets/e0a1c9ef-c31a-4209-94f4-3a2fc3bff248



# Arabic Call Center AI — Local Demo

A local, privacy-first prototype showing how AI can support a call center that handles **Arabic** calls: speech-to-text, answers grounded in a knowledge base, and QA scoring. It runs from a single PowerShell script on a normal Windows laptop. There is no framework, no build step and no cloud backend, only two free-tier API keys.

> **Note:** All data in this repository is fictional placeholder content (a sample hotel, restaurant, pizza shop and learning platform). The four sample call recordings (hotel, restaurant, education, pizza shop) are demo audio, not real customer calls.

---

## Features

The app has three tools that share one pipeline: **call audio → transcript → AI answer grounded in a knowledge base.**

| Tool | What it does |
|---|---|
| **Coaching Dashboard** | Transcribes a recorded call and scores the agent against a QA scorecard, per account. Flags mistakes, good practices and upsell opportunities. |
| **Agent Assist** | Transcribes a call, picks out each customer question and suggests what the agent should say next, using only that account's knowledge base. Suggestions come in Arabic and English, with a short "why this answer". |
| **Training Simulator** | Voice practice. The trainee picks a scenario (hotel, restaurant, pizza order, education), listens to a sample call and practices the live response. The same call can be scored by the QA engine. |

Every tool is **account-aware**. Hotel, Restaurant, Pizza Shop and Education each have their own knowledge folder, so a hotel suggestion never leaks restaurant content.

---

## Architecture

```
 Browser (index.html)
      │  fetch() — API keys never reach the browser
      ▼
 Local PowerShell server (server.ps1)
      │
      ├── ElevenLabs Scribe v2        →  Speech-to-Text
      ├── ElevenLabs Multilingual v2  →  Text-to-Speech
      ├── Google Gemini (or Claude)   →  Answer generation
      └── knowledge/                  →  per-account knowledge base (Markdown/CSV), read fresh every request
```

**Why a local server?** An API key placed in browser JavaScript is visible to anyone who opens dev tools. The server keeps the keys on your machine and the browser only talks to `localhost`.

**Why a separate LLM layer?** Speech-to-text only converts audio to text. The reasoning comes from a general-purpose LLM that receives the transcript plus the relevant knowledge-base files for that account. This is a small RAG (retrieval-augmented generation) pipeline: retrieve the right documents, then answer from them instead of guessing.

### Request flow (Agent Assist)

1. `GET /api/calls` — list the local call recordings.
2. `POST /api/stt` — send the chosen recording to the server, which relays it to ElevenLabs Scribe v2 and returns the transcript.
3. `GET /api/knowledge?business=Hotel` — load that account's knowledge base.
4. `POST /api/answers` — send transcript + knowledge base; the server asks Gemini to answer using only that knowledge, in a fixed JSON shape (`ar`, `en`, `intent`, `action`, `why`).
5. Answers are cached on disk, keyed by a hash of the exact request, so repeating a question doesn't spend API quota again.

---

## Tech stack

| Layer | Technology |
|---|---|
| Frontend | Plain HTML / CSS / JavaScript |
| Local server | Windows PowerShell + `curl.exe` |
| Speech-to-text | ElevenLabs Scribe v2 (falls back to v1) |
| Text-to-speech | ElevenLabs Multilingual v2 |
| Answers and QA | Google Gemini (free tier); Anthropic Claude supported as a paid alternative |
| Knowledge base | Markdown / CSV files on disk, organised per account |

---

## Getting started

**Requirements:** Windows 10/11, `curl.exe` (included in modern Windows) and an internet connection.

1. Get a free [ElevenLabs](https://elevenlabs.io) API key (needs **Speech to Text**, plus **Text to Speech** for voice features) and a free Gemini key from [aistudio.google.com/apikey](https://aistudio.google.com/apikey).
2. Double-click **`Start-Demo.bat`**. When the window asks, paste each key. They are saved next to the script in `elevenlabs-key.txt` and `gemini-key.txt`, which are git-ignored.
3. The demo opens at `http://localhost:8000`.

> **Never paste your keys into `Start-Demo.bat` if you plan to commit or share the folder.** Paste them in the terminal prompt instead.

If your network blocks outgoing connections (common with HTTPS inspection or proxies), the server prints a hint such as "allow `api.elevenlabs.io`" instead of a bare error.

---

## Project structure

```
.
├── index.html            # the whole front end (3 tools)
├── server.ps1            # local server + API proxy
├── Start-Demo.bat        # launcher and optional config
├── hotel.mp3             # sample call (Hotel)
├── restaurant-order.mp3  # sample call (Restaurant)
├── pizza-order.mp3       # sample call (Pizza Shop)
├── educational-platform.mp3  # sample call (Education)
├── knowledge/
│   ├── general/          # included for every account
│   │   ├── company-guidelines.md
│   │   └── qa-scorecard.md
│   ├── hotel/hotel-info.md
│   ├── restaurant/       # menu.csv, delivery-and-policies.md
│   ├── pizza/            # menu.csv, pizza-shop-info.md
│   └── education/programs.md
└── transcripts/          # cached transcripts (git-ignored)
```

---

## Editing the knowledge base

All content under `knowledge/` is fictional. To change what the AI knows, edit the Markdown or CSV files and save. Files are read fresh on every request, so no code change or restart is needed.

---

## Using your own data

- Keep API keys out of version control (the included `.gitignore` already excludes key files, cached transcripts and audio other than the three samples).
- Replace the placeholder files under `knowledge/` with your own content.
- Treat any call recording you add as real customer data: get consent and store it appropriately.

---

## Limitations

- Local prototype for demonstration, not a production system.
- Windows only (PowerShell server).
- The Training Simulator's live voice flow is mocked; it plays a sample call and does not yet hold a two-way conversation.
- AI suggestions depend on the quality of the knowledge base and should be reviewed before use with real customers.

