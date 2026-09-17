import * as admin from "firebase-admin";
import {FieldValue, Timestamp, getFirestore} from "firebase-admin/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {onCall} from "firebase-functions/v2/https";
import {generateWisdomSnapshot} from "./pruningReview";
import {mergeDuplicateEntitiesWithRefs} from "./entityMerge";

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = getFirestore();

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
  const merge = await mergeDuplicateEntitiesWithRefs();
  const configuredRetention = await getRetentionDays();
  const retention = await archiveOldCaptures(configuredRetention);
  const insight = await generateWisdomSnapshot();
  console.log(
    `Pruning pass complete: merged ${merge.mergedGroups} groups ` +
    `(deleted ${merge.entitiesDeleted} entities, updated ${merge.actionItemsUpdated} action items, ` +
    `rel updated/removed/deduped ${merge.relationshipsUpdated}/${merge.relationshipsRemoved}/${merge.relationshipsDeduped}); ` +
    `archived ${retention.archived} captures older than ${configuredRetention} days.`,
  );
  console.log(`Wisdom snapshot generated: ${insight.docId} (${insight.clusterCount} clusters)`);
  return {
    ...merge,
    merged: merge.mergedGroups,
    archived: retention.archived,
  };
};

export const pruneGraphDaily = onSchedule(
  {
    schedule: "0 9 * * *",
    timeZone: "UTC",
  },
  async () => {
    const result = await pruneNow();
    console.log(
      `Merged ${result.merged} duplicate entity groups; ` +
      `updated ${result.actionItemsUpdated} action items; ` +
      `relationship hygiene u/r/d ` +
      `${result.relationshipsUpdated}/${result.relationshipsRemoved}/${result.relationshipsDeduped}.`,
    );
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

