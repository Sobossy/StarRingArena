shader_type canvas_item;
render_mode unshaded;

uniform float charge_progress : hint_range(0.0, 1.0) = 0.0;

// Recolour at draw time: the supplied PNG remains intact. The reveal climbs
// from the feet to the hair and follows the sprite when mirrored or rotated.
void fragment() {
	vec4 source = COLOR;
	float luma = dot(source.rgb, vec3(0.299, 0.587, 0.114));
	float purple = step(source.r * 1.06, source.b) * step(source.g * 1.15, source.b);
	float ink = 1.0 - smoothstep(0.055, 0.13, luma);
	vec3 pale_hair = mix(vec3(0.61, 0.58, 0.63), vec3(0.98, 0.95, 0.94), smoothstep(0.10, 0.43, luma));
	vec3 crimson = vec3(0.30 + luma * 0.84, 0.025 + luma * 0.09, 0.065 + luma * 0.12);
	float red_region = smoothstep(0.73, 0.85, UV.y);
	// The visible eye becomes red along with the outfit, preserving its highlights.
	red_region = max(red_region, 1.0 - smoothstep(0.75, 1.0, length((UV-vec2(0.29,0.65))/vec2(0.10,0.055))));
	vec3 changed = mix(pale_hair, crimson, red_region);
	changed = mix(changed, vec3(0.105, 0.035, 0.065), ink);
	changed = mix(source.rgb, changed, purple);
	float reveal = smoothstep(1.0 - charge_progress - 0.018, 1.0 - charge_progress + 0.018, UV.y);
	if (charge_progress <= 0.0) { reveal = 0.0; }
	if (charge_progress >= 1.0) { reveal = 1.0; }
	COLOR = vec4(mix(source.rgb, changed, reveal), source.a);
}
