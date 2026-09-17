import {FieldValue, getFirestore} from "firebase-admin/firestore";

const getDb = () => getFirestore();

export const normalizeEntityKey = (value: string): string =>
  value
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();

export const canonicalizeEntityName = (value: string): string =>
  value.trim().replace(/\s+/g, " ");

export const entityIdForName = (name: string): string =>
  canonicalizeEntityName(name)
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "");

export type AliasMaps = {
  /** normalized name key -> canonical display name */
  nameByKey: Map<string, string>;
  /** entity doc id (or derived id) -> canonical entity doc id */
  idByAlias: Map<string, string>;
  /** canonical entity doc id -> canonical display name */
  nameByCanonicalId: Map<string, string>;
};

export type MergeStats = {
  mergedGroups: number;
  entitiesDeleted: number;
  actionItemsUpdated: number;
  relationshipsUpdated: number;
  relationshipsRemoved: number;
  relationshipsDeduped: number;
  status: string;
};

export const emptyMergeStats = (): MergeStats => ({
  mergedGroups: 0,
  entitiesDeleted: 0,
  actionItemsUpdated: 0,
  relationshipsUpdated: 0,
  relationshipsRemoved: 0,
  relationshipsDeduped: 0,
  status: "ok",
});

/** Pure helper: rewrite a list of entity name strings onto canonical names. */
export const rewriteLinkedEntityNames = (
  linked: string[],
  aliasNames: Set<string>,
  canonicalName: string,
  normalize: (value: string) => string = normalizeEntityKey,
): {updated: string[]; changed: boolean} => {
  const aliasKeys = new Set(
    [...aliasNames].map((name) => normalize(name)).filter(Boolean),
  );
  const updated: string[] = [];
  let changed = false;

  for (const value of linked) {
    const trimmed = value.trim();
    if (!trimmed) continue;
    if (aliasKeys.has(normalize(trimmed))) {
      if (!updated.includes(canonicalName)) {
        updated.push(canonicalName);
      }
      if (trimmed !== canonicalName) changed = true;
    } else if (!updated.includes(trimmed)) {
      updated.push(trimmed);
    } else {
      changed = true; // dropped duplicate
    }
  }

  if (updated.length !== linked.filter((v) => v.trim()).length) {
    changed = true;
  }
  return {updated, changed};
};

/** Pure helper: rewrite linked entity id list onto canonical ids. */
export const rewriteLinkedEntityIds = (
  linkedIds: string[],
  aliasIds: Set<string>,
  canonicalId: string,
): {updated: string[]; changed: boolean} => {
  const updated: string[] = [];
  let changed = false;

  for (const value of linkedIds) {
    const trimmed = value.trim();
    if (!trimmed) continue;
    if (aliasIds.has(trimmed)) {
      if (!updated.includes(canonicalId)) {
        updated.push(canonicalId);
      }
      if (trimmed !== canonicalId) changed = true;
    } else if (!updated.includes(trimmed)) {
      updated.push(trimmed);
    } else {
      changed = true;
    }
  }

  if (updated.length !== linkedIds.filter((v) => v.trim()).length) {
    changed = true;
  }
  return {updated, changed};
};

export type RelationshipRewrite = {
  from_entity: string;
  to_entity: string;
  from_entity_id: string;
  to_entity_id: string;
  type: string;
  drop: boolean;
  changed: boolean;
  edgeKey: string;
};

/** Pure helper: remap one relationship edge through alias maps; drop self-loops. */
export const rewriteRelationshipEdge = (
  edge: {
    from_entity?: string;
    to_entity?: string;
    from_entity_id?: string;
    to_entity_id?: string;
    type?: string;
  },
  maps: AliasMaps,
): RelationshipRewrite => {
  const type = (edge.type ?? "related").toString().trim() || "related";
  let fromName = (edge.from_entity ?? "").toString().trim();
  let toName = (edge.to_entity ?? "").toString().trim();
  let fromId = (edge.from_entity_id ?? "").toString().trim();
  let toId = (edge.to_entity_id ?? "").toString().trim();
  let changed = false;

  const fromKey = normalizeEntityKey(fromName);
  const toKey = normalizeEntityKey(toName);

  if (fromKey && maps.nameByKey.has(fromKey)) {
    const next = maps.nameByKey.get(fromKey)!;
    if (next !== fromName) {
      fromName = next;
      changed = true;
    }
  }
  if (toKey && maps.nameByKey.has(toKey)) {
    const next = maps.nameByKey.get(toKey)!;
    if (next !== toName) {
      toName = next;
      changed = true;
    }
  }
  if (fromId && maps.idByAlias.has(fromId)) {
    const next = maps.idByAlias.get(fromId)!;
    if (next !== fromId) {
      fromId = next;
      changed = true;
    }
  }
  if (toId && maps.idByAlias.has(toId)) {
    const next = maps.idByAlias.get(toId)!;
    if (next !== toId) {
      toId = next;
      changed = true;
    }
  }

  // Fill missing ids from remapped names when possible.
  if (!fromId && fromName) {
    fromId = entityIdForName(fromName);
    const mapped = maps.idByAlias.get(fromId) ?? fromId;
    if (maps.nameByCanonicalId.has(mapped)) {
      fromId = mapped;
    }
  }
  if (!toId && toName) {
    toId = entityIdForName(toName);
    const mapped = maps.idByAlias.get(toId) ?? toId;
    if (maps.nameByCanonicalId.has(mapped)) {
      toId = mapped;
    }
  }

  const fromNorm = normalizeEntityKey(fromName);
  const toNorm = normalizeEntityKey(toName);
  const drop =
    !fromName ||
    !toName ||
    fromNorm === toNorm ||
    (Boolean(fromId) && Boolean(toId) && fromId === toId);

  const edgeKey = `${fromNorm}|${toNorm}|${normalizeEntityKey(type)}`;

  return {
    from_entity: fromName,
    to_entity: toName,
    from_entity_id: fromId,
    to_entity_id: toId,
    type,
    drop,
    changed,
    edgeKey,
  };
};

const pickCanonical = (
  docs: FirebaseFirestore.QueryDocumentSnapshot[],
): FirebaseFirestore.QueryDocumentSnapshot => {
  const ranked = [...docs].sort((a, b) => {
    const summaryA = (a.get("summary") ?? "").toString().trim().length;
    const summaryB = (b.get("summary") ?? "").toString().trim().length;
    if (summaryB !== summaryA) return summaryB - summaryA;
    const nameA = canonicalizeEntityName((a.get("name") ?? "").toString());
    const nameB = canonicalizeEntityName((b.get("name") ?? "").toString());
    if (nameA.length !== nameB.length) return nameB.length - nameA.length;
    return a.id.localeCompare(b.id);
  });
  return ranked[0];
};

const commitInChunks = async (
  ops: Array<(batch: FirebaseFirestore.WriteBatch) => void>,
) => {
  const chunkSize = 400;
  for (let i = 0; i < ops.length; i += chunkSize) {
    const batch = getDb().batch();
    for (const op of ops.slice(i, i + chunkSize)) {
      op(batch);
    }
    await batch.commit();
  }
};

/**
 * Merge duplicate entities (normalized name keys), rewrite references on
 * action_items + relationships, drop self-loops / edges to merged aliases,
 * and dedupe identical relationship edges.
 */
export const mergeDuplicateEntitiesWithRefs = async (): Promise<MergeStats> => {
  const stats = emptyMergeStats();
  const entitySnapshot = await getDb().collection("entities").get();
  const groups = new Map<string, FirebaseFirestore.QueryDocumentSnapshot[]>();

  for (const doc of entitySnapshot.docs) {
    const name = (doc.get("name") ?? "").toString().trim();
    if (!name) continue;
    const key = normalizeEntityKey(name);
    if (!key) continue;
    const existing = groups.get(key) ?? [];
    existing.push(doc);
    groups.set(key, existing);
  }

  const maps: AliasMaps = {
    nameByKey: new Map(),
    idByAlias: new Map(),
    nameByCanonicalId: new Map(),
  };

  type MergePlan = {
    canonical: FirebaseFirestore.QueryDocumentSnapshot;
    duplicates: FirebaseFirestore.QueryDocumentSnapshot[];
    canonicalName: string;
    aliasNames: Set<string>;
    aliasIds: Set<string>;
  };

  const plans: MergePlan[] = [];

  for (const docs of groups.values()) {
    if (docs.length < 2) {
      // Still register singleton for id/name lookup used by relationship rewrite.
      const only = docs[0];
      if (!only) continue;
      const name = canonicalizeEntityName((only.get("name") ?? "").toString());
      const key = normalizeEntityKey(name);
      if (key) maps.nameByKey.set(key, name);
      maps.idByAlias.set(only.id, only.id);
      maps.nameByCanonicalId.set(only.id, name);
      const derived = entityIdForName(name);
      if (derived) maps.idByAlias.set(derived, only.id);
      continue;
    }

    const canonical = pickCanonical(docs);
    const duplicates = docs.filter((doc) => doc.id !== canonical.id);
    const canonicalName = canonicalizeEntityName(
      (canonical.get("name") ?? "").toString(),
    );
    const aliasNames = new Set<string>();
    const aliasIds = new Set<string>([canonical.id]);

    for (const doc of docs) {
      const name = canonicalizeEntityName((doc.get("name") ?? "").toString());
      if (name) aliasNames.add(name);
      aliasIds.add(doc.id);
      const derived = entityIdForName(name);
      if (derived) aliasIds.add(derived);
    }

    plans.push({canonical, duplicates, canonicalName, aliasNames, aliasIds});

    for (const name of aliasNames) {
      const key = normalizeEntityKey(name);
      if (key) maps.nameByKey.set(key, canonicalName);
    }
    for (const aliasId of aliasIds) {
      maps.idByAlias.set(aliasId, canonical.id);
    }
    maps.nameByCanonicalId.set(canonical.id, canonicalName);
  }

  if (plans.length === 0) {
    // Still run relationship hygiene (dedupe + orphan cleanup) even with no merges.
    const hygiene = await hygieneRelationships(maps);
    stats.relationshipsRemoved = hygiene.removed;
    stats.relationshipsDeduped = hygiene.deduped;
    stats.relationshipsUpdated = hygiene.updated;
    return stats;
  }

  const entityOps: Array<(batch: FirebaseFirestore.WriteBatch) => void> = [];

  for (const plan of plans) {
    stats.mergedGroups += 1;
    const summary = [plan.canonical, ...plan.duplicates]
      .map((doc) => (doc.get("summary") ?? "").toString().trim())
      .filter(Boolean)
      .join(" • ");
    const canonicalType = (plan.canonical.get("type") ?? "concept").toString();

    entityOps.push((batch) => {
      batch.set(
        plan.canonical.ref,
        {
          name: plan.canonicalName,
          type: canonicalType,
          summary: summary || plan.canonical.get("summary") || "",
          last_updated: FieldValue.serverTimestamp(),
        },
        {merge: true},
      );
    });

    for (const duplicate of plan.duplicates) {
      stats.entitiesDeleted += 1;
      entityOps.push((batch) => {
        batch.delete(duplicate.ref);
      });
    }
  }

  await commitInChunks(entityOps);

  // Rewrite action_items via maps.nameByKey / idByAlias (already canonical).
  const taskSnapshot = await getDb().collection("action_items").get();
  const taskOps: Array<(batch: FirebaseFirestore.WriteBatch) => void> = [];

  for (const taskDoc of taskSnapshot.docs) {
    const linkedRaw = taskDoc.get("linked_entities");
    const linkedIdsRaw = taskDoc.get("linked_entity_ids");
    const linked = Array.isArray(linkedRaw) ?
      linkedRaw.filter((v): v is string => typeof v === "string") :
      [];
    const linkedIds = Array.isArray(linkedIdsRaw) ?
      linkedIdsRaw.filter((v): v is string => typeof v === "string") :
      [];

    // Remap names via global nameByKey so multi-group merges stay consistent.
    const remappedNames: string[] = [];
    let namesChanged = false;
    for (const value of linked) {
      const trimmed = value.trim();
      if (!trimmed) {
        namesChanged = true;
        continue;
      }
      const key = normalizeEntityKey(trimmed);
      const canonical = key && maps.nameByKey.has(key) ?
        maps.nameByKey.get(key)! :
        trimmed;
      if (canonical !== trimmed) namesChanged = true;
      if (!remappedNames.includes(canonical)) {
        remappedNames.push(canonical);
      } else if (canonical === trimmed) {
        // duplicate entry
        namesChanged = true;
      }
    }
    if (remappedNames.length !== linked.filter((v) => v.trim()).length) {
      namesChanged = true;
    }

    const remappedIds: string[] = [];
    let idsChanged = false;
    for (const value of linkedIds) {
      const trimmed = value.trim();
      if (!trimmed) {
        idsChanged = true;
        continue;
      }
      const canonical = maps.idByAlias.has(trimmed) ?
        maps.idByAlias.get(trimmed)! :
        trimmed;
      if (canonical !== trimmed) idsChanged = true;
      if (!remappedIds.includes(canonical)) {
        remappedIds.push(canonical);
      } else {
        idsChanged = true;
      }
    }
    if (remappedIds.length !== linkedIds.filter((v) => v.trim()).length) {
      idsChanged = true;
    }

    // If we have names but missing/stale ids, rebuild ids from remapped names.
    if (remappedNames.length > 0) {
      const derived = remappedNames.map((name) => {
        const key = normalizeEntityKey(name);
        // Prefer live canonical doc id when known.
        for (const [id, display] of maps.nameByCanonicalId.entries()) {
          if (normalizeEntityKey(display) === key) return id;
        }
        const fallback = entityIdForName(name);
        return maps.idByAlias.get(fallback) ?? fallback;
      });
      const uniqueDerived = [...new Set(derived.filter(Boolean))];
      if (
        uniqueDerived.length !== remappedIds.length ||
        uniqueDerived.some((id, i) => id !== remappedIds[i])
      ) {
        remappedIds.splice(0, remappedIds.length, ...uniqueDerived);
        idsChanged = true;
      }
    }

    if (namesChanged || idsChanged) {
      stats.actionItemsUpdated += 1;
      const patch: Record<string, unknown> = {};
      if (namesChanged || linked.length > 0) {
        patch.linked_entities = remappedNames;
      }
      if (idsChanged || linkedIds.length > 0 || remappedNames.length > 0) {
        patch.linked_entity_ids = remappedIds;
      }
      taskOps.push((batch) => {
        batch.update(taskDoc.ref, patch);
      });
    }
  }

  if (taskOps.length > 0) {
    await commitInChunks(taskOps);
  }

  const hygiene = await hygieneRelationships(maps);
  stats.relationshipsRemoved = hygiene.removed;
  stats.relationshipsDeduped = hygiene.deduped;
  stats.relationshipsUpdated = hygiene.updated;

  return stats;
};

const hygieneRelationships = async (
  maps: AliasMaps,
): Promise<{updated: number; removed: number; deduped: number}> => {
  const snapshot = await getDb().collection("relationships").get();
  const ops: Array<(batch: FirebaseFirestore.WriteBatch) => void> = [];
  let updated = 0;
  let removed = 0;
  let deduped = 0;
  const seenKeys = new Map<string, string>(); // edgeKey -> kept doc id

  for (const doc of snapshot.docs) {
    const rewritten = rewriteRelationshipEdge(
      {
        from_entity: (doc.get("from_entity") ?? "").toString(),
        to_entity: (doc.get("to_entity") ?? "").toString(),
        from_entity_id: (doc.get("from_entity_id") ?? "").toString(),
        to_entity_id: (doc.get("to_entity_id") ?? "").toString(),
        type: (doc.get("type") ?? "related").toString(),
      },
      maps,
    );

    // Drop self-loops / empty ends after alias remap (merged entity pointing at itself).
    if (rewritten.drop) {
      removed += 1;
      ops.push((batch) => batch.delete(doc.ref));
      continue;
    }

    const existing = seenKeys.get(rewritten.edgeKey);
    if (existing) {
      deduped += 1;
      ops.push((batch) => batch.delete(doc.ref));
      continue;
    }
    seenKeys.set(rewritten.edgeKey, doc.id);

    if (rewritten.changed) {
      updated += 1;
      ops.push((batch) => {
        batch.update(doc.ref, {
          from_entity: rewritten.from_entity,
          to_entity: rewritten.to_entity,
          from_entity_id: rewritten.from_entity_id,
          to_entity_id: rewritten.to_entity_id,
          type: rewritten.type,
          last_updated: FieldValue.serverTimestamp(),
        });
      });
    }
  }

  if (ops.length > 0) {
    await commitInChunks(ops);
  }

  return {updated, removed, deduped};
};
