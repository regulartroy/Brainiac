import {onCall} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import {FieldValue, getFirestore} from "firebase-admin/firestore";
import {mergeDuplicateEntitiesWithRefs} from "./entityMerge";

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = getFirestore();

const normalizeEntityKey = (value: string) =>
  value.trim().toLowerCase().replace(/[^a-z0-9]+/g, " ").replace(/\s+/g, " ").trim();

const inferEntityName = (description: string) => {
  const match = /(?:with|for|about|to|at)\s+([A-Z][A-Za-z0-9.\- ]+?)(?:\?|\.|$)/.exec(description);
  if (match?.[1]?.trim()) {
    return match[1].trim();
  }

  const nameParts = (description.split(/\s+/) || [])
    .filter((word) => /^[A-Z]/.test(word))
    .map((word) => word.replace(/[^A-Za-z0-9.\- ]/g, ""))
    .filter(Boolean);

  return nameParts.slice(0, 3).join(" ");
};

const buildTaskClusters = (tasks: Array<Record<string, any>>) => {
  const grouped = new Map<string, { entity: string; count: number; examples: string[] }>();

  for (const task of tasks) {
    const description = (task.description ?? "").toString().trim();
    if (!description) continue;

    const linked = Array.isArray(task.linked_entities) ?
      task.linked_entities
        .filter((value): value is string => typeof value === "string")
        .map((value) => value.trim())
        .filter(Boolean) :
      [];

    const entity = linked[0] ?? inferEntityName(description);
    if (!entity) continue;

    const key = normalizeEntityKey(entity);
    const existing = grouped.get(key) ?? {entity, count: 0, examples: []};
    existing.count += 1;
    existing.examples.push(description);
    grouped.set(key, existing);
  }

  return Array.from(grouped.values())
    .map((cluster) => ({
      ...cluster,
      examples: cluster.examples.slice(0, 2),
      summary: `${cluster.count} tasks for ${cluster.entity}; batch them into one follow-up.`,
    }))
    .sort((a, b) => b.count - a.count)
    .slice(0, 5);
};

export const runPruningPass = async () => {
  return mergeDuplicateEntitiesWithRefs();
};

export const generateWisdomSnapshot = async () => {
  const [entitySnapshot, taskSnapshot] = await Promise.all([
    db.collection("entities").get(),
    db.collection("action_items").where("status", "==", "open").get(),
  ]);

  const names = entitySnapshot.docs
    .map((doc) => (doc.get("name") ?? "").toString().trim())
    .filter(Boolean);

  const openTasks = taskSnapshot.docs
    .map((doc) => ({
      id: doc.id,
      description: (doc.get("description") ?? "").toString().trim(),
      linked_entities: Array.isArray(doc.get("linked_entities")) ? doc.get("linked_entities") : [],
      status: (doc.get("status") ?? "open").toString(),
    }))
    .filter((task) => task.description);

  const clusters = buildTaskClusters(openTasks);
  const connections = clusters.length ?
    clusters.map((cluster) => ({
      entity: cluster.entity,
      signal: `Batch follow-up: ${cluster.examples.join(" • ")}`,
    })) :
    names.slice(0, 5).map((name, index) => ({
      entity: name,
      signal: `Connected to ${index === 0 ? "the current workstream" : "the surrounding system"}${index === 0 ? "" : " context"}`,
    }));

  const clusterAdvice = clusters.map(
    (cluster) => `Advice: ${cluster.entity} has ${cluster.count} open tasks; batch them into a single follow-up.`,
  );

  const summary = clusterAdvice.length ?
    `${clusters.length} high-priority clusters remain in motion across ${openTasks.length} open tasks.` :
    `${openTasks.length} active tasks remain in motion.`;

  const insightDoc = {
    summary,
    connections,
    clusterAdvice,
    open_tasks: openTasks.map((task) => task.description),
    generatedAt: FieldValue.serverTimestamp(),
    type: "wisdom_snapshot",
  };

  const docRef = await db.collection("insights").add(insightDoc);
  return {
    docId: docRef.id,
    summary,
    connectCount: connections.length,
    clusterCount: clusters.length,
    connections,
    clusterAdvice,
  };
};

export const generateWisdomSnapshotCallable = onCall({cors: true}, async () => {
  return generateWisdomSnapshot();
});

export const pruneDuplicateEntities = onCall({cors: true}, async () => {
  return runPruningPass();
});

type CurationQuestion = {
  id: string;
  kind: "entity_detail" | "entity_date" | "entity_status" | "relationship";
  entityId: string;
  entityName: string;
  relatedEntityId?: string;
  relatedEntityName?: string;
  prompt: string;
};

const buildFallbackQuestions = (entities: Array<{
  id: string;
  name: string;
  type: string;
  summary: string;
}>): CurationQuestion[] => {
  const questions: CurationQuestion[] = [];
  const people = entities.filter((entity) =>
    entity.type.toLowerCase() === "person",
  );

  for (const person of people) {
    if (questions.length >= 5) break;
    questions.push({
      id: `person-detail-${person.id}`,
      kind: "entity_status",
      entityId: person.id,
      entityName: person.name,
      prompt: `Is ${person.name} currently active and needing attention, waiting on something, dormant, or clear for now? What is the current focus or next action?`,
    });
    if (questions.length >= 5) break;
    questions.push({
      id: `person-date-${person.id}`,
      kind: "entity_date",
      entityId: person.id,
      entityName: person.name,
      prompt: `Do you have any upcoming date, appointment, or deadline involving ${person.name}?`,
    });
  }

  for (let i = 0; i < entities.length && questions.length < 5; i++) {
    for (let j = i + 1; j < entities.length && questions.length < 5; j++) {
      questions.push({
        id: `relationship-${entities[i].id}-${entities[j].id}`,
        kind: "relationship",
        entityId: entities[i].id,
        entityName: entities[i].name,
        relatedEntityId: entities[j].id,
        relatedEntityName: entities[j].name,
        prompt: `How are ${entities[i].name} and ${entities[j].name} connected?`,
      });
    }
  }

  return questions;
};

const rankCurationGaps = async (
  entities: Array<{
    id: string;
    name: string;
    type: string;
    summary: string;
    attentionStatus?: string;
    currentFocus?: string;
  }>,
  excludedIds: string[] = [],
): Promise<CurationQuestion[]> => {
  const fallback = buildFallbackQuestions(entities).filter(
    (question) => !excludedIds.includes(question.id),
  );
  const apiKey = process.env.GEMINI_API_KEY ?? process.env.GOOGLE_API_KEY;
  if (!apiKey || entities.length === 0) return fallback;

  const entityIndex = new Map(entities.map((entity) => [entity.id, entity]));
  const graph = entities.map((entity) => ({
    id: entity.id,
    name: entity.name,
    type: entity.type,
    summary: entity.summary.slice(0, 500),
    attentionStatus: entity.attentionStatus ?? "unknown",
    currentFocus: entity.currentFocus ?? "",
  }));
  const prompt = `You are the curation intelligence for a personal second-brain graph.
Find the five most useful missing facts in this graph. Prefer gaps that improve future decisions:
- ask whether a person is currently active, waiting, dormant, or clear, and what their current focus or next action is;
- ask for an upcoming date only when a person or project has no known date;
- ask how two likely-related entities are connected when that relationship is unknown.
Avoid generic questions, duplicate questions, and invented facts. Return JSON only as:
{"questions":[{"kind":"entity_detail|entity_date|entity_status|relationship","entityId":"...","relatedEntityId":"...","prompt":"..."}]}
Use only entity IDs from the graph. Make each prompt answerable in one short sentence.
Do not repeat these answered prompt IDs: ${JSON.stringify(excludedIds)}
Graph: ${JSON.stringify(graph)}`;

  try {
    const response = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent?key=${encodeURIComponent(apiKey)}`,
      {
        method: "POST",
        headers: {"Content-Type": "application/json"},
        body: JSON.stringify({
          contents: [{role: "user", parts: [{text: prompt}]}],
          generationConfig: {temperature: 0.1},
        }),
      },
    );
    if (!response.ok) return fallback;
    const data = await response.json() as {
      candidates?: Array<{ content?: { parts?: Array<{ text?: string }> } }>;
    };
    const raw = data.candidates?.[0]?.content?.parts?.[0]?.text?.trim() ?? "";
    const start = raw.indexOf("{");
    const end = raw.lastIndexOf("}");
    if (start < 0 || end <= start) return fallback;
    const parsed = JSON.parse(raw.slice(start, end + 1)) as { questions?: unknown[] };
    const questions = (parsed.questions ?? []).flatMap((item, index): CurationQuestion[] => {
      if (!item || typeof item !== "object") return [];
      const candidate = item as Record<string, unknown>;
      const kind = candidate.kind;
      const entityId = typeof candidate.entityId === "string" ? candidate.entityId : "";
      const relatedEntityId = typeof candidate.relatedEntityId === "string" ? candidate.relatedEntityId : undefined;
      const promptText = typeof candidate.prompt === "string" ? candidate.prompt.trim() : "";
      const entity = entityIndex.get(entityId);
      const related = relatedEntityId ? entityIndex.get(relatedEntityId) : undefined;
      if (!entity || !promptText || !["entity_detail", "entity_date", "entity_status", "relationship"].includes(kind as string)) return [];
      if (kind === "relationship" && !related) return [];
      return [{
        id: `ai-${entityId}-${relatedEntityId ?? kind}-${index}`,
        kind: kind as CurationQuestion["kind"],
        entityId,
        entityName: entity.name,
        relatedEntityId,
        relatedEntityName: related?.name,
        prompt: promptText,
      }];
    }).slice(0, 5);
    return questions
      .filter((question) => !excludedIds.includes(question.id))
      .length > 0 ? questions.filter((question) => !excludedIds.includes(question.id)) : fallback;
  } catch (error) {
    console.error("Curation ranking failed; using fallback:", error);
    return fallback;
  }
};

export const generateDailyQuestions = onCall({cors: true}, async (request) => {
  const snapshot = await db.collection("entities").get();
  const entities = snapshot.docs
    .map((doc) => ({
      id: doc.id,
      name: (doc.get("name") ?? "").toString().trim(),
      type: (doc.get("type") ?? "concept").toString(),
      summary: (doc.get("summary") ?? "").toString().trim(),
      attentionStatus: (doc.get("attention_status") ?? "unknown").toString(),
      currentFocus: (doc.get("current_focus") ?? "").toString().trim(),
    }))
    .filter((entity) => entity.name);

  const excludedIds = request.data && Array.isArray(request.data.exclude_ids) ?
    request.data.exclude_ids.filter((id: unknown): id is string => typeof id === "string") :
    [];
  const questions = await rankCurationGaps(entities, excludedIds);

  return {
    questions,
    count: questions.length,
  };
});
