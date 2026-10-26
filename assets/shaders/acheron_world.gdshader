shader_type canvas_item;
render_mode unshaded;

uniform int wave_count = 0;
// Canvas pixel coordinates, radius and intensity. No real-time clock is used:
// battle pause, speed and time stop all use the skill's fixed-step clock.
uniform vec4 waves[8];
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform vec4 board_rect;
uniform vec2 canvas_size = vec2(1360.0, 900.0);

void fragment() {
	vec4 base = texture(screen_texture, SCREEN_UV);
	// UI transforms use logical canvas coordinates. FRAGCOORD is a rendering
	// pixel coordinate and diverges when the window/device scales the canvas.
	vec2 canvas_position = SCREEN_UV * canvas_size;
	float amount = 0.0;
	for (int i = 0; i < 8; i++) {
		if (i >= wave_count) { break; }
		float distance_from_source = distance(canvas_position, waves[i].xy);
		amount = max(amount, (1.0 - smoothstep(waves[i].z - 5.0, waves[i].z + 5.0, distance_from_source)) * waves[i].w);
	}
	float luma = dot(base.rgb, vec3(0.299, 0.587, 0.114));
	// Blue arena panels become paper grey; black outlines remain readable.
	float blue_panel = step(base.r * 1.13, base.b) * step(base.g * 0.97, base.b);
	float inside_board = step(board_rect.x, canvas_position.x) * step(canvas_position.x, board_rect.z) * step(board_rect.y, canvas_position.y) * step(canvas_position.y, board_rect.w);
	float grey = mix(luma, min(0.94, 0.06 + 3.3 * luma), blue_panel * inside_board * smoothstep(0.065, 0.09, luma));
	float keep_red = step(base.g * 1.35, base.r) * step(base.b * 1.12, base.r);
	COLOR = vec4(mix(base.rgb, vec3(grey), amount * (1.0 - keep_red)), base.a);
}
