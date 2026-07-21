cbuffer FrameData : register(b0, space1) {
	float2 viewport_size;
	float2 inverse_viewport_size;
}

struct VertexInput {
	// vertex
	float2 corner  : TEXCOORD0;

	// instance
	float2 origin  : TEXCOORD1;
	float2 size    : TEXCOORD2;
	float4 color   : TEXCOORD3;
};

struct VertexOutput {
	float4 position : SV_Position;
	float4 color    : TEXCOORD0;
};

VertexOutput main(VertexInput input) {
	VertexOutput output;

	float2 pixel_position = input.origin + input.corner * input.size;
	float2 ndc_position = float2(
		pixel_position.x * (2.0 * inverse_viewport_size.x) - 1.0,
		1.0 - pixel_position.y * (2.0 * inverse_viewport_size.y)
	);
	
	output.position = float4(ndc_position, 0.0, 1.0);
	output.color = input.color;
	return output;
}
