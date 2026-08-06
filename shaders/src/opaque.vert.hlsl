cbuffer FrameData : register(b0, space1) {
	float2 viewport_size;
	float2 inverse_viewport_size;
}

struct VertexInput {
	// vertex
	uint2 corner  : TEXCOORD0;

	// instance
	uint2 origin   : TEXCOORD1;
	uint2 size     : TEXCOORD2;
	uint4 color    : TEXCOORD3;
	uint kind      : TEXCOORD4;
	float4 shape_data_a : TEXCOORD5;
	float4 shape_data_b : TEXCOORD6;
	float depth    : TEXCOORD7;
};

struct VertexOutput {
	float4 position : SV_Position;
	nointerpolation float4 color : TEXCOORD0;
	nointerpolation uint kind : TEXCOORD1;
	nointerpolation float4 shape_data_a : TEXCOORD2;
	nointerpolation float4 shape_data_b : TEXCOORD3;
};

VertexOutput main(VertexInput input) {
	VertexOutput output;

	float2 pixel_position = float2(input.origin) + float2(input.corner) * float2(input.size);
	float2 ndc_position = float2(
		pixel_position.x * (2.0 * inverse_viewport_size.x) - 1.0,
		1.0 - pixel_position.y * (2.0 * inverse_viewport_size.y)
	);
	
	output.position = float4(ndc_position, input.depth, 1.0);
	output.color = float4(input.color) / 255.0;
	output.kind = input.kind;
	output.shape_data_a = input.shape_data_a;
	output.shape_data_b = input.shape_data_b;
	return output;
}
