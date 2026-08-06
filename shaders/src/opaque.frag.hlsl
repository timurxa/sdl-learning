struct FragmentInput {
	float4 position : SV_Position;
	nointerpolation float4 color : TEXCOORD0;
	nointerpolation uint kind : TEXCOORD1;
	nointerpolation float4 shape_data_a : TEXCOORD2;
	nointerpolation float4 shape_data_b : TEXCOORD3;
};

float edge(float2 a, float2 b, float2 sample_position) {
	float2 delta = b - a;
	float2 offset = sample_position - a;
	return delta.x * offset.y - delta.y * offset.x;
}

bool point_in_triangle(float2 sample_position, float2 a, float2 b, float2 c) {
	float first = edge(a, b, sample_position);
	float second = edge(b, c, sample_position);
	float third = edge(c, a, sample_position);
	return (first >= 0.0 && second >= 0.0 && third >= 0.0) ||
		(first <= 0.0 && second <= 0.0 && third <= 0.0);
}

float4 main(FragmentInput input) : SV_Target0 {
	if (input.kind == 1) {
		float2 delta = input.position.xy - input.shape_data_a.xy;
		if (dot(delta, delta) > input.shape_data_a.z * input.shape_data_a.z) {
			discard;
		}
	} else if (input.kind == 2) {
		float2 first = input.shape_data_a.xy;
		float2 second = input.shape_data_a.zw;
		float2 third = input.shape_data_b.xy;
		float2 fourth = input.shape_data_b.zw;
		if (!point_in_triangle(input.position.xy, first, second, third) &&
			!point_in_triangle(input.position.xy, first, third, fourth)) {
			discard;
		}
	} else if (input.kind == 3) {
		if (!point_in_triangle(
			input.position.xy,
			input.shape_data_a.xy,
			input.shape_data_a.zw,
			input.shape_data_b.xy)) {
			discard;
		}
	}
	return input.color;
}
