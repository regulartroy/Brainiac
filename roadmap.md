Project Name: Brainiac (Autonomous Second Brain)
1. The Mission
The goal is to build a proactive, cross-platform (PWA) "Second Brain" AI agent. Instead of a passive note-taking app, Brainiac acts as an autonomous knowledge engine that actively curates and optimizes its own state.

Core Concept: Raw inputs (voice dictation or text) are processed in the background into a semantic graph database (Entities, Edges, Tasks).

Optimization: The system continuously prunes duplicates and compresses old data to maintain high-level abstractions, allowing for full-life queries without burning massive token counts.

Proactivity: The system will eventually feature an automated curation loop (e.g., surfacing 5 questions daily) to bridge disconnected nodes in the graph.

2. The Tech Stack

Frontend: Flutter (Web/PWA)

Backend: Node.js, Firebase Cloud Functions, Google Genkit

Database: Firebase Firestore



3. Current State & Architecture
The project is currently running in a hybrid development environment: the frontend and AI backend run locally for fast iteration, but read/write directly to the live production Firestore database.

The UI: A Flutter web client running locally. It features an integrated speech_to_text dictation microphone, a manual text fallback field, and a StreamBuilder that listens directly to the live Firestore database to render UI updates in real-time.

The Pipeline: We just refactored the data flow. The Flutter app uses BrainAgentService to fire an HTTPS Callable request directly to a local Cloud Function (extractTasks).

The Database (Graph Structure): We have transitioned away from flat text documents. The Genkit function uses Zod schemas to extract and route data into three live Firestore collections:

captures: Raw input staging.

entities: Deduplicated nodes (people, venues, equipment, projects).

action_items: Tasks linked dynamically to specific entity IDs.

4. Immediate Next Step
Continue on with the feature set