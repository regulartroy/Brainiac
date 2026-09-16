import * as admin from "firebase-admin";
import {FieldValue, Timestamp, getFirestore} from "firebase-admin/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {onCall} from "firebase-functions/v2/https";
import {generateWisdomSnapshot} from "./pruningReview";

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = getFirestore();

const normalizeEntityKey = (value: string) =>
  value.trim().toLowerCase().replace(/[^a-z0-9]+/g, " ").replace(/\s+/g, " ").trim();

const summarizeCapture = (content: string) => {
  const clean = content.replace(/\s+/g, " ").trim();
  if (!clean) return "Empty capture";
  return clean.length > 180 ? `${clean.slice(0, 177)}...` : clean;
};

const getRetentionDays = async () => {
  const configDoc = await db.collection("system_settings").doc("retention_policy").get();
  const storedValue = configDoc.get("retentionDays");
  const parsed = typeof storedValue === "number" ? storedValue : Number(storedValue);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    return 30;
  }
  return Math.min(365, Math.max(1, Math.round(parsed)));
};

const archiveOldCaptures = async (retentionDays?: number) => {
  const effectiveRetention = retentionDays ?? (await getRetentionDays());
  const cutoff = Timestamp.fromDate(
    new Date(Date.now() - effectiveRetention * 24 * 60 * 60 * 1000),
  );

  const snapshot = await db
    .collection("captures")
    .where("createdAt", "<", cutoff)
    .get();

  if (snapshot.empty) {
    return {archived: 0, retentionDays};
  }

  const batch = db.batch();

  for (const doc of snapshot.docs) {
    const content = (doc.get("content") ?? "").toString();
    const summary = summarizeCapture(content);

    batch.set(
      db.collection("capture_archive").doc(doc.id),
      {
        archivedAt: FieldValue.serverTimestamp(),
        originalCaptureId: doc.id,
        content: summary,
        rawPreview: content.slice(0, 1200),
        createdAt: doc.get("createdAt") ?? FieldValue.serverTimestamp(),
      },
      {merge: true},
    );

    batch.delete(doc.ref);
  }

  await batch.commit();
  return {archived: snapshot.size, retentionDays};
};

const pruneNow = async () => {
  const snapshot = await db.collection("entities").get();
  const groups = new Map<string, FirebaseFirestore.QueryDocumentSnapshot[]>();

  for (const doc of snapshot.docs) {
    const name = (doc.get("name") ?? "").toString().trim();
    if (!name) continue;

    const key = normalizeEntityKey(name);
    const existing = groups.get(key) ?? [];
    existing.push(doc);
    groups.set(key, existing);
  }

  const batch = db.batch();
  let merged = 0;

  for (const docs of groups.values()) {
    if (docs.length < 2) continue;

    merged += 1;
    const canonical = docs[0];
    const canonicalName = (canonical.get("name") ?? "").toString().trim();
    const canonicalType = (canonical.get("type") ?? "concept").toString();
    const summary = docs
      .map((doc) => (doc.get("summary") ?? "").toString().trim())
      .filter(Boolean)
      .join(" • ");

    batch.set(
      db.collection("entities").doc(canonical.id),
      {
        name: canonicalName,
        type: canonicalType,
        summary: summary || canonical.get("summary") || "",
        last_updated: FieldValue.serverTimestamp(),
      },
      {merge: true},
    );

    for (const duplicate of docs.slice(1)) {
      batch.delete(db.collection("entities").doc(duplicate.id));
    }
  }

  if (merged > 0) {
    await batch.commit();
  }

  const configuredRetention = await getRetentionDays();
  const retention = await archiveOldCaptures(configuredRetention);
  const insight = await generateWisdomSnapshot();
  console.log(
    `Pruning pass complete: merged ${merged} groups and archived ${retention.archived} captures older than ${configuredRetention} days.`,
  );
  console.log(`Wisdom snapshot generated: ${insight.docId} (${insight.clusterCount} clusters)`);
  return {merged, archived: retention.archived};
};

export const pruneGraphDaily = onSchedule(
  {
    schedule: "0 9 * * *",
    timeZone: "UTC",
  },
  async () => {
    const merged = await pruneNow();
    console.log(`Merged ${merged} duplicate entity groups.`);
  },
);

export const pruneOnCaptureCreated = onDocumentCreated("captures/{captureId}", async () => {
  const result = await pruneNow();
  console.log(
    `Pruning pass ran after capture creation; merged ${result.merged} groups and archived ${result.archived} captures.`,
  );
});

export const runRetentionSweep = onCall({cors: true}, async (request: any) => {
  const requestedDays = request.data && typeof request.data.retentionDays === "number" ?
    request.data.retentionDays :
    undefined;

  const configuredRetention = requestedDays ?? (await getRetentionDays());
  const result = await archiveOldCaptures(configuredRetention);

  return {
    archived: result.archived,
    retentionDays: configuredRetention,
  };
});

export const pruneOldCaptureArchive = onSchedule(
  {
    schedule: "0 3 * * *",
    timeZone: "UTC",
  },
  async () => {
    const configuredRetention = await getRetentionDays();
    const result = await archiveOldCaptures(configuredRetention);
    console.log(`Retention sweep archived ${result.archived} captures older than ${configuredRetention} days.`);
  },
);

