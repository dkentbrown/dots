shader_type spatial;

// Batched entity drawing (separation stage 5): one material for every dot, block, wall, speck and
// mark. Each MultiMesh instance carries its albedo in the instance colour and its emission in the
// instance custom data, both in sRGB like the StandardMaterial3D colours they replace (those
// convert to linear; instance data doesn't, so we do it here).
// The custom data's alpha marks the player's own colony (1) from everyone else's (0): those
// instances shimmer — their glow swells and whitens on a slow shared pulse — so you can find
// your colony among look-alike CCE tints without changing the colours themselves.
uniform float emission_energy = 1.0;
uniform float shimmer_period = 2.0;      // seconds per pulse
uniform float shimmer_strength = 1.2;    // extra glow at the pulse's peak (× the normal glow)
uniform float shimmer_whiten = 0.35;     // how far toward white the glow goes at the peak
varying vec3 v_emission;
varying float v_own;

vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + vec3(0.055)) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}

void vertex() {
	v_emission = srgb_to_linear(INSTANCE_CUSTOM.rgb);
	v_own = INSTANCE_CUSTOM.a;
}

void fragment() {
	ALBEDO = srgb_to_linear(COLOR.rgb);
	float pulse = v_own * (0.5 - 0.5 * cos(TIME * TAU / shimmer_period));
	EMISSION = mix(v_emission, vec3(1.0), shimmer_whiten * pulse) * emission_energy * (1.0 + shimmer_strength * pulse);
}
