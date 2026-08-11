import std/[json, strutils]
import ../src/codex_bridge
import ../src/codex_json
import ../src/orchestration

let tools = graph_creation_tools()
doAssert tools.len == 9
doAssert tools[0].name == create_node_name
doAssert tools[1].name == update_node_name
doAssert tools[5].name == get_graph_view_name
doAssert tools[0].input_schema["required"].len == 1
doAssert tools[0].input_schema["properties"].contains("node_definition")
doAssert tools[0].input_schema["properties"]["node_definition"]["properties"].contains("outputs")
doAssert tools[0].input_schema["properties"]["node_definition"]["properties"]["execution_plan"]["properties"].contains("reasoning_level")
doAssert tools[0].input_schema["properties"]["node_definition"]["properties"]["inputs"]["items"]["required"].len == 3
doAssert tools[0].description.contains("producer_node_id, path, description")
doAssert tools[0].input_schema["properties"]["node_definition"]["required"].len == 5

var input_tool_graph = new_work_graph(objective = "tool input dependency")
input_tool_graph.nodes[0].state = running
input_tool_graph.nodes[0].outputs = @[OutputArtifactDecl(
  path: "root.txt", description: "Root output")]
let input_tool_event = CodexRuntimeEvent(
  kind: cre_global_notification,
  node_id: 1,
  server_request_kind: sr_tool_call,
  tool_name: create_node_name,
  params_json: $(%*{
    "arguments": {
      "node_definition": {
        "description": "Tool input node",
        "objective": "Consume root output",
        "inputs": [{
          "producer_node_id": 1,
          "path": "root.txt",
          "description": "Root input"
        }],
        "outputs": [{
          "path": "tool-input.txt",
          "description": "Tool input output"
        }],
        "wait_for": [],
        "execution_plan": {
          "type": "llm_worker",
          "instructions": "Consume root output",
          "reasoning_level": "bounded"
        }
      }
    }
  }))
discard input_tool_graph.handle_codex_event(nil, input_tool_event)
doAssert input_tool_graph.nodes.len == 2
doAssert input_tool_graph.nodes[1].wait_for == @[]
doAssert input_tool_graph.nodes[1].inputs.len == 1
doAssert input_tool_graph.nodes[1].inputs[0].producer_node_id == 1
doAssert input_tool_graph.nodes[1].node_dependency_ids == @[1'u32]
