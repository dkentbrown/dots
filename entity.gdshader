shader_type spatial;

// Batched entity drawing (separation stage 5): one material for every dot, block, wall, speck and
// mark. Each MultiMesh instance carries its albedo in the instance colour and its emission in the
// instance custom data, both in sRGB like the StandardMaterial3D colours they replace (those
// convert to linear; instance data doesn't, so we do it here).
uniform float emission_energy = 1.0;
varying vec3 v_emission;

vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + vec3(0.055)) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}

void vertex() {
	v_emission = srgb_to_linear(INSTANCE_CUSTOM.rgb);
}

void fragment() {
	ALBEDO = srgb_to_linear(COLOR.rgb);
	EMISSION = v_emission * emission_energy;
}
