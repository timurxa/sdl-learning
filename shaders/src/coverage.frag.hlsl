Texture2D spriteTexture : register(t0, space2);
SamplerState spriteSampler : register(s0, space2);

struct FragmentInput {
	float4 position              : SV_Position;
	nointerpolation float4 color : TEXCOORD0;
	float2 uv                    : TEXCOORD1;
};

float4 main(FragmentInput input) : SV_Target0 {
	float coverage = spriteTexture.Sample(spriteSampler, input.uv).r;
	if (coverage <= 0.0) {
		discard;
	}
	return float4(input.color.rgb, input.color.a * coverage);
}
