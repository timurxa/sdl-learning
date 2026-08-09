#set document(title: "Work-Graph Orchestration Framework — Version 1")
#set page(
  paper: "us-letter",
  margin: (x: 0.82in, y: 0.78in),
  numbering: "1",
)
#set text(font: "Libertinus Serif", size: 10.5pt, lang: "en")
#set par(justify: true, leading: 0.62em)
#set heading(numbering: "1.1")
#set list(indent: 1.2em, body-indent: 0.55em, spacing: 0.32em)
#set enum(indent: 1.2em, body-indent: 0.55em, spacing: 0.32em)
#show raw.where(block: true): set text(size: 8.3pt)

#let term(body) = text(weight: "semibold", body)
#let req(body) = block(
  inset: (left: 9pt, right: 9pt, top: 6pt, bottom: 6pt),
  stroke: (left: 1.4pt + rgb("4b5563")),
  fill: rgb("f7f7f8"),
  radius: 2pt,
  body,
)

#align(center)[
  #text(size: 19pt, weight: "bold")[Work-Graph Orchestration Framework]
  #v(4pt)
  #text(size: 12pt, weight: "semibold")[Version 1 Specification]
  #v(8pt)
  #text(size: 9pt, fill: rgb("555555"))[4 August 2026]
]

#v(14pt)

#req[
  This document defines the first implementation of a dynamic, artifact-oriented work-graph runtime for LLM workers, graph-creation agents, and explicit human input. It is intentionally narrow: no automatic retry policy, no recovery planner, no persistent model sessions, and no security boundary beyond basic artifact-path isolation.
]

#outline(title: [Contents], depth: 3)
#pagebreak()

= Scope and design principles

The runtime represents orchestration as one mutable directed acyclic graph rather than as separate goal, control, artifact, and task graphs. Goals, execution instructions, dependencies, and artifact declarations are properties of work nodes. Graph mutation is itself ordinary work performed by a specialized node type.

The version-1 design follows these principles:

- The canonical work graph is the only authoritative orchestration state.
- A node has one explicit objective and one execution plan.
- Artifact production and consumption are declared before execution.
- Human clarification is represented as graph work, not as an out-of-band interruption.
- Graph mutation is permitted only where a graph-creation node has exclusive downstream authority.
- Valid graph edits normally commit immediately. Staging exists only after an invalid edit opens a pending edit sequence.
- Runtime policy maps abstract reasoning levels to concrete models and inference settings.
- The scheduler runs every runnable node concurrently, subject only to execution-backend limits.

== Non-goals

Version 1 does not define:

- automatic retries, repair nodes, or failure recovery;
- persistent or shared LLM sessions;
- a structured failure record beyond node state;
- a graph-mutation event log;
- artifact MIME types, schemas, checksums, or file-versus-directory validation;
- a security sandbox for ordinary repository files;
- model names, token budgets, or provider-specific inference controls.

= Formal graph model

Let the canonical work graph be

$ G = (V, E_w, E_a) $,

where:

- $V$ is the set of canonical nodes;
- $E_w subset.eq V times V$ contains explicit `wait_for` edges;
- $E_a subset.eq V times V$ contains artifact-producer edges induced by node inputs.

For a node $v$, let $W(v)$ be its explicit `wait_for` set, and let $P(v)$ be the set of producer nodes referenced by its declared inputs. Its effective dependency set is

$ D(v) = W(v) union P(v). $

The effective edge relation is therefore

$ E = lr({ (u, v) | u in D(v) }). $

The runtime MUST preserve acyclicity of $(V, E)$ after every committed mutation.

== Readiness

A node $v$ is runnable exactly when

$ sigma(v) = "pending" and forall u in D(v): sigma(u) = "completed". $

`runnable` and `blocked` are derived properties and are not persisted.

A failed effective dependency leaves the descendant pending and permanently blocked in version 1. No automatic remediation is attempted.

== Domination and mutation authority

For graph-creation node $a$ and target node $v$, define

$ "dominates"(a, v) <=> forall p in "Paths"("Roots"(G), v): a in p. $

That is, every dependency path from every graph root to $v$ passes through $a$.

A graph-creation node may mutate a canonical node only when:

- the target is `pending`; and
- the graph-creation node dominates the target in the effective graph.

Running, completed, and failed nodes are immutable. This domination rule is the concurrency-control mechanism: graph-creation nodes may execute and commit concurrently because their editable regions cannot overlap.

= Canonical node model

Every canonical node has the following logical shape:

```json
{
  "id": "opaque-random-id",
  "description": "extremely short graph label",
  "objective": "required result",
  "inputs": [InputArtifactRef, ...],
  "outputs": [OutputArtifactDecl, ...],
  "wait_for": ["node-id", ...],
  "execution_plan": {
    "type": "llm_worker | graph_creation | human_input",
    "instructions": "executor-facing instructions"
  },
  "reasoning_level": "straightforward | bounded | deep_reasoning",
  "state": "pending | running | completed | failed"
}
```

`id` and `state` are runtime-owned. `create_node` accepts every other applicable field, generates a random opaque identifier, and initializes `state` to `pending`.

== Field semantics

#table(
  columns: (1.25fr, 3.75fr),
  inset: 5pt,
  stroke: 0.45pt + rgb("b8b8b8"),
  [*Field*], [*Meaning*],
  [`description`], [An extremely short graph label used in compact graph views.],
  [`objective`], [The result the node must achieve.],
  [`inputs`], [Declared artifact references available to the node.],
  [`outputs`], [Paths whose existence is required for successful completion.],
  [`wait_for`], [Explicit completion dependencies only. Artifact-producer dependencies are computed dynamically.],
  [`execution_plan.type`], [Selects execution semantics and available orchestration tools.],
  [`execution_plan.instructions`], [How the executor should perform the work. For human input, this is the exact question shown to the user.],
  [`reasoning_level`], [Abstract inference requirement mapped externally to a concrete runtime configuration.],
  [`state`], [Persisted lifecycle state.],
)

== Reasoning levels

The allowed reasoning levels are:

- `straightforward`: the task is clear and requires little discretionary reasoning;
- `bounded`: the task requires nontrivial but limited analysis;
- `deep_reasoning`: the task requires extensive planning, synthesis, or difficult reasoning.

`reasoning_level` is required for `llm_worker` and `graph_creation`, and omitted for `human_input`. The runtime, not the node schema, maps these values to models, reasoning effort, and related provider settings.

= Artifact model

== Declarations

An input artifact reference is:

```json
{
  "producer_node_id": "node-id",
  "path": "nested/relative/path.ext",
  "description": "brief purpose"
}
```

An output artifact declaration is:

```json
{
  "path": "nested/relative/path.ext",
  "description": "brief content description",
  "final": false
}
```

`final` defaults to `false` when omitted.

Every input reference MUST exactly match an output path declared by `producer_node_id`. A declaration may refer to either a regular file or a directory. Completion validates existence only; it does not validate object type or content.

Within one node, duplicate output paths are invalid. Different nodes may use the same relative output path because each node has a separate artifact root.

== Paths and isolation

The controlled artifact repository is

```text
{cwd}/orchestration/artifacts/
```

A node output path resolves to

```text
{cwd}/orchestration/artifacts/{current_node_id}/{declared_output_path}
```

Within this repository:

- a node may read only artifacts declared in its `inputs`;
- a node may write only beneath its own node directory;
- absolute artifact paths are invalid;
- traversal components such as `..` are invalid.

This is basic race and ownership isolation, not a security boundary. Version 1 imposes no additional restrictions on ordinary files outside `orchestration/artifacts/`. In particular, a `graph_creation` node may use normal filesystem and task tools outside the artifact repository even though it cannot declare task artifacts.

== Prompt inclusion

Node prompts include only each input artifact's structured reference, resolved path, and brief description. Artifact contents are not injected into the prompt. The model reads an artifact through filesystem tools when necessary.

= Execution-plan semantics

== `llm_worker`

An `llm_worker` receives:

- its complete canonical node record;
- resolved input references, without injected contents;
- a compact canonical graph context;
- ordinary task and filesystem tools;
- `finish_node()`.

It does not receive `get_node`, graph-view, or graph-mutation tools. It MUST not create or modify the work graph.

== `graph_creation`

A `graph_creation` node receives:

- its complete canonical node record;
- resolved input references, without injected contents;
- the default compact canonical graph context;
- ordinary task and filesystem tools;
- canonical graph-inspection tools;
- graph-mutation tools;
- pending-edit inspection and control tools;
- `finish_node()`.

It may consume declared artifacts. Its canonical `outputs` MUST be `[]`. It may complete without creating or modifying downstream nodes.

Its durable orchestration effect is graph mutation. Its instructions SHOULD direct it to create human-input work when the objective contains material ambiguity or underspecification. A common clarification structure is:

```text
human_input node(s)
        ↓
subsequent graph_creation node
        ↓
clarified worker subgraph
```

Independent questions may be represented by parallel human-input nodes. A downstream graph-creation node can consume their responses and synthesize the clarified work graph.

== `human_input`

A `human_input` node invokes no model. One node produces exactly one human response.

The orchestrator:

1. presents `execution_plan.instructions` exactly as the user-facing question;
2. waits for one user response;
3. creates the node's single runtime-generated output;
4. writes the instructions first and the response verbatim beneath them;
5. completes the node after the artifact exists.

The runtime-generated artifact uses a conventional path such as `response.txt` beneath the node's artifact directory and logically contains:

```text
Instructions:
{execution_plan.instructions}

Response:
{verbatim user response}
```

The graph creator does not choose this output path or declaration.

= Context construction and graph inspection

== Default compact context

Both LLM-backed node types receive a local compact view of the canonical graph. Selection is breadth-first by shortest graph distance, with deterministic tie-breaking. The default includes approximately two to five nearby nodes in each direction, depending on configured context limits.

Each compact node entry contains only:

- node ID;
- extremely short description;
- execution-plan type;
- relevant incoming and outgoing edges.

Full objectives, instructions, artifact declarations, and other node fields are omitted from this compact view.

== Graph-creation inspection tools

A graph-creation node may request more canonical context through:

```text
get_node(node_id)
get_graph_view(direction, depth, max_nodes)
```

`direction` supports ancestor, descendant, or bidirectional traversal. Context breadth and depth are runtime-configurable so larger descendant regions can be exposed when needed.

All ordinary graph-inspection operations show the canonical graph only. They never expose speculative graph state. Speculative state is visible exclusively through pending-edit tools.

= Scheduling and lifecycle

== State machine

The canonical lifecycle is:

```text
pending → running → completed
                  ↘ failed
```

The scheduler launches every runnable node concurrently. The orchestration layer defines no separate concurrency cap; provider, process, and execution-backend limits may constrain actual parallelism.

Each LLM-backed node receives a fresh model thread in version 1.

== Completion attempts

A completion attempt occurs when either:

- the executor calls `finish_node()`; or
- the model turn terminates normally.

Both paths use identical validation. `finish_node()` takes no arguments.

For an LLM worker, completion succeeds only when every declared output path exists.

For a graph-creation node, completion succeeds only when:

- `outputs` is empty; and
- no pending edit remains.

Any failed completion attempt immediately marks the node `failed`. The thread is not resumed for correction. This applies equally to explicit `finish_node()` and normal turn termination.

Crashes, timeouts, and uncaught execution errors also mark the current node `failed`. Version 1 performs no automatic retry.

If a graph-creation node fails, every uncommitted pending edit owned by that node is discarded and the canonical graph remains unchanged by those edits.

= Graph mutation API

Only a running `graph_creation` node may use graph mutation tools.

== Core tools

The logical API is:

```text
create_node(node_definition, edit_id?)
update_node(node_id, changes, edit_id?)
delete_node(node_id, edit_id?)
reassign_output(
  source_node_id,
  source_path,
  destination_node_id,
  destination_path,
  edit_id?
)

get_node(node_id)
get_graph_view(direction, depth, max_nodes)

list_pending_edits()
get_pending_edit(edit_id)
discard_edit(edit_id)

finish_node()
```

`update_node` may replace multiple top-level fields atomically. Array-valued fields such as `inputs`, `outputs`, and `wait_for` are replaced as complete values. It may change any field of an editable pending node except runtime-owned `id` and `state`, including execution type and reasoning level.

== Creation rules

`create_node` accepts a complete applicable node definition except `id` and `state`.

The runtime automatically ensures that a created node effectively depends on the current graph-creation node. If this dependency is not already induced by an input artifact, the current graph-creation node is added to the new node's explicit `wait_for` set.

The resulting graph must still satisfy acyclicity and domination authority. A proposal that introduces another root-to-target path bypassing the current graph creator is invalid.

== Deletion

A pending dominated node may be deleted only after all references to it have been removed or rewired. If any canonical or earlier speculative `wait_for` entry or input reference still targets it, deletion is invalid and enters or remains in the pending edit sequence.

== Output reassignment

`reassign_output` is one atomic logical mutation. It:

1. removes an output declaration from a pending source node;
2. adds the declaration to a pending destination node, optionally under a new relative path;
3. rewrites every mutable pending input reference to the destination producer and path;
4. revalidates effective dependencies, authority, and acyclicity.

Because only pending nodes are editable, the artifact does not yet exist and no physical filesystem move is required. Domination and pending-only mutation rules already guarantee that affected consumers are mutable; no redundant consumer-state rule is needed.

= Validation and pending edit sequences

== Immediate commit path

When no pending sequence exists, a valid proposed mutation commits immediately to the canonical graph.

== Opening a pending sequence

When a mutation is invalid:

- it receives an opaque `edit_id`;
- it becomes the first pending edit;
- the canonical graph is unchanged;
- every subsequent mutation from that same graph-creation node is appended to the same pending sequence, even if individually valid.

Pending sequences are scoped to the invoking graph-creation node. Unrelated graph creators may continue committing edits concurrently in disjoint dominated regions.

== Speculative evaluation

Pending edits are applied and validated in sequence order against a private speculative graph derived from the canonical graph. Later edits may reference nodes created or modified by earlier pending edits using their normal opaque node IDs.

An invalid `create_node` still allocates its random opaque node ID immediately. The node is not canonical, is not schedulable, and is invisible to `get_node` and ordinary graph views, but later edits in the same sequence may reference it.

The runtime distinguishes at least:

```text
committed
pending_valid
pending_invalid
```

Mutation responses SHOULD include:

```json
{
  "edit_id": "opaque-edit-id",
  "status": "committed | pending_valid | pending_invalid",
  "errors": [
    {
      "field_path": "inputs[1]",
      "code": "unknown_output",
      "message": "Referenced output is not declared by producer",
      "expected": "a declared producer output path"
    }
  ]
}
```

Errors identify erroneous fields precisely enough for correction and MUST be relayed to the LLM.

== Correcting an edit

There is no separate patch command. The graph creator calls the original mutation command again with the pending `edit_id` and replacement values for one or more top-level fields. Omitted fields retain their staged values. The runtime then revalidates that edit and every later edit in sequence order.

== Inspecting pending state

`list_pending_edits()` returns the sequence order, status, affected node IDs, and current validation errors for all pending edits owned by the current graph-creation node.

`get_pending_edit(edit_id)` returns the staged mutation payload, status, affected node IDs, and current errors for one edit.

These tools expose speculative mutation state. Ordinary graph-inspection tools do not.

== Discarding and revalidation

`discard_edit(edit_id)` removes the selected edit and revalidates every later edit against the revised speculative sequence.

If discarding an earlier edit invalidates dependent later edits, those edits remain pending and their new field-level errors are returned to the LLM.

== Automatic group commit

After every correction or discard, if every remaining staged edit is valid, the runtime atomically commits the entire ordered sequence to the canonical graph and clears the pending sequence.

A graph-creation node cannot complete while any pending edit exists. Attempting completion in that state marks the node failed and discards the sequence.

= Bootstrap procedure

A new orchestration begins with exactly one root node:

```json
{
  "description": "Create work graph",
  "objective": "{original user request, verbatim}",
  "inputs": [],
  "outputs": [],
  "wait_for": [],
  "execution_plan": {
    "type": "graph_creation",
    "instructions": "Construct the work graph for the objective. If material ambiguities or underspecifications exist, strongly prefer creating one or more human_input nodes and a subsequent graph_creation node that consumes and synthesizes their responses before expanding the affected work."
  },
  "reasoning_level": "{runtime-selected graph-planning level}",
  "state": "pending"
}
```

There is no privileged planner outside the graph. The bootstrap node is an ordinary graph-creation node and follows the same mutation, authority, context, and completion rules.

The runtime selects the bootstrap reasoning level according to request complexity. This selection is a runtime policy, not an additional node field.

= Orchestration termination

The orchestration succeeds exactly when

$ forall v in V: sigma(v) = "completed". $

If any node is failed, or any pending node is blocked by a failed dependency, the orchestration remains incomplete. Version 1 does not define a recovery transition.

On successful completion, the runtime lists every existing artifact whose declaration has `final: true`. It does not infer finality from file type, graph position, or naming convention.

Zero final artifacts is valid. In that case, successful completion reports no final artifact paths.

= Normative invariants

The implementation MUST preserve all of the following:

1. The effective dependency graph is acyclic.
2. Canonical node IDs are opaque and random.
3. Only `pending` dominated nodes are mutable.
4. `wait_for` stores explicit dependencies only.
5. Artifact-producer dependencies are derived dynamically from validated inputs.
6. Every input references an output declared by its producer.
7. Output paths are relative, traversal-free, and unique within a node.
8. `graph_creation.outputs` is always empty.
9. `human_input` has exactly one runtime-generated response output.
10. Ordinary graph views expose canonical state only.
11. Pending edits are evaluated in deterministic sequence order.
12. A pending sequence commits only when every retained edit is valid.
13. A failed graph-creation node leaves no uncommitted speculative mutation behind.
14. Completion failure is terminal for the current node.
15. Successful orchestration requires every canonical node to be completed.

= Reference execution flow

Consider an underspecified request requiring two independent human decisions.

```text
G0: Create work graph
 ├─ H1: Ask deployment target
 └─ H2: Ask latency constraint
          H1 ─┐
              ├─ G1: Synthesize answers and expand graph
          H2 ─┘
                    ├─ W1: Implement
                    └─ W2: Verify
```

1. `G0` creates `H1`, `H2`, and `G1`; each created node effectively depends on `G0`.
2. `G0` completes. `H1` and `H2` become runnable and are presented concurrently.
3. The runtime writes each question and verbatim response to that node's generated artifact.
4. `G1` becomes runnable after both human inputs complete.
5. `G1` reads the two response artifacts and creates `W1` and `W2`.
6. Worker nodes execute when their explicit and artifact-derived dependencies are completed.
7. The orchestration succeeds only when every canonical node is completed.
8. The final response lists outputs explicitly marked `final: true`.

= Minimal implementation decomposition

A direct implementation can be organized into the following components:

- *Canonical graph store*: nodes, explicit edges, and derived producer edges.
- *Validator*: schema, reference, path, acyclicity, domination, and state checks.
- *Scheduler*: readiness derivation and concurrent launch.
- *Execution adapters*: LLM worker, graph creation, and human input.
- *Artifact resolver*: path resolution, access checks, and completion existence checks.
- *Context builder*: deterministic breadth-first compact graph views.
- *Mutation engine*: immediate commits and per-graph-creator pending sequences.
- *Completion controller*: explicit and implicit completion attempts.
- *Result collector*: enumeration of existing `final: true` artifacts.

No additional goal graph, artifact graph, control graph, or planner service is required for version 1.
