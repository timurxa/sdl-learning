struct FragmentInput {
	float4 position : SV_Position;
	nointerpolation float4 color : TEXCOORD0;
	nointerpolation uint kind : TEXCOORD1;
	nointerpolation float4 shape_data : TEXCOORD2;
};

float4 main(FragmentInput input) : SV_Target0 {
	if (input.kind == 1) {
		float2 delta = input.position.xy - input.shape_data.xy;
		if (dot(delta, delta) > input.shape_data.z * input.shape_data.z) {
			discard;
		}
	}
	return input.color;
}
