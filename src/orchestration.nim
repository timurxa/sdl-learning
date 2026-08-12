import std/[json, monotimes, os, options, sequtils, strutils, tables]
import codex_bridge
import codex_json
import orchestration_storage

type
  ExecutionPlanType* = enum
    llm_worker
    graph_creation
    human_input

  ReasoningLevel* = enum
    straightforward
    bounded
    deep_reasoning

  ExecutionPlan* = object
    instructions*: string
    reasoning_level*: ReasoningLevel
    case `type`*: ExecutionPlanType
    of graph_creation:
      allowed*: seq[string]
      disallowed*: seq[string]
    of llm_worker, human_input:
      discard

  ExecutionContract = object
    requires_single_output: bool
    graph_creator: bool
    missing_output_label: string

  InputArtifactRef* = object
    producer_node_id*: uint32
    path*: string
    description*: string

  OutputArtifactDecl* = object
    path*: string
    description*: string
    final*: bool

  NodeState* = enum
    pending
    running
    awaiting_human_input
    completed
    failed

  CompletionSource* = enum
    completion_normal_turn
    completion_finish_node
    completion_human_input
    completion_runtime_error
    completion_watchdog

  LifecycleDisposition* = enum
    lifecycle_accepted
    lifecycle_rejected
    lifecycle_duplicate
    lifecycle_late_suppressed

  LifecycleDiagnostic* = object
    node_id*: uint32
    execution_type*: ExecutionPlanType
    source*: CompletionSource
    disposition*: LifecycleDisposition
    old_state*: NodeState
    new_state*: NodeState
    reason*: string
    thread_id*: string
    turn_id*: string
    request_id*: string
    output_paths_checked*: seq[string]
    validation_result*: string
    started_ticks*: int64
    terminal_ticks*: int64
    elapsed_milliseconds*: int64

  CodexEventResult* = object
    error*: string
    disposition*: LifecycleDisposition

  LifecycleCounters* = object
    node_starts*: uint64
    explicit_finish_calls*: uint64
    successful_completion_attempts*: uint64
    failed_completion_attempts*: uint64
    duplicate_finish_calls*: uint64
    late_terminal_events*: uint64
    post_terminal_turn_starts*: uint64
    watchdog_timeouts*: uint64
    unmapped_completions*: uint64
    finish_response_enqueue_failures*: uint64

  NodeLifecycle = object
    node_id: uint32
    started_ticks: int64
    terminal_ticks: int64
    thread_id: string
    turn_id: string
    pending_finish_request_id: string
    idle_observed: bool
    terminal: bool

  WorkNode* = object
    id*: uint32
    description*: string
    objective*: string
    inputs*: seq[InputArtifactRef]
    outputs*: seq[OutputArtifactDecl]
    wait_for*: seq[uint32]
    state*: NodeState
    execution_plan*: ExecutionPlan

  GraphMutationStatus* = enum
    committed
    pending_valid
    pending_invalid

  GraphMutationError* = object
    field_path*: string
    message*: string

  GraphMutationResult* = object
    status*: GraphMutationStatus
    edit_id*: uint32
    node_id*: uint32
    errors*: seq[GraphMutationError]

  WorkNodeChanges* = object
    has_description*: bool
    description*: string
    has_objective*: bool
    objective*: string
    has_inputs*: bool
    inputs*: seq[InputArtifactRef]
    has_outputs*: bool
    outputs*: seq[OutputArtifactDecl]
    has_wait_for*: bool
    wait_for*: seq[uint32]
    has_execution_plan*: bool
    execution_plan*: ExecutionPlan

  GraphEditKind = enum
    create_edit
    update_edit
    delete_edit
    reassign_output_edit

  GraphEdit = object
    id: uint32
    case kind: GraphEditKind
    of create_edit:
      created_node: WorkNode
    of update_edit:
      update_node_id: uint32
      changes: WorkNodeChanges
    of delete_edit:
      deleted_node_id: uint32
    of reassign_output_edit:
      source_node_id: uint32
      source_path: string
      destination_node_id: uint32
      destination_path: string

  PendingEditSequence = object
    owner_node_id: uint32
    edits: seq[GraphEdit]

  WorkGraphMessage* = object
    node_id*: uint32
    text*: string

  WorkGraph* = object
    nodes*: seq[WorkNode]
    artifact_root*: string
    log_messages*: seq[string]
    outgoing_messages*: seq[WorkGraphMessage]
    next_node_id: uint32
    next_edit_id: uint32
    final_artifacts_reported: bool
    pending_sequences: seq[PendingEditSequence]
    watchdog_timeout_seconds*: float64
    lifecycle_diagnostics*: seq[LifecycleDiagnostic]
    lifecycle_counters*: LifecycleCounters
    node_lifecycles: seq[NodeLifecycle]

  ResolvedOutputArtifact = object
    declaration: OutputArtifactDecl
    path: string

const human_response_output_path = "response.txt"
const
  ## Initial rollout bound. Override with `CODEX_WORKER_LIFETIME_SECONDS`.
  default_worker_lifetime_seconds* = 300.0
  worker_lifetime_env_name* = "CODEX_WORKER_LIFETIME_SECONDS"

proc configured_worker_lifetime_seconds*(): float64 =
  let configured = getEnv(worker_lifetime_env_name)
  if configured.len > 0:
    try:
      let value = parseFloat(configured)
      if value > 0:
        return value
    except ValueError:
      discard
  default_worker_lifetime_seconds

proc reasoning_effort(level: ReasoningLevel): ReasoningEffort =
  case level:
  of straightforward: re_low
  of bounded: re_medium
  of deep_reasoning: re_high

proc node_execution_contract(execution_type: ExecutionPlanType): ExecutionContract =
  result.missing_output_label = "output artifact"
  case execution_type:
  of llm_worker:
    discard
  of graph_creation:
    result.graph_creator = true
  of human_input:
    result.requires_single_output = true
    result.missing_output_label = "human input artifact"

proc normalize_runtime_owned_outputs(node: var WorkNode) =
  if node.execution_plan.`type`.node_execution_contract.requires_single_output:
    node.outputs = @[OutputArtifactDecl(
      path: human_response_output_path,
      description: "Human response")]

proc new_work_graph*(cwd = getCurrentDir(); objective = ""): WorkGraph =
  WorkGraph(
    artifact_root: orchestration_paths(cwd).artifacts,
    nodes: @[
      WorkNode(
        id: 1,
        description: "Create work graph",
        objective: objective,
        state: pending,
        execution_plan: ExecutionPlan(
          `type`: graph_creation,
          allowed: @["*"],
          reasoning_level: bounded,
          instructions: "Construct the smallest work graph that can complete the objective. Identify its dominant pattern and use applicable motifs: pipeline for ordered transform, review, or publish stages; decompose/solve/aggregate for independent subproblems and integration; retrieve/synthesize/cite for parallel retrieval, grounded synthesis, and citation or fact checking; research/gaps/follow-up for bounded follow-up on material gaps; proposal/judge/select for alternatives, explicit criteria, and selection or refinement; and adversarial verification/simplification/performance review for independent challenge, simplification, and performance assessment before integration. Treat compare, alternatives, choose, verify, challenge, simplify, optimize, benchmark, research, sources, cite, decompose, independent, and follow up as signals, not mandatory steps. Combine motifs only when their dependencies are distinct; avoid redundant reviewers and unnecessary serial stages. If material ambiguity blocks safe execution, create human_input nodes, then a graph_creation node consuming their responses. Human_input always gets implicit response.txt; do not declare it. Graph structure is created only with graph tools; artifacts are files for the final user or downstream workers. After planning, create another graph_creation node only when unfinished work, a material research gap, or a verification result requires a new planning decision; if the objective is complete, create no continuation planner and finish this graph-creation node after committing its execution graph."))],
    next_node_id: 2,
    next_edit_id: 1,
    watchdog_timeout_seconds: configured_worker_lifetime_seconds(),
    lifecycle_diagnostics: @[],
    node_lifecycles: @[])

proc node_index*(graph: WorkGraph; node_id: uint32): int =
  for index, node in graph.nodes:
    if node.id == node_id:
      return index
  -1

proc artifact_path_is_valid(path: string): bool =
  if path.len == 0 or path.isAbsolute:
    return false
  for component in path.split({DirSep, AltSep}):
    if component in [".", ".."]:
      return false
  true

proc graph_artifact_root(graph: WorkGraph): string =
  if graph.artifact_root.len == 0:
    raise newException(ValueError, "artifact root is not configured")
  graph.artifact_root

proc resolve_artifact_path(graph: WorkGraph; node_id: uint32;
    path: string): string =
  if not path.artifact_path_is_valid:
    raise newException(ValueError, "invalid artifact path: " & path)
  joinPath(graph.graph_artifact_root, $node_id, path)

proc resolve_input_path*(graph: WorkGraph; input: InputArtifactRef): string =
  graph.resolve_artifact_path(input.producer_node_id, input.path)

proc resolve_output_path*(graph: WorkGraph; node_id: uint32;
    output: OutputArtifactDecl): string =
  graph.resolve_artifact_path(node_id, output.path)

proc resolved_output_artifacts(graph: WorkGraph;
    node: WorkNode): seq[ResolvedOutputArtifact] =
  for output in node.outputs:
    result.add(ResolvedOutputArtifact(
      declaration: output,
      path: graph.resolve_output_path(node.id, output)))

proc output_declared(node: WorkNode; path: string): bool =
  for output in node.outputs:
    if output.path == path:
      return true
  false

proc duplicate_dependency_id(dependency_ids: seq[uint32]): Option[uint32] =
  var seen: seq[uint32] = @[]
  for dependency_id in dependency_ids:
    if dependency_id in seen:
      return some(dependency_id)
    seen.add(dependency_id)
  none(uint32)

proc node_artifact_error*(graph: WorkGraph; node: WorkNode): string =
  let duplicate_dependency = node.wait_for.duplicate_dependency_id
  if duplicate_dependency.isSome:
    return "duplicate wait_for dependency: " & $duplicate_dependency.get

  var output_paths: seq[string] = @[]
  for output in node.outputs:
    if not output.path.artifact_path_is_valid:
      return "invalid output artifact path: " & output.path
    if output.path in output_paths:
      return "duplicate output artifact path: " & output.path
    output_paths.add(output.path)

  let contract = node.execution_plan.`type`.node_execution_contract
  if contract.requires_single_output:
    if node.outputs.len != 1:
      return "human_input nodes must have exactly one runtime output artifact"
    if node.outputs[0].path != human_response_output_path:
      return "human_input output path is runtime-controlled: " &
        human_response_output_path

  for input in node.inputs:
    if not input.path.artifact_path_is_valid:
      return "invalid input artifact path: " & input.path
    let producer_index = graph.node_index(input.producer_node_id)
    if producer_index < 0:
      return "unknown input artifact producer node: " &
        $input.producer_node_id
    if not graph.nodes[producer_index].output_declared(input.path):
      return "input artifact is not declared by producer: " &
        $input.producer_node_id & "/" & input.path
  ""

proc node_dependency_ids*(node: WorkNode): seq[uint32] =
  for dependency_id in node.wait_for:
    if dependency_id notin result:
      result.add(dependency_id)
  for input in node.inputs:
    if input.producer_node_id notin result:
      result.add(input.producer_node_id)

proc dependency_children(graph: WorkGraph; node_id: uint32): seq[uint32] =
  for node in graph.nodes:
    if node_id in node.node_dependency_ids:
      result.add(node.id)

proc dependency_neighbors(graph: WorkGraph; node_id: uint32;
    include_ancestors, include_descendants: bool): seq[uint32] =
  let index = graph.node_index(node_id)
  if index < 0:
    return
  if include_ancestors:
    result.add(graph.nodes[index].node_dependency_ids)
  if include_descendants:
    for child_id in graph.dependency_children(node_id):
      if child_id notin result:
        result.add(child_id)

proc root_indices(graph: WorkGraph): seq[int] =
  var indegree = newSeq[int](graph.nodes.len)
  for node in graph.nodes:
    let node_index = graph.node_index(node.id)
    if node_index < 0:
      continue
    for dependency_id in node.node_dependency_ids:
      if graph.node_index(dependency_id) >= 0:
        inc indegree[node_index]
  for index, degree in indegree:
    if degree == 0:
      result.add(index)

proc mutation_error(field_path, message: string): GraphMutationError =
  GraphMutationError(field_path: field_path, message: message)

proc copy_nodes(nodes: seq[WorkNode]): seq[WorkNode] =
  for node in nodes:
    var copied = node
    copied.inputs = node.inputs.toSeq
    copied.outputs = node.outputs.toSeq
    copied.wait_for = node.wait_for.toSeq
    result.add(copied)

proc copy_graph(graph: WorkGraph): WorkGraph =
  result = graph
  result.nodes = graph.nodes.copy_nodes
  result.pending_sequences = @[]

proc graph_validation_errors*(graph: WorkGraph): seq[GraphMutationError] =
  if graph.nodes.len == 0:
    result.add(mutation_error("nodes", "Graph must contain one bootstrap root node."))
    return

  for first_index, first_node in graph.nodes:
    for second_index in 0 ..< first_index:
      if graph.nodes[second_index].id == first_node.id:
        result.add(mutation_error(
          "nodes[" & $first_index & "].id",
          "Node ID is duplicated."))
        break

  for index, node in graph.nodes:
    let artifact_error = graph.node_artifact_error(node)
    if artifact_error.len > 0:
      result.add(mutation_error("nodes[" & $index & "]", artifact_error))
    for dependency_id in node.node_dependency_ids:
      let dependency_index = graph.node_index(dependency_id)
      if dependency_index < 0:
        result.add(mutation_error(
          "nodes[" & $index & "].dependencies",
          "Dependency node " & $dependency_id & " does not exist."))

  let roots = graph.root_indices
  let bootstrap_index = graph.node_index(1)
  if bootstrap_index < 0:
    result.add(mutation_error(
      "nodes",
      "Graph must contain bootstrap root node 1."))
  else:
    if bootstrap_index notin roots:
      result.add(mutation_error(
        "nodes[" & $bootstrap_index & "]",
        "Bootstrap node 1 must be the sole graph root."))
    if not graph.nodes[bootstrap_index].execution_plan.`type`.
        node_execution_contract.graph_creator:
      result.add(mutation_error(
        "nodes[" & $bootstrap_index & "].execution_plan.type",
        "Bootstrap root must use graph_creation execution."))
  if roots.len != 1:
    result.add(mutation_error(
      "nodes",
      "Graph must have exactly one connected root."))

  var colors = newSeq[int](graph.nodes.len)
  proc has_cycle(index: int): bool =
    if colors[index] == 1:
      return true
    if colors[index] == 2:
      return false
    colors[index] = 1
    for dependency_id in graph.nodes[index].node_dependency_ids:
      let dependency_index = graph.node_index(dependency_id)
      if dependency_index >= 0 and has_cycle(dependency_index):
        return true
    colors[index] = 2
    false

  for index in 0 ..< graph.nodes.len:
    if has_cycle(index):
      result.add(mutation_error("nodes", "Effective dependency graph contains a cycle."))
      break

  if roots.len == 1:
    var reachable = newSeq[bool](graph.nodes.len)
    var queue = @[roots[0]]
    reachable[roots[0]] = true
    var queue_index = 0
    while queue_index < queue.len:
      let current = queue[queue_index]
      inc queue_index
      for child_id in graph.dependency_children(graph.nodes[current].id):
        let child_index = graph.node_index(child_id)
        if child_index >= 0 and not reachable[child_index]:
          reachable[child_index] = true
          queue.add(child_index)
    for index, is_reachable in reachable:
      if not is_reachable:
        result.add(mutation_error(
          "nodes[" & $index & "]",
          "Node is disconnected from bootstrap root."))

proc graph_roots(graph: WorkGraph): seq[uint32] =
  for index in graph.root_indices:
    result.add(graph.nodes[index].id)

proc dominates(graph: WorkGraph; actor_node_id, target_node_id: uint32): bool =
  if actor_node_id == target_node_id:
    return true
  let target_index = graph.node_index(target_node_id)
  if target_index < 0:
    return false

  var roots = graph.graph_roots
  if roots.len == 0:
    return false
  var visited = initTable[uint32, bool]()
  var queue: seq[uint32] = @[]
  for root_id in roots:
    if root_id != actor_node_id:
      queue.add(root_id)
      visited[root_id] = true
  var queue_index = 0
  while queue_index < queue.len:
    let current_id = queue[queue_index]
    inc queue_index
    if current_id == actor_node_id:
      continue
    if current_id == target_node_id:
      return false
    for child_id in graph.dependency_children(current_id):
      if not visited.getOrDefault(child_id):
        visited[child_id] = true
        queue.add(child_id)
  true

proc is_running_graph_creator(graph: WorkGraph; node_id: uint32): bool =
  let index = graph.node_index(node_id)
  index >= 0 and graph.nodes[index].state == running and
    graph.nodes[index].execution_plan.`type`.node_execution_contract.graph_creator

proc actor_can_edit(graph: WorkGraph; actor_node_id, target_node_id: uint32): bool =
  let target_index = graph.node_index(target_node_id)
  graph.is_running_graph_creator(actor_node_id) and target_index >= 0 and
    graph.nodes[target_index].state == pending and
    graph.dominates(actor_node_id, target_node_id)

proc add_edit_target_error(errors: var seq[GraphMutationError];
    graph: WorkGraph; owner_node_id, target_node_id: uint32;
    field_path, missing_message, authority_message: string) =
  if graph.node_index(target_node_id) < 0:
    errors.add(mutation_error(field_path, missing_message))
  elif not graph.actor_can_edit(owner_node_id, target_node_id):
    errors.add(mutation_error(field_path, authority_message))

proc apply_node_changes(node: var WorkNode; changes: WorkNodeChanges) =
  if changes.has_description:
    node.description = changes.description
  if changes.has_objective:
    node.objective = changes.objective
  if changes.has_inputs:
    node.inputs = changes.inputs.toSeq
  if changes.has_outputs:
    node.outputs = changes.outputs.toSeq
  if changes.has_wait_for:
    node.wait_for = changes.wait_for.toSeq
  if changes.has_execution_plan:
    node.execution_plan = changes.execution_plan
  node.normalize_runtime_owned_outputs

proc apply_edit(graph: var WorkGraph; edit: GraphEdit): bool =
  case edit.kind
  of create_edit:
    if graph.node_index(edit.created_node.id) >= 0:
      return false
    graph.nodes.add(edit.created_node)
    true
  of update_edit:
    let index = graph.node_index(edit.update_node_id)
    if index < 0:
      return false
    graph.nodes[index].apply_node_changes(edit.changes)
    true
  of delete_edit:
    let index = graph.node_index(edit.deleted_node_id)
    if index < 0:
      return false
    graph.nodes.delete(index)
    true
  of reassign_output_edit:
    let source_index = graph.node_index(edit.source_node_id)
    let destination_index = graph.node_index(edit.destination_node_id)
    if source_index < 0 or destination_index < 0:
      return false
    var moved_output: OutputArtifactDecl
    var output_index = -1
    for index, output in graph.nodes[source_index].outputs:
      if output.path == edit.source_path:
        moved_output = output
        output_index = index
        break
    if output_index < 0:
      return false
    graph.nodes[source_index].outputs.delete(output_index)
    moved_output.path = if edit.destination_path.len > 0:
      edit.destination_path else: edit.source_path
    graph.nodes[destination_index].outputs.add(moved_output)
    for node in graph.nodes.mitems:
      for input in node.inputs.mitems:
        if input.producer_node_id == edit.source_node_id and
            input.path == edit.source_path:
          input.producer_node_id = edit.destination_node_id
          input.path = moved_output.path
    true

proc edit_affected_node_ids(edit: GraphEdit): seq[uint32] =
  case edit.kind
  of create_edit:
    @[edit.created_node.id]
  of update_edit:
    @[edit.update_node_id]
  of delete_edit:
    @[edit.deleted_node_id]
  of reassign_output_edit:
    @[edit.source_node_id, edit.destination_node_id]

proc reassign_consumer_ids(graph: WorkGraph; edit: GraphEdit): seq[uint32] =
  if edit.kind != reassign_output_edit:
    return
  for node in graph.nodes:
    for input in node.inputs:
      if input.producer_node_id == edit.source_node_id and
          input.path == edit.source_path:
        if node.id notin result:
          result.add(node.id)
        break

proc edit_authority_errors(graph: WorkGraph; owner_node_id: uint32;
    edit: GraphEdit): seq[GraphMutationError] =
  if not graph.is_running_graph_creator(owner_node_id):
    result.add(mutation_error(
      "caller",
      "Only a running graph_creation node may mutate the graph."))
    return

  case edit.kind
  of create_edit:
    discard
  of update_edit:
    result.add_edit_target_error(
      graph, owner_node_id, edit.update_node_id, "node_id",
      "Target node does not exist.",
      "Target must be pending and dominated by the current graph creator.")
  of delete_edit:
    result.add_edit_target_error(
      graph, owner_node_id, edit.deleted_node_id, "node_id",
      "Target node does not exist.",
      "Target must be pending and dominated by the current graph creator.")
  of reassign_output_edit:
    result.add_edit_target_error(
      graph, owner_node_id, edit.source_node_id, "source_node_id",
      "Source node does not exist.",
      "Source node must be pending and dominated by the current graph creator.")
    result.add_edit_target_error(
      graph, owner_node_id, edit.destination_node_id, "destination_node_id",
      "Destination node does not exist.",
      "Destination node must be pending and dominated by the current graph creator.")
    for consumer_id in graph.reassign_consumer_ids(edit):
      if not graph.actor_can_edit(owner_node_id, consumer_id):
        result.add(mutation_error(
          "consumers",
          "Every output consumer must be pending and dominated by the current graph creator."))

proc edit_operation_error(graph: WorkGraph; edit: GraphEdit): seq[GraphMutationError] =
  case edit.kind
  of create_edit:
    discard
  of update_edit:
    if graph.node_index(edit.update_node_id) < 0:
      return
  of delete_edit:
    if graph.node_index(edit.deleted_node_id) < 0:
      return
  of reassign_output_edit:
    let source_index = graph.node_index(edit.source_node_id)
    let destination_index = graph.node_index(edit.destination_node_id)
    if source_index < 0 or destination_index < 0:
      return
    var found_source = false
    for output in graph.nodes[source_index].outputs:
      if output.path == edit.source_path:
        found_source = true
        break
    if not found_source:
      result.add(mutation_error(
        "source_path",
        "Source output path is not declared by source node."))
    if edit.destination_path.len > 0 and
        not edit.destination_path.artifact_path_is_valid:
      result.add(mutation_error(
        "destination_path",
        "Destination path must be relative and traversal-free."))
    if edit.destination_path.len > 0:
      for output in graph.nodes[destination_index].outputs:
        if output.path == edit.destination_path and
            not (edit.source_node_id == edit.destination_node_id and
                 output.path == edit.source_path):
          result.add(mutation_error(
            "destination_path",
            "Destination node already declares that output path."))

proc edit_evaluation_errors(graph: WorkGraph; owner_node_id: uint32;
    edit: GraphEdit): seq[GraphMutationError] =
  result.add(graph.edit_authority_errors(owner_node_id, edit))
  if result.len > 0:
    return
  result.add(graph.edit_operation_error(edit))

type
  GraphEditEvaluation = object
    id: uint32
    status: GraphMutationStatus
    affected_node_ids: seq[uint32]
    errors: seq[GraphMutationError]

proc replay_edits(graph: WorkGraph; owner_node_id: uint32;
    edits: seq[GraphEdit]; final_graph: var WorkGraph): seq[GraphEditEvaluation] =
  var speculative = graph.copy_graph
  for edit in edits:
    var evaluation = GraphEditEvaluation(
      id: edit.id,
      status: pending_valid,
      affected_node_ids: edit.edit_affected_node_ids,
      errors: @[])
    evaluation.affected_node_ids.add(
      speculative.reassign_consumer_ids(edit))
    evaluation.errors = speculative.edit_evaluation_errors(owner_node_id, edit)
    if evaluation.errors.len == 0:
      if not speculative.apply_edit(edit):
        evaluation.errors.add(mutation_error(
          "edit",
          "Mutation could not be applied to staged graph."))
      else:
        for affected_node_id in evaluation.affected_node_ids:
          let affected_index = speculative.node_index(affected_node_id)
          if affected_index >= 0 and
              not speculative.dominates(owner_node_id, affected_node_id):
            evaluation.errors.add(mutation_error(
              "node_id",
              "Mutation creates a node path that bypasses current graph creator."))
        evaluation.errors.add(speculative.graph_validation_errors)
        if evaluation.errors.len > 0:
          discard
    if evaluation.errors.len > 0:
      evaluation.status = pending_invalid
    result.add(evaluation)
  final_graph = speculative

type
  GraphSequenceEvaluation = object
    final_graph: WorkGraph
    evaluations: seq[GraphEditEvaluation]

proc evaluate_sequence(graph: WorkGraph; owner_node_id: uint32;
    edits: seq[GraphEdit]): GraphSequenceEvaluation =
  result.evaluations = graph.replay_edits(
    owner_node_id,
    edits,
    result.final_graph)

proc pending_sequence_index(graph: WorkGraph; owner_node_id: uint32): int =
  for index, sequence in graph.pending_sequences:
    if sequence.owner_node_id == owner_node_id:
      return index
  -1

proc pending_edit_index(sequence: PendingEditSequence; edit_id: uint32): int =
  for index, edit in sequence.edits:
    if edit.id == edit_id:
      return index
  -1

proc next_node_identifier(graph: var WorkGraph): uint32 =
  if graph.next_node_id == 0:
    graph.next_node_id = 1
    for node in graph.nodes:
      if node.id >= graph.next_node_id:
        graph.next_node_id = node.id + 1
  while true:
    var used = graph.node_index(graph.next_node_id) >= 0
    if not used:
      for sequence in graph.pending_sequences:
        for edit in sequence.edits:
          if edit.kind == create_edit and
              edit.created_node.id == graph.next_node_id:
            used = true
            break
        if used:
          break
    if not used:
      break
    inc graph.next_node_id
  result = graph.next_node_id
  inc graph.next_node_id

proc next_edit_identifier(graph: var WorkGraph): uint32 =
  if graph.next_edit_id == 0:
    graph.next_edit_id = 1
  while true:
    var used = false
    for sequence in graph.pending_sequences:
      for edit in sequence.edits:
        if edit.id == graph.next_edit_id:
          used = true
          break
      if used:
        break
    if not used:
      break
    inc graph.next_edit_id
  result = graph.next_edit_id
  inc graph.next_edit_id

proc mutation_result(status: GraphMutationStatus; node_id = 0'u32;
    edit_id = 0'u32; errors: seq[GraphMutationError] = @[]): GraphMutationResult =
  GraphMutationResult(
    status: status,
    edit_id: edit_id,
    node_id: node_id,
    errors: errors)

proc commit_evaluated_sequence(graph: var WorkGraph; sequence_index: int;
    evaluation: GraphSequenceEvaluation): bool =
  if sequence_index < 0 or sequence_index >= graph.pending_sequences.len:
    return false
  for edit_evaluation in evaluation.evaluations:
    if edit_evaluation.errors.len > 0:
      return false
  graph.nodes = evaluation.final_graph.nodes.copy_nodes
  graph.pending_sequences.delete(sequence_index)
  true

proc pending_edit_not_found(edit_id: uint32): GraphMutationResult =
  mutation_result(
    pending_invalid,
    edit_id = edit_id,
    errors = @[mutation_error(
      "edit_id",
      "Pending edit does not exist for current graph creator.")])

proc mutation_from_sequence(graph: var WorkGraph; sequence_index: int;
    edit_id: uint32): GraphMutationResult =
  let sequence = graph.pending_sequences[sequence_index]
  let sequence_evaluation = graph.evaluate_sequence(
    sequence.owner_node_id,
    sequence.edits)
  var current_evaluation: GraphEditEvaluation
  var found_current = false
  var sequence_errors: seq[GraphMutationError] = @[]
  for evaluation in sequence_evaluation.evaluations:
    if evaluation.errors.len > 0:
      sequence_errors.add(evaluation.errors)
    if evaluation.id == edit_id:
      current_evaluation = evaluation
      found_current = true
  if not found_current:
    return pending_edit_not_found(edit_id)
  let current_node_id = if current_evaluation.affected_node_ids.len > 0:
    current_evaluation.affected_node_ids[0] else: 0
  if sequence_errors.len > 0:
    return mutation_result(
      pending_invalid,
      node_id = current_node_id,
      edit_id = edit_id,
      errors = sequence_errors)
  if graph.commit_evaluated_sequence(sequence_index, sequence_evaluation):
    return mutation_result(
      committed,
      node_id = current_node_id,
      edit_id = edit_id)
  mutation_result(
    pending_valid,
    node_id = current_node_id,
    edit_id = edit_id)

proc stage_or_commit(graph: var WorkGraph; owner_node_id: uint32;
    edit: GraphEdit; requested_edit_id: uint32): GraphMutationResult =
  let sequence_index = graph.pending_sequence_index(owner_node_id)
  if requested_edit_id > 0:
    if sequence_index < 0:
      return pending_edit_not_found(requested_edit_id)
    var sequence = graph.pending_sequences[sequence_index]
    let edit_index = sequence.pending_edit_index(requested_edit_id)
    if edit_index < 0:
      return pending_edit_not_found(requested_edit_id)
    let original = sequence.edits[edit_index]
    if original.kind != edit.kind:
      return mutation_result(
        pending_invalid,
        edit_id = requested_edit_id,
        errors = @[mutation_error(
          "edit_id",
          "Correction must use the original mutation tool.")])
    case original.kind
    of create_edit:
      discard
    of update_edit:
      if original.update_node_id != edit.update_node_id:
        return mutation_result(
          pending_invalid,
          edit_id = requested_edit_id,
          errors = @[mutation_error(
            "node_id",
            "Correction must target the original node.")])
    of delete_edit:
      if original.deleted_node_id != edit.deleted_node_id:
        return mutation_result(
          pending_invalid,
          edit_id = requested_edit_id,
          errors = @[mutation_error(
            "node_id",
            "Correction must target the original node.")])
    of reassign_output_edit:
      if original.source_node_id != edit.source_node_id or
          original.source_path != edit.source_path or
          original.destination_node_id != edit.destination_node_id:
        return mutation_result(
          pending_invalid,
          edit_id = requested_edit_id,
          errors = @[mutation_error(
            "edit_id",
            "Correction must target the original output reassignment.")])
    var replacement = edit
    replacement.id = requested_edit_id
    sequence.edits[edit_index] = replacement
    graph.pending_sequences[sequence_index] = sequence
    return graph.mutation_from_sequence(sequence_index, requested_edit_id)

  var staged_edit = edit
  if sequence_index >= 0:
    staged_edit.id = graph.next_edit_identifier()
    var sequence = graph.pending_sequences[sequence_index]
    sequence.edits.add(staged_edit)
    graph.pending_sequences[sequence_index] = sequence
    return graph.mutation_from_sequence(sequence_index, staged_edit.id)

  let sequence_evaluation = graph.evaluate_sequence(
    owner_node_id,
    @[staged_edit])
  if sequence_evaluation.evaluations.len == 1 and
      sequence_evaluation.evaluations[0].errors.len == 0:
    graph.nodes = sequence_evaluation.final_graph.nodes.copy_nodes
    return mutation_result(committed, staged_edit.edit_affected_node_ids[0])

  staged_edit.id = graph.next_edit_identifier()
  graph.pending_sequences.add(PendingEditSequence(
    owner_node_id: owner_node_id,
    edits: @[staged_edit]))
  let errors = if sequence_evaluation.evaluations.len == 1:
    sequence_evaluation.evaluations[0].errors else: @[
    mutation_error("edit", "Mutation could not be evaluated.")]
  mutation_result(
    pending_invalid,
    node_id = staged_edit.edit_affected_node_ids[0],
    edit_id = staged_edit.id,
    errors = errors)

proc speculative_graph_before_create(graph: WorkGraph;
    owner_node_id, edit_id: uint32): WorkGraph =
  let sequence_index = graph.pending_sequence_index(owner_node_id)
  if sequence_index < 0:
    return graph.copy_graph

  let sequence = graph.pending_sequences[sequence_index]
  var end_index = sequence.edits.len
  if edit_id > 0:
    let edit_index = sequence.pending_edit_index(edit_id)
    if edit_index >= 0:
      end_index = edit_index
  if end_index == 0:
    return graph.copy_graph
  discard graph.replay_edits(
    owner_node_id,
    sequence.edits[0 ..< end_index],
    result)

proc owner_dependency_is_implied(graph: WorkGraph; owner_node_id: uint32;
    node: WorkNode): bool =
  var has_proposed_parent = false
  for dependency_id in node.wait_for:
    has_proposed_parent = true
    if dependency_id == owner_node_id:
      return true
  for input in node.inputs:
    has_proposed_parent = true
    if input.producer_node_id == owner_node_id:
      return true

  for dependency_id in node.wait_for:
    if not graph.dominates(owner_node_id, dependency_id):
      return false
  for input in node.inputs:
    if not graph.dominates(owner_node_id, input.producer_node_id):
      return false
  has_proposed_parent

proc create_node*(graph: var WorkGraph; owner_node_id: uint32;
    node_definition: WorkNode; edit_id = 0'u32): GraphMutationResult =
  var node = node_definition
  node.state = pending
  node.normalize_runtime_owned_outputs
  var staged_node_id = 0'u32
  if edit_id > 0:
    let sequence_index = graph.pending_sequence_index(owner_node_id)
    if sequence_index >= 0:
      let edit_index = graph.pending_sequences[sequence_index].pending_edit_index(edit_id)
      if edit_index >= 0 and
          graph.pending_sequences[sequence_index].edits[edit_index].kind == create_edit:
        staged_node_id = graph.pending_sequences[sequence_index].edits[edit_index].created_node.id
  node.id = if staged_node_id > 0: staged_node_id else: graph.next_node_identifier()
  let speculative = graph.speculative_graph_before_create(owner_node_id, edit_id)
  if not speculative.owner_dependency_is_implied(owner_node_id, node):
    node.wait_for.add(owner_node_id)
  graph.stage_or_commit(
    owner_node_id,
    GraphEdit(id: 0, kind: create_edit, created_node: node),
    edit_id)

proc update_node*(graph: var WorkGraph; owner_node_id, node_id: uint32;
    changes: WorkNodeChanges; edit_id = 0'u32): GraphMutationResult =
  graph.stage_or_commit(
    owner_node_id,
    GraphEdit(
      id: 0,
      kind: update_edit,
      update_node_id: node_id,
      changes: changes),
    edit_id)

proc delete_node*(graph: var WorkGraph; owner_node_id, node_id: uint32;
    edit_id = 0'u32): GraphMutationResult =
  graph.stage_or_commit(
    owner_node_id,
    GraphEdit(
      id: 0,
      kind: delete_edit,
      deleted_node_id: node_id),
    edit_id)

proc reassign_output*(graph: var WorkGraph; owner_node_id, source_node_id: uint32;
    source_path: string; destination_node_id: uint32;
    destination_path = ""; edit_id = 0'u32): GraphMutationResult =
  var effective_destination_path = destination_path
  if edit_id > 0 and effective_destination_path.len == 0:
    let sequence_index = graph.pending_sequence_index(owner_node_id)
    if sequence_index >= 0:
      let edit_index = graph.pending_sequences[sequence_index].pending_edit_index(edit_id)
      if edit_index >= 0:
        let original = graph.pending_sequences[sequence_index].edits[edit_index]
        if original.kind == reassign_output_edit:
          effective_destination_path = original.destination_path
  graph.stage_or_commit(
    owner_node_id,
    GraphEdit(
      id: 0,
      kind: reassign_output_edit,
      source_node_id: source_node_id,
      source_path: source_path,
      destination_node_id: destination_node_id,
      destination_path: effective_destination_path),
    edit_id)

proc discard_edit*(graph: var WorkGraph; owner_node_id, edit_id: uint32): GraphMutationResult =
  let sequence_index = graph.pending_sequence_index(owner_node_id)
  if sequence_index < 0:
    return pending_edit_not_found(edit_id)
  var sequence = graph.pending_sequences[sequence_index]
  let edit_index = sequence.pending_edit_index(edit_id)
  if edit_index < 0:
    return pending_edit_not_found(edit_id)
  sequence.edits.delete(edit_index)
  if sequence.edits.len == 0:
    graph.pending_sequences.delete(sequence_index)
    return mutation_result(committed, edit_id = edit_id)
  graph.pending_sequences[sequence_index] = sequence
  let sequence_evaluation = graph.evaluate_sequence(
    owner_node_id,
    sequence.edits)
  for evaluation in sequence_evaluation.evaluations:
    if evaluation.errors.len > 0:
      return mutation_result(
        pending_invalid,
        edit_id = edit_id,
        errors = evaluation.errors)
  if graph.commit_evaluated_sequence(sequence_index, sequence_evaluation):
    mutation_result(committed, edit_id = edit_id)
  else:
    mutation_result(
      pending_invalid,
      edit_id = edit_id,
      errors = @[mutation_error("edit", "Pending edits could not be committed.")])

proc require_object(node: JsonNode; field_path: string): JsonNode =
  if node.kind != JObject:
    raise newException(ValueError, field_path & " must be an object")
  node

proc require_array(node: JsonNode; field_path: string): JsonNode =
  if node.kind != JArray:
    raise newException(ValueError, field_path & " must be an array")
  node

proc require_field(node: JsonNode; key, field_path: string): JsonNode =
  if node.kind != JObject or not node.contains(key):
    raise newException(ValueError, "missing required field: " & field_path)
  node[key]

proc require_string(node: JsonNode; field_path: string): string =
  if node.kind != JString or node.getStr.len == 0:
    raise newException(ValueError, field_path & " must be a non-empty string")
  node.getStr

proc parse_string_array(node: JsonNode; field_path: string): seq[string] =
  let values = node.require_array(field_path)
  for index in 0 ..< values.len:
    result.add(values[index].require_string(
      field_path & "[" & $index & "]"))

proc optional_string_array(node: JsonNode; key, field_path: string): seq[string] =
  if node.contains(key):
    return parse_string_array(node[key], field_path)
  @[]

proc reject_unknown_fields(node: JsonNode; field_path: string;
    allowed: openArray[string]) =
  for key, value in node.pairs:
    if key notin allowed:
      raise newException(ValueError, "unknown field: " & field_path & "." & key)

proc parse_identifier(node: JsonNode; field_path: string): uint32 =
  if node.kind != JInt:
    raise newException(ValueError, field_path & " must be a positive integer")
  let value = node.getInt
  if value < 1 or value > int64(high(uint32)):
    raise newException(ValueError, field_path & " must be a positive integer")
  uint32(value)

proc parse_execution_plan(node: JsonNode; field_path: string): ExecutionPlan =
  let value = node.require_object(field_path)
  value.reject_unknown_fields(
    field_path, ["type", "instructions", "reasoning_level", "allowed", "disallowed"])
  let type_name = value["type"].require_string(field_path & ".type")
  let execution_type = case type_name
    of llm_worker_type_name: llm_worker
    of graph_creation_type_name: graph_creation
    of human_input_type_name: human_input
    else: raise newException(ValueError, field_path & ".type is invalid")
  let reasoning_level = if value.contains("reasoning_level"):
    case value["reasoning_level"].require_string(field_path & ".reasoning_level")
    of straightforward_reasoning_name: straightforward
    of bounded_reasoning_name: bounded
    of deep_reasoning_name: deep_reasoning
    else: raise newException(ValueError,
      field_path & ".reasoning_level is invalid")
  else:
    straightforward
  if execution_type != graph_creation and
      (value.contains("allowed") or value.contains("disallowed")):
    raise newException(ValueError,
      field_path & ".allowed and .disallowed only valid for graph_creation")
  let instructions = value["instructions"].require_string(field_path & ".instructions")
  case execution_type
  of graph_creation:
    ExecutionPlan(
      `type`: graph_creation,
      instructions: instructions,
      reasoning_level: reasoning_level,
      allowed: value.optional_string_array("allowed", field_path & ".allowed"),
      disallowed: value.optional_string_array("disallowed", field_path & ".disallowed"))
  of llm_worker, human_input:
    ExecutionPlan(
      `type`: execution_type,
      instructions: instructions,
      reasoning_level: reasoning_level)

proc parse_inputs(node: JsonNode; field_path: string): seq[InputArtifactRef] =
  let values = node.require_array(field_path)
  for index in 0 ..< values.len:
    let item = values[index]
    let value = item.require_object(field_path & "[" & $index & "]")
    value.reject_unknown_fields(
      field_path & "[" & $index & "]",
      ["producer_node_id", "path", "description"])
    result.add(InputArtifactRef(
      producer_node_id: parse_identifier(
        value.require_field("producer_node_id", field_path & "[" & $index & "].producer_node_id"),
        field_path & "[" & $index & "].producer_node_id"),
      path: value.require_field("path", field_path & "[" & $index & "].path").require_string(
        field_path & "[" & $index & "].path"),
      description: value.require_field("description", field_path & "[" & $index & "].description").require_string(
        field_path & "[" & $index & "].description")))

proc parse_outputs(node: JsonNode; field_path: string): seq[OutputArtifactDecl] =
  let values = node.require_array(field_path)
  for index in 0 ..< values.len:
    let item = values[index]
    let value = item.require_object(field_path & "[" & $index & "]")
    value.reject_unknown_fields(
      field_path & "[" & $index & "]",
      ["path", "description", "final"])
    var final = false
    if value.contains("final"):
      if value["final"].kind != JBool:
        raise newException(ValueError, field_path & "[" & $index & "].final must be boolean")
      final = value["final"].getBool
    result.add(OutputArtifactDecl(
      path: value.require_field("path", field_path & "[" & $index & "].path").require_string(
        field_path & "[" & $index & "].path"),
      description: value.require_field("description", field_path & "[" & $index & "].description").require_string(
        field_path & "[" & $index & "].description"),
      final: final))

proc parse_wait_for(node: JsonNode; field_path: string): seq[uint32] =
  let values = node.require_array(field_path)
  for index in 0 ..< values.len:
    let item = values[index]
    let dependency_id = parse_identifier(item, field_path & "[" & $index & "]")
    result.add(dependency_id)
    if result.duplicate_dependency_id.isSome:
      raise newException(ValueError, field_path & "[" & $index & "] duplicates dependency " & $dependency_id)

proc parse_node_definition*(node: JsonNode): WorkNode =
  let value = node.require_object("node_definition")
  value.reject_unknown_fields(
    "node_definition",
    ["description", "objective", "inputs", "outputs", "wait_for",
     "execution_plan"])
  let parsed_outputs = if value.contains("outputs"):
    parse_outputs(value["outputs"], "node_definition.outputs")
  else:
    @[]
  result = WorkNode(
    description: value.require_field("description", "node_definition.description").require_string(
      "node_definition.description"),
    objective: value.require_field("objective", "node_definition.objective").require_string(
      "node_definition.objective"),
    inputs: parse_inputs(
      value.require_field("inputs", "node_definition.inputs"),
      "node_definition.inputs"),
    outputs: parsed_outputs,
    wait_for: parse_wait_for(
      value.require_field("wait_for", "node_definition.wait_for"),
      "node_definition.wait_for"),
    state: pending,
    execution_plan: parse_execution_plan(
      value.require_field("execution_plan", "node_definition.execution_plan"),
      "node_definition.execution_plan"))

proc parse_node_field(changes: var WorkNodeChanges; key: string;
    item: JsonNode; field_path: string) =
  case key
  of "description":
    changes.has_description = true
    changes.description = item.require_string(field_path)
  of "objective":
    changes.has_objective = true
    changes.objective = item.require_string(field_path)
  of "inputs":
    changes.has_inputs = true
    changes.inputs = parse_inputs(item, field_path)
  of "outputs":
    changes.has_outputs = true
    changes.outputs = parse_outputs(item, field_path)
  of "wait_for":
    changes.has_wait_for = true
    changes.wait_for = parse_wait_for(item, field_path)
  of "execution_plan":
    changes.has_execution_plan = true
    changes.execution_plan = parse_execution_plan(item, field_path)
  else:
    raise newException(ValueError, "unknown field: " & field_path)

proc parse_node_changes*(node: JsonNode): WorkNodeChanges =
  let value = node.require_object("changes")
  var seen = false
  for key, item in value.pairs:
    result.parse_node_field(key, item, "changes." & key)
    seen = true
  if not seen:
    raise newException(ValueError, "changes must replace at least one field")

proc optional_edit_id(node: JsonNode): uint32 =
  if node.kind == JObject and node.contains("edit_id"):
    return parse_identifier(node["edit_id"], "edit_id")
  0

proc output_decl_json(output: OutputArtifactDecl): JsonNode =
  %*{
    "path": output.path,
    "description": output.description,
    "final": output.final
  }

proc input_ref_json(input: InputArtifactRef): JsonNode =
  %*{
    "producer_node_id": input.producer_node_id,
    "path": input.path,
    "description": input.description
  }

proc execution_plan_json(plan: ExecutionPlan): JsonNode =
  var value = %*{
    "type": $plan.`type`,
    "instructions": plan.instructions
  }
  if plan.`type` != human_input:
    value["reasoning_level"] = %($plan.reasoning_level)
  case plan.`type`:
  of graph_creation:
    value["allowed"] = %plan.allowed
    value["disallowed"] = %plan.disallowed
  of llm_worker, human_input:
    discard
  value

proc node_json(node: WorkNode): JsonNode =
  result = %*{
    "id": node.id,
    "description": node.description,
    "objective": node.objective,
    "inputs": [],
    "outputs": [],
    "wait_for": node.wait_for,
    "execution_plan": node.execution_plan.execution_plan_json,
    "state": $node.state
  }
  for input in node.inputs:
    result["inputs"].add(input.input_ref_json)
  for output in node.outputs:
    result["outputs"].add(output.output_decl_json)

proc mutation_error_json(error: GraphMutationError): JsonNode =
  %*{
    "field_path": error.field_path,
    "message": error.message
  }

proc mutation_result_json(value: GraphMutationResult): JsonNode =
  result = %*{
    "status": $value.status,
    "errors": []
  }
  if value.node_id > 0:
    result["node_id"] = %value.node_id
  if value.edit_id > 0:
    result["edit_id"] = %value.edit_id
  for error in value.errors:
    result["errors"].add(error.mutation_error_json)

proc graph_edit_json(edit: GraphEdit): JsonNode =
  proc changes_json(changes: WorkNodeChanges): JsonNode =
    result = newJObject()
    if changes.has_description:
      result["description"] = %changes.description
    if changes.has_objective:
      result["objective"] = %changes.objective
    if changes.has_inputs:
      result["inputs"] = newJArray()
      for input in changes.inputs:
        result["inputs"].add(input.input_ref_json)
    if changes.has_outputs:
      result["outputs"] = newJArray()
      for output in changes.outputs:
        result["outputs"].add(output.output_decl_json)
    if changes.has_wait_for:
      result["wait_for"] = %changes.wait_for
    if changes.has_execution_plan:
      result["execution_plan"] = changes.execution_plan.execution_plan_json

  result = %*{"edit_id": edit.id}
  case edit.kind
  of create_edit:
    result["operation"] = %create_node_name
    result["node_definition"] = edit.created_node.node_json
  of update_edit:
    result["operation"] = %update_node_name
    result["node_id"] = %edit.update_node_id
    result["changes"] = edit.changes.changes_json
  of delete_edit:
    result["operation"] = %delete_node_name
    result["node_id"] = %edit.deleted_node_id
  of reassign_output_edit:
    result["operation"] = %reassign_output_name
    result["source_node_id"] = %edit.source_node_id
    result["source_path"] = %edit.source_path
    result["destination_node_id"] = %edit.destination_node_id
    if edit.destination_path.len > 0:
      result["destination_path"] = %edit.destination_path

proc pending_edit_json(sequence: PendingEditSequence; edit_index: int;
    evaluation: GraphEditEvaluation): JsonNode =
  let edit_id = evaluation.id
  result = %*{
    "edit_id": edit_id,
    "status": $evaluation.status,
    "affected_node_ids": evaluation.affected_node_ids,
    "mutation": sequence.edits[edit_index].graph_edit_json,
    "errors": []
  }
  for error in evaluation.errors:
    result["errors"].add(error.mutation_error_json)

proc pending_edit_json*(graph: WorkGraph; owner_node_id, edit_id: uint32): JsonNode =
  let sequence_index = graph.pending_sequence_index(owner_node_id)
  if sequence_index < 0:
    raise newException(ValueError, "pending edit does not exist")
  let sequence = graph.pending_sequences[sequence_index]
  let edit_index = sequence.pending_edit_index(edit_id)
  if edit_index < 0:
    raise newException(ValueError, "pending edit does not exist")
  let sequence_evaluation = graph.evaluate_sequence(owner_node_id, sequence.edits)
  for evaluation in sequence_evaluation.evaluations:
    if evaluation.id != edit_id:
      continue
    return sequence.pending_edit_json(edit_index, evaluation)
  raise newException(ValueError, "pending edit does not exist")

proc pending_edits_json(graph: WorkGraph; owner_node_id: uint32): JsonNode =
  result = %*{"edits": []}
  let sequence_index = graph.pending_sequence_index(owner_node_id)
  if sequence_index < 0:
    return
  let sequence = graph.pending_sequences[sequence_index]
  let sequence_evaluation = graph.evaluate_sequence(owner_node_id, sequence.edits)
  for edit_index, edit in sequence.edits:
    if edit_index < sequence_evaluation.evaluations.len:
      let evaluation = sequence_evaluation.evaluations[edit_index]
      if evaluation.id == edit.id:
        result["edits"].add(sequence.pending_edit_json(
          edit_index, evaluation))

type GraphViewDirection = enum
  ancestors
  descendants
  both_directions

proc parse_graph_view_direction(value: string): GraphViewDirection =
  case value
  of "ancestor": ancestors
  of "descendant": descendants
  of "bidirectional": both_directions
  else: raise newException(ValueError, "direction must be ancestor, descendant, or bidirectional")

proc graph_neighbors(graph: WorkGraph; node_id: uint32;
    direction: GraphViewDirection): seq[uint32] =
  graph.dependency_neighbors(
    node_id,
    direction in {ancestors, both_directions},
    direction in {descendants, both_directions})

proc graph_view_summary*(graph: WorkGraph; owner_node_id: uint32;
    direction: string; depth, max_nodes: int): string =
  if graph.node_index(owner_node_id) < 0:
    raise newException(ValueError, "current graph creator does not exist")
  if depth < 0 or max_nodes < 1:
    raise newException(ValueError, "depth must be non-negative and max_nodes must be positive")
  let parsed_direction = parse_graph_view_direction(direction)
  var queue: seq[(uint32, int)] = @[(owner_node_id, 0)]
  var visited = initTable[uint32, bool]()
  visited[owner_node_id] = true
  var queue_index = 0
  while queue_index < queue.len and queue.len <= max_nodes:
    let current = queue[queue_index]
    inc queue_index
    if current[1] >= depth:
      continue
    for neighbor_id in graph.graph_neighbors(current[0], parsed_direction):
      if not visited.getOrDefault(neighbor_id) and queue.len < max_nodes:
        visited[neighbor_id] = true
        queue.add((neighbor_id, current[1] + 1))
  for index, item in queue:
    let node_index = graph.node_index(item[0])
    if node_index < 0:
      continue
    let node = graph.nodes[node_index]
    let incoming = node.node_dependency_ids
    let outgoing = graph.dependency_children(node.id).mapIt($it)
    result.add("Node " & $node.id & ": " & node.description & "\n")
    result.add("  Type: " & $node.execution_plan.`type` & "\n")
    result.add("  Incoming: " & (if incoming.len == 0: "none" else: incoming.mapIt($it).join(", ")) & "\n")
    result.add("  Outgoing: " & (if outgoing.len == 0: "none" else: outgoing.join(", ")))
    if index + 1 < queue.len:
      result.add("\n")

proc node_completion_error*(graph: WorkGraph; node_id: uint32): string =
  let index = graph.node_index(node_id)
  if index < 0:
    return "unknown node"
  let node = graph.nodes[index]
  result = graph.node_artifact_error(node)
  if result.len > 0:
    return
  let resolved_outputs = graph.resolved_output_artifacts(node)
  let contract = node.execution_plan.`type`.node_execution_contract
  if contract.graph_creator and graph.pending_sequence_index(node_id) >= 0:
    return "graph-creation node has pending edits"
  for output in resolved_outputs:
    if not path_exists(output.path):
      return "missing " & contract.missing_output_label & ": " & output.path

proc add_artifact_prompt(result: var string; title, path, description: string) =
  result.add("  - " & title & "\n")
  result.add("    Resolved path: " & path & "\n")
  result.add("    Description: " & description & "\n")

proc graph_creation_authority_prompt(allowed, disallowed: seq[string]): string =
  "  - Authority: allowed=[" & allowed.join(", ") & "]; disallowed=[" &
    disallowed.join(", ") & "]. Authority covers decisions, not file access. " &
    "Allowed is exhaustive; `*` means all decision scopes; disallowed clarifies " &
    "explicit exclusions. Both lists may be modified for graph_creation nodes.\n" &
    "  - Make decisions only within allowed. For any outside-authority decision, " &
    "create human_input; create independent human_input nodes in parallel. " &
    "Re-plan after responses until no violating decisions remain.\n" &
    "  - After human_input responses, infer authority from user text and update " &
    "both lists before continuing. Set child authority from explicit user grants; " &
    "do not expand it otherwise.\n"

proc add_node_prompt_contract(result: var string; node: WorkNode) =
  let contract = node.execution_plan.`type`.node_execution_contract
  result.add("Completion rules:\n")
  if contract.graph_creator:
    result.add(graph_creation_authority_prompt(
      node.execution_plan.allowed, node.execution_plan.disallowed))
    result.add("  - Use graph tools for graph changes.\n")
    result.add("  - Artifacts are files for the final user or downstream workers; " &
      "graph structure uses tools, not files.\n")
    result.add("  - Inputs require producer_node_id, path, description; " &
      "normal outputs require path, description; final is optional. " &
      "Human_input omits outputs; runtime adds response.txt.\n")
    result.add("Graph tool guide: only this running graph_creation node may use tools; " &
      "inspect; mutate pending nodes dominated by this creator; " &
      "on pending_invalid, retry same tool with edit_id or discard_edit; finish last.\n")
    result.add("  - Correct or discard every pending invalid edit before finishing.\n")
    result.add("  - Correct a pending edit with its edit_id and original tool, or discard it.\n")
  elif contract.requires_single_output:
    result.add("  - Human-input node; no model execution; response.txt output is implicit; do not declare it.\n")
  else:
    result.add("  - Do not create or modify the work graph.\n")
  result.add("  - Write every declared output before calling finish_node.\n")
  result.add("  - Call finish_node only after completion rules are satisfied.\n")
  result.add("  - finish_node is preferred explicit completion handshake.\n")
  result.add("  - After finish_node succeeds, stop immediately: do not do more work, " &
    "send another task, call finish_node again, or wait for continuation.\n")
  result.add("  - Ordinary text saying done is not completion; runtime accepts only " &
    "validated finish_node or normal turn termination.\n")
  result.add("  - Never create or update a Codex platform goal; goal state belongs to " &
    "the goal layer.\n")

proc node_developer_prompt*(graph: WorkGraph; node: WorkNode): string =
  result.add("Current orchestration node:\n")
  result.add("  ID: " & $node.id & "\n")
  result.add("  Type: " & $node.execution_plan.`type` & "\n")
  result.add("  Reasoning level: " & $node.execution_plan.reasoning_level & "\n")
  result.add("  Description: " & node.description & "\n")
  result.add("  Objective: " & node.objective & "\n")
  result.add("  State: " & $node.state & "\n")
  result.add("  Explicit dependencies: " &
    (if node.wait_for.len == 0: "none" else: node.wait_for.mapIt($it).join(", ")) & "\n\n")
  if node.inputs.len > 0:
    result.add("Input artifacts (read from these paths):\n")
  for input in node.inputs:
    result.add_artifact_prompt(
      "From node " & $input.producer_node_id,
      graph.resolve_input_path(input), input.description)
  if node.outputs.len > 0:
    result.add("Output artifacts (write before completion):\n")
  for output in graph.resolved_output_artifacts(node):
    result.add_artifact_prompt(
      if output.declaration.final: "Final output" else: "Output",
      output.path, output.declaration.description)
  result.add("\n")
  result.add_node_prompt_contract(node)
  result.add("\nNearby canonical graph:\n")
  result.add(graph.graph_view_summary(node.id, "bidirectional", 1, 8))

proc final_artifact_paths*(graph: WorkGraph): seq[string] =
  for node in graph.nodes:
    if node.state != completed:
      continue
    for output in graph.resolved_output_artifacts(node):
      if output.declaration.final and path_exists(output.path):
        result.add(output.path)

proc all_nodes_completed(graph: WorkGraph): bool =
  if graph.nodes.len == 0:
    return false
  for node in graph.nodes:
    if node.state != completed:
      return false
  true

proc report_final_artifacts(graph: var WorkGraph) =
  graph.final_artifacts_reported = true
  let paths = graph.final_artifact_paths
  var message = "ORCHESTRATION COMPLETE\nFinal artifacts:"
  if paths.len == 0:
    message.add(" none")
  else:
    for path in paths:
      message.add("\n  " & path)
  graph.outgoing_messages.add(WorkGraphMessage(node_id: 0, text: message))

proc node_runnable(graph: WorkGraph; node: WorkNode): bool =
  if node.state != pending:
    return false
  if graph.node_artifact_error(node).len > 0:
    return false
  for dependency_id in node.node_dependency_ids:
    let dependency_index = graph.node_index(dependency_id)
    if dependency_index < 0 or
        graph.nodes[dependency_index].state != completed:
      return false
  true

proc node_state_is_active(state: NodeState): bool {.inline.} =
  state in {running, awaiting_human_input}

proc runnable_node_ids*(graph: WorkGraph): seq[uint32] =
  for node in graph.nodes:
    if graph.node_runnable(node):
      result.add(node.id)

proc node_prompt(node: WorkNode): string =
  if node.execution_plan.`type`.node_execution_contract.requires_single_output:
    return node.execution_plan.instructions
  result = "Execute this orchestration task."
  if node.execution_plan.instructions.len > 0:
    result.add("\n\nInstructions:\n" & node.execution_plan.instructions)
  if node.objective.len > 0:
    result.add("\n\nObjective:\n" & node.objective)

proc log_node_failure(graph: var WorkGraph; node_id: uint32; reason: string) =
  graph.log_messages.add("NODE " & $node_id & " FAILED: " & reason)

proc lifecycle_index(graph: WorkGraph; node_id: uint32): int =
  for index, lifecycle in graph.node_lifecycles:
    if lifecycle.node_id == node_id:
      return index
  -1

proc pending_finish_index(graph: WorkGraph; request_id: string): int =
  if request_id.len == 0:
    return -1
  for index, lifecycle in graph.node_lifecycles:
    if lifecycle.pending_finish_request_id == request_id:
      return index
  -1

proc pending_finish_for_node(graph: WorkGraph; node_id: uint32): int =
  let index = graph.lifecycle_index(node_id)
  if index >= 0 and graph.node_lifecycles[index].pending_finish_request_id.len > 0:
    return index
  -1

proc clear_pending_finish(graph: var WorkGraph; node_id: uint32) =
  let index = graph.lifecycle_index(node_id)
  if index >= 0:
    graph.node_lifecycles[index].pending_finish_request_id.setLen(0)

proc set_pending_finish(graph: var WorkGraph; node_id: uint32;
    request_id, thread_id, turn_id: string) =
  let index = graph.lifecycle_index(node_id)
  if index >= 0:
    graph.node_lifecycles[index].pending_finish_request_id = request_id
    graph.node_lifecycles[index].thread_id = thread_id
    graph.node_lifecycles[index].turn_id = turn_id
  else:
    graph.node_lifecycles.add(NodeLifecycle(
      node_id: node_id,
      started_ticks: getMonoTime().ticks,
      thread_id: thread_id,
      turn_id: turn_id,
      pending_finish_request_id: request_id))

proc add_lifecycle_diagnostic(graph: var WorkGraph; node_id: uint32;
    source: CompletionSource; disposition: LifecycleDisposition;
    old_state, new_state: NodeState; reason: string;
    thread_id = ""; turn_id = ""; request_id = ""; started_ticks = 0'i64) =
  let terminal_ticks = getMonoTime().ticks
  let elapsed_milliseconds = if started_ticks > 0:
    (terminal_ticks - started_ticks) div 1_000_000 else: 0'i64
  let node_index = graph.node_index(node_id)
  let execution_type = if node_index >= 0:
    graph.nodes[node_index].execution_plan.`type` else: llm_worker
  var output_paths: seq[string] = @[]
  if node_index >= 0:
    for output in graph.nodes[node_index].outputs:
      try:
        output_paths.add(graph.resolve_output_path(node_id, output))
      except CatchableError:
        output_paths.add(output.path)
  graph.lifecycle_diagnostics.add(LifecycleDiagnostic(
    node_id: node_id,
    execution_type: execution_type,
    source: source,
    disposition: disposition,
    old_state: old_state,
    new_state: new_state,
    reason: reason,
    thread_id: thread_id,
    turn_id: turn_id,
    request_id: request_id,
    output_paths_checked: output_paths,
    validation_result: reason,
    started_ticks: started_ticks,
    terminal_ticks: terminal_ticks,
    elapsed_milliseconds: elapsed_milliseconds))

proc begin_node_lifecycle(graph: var WorkGraph; node_id: uint32): bool =
  if graph.lifecycle_index(node_id) >= 0:
    return false
  let started_ticks = getMonoTime().ticks
  graph.node_lifecycles.add(NodeLifecycle(
    node_id: node_id,
    started_ticks: started_ticks))
  inc graph.lifecycle_counters.node_starts
  graph.add_lifecycle_diagnostic(
    node_id,
    completion_normal_turn,
    lifecycle_accepted,
    pending,
    running,
    "node_started",
    started_ticks = started_ticks)
  true

proc mark_node_started(graph: var WorkGraph; index: int): bool =
  if index < 0 or graph.nodes[index].state != pending:
    return false
  let node_id = graph.nodes[index].id
  graph.nodes[index].state = running
  if graph.begin_node_lifecycle(node_id):
    return true
  graph.nodes[index].state = pending
  false

proc lifecycle_node_for_thread(graph: WorkGraph; thread_id: string): uint32 =
  if thread_id.len == 0:
    return 0
  for lifecycle in graph.node_lifecycles:
    if lifecycle.thread_id == thread_id:
      return lifecycle.node_id
  0

proc update_lifecycle_transport(graph: var WorkGraph;
    event: CodexRuntimeEvent) =
  var node_id = event.node_id
  if node_id == 0:
    node_id = graph.lifecycle_node_for_thread(event.thread_id)
  let lifecycle_index = graph.lifecycle_index(node_id)
  if lifecycle_index < 0:
    return
  let node_index = graph.node_index(node_id)
  if node_index < 0 or not graph.nodes[node_index].state.node_state_is_active:
    return
  var lifecycle = graph.node_lifecycles[lifecycle_index]
  if event.kind == cre_thread_ready and event.text.len > 0:
    lifecycle.thread_id = event.text
  elif event.thread_id.len > 0:
    lifecycle.thread_id = event.thread_id
  if event.turn_id.len > 0:
    lifecycle.turn_id = event.turn_id
  if event.kind == cre_global_notification and
      event.notification_kind == nk_turn_started:
    lifecycle.idle_observed = false
  elif event.kind == cre_global_notification and
      event.notification_kind == nk_thread_status_changed and
      event.thread_status.isSome and event.thread_status.get == tsk_idle:
    lifecycle.idle_observed = true
  graph.node_lifecycles[lifecycle_index] = lifecycle

proc transition_to_terminal(graph: var WorkGraph; node_id: uint32;
    new_state: NodeState; source: CompletionSource; reason: string;
    thread_id = ""; turn_id = ""; request_id = ""): LifecycleDisposition =
  let index = graph.node_index(node_id)
  if index < 0:
    return lifecycle_rejected
  let old_state = graph.nodes[index].state
  if old_state notin {pending, running, awaiting_human_input}:
    graph.add_lifecycle_diagnostic(
      node_id,
      source,
      lifecycle_late_suppressed,
      old_state,
      old_state,
      reason,
      thread_id,
      turn_id,
      request_id)
    return lifecycle_late_suppressed
  graph.nodes[index].state = new_state
  graph.clear_pending_finish(node_id)
  if new_state == failed and
      graph.nodes[index].execution_plan.`type`.node_execution_contract.graph_creator:
    let sequence_index = graph.pending_sequence_index(node_id)
    if sequence_index >= 0:
      graph.pending_sequences.delete(sequence_index)
  let lifecycle_index = graph.lifecycle_index(node_id)
  var started_ticks = 0'i64
  if lifecycle_index >= 0:
    var lifecycle = graph.node_lifecycles[lifecycle_index]
    started_ticks = lifecycle.started_ticks
    lifecycle.terminal = true
    lifecycle.terminal_ticks = getMonoTime().ticks
    if thread_id.len > 0:
      lifecycle.thread_id = thread_id
    if turn_id.len > 0:
      lifecycle.turn_id = turn_id
    graph.node_lifecycles[lifecycle_index] = lifecycle
  graph.add_lifecycle_diagnostic(
    node_id,
    source,
    lifecycle_accepted,
    old_state,
    new_state,
    reason,
    thread_id,
    turn_id,
    request_id,
    started_ticks)
  lifecycle_accepted

proc fail_node_with_source(graph: var WorkGraph; node_id: uint32;
    reason: string; source: CompletionSource;
    thread_id = ""; turn_id = ""; request_id = ""): bool =
  let index = graph.node_index(node_id)
  if index < 0:
    graph.log_node_failure(node_id, reason)
    return false
  let old_state = graph.nodes[index].state
  let disposition = graph.transition_to_terminal(
    node_id,
    failed,
    source,
    reason,
    thread_id,
    turn_id,
    request_id)
  if disposition == lifecycle_accepted:
    graph.log_node_failure(node_id, reason)
    inc graph.lifecycle_counters.failed_completion_attempts
  elif old_state in {completed, failed}:
    inc graph.lifecycle_counters.late_terminal_events
  disposition == lifecycle_accepted

proc fail_node*(graph: var WorkGraph; node_id: uint32; reason: string): bool =
  graph.fail_node_with_source(node_id, reason, completion_runtime_error)

proc fail_and_terminalize(graph: var WorkGraph; bridge: CodexBridge;
    node_id: uint32; reason: string; source = completion_runtime_error;
    thread_id = ""; turn_id = ""; request_id = ""): bool =
  result = graph.fail_node_with_source(
    node_id, reason, source, thread_id, turn_id, request_id)
  if result:
    bridge.terminalize_node(node_id)

proc fail_active_nodes(graph: var WorkGraph; bridge: CodexBridge;
    reason: string; source = completion_runtime_error) =
  var active_node_ids: seq[uint32] = @[]
  for node in graph.nodes:
    if node.state.node_state_is_active:
      active_node_ids.add(node.id)
  for node_id in active_node_ids:
    discard graph.fail_and_terminalize(bridge, node_id, reason, source)

proc complete_node_state(graph: var WorkGraph; index: int;
    source = completion_normal_turn; thread_id = ""; turn_id = "";
    request_id = ""): bool =
  if index < 0:
    return false
  if graph.nodes[index].state == completed:
    discard graph.transition_to_terminal(
      graph.nodes[index].id,
      completed,
      source,
      "duplicate_completion",
      thread_id,
      turn_id,
      request_id)
    return true
  if graph.nodes[index].state == failed:
    discard graph.transition_to_terminal(
      graph.nodes[index].id,
      failed,
      source,
      "completion_after_failure",
      thread_id,
      turn_id,
      request_id)
    return false
  if not graph.nodes[index].state.node_state_is_active:
    return false
  let node_id = graph.nodes[index].id
  let disposition = graph.transition_to_terminal(
      node_id,
      completed,
      source,
      "completion_accepted",
      thread_id,
      turn_id,
      request_id)
  if disposition != lifecycle_accepted:
    return graph.nodes[index].state == completed
  inc graph.lifecycle_counters.successful_completion_attempts
  if graph.all_nodes_completed and not graph.final_artifacts_reported:
    graph.report_final_artifacts
  true

proc completion_validation_error(graph: WorkGraph; node_id: uint32;
    source: CompletionSource): string =
  let index = graph.node_index(node_id)
  if index < 0:
    return "unknown node"
  let expected_state = if source == completion_human_input:
    awaiting_human_input else: running
  if graph.nodes[index].state != expected_state:
    return "node is not active"
  graph.node_completion_error(node_id)

proc attempt_completion_error*(graph: var WorkGraph; node_id: uint32;
    source = completion_normal_turn): string =
  let index = graph.node_index(node_id)
  if index < 0:
    return "unknown node"
  if graph.nodes[index].state in {completed, failed}:
    if graph.complete_node_state(index, source):
      return
    return "node is not active"
  result = graph.completion_validation_error(node_id, source)
  if result.len > 0:
    discard graph.fail_node_with_source(node_id, result, source)
    return result
  if not graph.complete_node_state(index, source):
    result = "node completion failed"

proc attempt_completion*(graph: var WorkGraph; node_id: uint32;
    source = completion_normal_turn): bool =
  graph.attempt_completion_error(node_id, source).len == 0

proc complete_node*(graph: var WorkGraph; node_id: uint32;
    source = completion_normal_turn): bool =
  var effective_source = source
  let index = graph.node_index(node_id)
  if source == completion_normal_turn and index >= 0 and
      graph.nodes[index].state == awaiting_human_input:
    effective_source = completion_human_input
  graph.attempt_completion(node_id, effective_source)

proc node_is_running*(graph: WorkGraph; node_id: uint32): bool =
  let index = graph.node_index(node_id)
  index >= 0 and graph.nodes[index].state == running

proc node_can_accept_user_input*(graph: WorkGraph; node_id: uint32): bool =
  let index = graph.node_index(node_id)
  index >= 0 and graph.nodes[index].state.node_state_is_active

proc set_node_objective*(graph: var WorkGraph; node_id: uint32;
    objective: string): bool =
  let index = graph.node_index(node_id)
  if index < 0 or objective.len == 0:
    return false
  if graph.nodes[index].objective.len > 0:
    return false
  graph.nodes[index].objective = objective
  true

proc mark_awaiting_human_input*(graph: var WorkGraph; node_id: uint32): bool =
  let index = graph.node_index(node_id)
  if index < 0 or graph.nodes[index].state notin {pending, running}:
    return false
  let old_state = graph.nodes[index].state
  graph.nodes[index].state = awaiting_human_input
  graph.add_lifecycle_diagnostic(
    node_id,
    completion_human_input,
    lifecycle_accepted,
    old_state,
    awaiting_human_input,
    "human_input_requested")
  true

proc answer_human_input*(graph: var WorkGraph; node_id: uint32;
    answer: string): bool =
  let index = graph.node_index(node_id)
  if index < 0:
    return false
  let node = graph.nodes[index]
  if not node.execution_plan.`type`.node_execution_contract.requires_single_output or
      node.state != awaiting_human_input or answer.strip.len == 0:
    return false
  try:
    let path = graph.resolve_artifact_path(node_id, human_response_output_path)
    createDir(graph.graph_artifact_root)
    createDir(parentDir(path))
    writeFile(path, "Instructions:\n" &
      node.execution_plan.instructions &
      "\n\nResponse:\n" & answer)
    graph.attempt_completion(node_id, completion_human_input)
  except CatchableError as error:
    discard graph.fail_node(node_id, error.msg)
    false

proc drain_outgoing_messages*(graph: var WorkGraph): seq[WorkGraphMessage] =
  result = graph.outgoing_messages
  graph.outgoing_messages = @[]

proc send_work_graph_message(graph: var WorkGraph; bridge: CodexBridge;
    node_id: uint32; text: string; developer_instructions = "";
    graph_creation_node = false; effort = re_low): bool =
  try:
    bridge.send_node_message(
      node_id,
      text,
      developer_instructions,
      graph_creation_node,
      effort)
    graph.outgoing_messages.add(WorkGraphMessage(
      node_id: node_id,
      text: text))
    if developer_instructions.len > 0:
      graph.outgoing_messages.add(WorkGraphMessage(
        node_id: node_id,
        text: "DEVELOPER INSTRUCTIONS:\n" & developer_instructions))
    true
  except CatchableError as error:
    discard graph.fail_and_terminalize(bridge, node_id, error.msg)
    false

proc start_available_nodes*(graph: var WorkGraph; bridge: CodexBridge) =
  for index in 0 ..< graph.nodes.len:
    let node = graph.nodes[index]
    let contract = node.execution_plan.`type`.node_execution_contract
    let prompt = node.node_prompt
    if not graph.node_runnable(node):
      continue
    let node_id = node.id
    if contract.requires_single_output:
      if graph.mark_awaiting_human_input(node_id):
        graph.outgoing_messages.add(WorkGraphMessage(
          node_id: node_id,
          text: prompt))
      continue
    if bridge == nil:
      continue
    if not graph.mark_node_started(index):
      continue
    let running_node = graph.nodes[index]
    let developer_prompt = graph.node_developer_prompt(running_node)
    discard graph.send_work_graph_message(
      bridge,
      node_id,
      prompt,
      developer_prompt,
      contract.graph_creator,
      running_node.execution_plan.reasoning_level.reasoning_effort)

proc effective_watchdog_timeout_seconds(graph: WorkGraph): float64 =
  if graph.watchdog_timeout_seconds > 0:
    graph.watchdog_timeout_seconds
  else:
    configured_worker_lifetime_seconds()

proc check_watchdogs*(graph: var WorkGraph; bridge: CodexBridge;
    now_ticks = getMonoTime().ticks): seq[uint32] =
  let timeout_ticks = int64(
    graph.effective_watchdog_timeout_seconds * 1_000_000_000.0)
  if timeout_ticks <= 0:
    return @[]
  for index in 0 ..< graph.nodes.len:
    if graph.nodes[index].state == running and
        graph.lifecycle_index(graph.nodes[index].id) < 0:
      discard graph.begin_node_lifecycle(graph.nodes[index].id)
  var expired_nodes: seq[(uint32, bool)] = @[]
  for lifecycle in graph.node_lifecycles:
    if lifecycle.terminal or lifecycle.started_ticks <= 0 or
        now_ticks - lifecycle.started_ticks < timeout_ticks:
      continue
    let index = graph.node_index(lifecycle.node_id)
    if index >= 0 and graph.nodes[index].state == running:
      expired_nodes.add((lifecycle.node_id, lifecycle.idle_observed))
  for expired_node in expired_nodes:
    let node_id = expired_node[0]
    let reason = if expired_node[1]:
      "idle_without_completion" else: "worker_watchdog_timeout"
    if graph.fail_and_terminalize(
        bridge, node_id, reason, completion_watchdog):
      inc graph.lifecycle_counters.watchdog_timeouts
      result.add(node_id)

proc reply_tool_call(bridge: CodexBridge; event: CodexRuntimeEvent;
    success: bool; message: string): bool =
  if bridge == nil:
    return false
  bridge.reply_server_request(
    event.request_id_value,
    event.node_id,
    DynamicToolCallResponse(
      success: success,
      content_items: if message.len > 0:
        @[dynamic_tool_text(message)]
      else: @[]))

proc fail_tool_call_after_reply(graph: var WorkGraph; bridge: CodexBridge;
    event: CodexRuntimeEvent; reason, response_message: string;
    source = completion_runtime_error): string =
  result = reason
  let did_fail = graph.fail_node_with_source(
    event.node_id,
    reason,
    source,
    event.thread_id,
    event.turn_id,
    event.request_id)
  discard bridge.reply_tool_call(event, false, response_message)
  if did_fail:
    bridge.terminalize_node(event.node_id)

proc event_arguments(event: CodexRuntimeEvent): JsonNode =
  let value = parseJson(event.params_json)
  if value.kind == JObject and value.contains("arguments"):
    return value["arguments"]
  value

proc parse_nonnegative_int(node: JsonNode; field_path: string): int =
  if node.kind != JInt:
    raise newException(ValueError, field_path & " must be an integer")
  let value = node.getInt
  if value < 0 or value > int64(high(int)):
    raise newException(ValueError, field_path & " is out of range")
  int(value)

proc handle_graph_tool_call(graph: var WorkGraph; bridge: CodexBridge;
    event: CodexRuntimeEvent): string =
  try:
    if not graph.is_running_graph_creator(event.node_id):
      raise newException(ValueError,
        "graph-creation tools require a running graph_creation node")
    let args = event.event_arguments.require_object("arguments")
    var response: JsonNode
    case event.tool_name
    of create_node_name:
      response = graph.create_node(
        event.node_id,
        parse_node_definition(args.require_field("node_definition", "node_definition")),
        args.optional_edit_id).mutation_result_json
    of update_node_name:
      response = graph.update_node(
        event.node_id,
        parse_identifier(args.require_field("node_id", "node_id"), "node_id"),
        parse_node_changes(args.require_field("changes", "changes")),
        args.optional_edit_id).mutation_result_json
    of delete_node_name:
      response = graph.delete_node(
        event.node_id,
        parse_identifier(args.require_field("node_id", "node_id"), "node_id"),
        args.optional_edit_id).mutation_result_json
    of reassign_output_name:
      let destination_path = if args.contains("destination_path"):
        args["destination_path"].require_string("destination_path") else: ""
      response = graph.reassign_output(
        event.node_id,
        parse_identifier(args.require_field("source_node_id", "source_node_id"), "source_node_id"),
        args.require_field("source_path", "source_path").require_string("source_path"),
        parse_identifier(args.require_field("destination_node_id", "destination_node_id"), "destination_node_id"),
        destination_path,
        args.optional_edit_id).mutation_result_json
    of get_node_name:
      let node_id = parse_identifier(args.require_field("node_id", "node_id"), "node_id")
      let index = graph.node_index(node_id)
      if index < 0:
        raise newException(ValueError, "node_id does not identify a canonical node")
      response = graph.nodes[index].node_json
    of get_graph_view_name:
      let direction = args.require_field("direction", "direction").require_string("direction")
      let depth = parse_nonnegative_int(
        args.require_field("depth", "depth"), "depth")
      let max_nodes = parse_nonnegative_int(
        args.require_field("max_nodes", "max_nodes"), "max_nodes")
      response = %*{
        "summary": graph.graph_view_summary(
          event.node_id, direction, depth, max_nodes)
      }
    of list_pending_edits_name:
      response = graph.pending_edits_json(event.node_id)
    of get_pending_edit_name:
      response = graph.pending_edit_json(
        event.node_id,
        parse_identifier(args.require_field("edit_id", "edit_id"), "edit_id"))
    of discard_edit_name:
      response = graph.discard_edit(
        event.node_id,
        parse_identifier(args.require_field("edit_id", "edit_id"), "edit_id")).mutation_result_json
    else:
      raise newException(ValueError, "unknown graph-creation tool")
    if not bridge.reply_tool_call(event, true, response.pretty):
      result = "graph tool response could not be queued"
      discard graph.fail_and_terminalize(
        bridge, event.node_id, result, completion_runtime_error)
  except CatchableError as error:
    if not bridge.reply_tool_call(event, false, error.msg):
      result = "graph tool error response could not be queued"
      discard graph.fail_and_terminalize(
        bridge, event.node_id, result, completion_runtime_error)

proc handle_finish_node_call(graph: var WorkGraph; bridge: CodexBridge;
    event: CodexRuntimeEvent): string =
  inc graph.lifecycle_counters.explicit_finish_calls
  if event.tool_name != finish_node_name:
    result = "unknown dynamic tool: " & event.tool_name
    result = graph.fail_tool_call_after_reply(
      bridge,
      event,
      result,
      "unknown dynamic tool",
      completion_finish_node)
    return

  let index = graph.node_index(event.node_id)
  if index < 0:
    result = "finish_node called for unknown node"
    discard bridge.reply_tool_call(event, false, result)
    return
  let state = graph.nodes[index].state
  if state in {completed, failed}:
    inc graph.lifecycle_counters.duplicate_finish_calls
    discard graph.transition_to_terminal(
      event.node_id,
      state,
      completion_finish_node,
      "finish_node_after_terminal",
      event.thread_id,
      event.turn_id,
      event.request_id)
    discard bridge.reply_tool_call(event, false, "finish_node already terminal")
    return
  if state != running:
    result = "finish_node called for non-running node"
    result = graph.fail_tool_call_after_reply(
      bridge,
      event,
      result,
      result,
      completion_finish_node)
    return
  if graph.pending_finish_for_node(event.node_id) >= 0:
    result = "finish_node response already pending"
    inc graph.lifecycle_counters.duplicate_finish_calls
    graph.add_lifecycle_diagnostic(
      event.node_id,
      completion_finish_node,
      lifecycle_duplicate,
      running,
      running,
      "duplicate_finish_node",
      event.thread_id,
      event.turn_id,
      event.request_id)
    discard bridge.reply_tool_call(event, false, result)
    return

  let completion_error = graph.completion_validation_error(
    event.node_id, completion_finish_node)
  if completion_error.len > 0:
    result = graph.fail_tool_call_after_reply(
      bridge,
      event,
      completion_error,
      completion_error,
      completion_finish_node)
  elif not bridge.reply_tool_call(event, true, "node completed"):
    result = "finish_node response could not be queued"
    inc graph.lifecycle_counters.finish_response_enqueue_failures
    discard graph.fail_and_terminalize(
      bridge,
      event.node_id,
      result,
      completion_finish_node,
      event.thread_id,
      event.turn_id,
      event.request_id)
  else:
    graph.set_pending_finish(
      event.node_id,
      event.request_id,
      event.thread_id,
      event.turn_id)

proc handle_graph_server_request(graph: var WorkGraph; bridge: CodexBridge;
    event: CodexRuntimeEvent): string =
  if event.server_request_kind == sr_tool_user_input:
    let index = graph.node_index(event.node_id)
    if index >= 0 and graph.nodes[index].execution_plan.`type`.
        node_execution_contract.requires_single_output:
      discard graph.mark_awaiting_human_input(event.node_id)
  elif event.server_request_kind == sr_tool_call:
    if event.tool_name == finish_node_name:
      result = graph.handle_finish_node_call(bridge, event)
    elif event.tool_name.is_graph_creation_tool_name:
      result = graph.handle_graph_tool_call(bridge, event)
    else:
      result = graph.fail_tool_call_after_reply(
        bridge,
        event,
        "unknown dynamic tool: " & event.tool_name,
        "unknown dynamic tool",
        completion_runtime_error)

proc handle_codex_event_impl(graph: var WorkGraph; bridge: CodexBridge;
    event: CodexRuntimeEvent;
    disposition: var LifecycleDisposition): string =
  disposition = lifecycle_accepted
  graph.update_lifecycle_transport(event)
  let node_index = graph.node_index(event.node_id)
  if node_index >= 0 and graph.nodes[node_index].state in {completed, failed} and
      event.kind in {
        cre_thread_ready,
        cre_agent_message_delta,
        cre_turn_completed,
        cre_node_error,
        cre_thread_error,
        cre_tool_response_sent,
        cre_global_notification}:
    if event.kind == cre_global_notification and
        event.server_request_kind == sr_tool_call:
      discard bridge.reply_tool_call(event, false, "node is terminal")
    elif event.kind == cre_global_notification and
        event.server_request_kind == sr_tool_user_input:
      discard bridge.reply_user_input(event.request_id_value, event.node_id, @[])
    disposition = lifecycle_late_suppressed
    graph.add_lifecycle_diagnostic(
      event.node_id,
      completion_runtime_error,
      lifecycle_late_suppressed,
      graph.nodes[node_index].state,
      graph.nodes[node_index].state,
      "late_event_suppressed",
      event.thread_id,
      event.turn_id,
      event.request_id)
    inc graph.lifecycle_counters.late_terminal_events
    return
  case event.kind
  of cre_thread_ready:
    discard
  of cre_global_notification:
    let thread_status = event.thread_status
    if event.notification_kind == nk_thread_status_changed and
        thread_status.isSome:
      let status = thread_status.get
      if status.thread_status_is_terminal:
        let reason = if status == tsk_system_error:
          "Codex thread system error" else: "Codex thread not loaded"
        discard graph.fail_and_terminalize(
          bridge, event.node_id, reason, completion_runtime_error,
          event.thread_id, event.turn_id)
    elif event.server_request_kind in {sr_tool_user_input, sr_tool_call}:
      result = graph.handle_graph_server_request(bridge, event)
  of cre_turn_completed:
    let was_active = graph.node_is_running(event.node_id)
    if graph.pending_finish_for_node(event.node_id) >= 0:
      let node_index = graph.node_index(event.node_id)
      if node_index >= 0:
        graph.add_lifecycle_diagnostic(
          event.node_id,
          completion_normal_turn,
          lifecycle_late_suppressed,
          graph.nodes[node_index].state,
          graph.nodes[node_index].state,
          "normal_completion_waiting_for_finish_response",
          event.thread_id,
          event.turn_id,
          event.request_id)
    else:
      result = graph.attempt_completion_error(
        event.node_id, completion_normal_turn)
      if result.len > 0:
        disposition = lifecycle_rejected
    if was_active and graph.nodes[graph.node_index(event.node_id)].state in {
        completed, failed}:
      bridge.terminalize_node(event.node_id)
  of cre_tool_response_sent:
    let pending_index = graph.pending_finish_index(event.request_id)
    if pending_index >= 0:
      let pending_lifecycle = graph.node_lifecycles[pending_index]
      let pending_node_id = pending_lifecycle.node_id
      graph.clear_pending_finish(pending_node_id)
      let node_index = graph.node_index(pending_node_id)
      if node_index >= 0 and graph.nodes[node_index].state == running:
        if graph.complete_node_state(
            node_index,
            completion_finish_node,
            pending_lifecycle.thread_id,
            pending_lifecycle.turn_id,
            event.request_id):
          bridge.terminalize_node(pending_node_id)
      else:
        graph.add_lifecycle_diagnostic(
          pending_node_id,
          completion_finish_node,
          lifecycle_late_suppressed,
          if node_index >= 0: graph.nodes[node_index].state else: pending,
          if node_index >= 0: graph.nodes[node_index].state else: pending,
          "late_finish_response_suppressed",
          pending_lifecycle.thread_id,
          pending_lifecycle.turn_id,
          event.request_id)
  of cre_thread_error, cre_node_error:
    discard graph.fail_and_terminalize(
      bridge, event.node_id, event.text, completion_runtime_error,
      event.thread_id, event.turn_id, event.request_id)
  of cre_lifecycle_diagnostic:
    if event.text.contains("post-terminal turn start"):
      inc graph.lifecycle_counters.post_terminal_turn_starts
    graph.add_lifecycle_diagnostic(
      event.node_id,
      completion_runtime_error,
      lifecycle_late_suppressed,
      if graph.node_index(event.node_id) >= 0:
        graph.nodes[graph.node_index(event.node_id)].state else: pending,
      if graph.node_index(event.node_id) >= 0:
        graph.nodes[graph.node_index(event.node_id)].state else: pending,
      event.text,
      event.thread_id,
      event.turn_id,
      event.request_id)
    inc graph.lifecycle_counters.late_terminal_events
  of cre_runtime_error:
    if event.text.startsWith("unmapped completion"):
      inc graph.lifecycle_counters.unmapped_completions
      let node_id = graph.lifecycle_node_for_thread(event.thread_id)
      graph.add_lifecycle_diagnostic(
        node_id,
        completion_runtime_error,
        lifecycle_rejected,
        if node_id > 0:
          graph.nodes[graph.node_index(node_id)].state else: pending,
        if node_id > 0:
          graph.nodes[graph.node_index(node_id)].state else: pending,
        "unmapped_completion",
        event.thread_id,
        event.turn_id)
    else:
      graph.fail_active_nodes(bridge, event.text, completion_runtime_error)
  of cre_runtime_closed:
    graph.fail_active_nodes(
      bridge, "Codex runtime closed", completion_runtime_error)
  else:
    discard

proc handle_codex_event_result*(graph: var WorkGraph; bridge: CodexBridge;
    event: CodexRuntimeEvent): CodexEventResult =
  result.disposition = lifecycle_accepted
  result.error = graph.handle_codex_event_impl(
    bridge, event, result.disposition)

proc handle_codex_event*(graph: var WorkGraph; bridge: CodexBridge;
    event: CodexRuntimeEvent): string =
  var disposition: LifecycleDisposition
  graph.handle_codex_event_impl(bridge, event, disposition)
