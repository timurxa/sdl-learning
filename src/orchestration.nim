type
  ExecutionPlanType* = enum
    llm_worker
    graph_creation
    human_input

  ExecutionPlan* = object
    `type`*: ExecutionPlanType

  NodeState* = enum
    pending
    running
    completed
    failed

  WorkNode* = object
    id*: uint32
    wait_for*: seq[uint32]
    state*: NodeState
    execution_plan*: ExecutionPlan

  WorkGraph* = object
    nodes*: seq[WorkNode]
