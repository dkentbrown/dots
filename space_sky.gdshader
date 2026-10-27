shader_type sky;

// Ambient deep-space backdrop: a near-black base, faint nebula patches, a soft "galactic" band
// and two layers of procedural stars, plus a sun disk drawn wherever the scene's directional
// light is (LIGHT0). No TIME: the backdrop only changes as the camera orbits and the sun moves.
// Everything is a function of view direction only, so zoom never changes it. The globe is
// drawn over the sky, so it eclipses the sun whenever the sun is behind it.

uniform vec3 space_color : source_color = vec3(0.008, 0.010, 0.022);
uniform vec3 nebula_a : source_color = vec3(0.16, 0.10, 0.32);
uniform vec3 nebula_b : source_color = vec3(0.05, 0.20, 0.28);
uniform float nebula_strength : hint_range(0.0, 1.0) = 0.65;
uniform float star_density : hint_range(0.0, 1.0) = 0.25;
uniform float star_brightness : hint_range(0.0, 4.0) = 1.4;
uniform vec3 band_axis = vec3(0.35, 0.9, 0.25);
uniform vec3 sun_color : source_color = vec3(1.0, 0.93, 0.8);
uniform float sun_radius : hint_range(0.0, 0.2) = 0.025;  // angular radius, radians (~1.4°)
uniform float sun_glow : hint_range(0.0, 2.0) = 0.6;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

vec3 hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i);
	float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(i + vec3(1.0, 1.0, 1.0));
	return mix(
		mix(mix(n000, n100, u.x), mix(n010, n110, u.x), u.y),
		mix(mix(n001, n101, u.x), mix(n011, n111, u.x), u.y),
		u.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * value_noise(p);
		p = p * 2.03 + vec3(17.1, 3.7, 9.2);
		a *= 0.5;
	}
	return v;
}

// One star per grid cell at most; `density` is the chance a cell holds one. The star sits at
// least 0.2 from the cell walls and `radius` stays under that, so stars are never clipped.
vec3 star_layer(vec3 dir, float scale, float density, float radius) {
	vec3 p = dir * scale;
	vec3 cell = floor(p);
	if (hash13(cell + vec3(7.31)) > density) {
		return vec3(0.0);
	}
	vec3 h = hash33(cell);
	vec3 center = cell + 0.2 + 0.6 * h;
	float core = 1.0 - smoothstep(0.0, radius, length(p - center));
	vec3 tint = mix(vec3(0.72, 0.82, 1.0), vec3(1.0, 0.88, 0.72), h.y);
	return tint * core * core * (0.35 + 0.65 * h.z);
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float band = exp(-pow(dot(dir, normalize(band_axis)) * 3.5, 2.0));
	float clouds = fbm(dir * 2.4);
	float patches = smoothstep(0.42, 0.78, fbm(dir * 1.3 + vec3(5.2, 1.3, 7.7)));
	vec3 nebula = mix(nebula_a, nebula_b, fbm(dir * 3.1 + vec3(11.0)));
	vec3 col = space_color;
	col += nebula * clouds * (patches + 0.5 * band) * nebula_strength;
	col += star_layer(dir, 140.0, star_density * (0.5 + band), 0.16) * 0.6 * star_brightness;
	col += star_layer(dir, 55.0, star_density * 0.08, 0.13) * star_brightness;
	if (LIGHT0_ENABLED) {
		// LIGHT0_DIRECTION points toward the light. A hard-edged disk plus a tight and a wide glow.
		float ang = acos(clamp(dot(dir, LIGHT0_DIRECTION), -1.0, 1.0));
		float disk = 1.0 - smoothstep(sun_radius * 0.85, sun_radius, ang);
		float glow = exp(-ang * 12.0) * sun_glow + exp(-ang * 3.0) * sun_glow * 0.15;
		col += sun_color * (disk * 6.0 + glow) * LIGHT0_ENERGY;
	}
	COLOR = col;
}
