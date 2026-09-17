import * as admin from "firebase-admin";
import {getFirestore, FieldValue} from "firebase-admin/firestore";
import {onCall} from "firebase-functions/v2/https";

// Initialize Firebase Admin for Firestore access
if (!admin.apps.length) {
  admin.initializeApp();
}
const db = getFirestore();

const googleApiKey = process.env.GEMINI_API_KEY ?? process.env.GOOGLE_API_KEY;
const geminiModelName = "gemini-3.6-flash";

if (!googleApiKey) {
  throw new Error("Missing Gemini API key. Set GEMINI_API_KEY or GOOGLE_API_KEY in functions/.env");
}

const normalizeEntityName = (value: string) => value.trim().replace(/\s+/g, " ");

type ExtractedTask = {
  description: string;
  place?: string;
  startAt?: string;
  endAt?: string;
  linked_entities?: string[];
};

type ExtractedRelationship = {
  from_entity: string;
  to_entity: string;
  type: string;
  summary: string;
};

const normalizeIsoMaybe = (value: unknown): string | undefined => {
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim();
  if (!trimmed) return undefined;
  const parsed = Date.parse(trimmed);
  return Number.isNaN(parsed) ? undefined : new Date(parsed).toISOString();
};

const normalizeTaskEntry = (task: unknown): ExtractedTask | null => {
  if (typeof task === "string") {
    const description = task.trim();
    return description ? {description} : null;
  }
  if (!task || typeof task !== "object") return null;
  const candidate = task as Record<string, unknown>;
  const description = typeof candidate.description === "string" ?
    candidate.description.trim() :
    typeof candidate.title === "string" ? candidate.title.trim() : "";
  if (!description) return null;

  const place = typeof candidate.place === "string" ? candidate.place.trim() : "";
  const startAt = normalizeIsoMaybe(
    candidate.startAt ?? candidate.startsAt ?? candidate.scheduledAt ?? candidate.dueDate,
  );
  const endAt = normalizeIsoMaybe(candidate.endAt ?? candidate.endsAt);
  const linked = Array.isArray(candidate.linked_entities) ?
    candidate.linked_entities
      .map((item) => typeof item === "string" ? item.trim() : "")
      .filter((item) => item.length > 0) :
    undefined;

  return {
    description,
    ...(place ? {place} : {}),
    ...(startAt ? {startAt} : {}),
    ...(endAt ? {endAt} : {}),
    ...(linked && linked.length > 0 ? {linked_entities: linked} : {}),
  };
};

const normalizeRelationship = (item: unknown): ExtractedRelationship | null => {
  if (!item || typeof item !== "object") return null;
  const candidate = item as Record<string, unknown>;
  const from = typeof candidate.from_entity === "string" ?
    candidate.from_entity.trim() :
    typeof candidate.from === "string" ? candidate.from.trim() : "";
  const to = typeof candidate.to_entity === "string" ?
    candidate.to_entity.trim() :
    typeof candidate.to === "string" ? candidate.to.trim() : "";
  if (!from || !to || from.toLowerCase() === to.toLowerCase()) return null;
  const type = typeof candidate.type === "string" && candidate.type.trim() ?
    candidate.type.trim() :
    "related";
  const summary = typeof candidate.summary === "string" && candidate.summary.trim() ?
    candidate.summary.trim() :
    typeof candidate.description === "string" && candidate.description.trim() ?
      candidate.description.trim() :
      `${from} related to ${to}`;
  return {from_entity: from, to_entity: to, type, summary};
};

const normalizeReviewItem = (item: unknown): { id: string; label: string; type: string } | null => {
  if (!item || typeof item !== "object") return null;
  const candidate = item as Record<string, unknown>;
  const label = typeof candidate.label === "string" ? candidate.label.trim() : "";
  if (!label) return null;

  const type = typeof candidate.type === "string" ? candidate.type : "concept";
  const id = typeof candidate.id === "string" && candidate.id.trim().length > 0 ?
    candidate.id.trim() :
    label.toLowerCase().replace(/[^a-z0-9]+/g, "_");

  return {id, label, type};
};

const callGeminiExtraction = async (
  transcript: string,
  selectedReviewItems: Array<{ id: string; label: string; type: string }>,
): Promise<{
  tasks: ExtractedTask[];
  needs_context: boolean;
  review_items: Array<{ id: string; label: string; type: string }>;
  relationships: ExtractedRelationship[];
}> => {
  const confirmedEntityNote = selectedReviewItems.length > 0 ?
    `\nConfirmed entity matches from the user: ${selectedReviewItems.map((item) => item.label).join(", ")}. Use these exact names when resolving ambiguous references.` :
    "";

  const prompt = `You are a routing agent for a Second Brain graph database.
Analyze the transcript and return valid JSON only.
Requirements:
1. Extract actionable tasks as an array of strings or objects with:
   - "description" (required)
   - "place" when a venue/location is present
   - "startAt" and optional "endAt" as ISO-8601 when a date/time is present
   - "linked_entities" when specific people/orgs/places are named for that task
2. Include a "needs_context" boolean when the note references vague references like "he", "the venue", or missing names.
3. Include a "review_items" array of entities with id, label, and type when the text includes candidate people, organizations, projects, venues, or equipment.
4. Include a "relationships" array of pairs when entities are related, each with from_entity, to_entity, type, and summary.
5. If the user confirmed entity matches, prefer those labels instead of guessing.
6. Do not invent times, places, or relationships that are not supported by the transcript.
7. Do not add explanation text outside JSON.
${confirmedEntityNote}
Transcript: ${transcript}`;

  const response = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${geminiModelName}:generateContent?key=${encodeURIComponent(googleApiKey)}`,
    {
      method: "POST",
      headers: {"Content-Type": "application/json"},
      body: JSON.stringify({
        contents: [{
          role: "user",
          parts: [{text: prompt}],
        }],
        generationConfig: {
          temperature: 0,
        },
      }),
    },
  );

  if (!response.ok) {
    const errorBody = await response.text();
    throw new Error(`Gemini API error ${response.status}: ${errorBody}`);
  }

  const data = await response.json() as {
    candidates?: Array<{ content?: { parts?: Array<{ text?: string }> } }>;
  };

  const rawText = data.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
  const jsonText = rawText.trim();
  let parsed: any;

  try {
    parsed = JSON.parse(jsonText);
  } catch {
    const startIndex = jsonText.indexOf("{");
    const endIndex = jsonText.lastIndexOf("}");
    if (startIndex >= 0 && endIndex > startIndex) {
      parsed = JSON.parse(jsonText.slice(startIndex, endIndex + 1));
    } else {
      throw new Error("Gemini returned a non-JSON response for task extraction.");
    }
  }

  const tasks = Array.isArray(parsed.tasks) ?
    parsed.tasks
      .map((task: unknown) => normalizeTaskEntry(task))
      .filter((task: ExtractedTask | null): task is ExtractedTask => task !== null) :
    [];

  const reviewItems = Array.isArray(parsed.review_items) ?
    parsed.review_items
      .map((item: unknown) => normalizeReviewItem(item))
      .filter(
        (item: { id: string; label: string; type: string } | null): item is { id: string; label: string; type: string } => item !== null,
      ) :
    [];

  const relationships = Array.isArray(parsed.relationships) ?
    parsed.relationships
      .map((item: unknown) => normalizeRelationship(item))
      .filter((item: ExtractedRelationship | null): item is ExtractedRelationship => item !== null) :
    [];

  const needsContext = Boolean(parsed.needs_context || reviewItems.length > 0);

  return {
    tasks,
    needs_context: needsContext,
    review_items: reviewItems,
    relationships,
  };
};

// 1. Define the Graph Schemas

// 2. Define the Internal Flow
const normalizeRequest = (payload: unknown): { transcript: string; reviewMode: boolean; reviewItems: Array<{ id: string; label: string; type: string }> } => {
  const reviewMode = !!(payload && typeof payload === "object" && "review_mode" in payload && payload.review_mode === true);

  const reviewItems =
    payload && typeof payload === "object" && "review_items" in payload && Array.isArray(payload.review_items) ?
      payload.review_items
        .filter((item): item is Record<string, unknown> => !!item && typeof item === "object")
        .map((item) => ({
          id: typeof item.id === "string" ? item.id : "",
          label: typeof item.label === "string" ? item.label : "",
          type: typeof item.type === "string" ? item.type : "unknown",
        }))
        .filter((item) => item.id || item.label) :
      [];

  if (typeof payload === "string") {
    return {transcript: payload, reviewMode, reviewItems};
  }

  if (payload && typeof payload === "object" && "text" in payload) {
    const value = (payload as { text?: unknown }).text;
    if (typeof value === "string") {
      return {transcript: value, reviewMode, reviewItems};
    }
  }

  throw new Error("Missing note text. Expected a string or an object with a text field.");
};

const processGraphFlow = async ({
  transcript,
  review_mode: reviewMode,
  review_items: selectedReviewItems,
}: {
  transcript: string;
  review_mode: boolean;
  review_items?: Array<{ id: string; label: string; type: string }>;
}) => {
  const output = await callGeminiExtraction(transcript, selectedReviewItems ?? []);

  if (reviewMode) {
    return {
      tasks: output.tasks.map((task) => task.description),
      needs_context: output.needs_context,
      review_items: output.review_items,
      relationships: output.relationships,
    };
  }

  const batch = db.batch();
  const timestamp = FieldValue.serverTimestamp();

  const captureRef = db.collection("captures").doc();
  batch.set(captureRef, {
    content: transcript,
    createdAt: timestamp,
    needs_context: output.needs_context,
    processed_status: true,
  });

  const entityRefs = new Map<string, { name: string; type: string; summary: string }>();
  for (const reviewItem of output.review_items) {
    const entityKey = normalizeEntityName(reviewItem.label).toLowerCase();
    if (!entityRefs.has(entityKey)) {
      entityRefs.set(entityKey, {
        name: reviewItem.label,
        type: reviewItem.type,
        summary: `Identified from transcript: ${reviewItem.label}`,
      });
    }
  }
  for (const relationship of output.relationships) {
    for (const label of [relationship.from_entity, relationship.to_entity]) {
      const entityKey = normalizeEntityName(label).toLowerCase();
      if (!entityRefs.has(entityKey)) {
        entityRefs.set(entityKey, {
          name: label,
          type: "entity",
          summary: `Identified from relationship: ${label}`,
        });
      }
    }
  }

  const entityIdFor = (name: string) =>
    normalizeEntityName(name).toLowerCase().replace(/[^a-z0-9]+/g, "_");

  for (const entity of entityRefs.values()) {
    const entityId = entityIdFor(entity.name);
    const entityRef = db.collection("entities").doc(entityId);
    batch.set(entityRef, {
      name: entity.name,
      type: entity.type,
      summary: entity.summary,
      last_updated: timestamp,
    }, {merge: true});
  }

  // Persist explicit relationship edges from extraction (not only entities/tasks).
  for (const relationship of output.relationships) {
    const relationshipRef = db.collection("relationships").doc();
    batch.set(relationshipRef, {
      from_entity: relationship.from_entity,
      to_entity: relationship.to_entity,
      from_entity_id: entityIdFor(relationship.from_entity),
      to_entity_id: entityIdFor(relationship.to_entity),
      type: relationship.type,
      summary: relationship.summary,
      createdAt: timestamp,
      last_updated: timestamp,
      source_capture_id: captureRef.id,
    });
  }

  for (const task of output.tasks) {
    const linked = task.linked_entities && task.linked_entities.length > 0 ?
      task.linked_entities :
      output.review_items.map((item) => item.label);
    const linkedEntityIds = linked.map((label) => entityIdFor(label));
    const taskRef = db.collection("action_items").doc();
    // Schedule fields live on action_items (smaller change than a parallel
    // appointments collection). Calendar UI only surfaces rows with startAt.
    batch.set(taskRef, {
      description: task.description,
      linked_entities: linked,
      linked_entity_ids: linkedEntityIds,
      status: output.needs_context ? "pending_review" : "open",
      createdAt: timestamp,
      source_capture_id: captureRef.id,
      ...(task.place ? {place: task.place} : {}),
      ...(task.startAt ? {
        startAt: task.startAt,
        scheduledAt: task.startAt,
        dueDate: task.startAt,
      } : {}),
      ...(task.endAt ? {endAt: task.endAt} : {}),
    });
  }

  await batch.commit();

  return {
    tasks: output.tasks.map((task) => task.description),
    needs_context: output.needs_context,
    review_items: output.review_items,
    relationships: output.relationships,
  };
};

// 3. EXPORT TO FIREBASE (This is what Flutter actually calls!)
export const extractTasks = onCall({cors: true}, async (request) => {
  try {
    const {transcript, reviewMode, reviewItems} = normalizeRequest(request.data);
    return await processGraphFlow({
      transcript,
      review_mode: reviewMode,
      review_items: reviewItems,
    });
  } catch (error) {
    console.error("extractTasks failed:", error);
    throw error;
  }
});

export * from "./pruningReview";
export * from "./pruningWorker";
