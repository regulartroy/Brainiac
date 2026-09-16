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

const normalizeTaskEntry = (task: unknown): string => {
  if (typeof task === "string") return task.trim();
  if (task && typeof task === "object" && "description" in task) {
    const description = (task as { description?: unknown }).description;
    if (typeof description === "string") return description.trim();
  }
  return "";
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
): Promise<{ tasks: string[]; needs_context: boolean; review_items: Array<{ id: string; label: string; type: string }> }> => {
  const confirmedEntityNote = selectedReviewItems.length > 0 ?
    `\nConfirmed entity matches from the user: ${selectedReviewItems.map((item) => item.label).join(", ")}. Use these exact names when resolving ambiguous references.` :
    "";

  const prompt = `You are a routing agent for a Second Brain graph database.
Analyze the transcript and return valid JSON only.
Requirements:
1. Extract actionable tasks as an array of strings or objects with a "description" field.
2. Include a "needs_context" boolean when the note references vague references like "he", "the venue", or missing names.
3. Include a "review_items" array of entities with id, label, and type when the text includes candidate people, organizations, projects, venues, or equipment.
4. If the user confirmed entity matches, prefer those labels instead of guessing.
5. Do not add explanation text outside JSON.
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
      .filter((task: string) => task.length > 0) :
    [];

  const reviewItems = Array.isArray(parsed.review_items) ?
    parsed.review_items
      .map((item: unknown) => normalizeReviewItem(item))
      .filter(
        (item: { id: string; label: string; type: string } | null): item is { id: string; label: string; type: string } => item !== null,
      ) :
    [];

  const needsContext = Boolean(parsed.needs_context || reviewItems.length > 0);

  return {
    tasks,
    needs_context: needsContext,
    review_items: reviewItems,
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
      tasks: output.tasks,
      needs_context: output.needs_context,
      review_items: output.review_items,
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

  for (const entity of entityRefs.values()) {
    const entityId = normalizeEntityName(entity.name).toLowerCase().replace(/[^a-z0-9]+/g, "_");
    const entityRef = db.collection("entities").doc(entityId);
    batch.set(entityRef, {
      name: entity.name,
      type: entity.type,
      summary: entity.summary,
      last_updated: timestamp,
    }, {merge: true});
  }

  for (const task of output.tasks) {
    const taskRef = db.collection("action_items").doc();
    batch.set(taskRef, {
      description: task,
      linked_entities: output.review_items.map((item) => item.label),
      status: output.needs_context ? "pending_review" : "open",
      createdAt: timestamp,
      source_capture_id: captureRef.id,
    });
  }

  await batch.commit();

  return {
    tasks: output.tasks,
    needs_context: output.needs_context,
    review_items: output.review_items,
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
