import std/json
import ../src/codex_bridge

let tools = graph_creation_tools()
doAssert tools.len == 9
doAssert tools[0].name == create_node_name
doAssert tools[1].name == update_node_name
doAssert tools[5].name == get_graph_view_name
doAssert tools[0].input_schema["required"].len == 1
doAssert tools[0].input_schema["properties"].contains("node_definition")
doAssert tools[0].input_schema["properties"]["node_definition"]["properties"].contains("outputs")
