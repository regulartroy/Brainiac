const assert = require("assert");
const {
  normalizeEntityKey,
  rewriteLinkedEntityNames,
  rewriteLinkedEntityIds,
  rewriteRelationshipEdge,
} = require("../lib/entityMerge");

function run() {
  assert.strictEqual(normalizeEntityKey("Alice Johnson!"), "alice johnson");

  const names = rewriteLinkedEntityNames(
    ["Alice Johnson ", "Studio A", "Alice Johnson"],
    new Set(["Alice Johnson", "Alice Johnson "]),
    "Alice Johnson",
  );
  assert.deepStrictEqual(names.updated, ["Alice Johnson", "Studio A"]);
  assert.strictEqual(names.changed, true);

  const ids = rewriteLinkedEntityIds(
    ["alice_dup", "studio_a"],
    new Set(["alice_dup", "alice_johnson"]),
    "alice_johnson",
  );
  assert.deepStrictEqual(ids.updated, ["alice_johnson", "studio_a"]);
  assert.strictEqual(ids.changed, true);

  const edge = rewriteRelationshipEdge(
    {
      from_entity: "Alice Johnson!",
      to_entity: "Project Atlas",
      from_entity_id: "alice_dup",
      to_entity_id: "project_atlas",
      type: "works_on",
    },
    {
      nameByKey: new Map([["alice johnson", "Alice Johnson"]]),
      idByAlias: new Map([["alice_dup", "alice_johnson"]]),
      nameByCanonicalId: new Map([["alice_johnson", "Alice Johnson"]]),
    },
  );
  assert.strictEqual(edge.from_entity, "Alice Johnson");
  assert.strictEqual(edge.from_entity_id, "alice_johnson");
  assert.strictEqual(edge.drop, false);
  assert.strictEqual(edge.changed, true);

  const loop = rewriteRelationshipEdge(
    {
      from_entity: "Alice Johnson!",
      to_entity: "Alice Johnson",
      from_entity_id: "alice_dup",
      to_entity_id: "alice_johnson",
      type: "related",
    },
    {
      nameByKey: new Map([["alice johnson", "Alice Johnson"]]),
      idByAlias: new Map([
        ["alice_dup", "alice_johnson"],
        ["alice_johnson", "alice_johnson"],
      ]),
      nameByCanonicalId: new Map([["alice_johnson", "Alice Johnson"]]),
    },
  );
  assert.strictEqual(loop.drop, true);

  console.log("entityMerge.pure.test.js: ok");
}

run();
