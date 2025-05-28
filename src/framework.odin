package main

import slog  "sokol/log"
import sg    "sokol/gfx"
import sgl    "sokol/gl"
import sapp  "sokol/app"
import sglue "sokol/glue"
import sdtx  "sokol/debugtext"

import "base:runtime"
import "core:c"
import "core:os"
import "core:fmt"
import "core:time"
import "core:log"
import "core:strings"
import "core:math/linalg"
import "core:math"
import "core:mem"

import "core:prof/spall"

import stbi  "vendor:stb/image"
import stbtt "vendor:stb/truetype"

PROFILE_ENABLE :: #config(PROFILE_ENABLE, false)

spall_ctx: spall.Context
spall_buffer_backing: []u8
spall_buffer: spall.Buffer

App_State :: struct {
    odin_ctx: runtime.Context,
    input:    Input_State,
    frame:    Draw_Frame,

    pass_action: sg.Pass_Action,
    pip:         sg.Pipeline,
    bind:        sg.Bindings,

    time_initialized: time.Time,
    last_frame_time:  time.Time,

    delta_time:       f32,

    debug: bool,
}

app_state: App_State
fps := 0
frame_count := 0
frame_timer: time.Time

main :: proc() {
    when PROFILE_ENABLE {
    spall_ctx = spall.context_create("trace.spall", 1)
	   defer spall.context_destroy(&spall_ctx)
	   spall_buffer_backing = make([]u8, spall.BUFFER_DEFAULT_SIZE)
	   spall_buffer = spall.buffer_create(spall_buffer_backing, 0)
	   defer spall.buffer_destroy(&spall_ctx, &spall_buffer)
    }

    app_state.time_initialized = time.now()
    frame_timer = app_state.time_initialized

    mode: int = 0
    when ODIN_OS == .Linux || ODIN_OS == .Darwin {
        mode = os.S_IRUSR | os.S_IWUSR | os.S_IRGRP | os.S_IROTH
    }
    logh, logh_err := os.open("game.log", (os.O_CREATE | os.O_TRUNC | os.O_RDWR), mode)

    when !ODIN_DEBUG {
        if logh_err == os.ERROR_NONE {
            os.stdout = logh
            os.stderr = logh
        }
    }

    LOG_OPTIONS :: log.Options{
    	.Level,
    	//.Terminal_Color,
    	//.Short_File_Path,
    	//.Line,
    	.Procedure,
    }

    logger := logh_err == os.ERROR_NONE ? log.create_multi_logger(log.create_file_logger(logh, opt=LOG_OPTIONS), log.create_console_logger(opt=LOG_OPTIONS)) : log.create_console_logger(opt=LOG_OPTIONS)
    context.logger = logger
    app_state.odin_ctx = context

    if _main() == false {
        log_error("Failed to init game")
    }
}

open_window :: proc(title: string, window_width, window_height: int) {
    sapp.run({
        init_cb      = init,
        frame_cb     = frame,
        cleanup_cb   = cleanup,
        event_cb     = event_handler,
        width        = c.int(window_width),
        height       = c.int(window_height),
        window_title = strings.clone_to_cstring(title, context.temp_allocator),
        icon         = { sokol_default = false },
        logger       = { func = slog.func },
    })
}

init :: proc "c" () {
    context = app_state.odin_ctx
    sg.setup({
		environment = sglue.environment(),
		logger = { func = slog.func },
		d3d11_shader_debugging = ODIN_DEBUG,
	})

	if !sg.isvalid() {
	   os.exit(-1)
	}

	sgl.setup({
        logger = { func = slog.func },
    })

    sdtx.setup({
        fonts = {
           sdtx.font_kc854(),
           sdtx.font_kc853(),
           sdtx.font_z1013(),
           sdtx.font_cpc(),
           sdtx.font_c64(),
           sdtx.font_oric(),
           {},
           {},
        },
        logger = { func = slog.func },
    })

    load_image("res/images/atlas.png")
    init_fonts()

    app_state.bind.vertex_buffers[0] = sg.make_buffer({
		usage = .DYNAMIC,
		size = size_of(Quad) * MAX_QUADS,
	})

	index_buffer_count :: MAX_QUADS*6
	indices : [index_buffer_count]u16;
	i := 0;
	for i < index_buffer_count {
		// vertex offset pattern to draw a quad
		// { 0, 1, 2,  0, 2, 3 }
		indices[i + 0] = u16((i/6)*4 + 0)
		indices[i + 1] = u16((i/6)*4 + 1)
		indices[i + 2] = u16((i/6)*4 + 2)
		indices[i + 3] = u16((i/6)*4 + 0)
		indices[i + 4] = u16((i/6)*4 + 2)
		indices[i + 5] = u16((i/6)*4 + 3)
		i += 6;
	}

	app_state.bind.index_buffer = sg.make_buffer({
		type = .INDEXBUFFER,
		data = { ptr = &indices, size = size_of(indices) },
	})

	app_state.bind.samplers[SMP_default_sampler] = sg.make_sampler({})

    // setup pipeline
	pipeline_desc : sg.Pipeline_Desc = {
		shader = sg.make_shader(quad_shader_desc(sg.query_backend())),
		index_type = .UINT16,
		layout = {
			attrs = {
				ATTR_quad_position        = { format = .FLOAT2 },
				ATTR_quad_color0          = { format = .FLOAT4 },
                ATTR_quad_uv0             = { format = .FLOAT2 },
                ATTR_quad_bytes0          = { format = .UBYTE4N },
                ATTR_quad_color_override0 = { format = .FLOAT4 }
			},
		}
	}

	blend_state : sg.Blend_State = {
		enabled          = true,
		src_factor_rgb   = .SRC_ALPHA,
		dst_factor_rgb   = .ONE_MINUS_SRC_ALPHA,
		op_rgb           = .ADD,
		src_factor_alpha = .ONE,
		dst_factor_alpha = .ONE_MINUS_SRC_ALPHA,
		op_alpha         = .ADD,
	}
	pipeline_desc.colors[0] = { blend = blend_state }
	app_state.pip = sg.make_pipeline(pipeline_desc)

	game_init()
}

frame :: proc "c" () {
    context = app_state.odin_ctx

    PROFILE(#procedure)

    if key_pressed(.F12) {
        app_state.debug = !app_state.debug
    }

    app_state.delta_time = f32(time.duration_seconds(time.since(app_state.last_frame_time)))

    // Clamp the DT because weird shit was happening if needed on first frame and the above gave a wacky value
    app_state.delta_time = math.clamp(app_state.delta_time, 0.0, 1.0)

    app_state.last_frame_time = get_time()

    if fps == 0 {
        fps = int(1 / app_state.delta_time)
    }

    frame_count += 1

    frame_timer_diff := time.duration_seconds(time.since(frame_timer))
    if frame_timer_diff >= 1 {
        fps = int(f64(frame_count) / frame_timer_diff)
        frame_count = 0
        frame_timer = time.now()
    }

    begin_debug_text_frame()

    gameplay_update_scope: {
        PROFILE("Game Update")

        game_update(get_dt())
    }

    gameplay_render_scope: {
        PROFILE("Game Render")
        game_render()
    }

    draw_debug(get_dt())

     sokol_render_scope: {
        PROFILE("Sokol Render")
        clear := app_state.frame.clear_color
        app_state.pass_action.colors[0] = { load_action = .CLEAR, clear_value = {clear.r, clear.g, clear.b, clear.a} }

        sg.begin_pass({ action = app_state.pass_action, swapchain = sglue.swapchain() })

        app_state.bind.images[IMG_tex0] = atlas_image.sg_img
        app_state.bind.images[IMG_tex1] = font.sg_img

        sg.update_buffer(
            app_state.bind.vertex_buffers[0],
            { ptr = &app_state.frame.quads[0], size = size_of(Quad) * MAX_QUADS },
        )

        sg.apply_pipeline(app_state.pip)
        sg.apply_bindings(app_state.bind)
        sg.draw(0, 6 * app_state.frame.quad_count, 1)

        sdtx.draw()

        sg.end_pass()
        sg.commit()

        app_state.frame = {}
    }

    reset_input_state()
    free_all(context.temp_allocator)
}

event_handler :: proc "c" (e: ^sapp.Event) {
    context = app_state.odin_ctx
    PROFILE(#procedure)

    #partial switch e.type {
        case .KEY_DOWN:
        current_state := app_state.input.key_states[remap_sokol_key(e.key_code)]
        new_pressed_state :Key_State= current_state.pressed == .None ? .Pressed : .Blocked
        app_state.input.key_states[remap_sokol_key(e.key_code)] = {current = .Pressed, pressed = new_pressed_state}
        case .KEY_UP:
             app_state.input.key_states[remap_sokol_key(e.key_code)] = {current = .Released, pressed = .None}
        case .MOUSE_SCROLL:
            app_state.input.mouse_scroll_y = e.scroll_y
        case .MOUSE_MOVE:
             app_state.input.mouse_move_delta = Vector2{e.mouse_dx, e.mouse_dy}
            app_state.input.mouse_position = {e.mouse_x, e.mouse_y}
        case .MOUSE_UP:
             app_state.input.mouse_states[e.mouse_button] = {current = .Released, pressed = .None}
        case .MOUSE_DOWN:
            current_state := app_state.input.mouse_states[e.mouse_button]
            new_pressed_state :Key_State= current_state.pressed == .None ? .Pressed : .Blocked
            app_state.input.mouse_states[e.mouse_button] = {current = .Pressed, pressed = new_pressed_state}
    }

}

cleanup :: proc "c" () {
    context = app_state.odin_ctx
    game_shutdown()
    sdtx.shutdown()
    sg.shutdown()
}

// APP
quit :: proc() {
    sapp.request_quit()
}

toggle_fullscreen :: proc() {
    sapp.toggle_fullscreen()
}

get_dt :: proc() -> f32 {
    return f32(app_state.delta_time)
}

get_time_alive :: proc() -> f32 {
    return f32(time.duration_seconds(time.since(app_state.time_initialized)))
}

get_time :: proc() -> time.Time {
    return time.now()
}

screen_width :: proc() -> f32 {
    return sapp.widthf()
}

screen_height :: proc() -> f32 {
    return sapp.heightf()
}

screen_width_i :: proc() -> int {
    return int(sapp.width())
}

screen_height_i :: proc() -> int {
    return int(sapp.height())
}

mouse_pos_screen :: proc() -> Vector2 {
    return app_state.input.mouse_position
}

to_world_space :: proc(screen_pos: Vector2) -> Vector2 {
    if app_state.frame.projection == 0 {
        log_error("no projection matrix set yet")
        return screen_pos
    }

    ndc_x, ndc_y: f32
    switch app_state.frame.draw_origin {
    case .Center:
        ndc_x = (screen_pos.x / (screen_width()  * 0.5)) - 1.0
        ndc_y = (screen_pos.y / (screen_height() * 0.5)) - 1.0
        ndc_y *= -1
    case .Bottom_Left:
        ndc_x = screen_pos.x / screen_width()
        ndc_y = 1.0 - (screen_pos.y / screen_height())
    // Add other alignments as needed
    }

    pos_ndc := v2{ndc_x, ndc_y}
    pos_world := v4{pos_ndc.x, pos_ndc.y, 0, 1}

    pos_world *= linalg.inverse(app_state.frame.projection)
    pos_world = app_state.frame.camera_xform * pos_world

    return pos_world.xy
}

to_screen_space :: proc(world_pos: Vector2) -> Vector2 {
    if app_state.frame.projection == 0 {
        log_error("no projection matrix set yet")
        return world_pos
    }

    pos_world := v4{world_pos.x, world_pos.y, 0, 1}
    pos_screen := linalg.inverse(app_state.frame.camera_xform) * pos_world
    pos_screen *= app_state.frame.projection

    screen_x, screen_y: f32
    switch app_state.frame.draw_origin {
    case .Center:
        screen_x = (pos_screen.x + 1.0) * (screen_width() * 0.5)
        screen_y = (-pos_screen.y + 1.0) * (screen_height() * 0.5)
    case .Bottom_Left:
        screen_x = pos_screen.x * screen_width()
        screen_y = (1.0 - pos_screen.y) * screen_height()
    // Add other alignments as needed
    }

    return v2{screen_x, screen_y}
}

mouse_pos_screen_space :: proc() -> Vector2 {
	if app_state.frame.projection == 0 {
		log_error("no projection matrix set yet")
	}

	mouse := v2{app_state.input.mouse_position.x, app_state.input.mouse_position.y}

	x := mouse.x / screen_width()
	y := mouse.y / screen_height() - 1.0
	y *= -1

	return v2{x * app_state.frame.camera.res.x, y * app_state.frame.camera.res.y}
}

mouse_pos_world_space :: proc() -> Vector2 {
    if app_state.frame.projection == 0 {
        log_error("no projection matrix set yet")
    }

    if app_state.frame.camera.res.x == screen_width() && app_state.frame.camera.res.y == screen_height() {
        return mouse_pos_screen_space()
    }

    mouse := v2{app_state.input.mouse_position.x, app_state.input.mouse_position.y}

    ndc_x, ndc_y: f32
    switch app_state.frame.draw_origin {
    case .Center:
        ndc_x = (mouse.x / (screen_width()  * 0.5)) - 1.0
        ndc_y = (mouse.y / (screen_height() * 0.5)) - 1.0
        ndc_y *= -1
    case .Bottom_Left:
        ndc_x = mouse.x / screen_width()
        ndc_y = 1.0 - (mouse.y / screen_height())
    // Add other alignments as needed
    }

    mouse_ndc := v2{ndc_x, ndc_y}

    mouse_world := v4{mouse_ndc.x, mouse_ndc.y, 0, 1}

    mouse_world *= linalg.inverse(app_state.frame.projection)
    mouse_world = app_state.frame.camera_xform * mouse_world

    return mouse_world.xy
}

// DRAWING
Camera :: struct {
    pos:  Vector2,
    zoom: f32,
    res:  Vector2
}

UV    :: distinct [4]f32;
Color :: distinct [4]f32

DEFAULT_UV :: UV{0, 0, 1, 1}

Vertex :: struct {
    pos:            Vector2,
    col:            Color,
    uv:             [2]f32,
    tex_index:      u8,
    padding:        [3]u8,      // 3 bytes of padding
    color_override: Color,
}

Quad      :: distinct [4]Vertex
MAX_QUADS :: 8192

Draw_Frame :: struct {
    quads:        [MAX_QUADS]Quad,
    quad_count:   int,
    projection:   Matrix4,
    camera_xform: Matrix4,
    clear_color:  Color,
    camera:       Camera,
    draw_origin:  Origin,
}

Pivot :: enum {
    center,
    center_right,
    center_left,
    top_center,
    top_left,
    top_right,

    bottom_center,
    bottom_left,
    bottom_right,
}

Origin :: enum {
    Center,
    Bottom_Left,
}

push_camera :: proc(res: v2, zoom: f32, pos := v2{}, origin: Origin = .Center) -> (old: Camera) {
    old = app_state.frame.camera

    screen_aspect := screen_width() / screen_height()
    camera_aspect := res.x / res.y

    width, height: f32
    if screen_aspect > camera_aspect {
        height = res.y
        width = height * screen_aspect
    } else {
        width = res.x
        height = width / screen_aspect
    }

    switch origin {
    case .Center:
        app_state.frame.projection = mat_ortho(-width * 0.5, width * 0.5, -height * 0.5, height * 0.5, -1, 1)
    case .Bottom_Left:
        app_state.frame.projection = mat_ortho(0, width, 0, height, -1, 1)
    }

    app_state.frame.camera_xform = Matrix4(1)

    if pos != 0 {
        app_state.frame.camera_xform *= xform_translate(pos)
    }

    app_state.frame.camera_xform *= xform_scale(zoom)

    app_state.frame.camera = {pos, zoom, res}
    app_state.frame.draw_origin = origin
    return old
}

set_camera_pos :: proc(pos: v2) {
    app_state.frame.camera.pos = pos

    app_state.frame.camera_xform = Matrix4(1)
    app_state.frame.camera_xform *= xform_translate(pos)
    app_state.frame.camera_xform *= xform_scale(app_state.frame.camera.zoom)
}

scale_from_pivot :: proc(pivot: Pivot) -> Vector2 {
	switch pivot {
		case .bottom_left:   return {0.0, 0.0}
		case .bottom_center: return {0.5, 0.0}
		case .bottom_right:  return {1.0, 0.0}
		case .center_left:   return {0.0, 0.5}
		case .center:        return {0.5, 0.5}
		case .center_right:  return {1.0, 0.5}
		case .top_center:    return {0.5, 1.0}
		case .top_left:      return {0.0, 1.0}
		case .top_right:     return {1.0, 1.0}
		case: return 0
	}
}

Transform :: struct {
    pos: Vector2,
    rot: f32,
    scl: Vector2
}

xform_translate :: proc(pos: Vector2) -> Matrix4 {
    return linalg.matrix4_translate_f32({pos.x, pos.y, 0})
}

xform_rotate :: proc(angle: f32) -> Matrix4 {
    return linalg.matrix4_rotate_f32(math.to_radians(angle), {0, 0, 1})
}

xform_scale :: proc(scale: Vector2) -> Matrix4 {
    return linalg.matrix4_scale_f32(Vector3{scale.x, scale.y, 1})
}

draw_sprite :: proc(pos: Vector2, img_id: Image_Name, pivot:= Pivot.bottom_center, color:=COLOR_WHITE, color_override:=COLOR_ZERO) {
	image := IMAGE_INFO[img_id]
	size := v2{auto_cast image.width, auto_cast image.height}

	xform0 := Matrix4(1)
	xform0 *= xform_translate(pos)
	xform0 *= xform_translate(size * -scale_from_pivot(pivot))

	draw_rect_matrix(xform0, size, color=color, color_override=color_override, img_id=img_id, uv=image.uv)
}

draw_rect :: proc(rect: Rect, pivot: Pivot, color: Color, color_override:=COLOR_ZERO, uv:=DEFAULT_UV,  img_id: Image_Name= .nil) {
    xform := linalg.matrix4_translate(Vector3{rect.x, rect.y, 0})
	xform *= xform_translate({rect.width, rect.height} * -scale_from_pivot(pivot))
	draw_rect_matrix(xform, {rect.width, rect.height}, color, color_override, uv, img_id)
}

draw_sprite_in_rect :: proc(rect: Rect, img_id: Image_Name, pivot := Pivot.center, color := COLOR_WHITE, color_override := COLOR_ZERO) {
    image := IMAGE_INFO[img_id]
    img_size := Vector2{auto_cast image.width, auto_cast image.height}
    rect_size := Vector2{rect.width, rect.height}

    scale := min(rect_size.x / img_size.x, rect_size.y / img_size.y)
    scaled_size := img_size * scale

    pos := Vector2{rect.x, rect.y} + (rect_size - scaled_size) * 0.5

    xform := Matrix4(1)
    xform *= xform_translate({pos.x, pos.y})
    xform *= xform_scale(scale)
    xform *= xform_translate(img_size * -scale_from_pivot(pivot))

    draw_rect_matrix(xform, img_size, color=color, color_override=color_override, img_id=img_id, uv=image.uv)
}


draw_rect_matrix :: proc(xform: Matrix4, size: Vector2, color: Color, color_override:=COLOR_ZERO, uv:=DEFAULT_UV, img_id: Image_Name= .nil) {
    draw_rect_projected(app_state.frame.projection * linalg.inverse(app_state.frame.camera_xform) * xform, size, color, color_override, uv, img_id)
}

draw_rect_projected :: proc(
    world_to_clip: Matrix4,
    size: Vector2,
    col := COLOR_WHITE,
    color_override:=COLOR_ZERO,
    uv := DEFAULT_UV,
    img_id: Image_Name= .nil
) {
    bl := v2{ 0, 0 }
	tl := v2{ 0, size.y }
	tr := v2{ size.x, size.y }
	br := v2{ size.x, 0 }

    uv0 := uv
    if uv == DEFAULT_UV {
        uv0 = atlas_image.atlas_uvs
    }

    tex_index := atlas_image.tex_index

	if img_id == .nil {
		tex_index = 255 // bypasses texture sampling
	}

	if img_id == .font {
		tex_index = 1 // draws the font
	}

	draw_quad_projected(world_to_clip, {bl, tl, tr, br}, col, {uv0.xy, uv0.xw, uv0.zw, uv0.zy}, tex_index, color_override)
}

draw_quad_projected :: proc(
	world_to_clip:   Matrix4,
	positions:       [4]Vector2,
	colors:          [4]Color,
	uvs:             [4]Vector2,
    tex_indicies:    [4]u8,
    col_overrides:   [4]Color,
) {
	if app_state.frame.quad_count >= MAX_QUADS {
		log_error("max quads reached")
		return
	}

	verts := &app_state.frame.quads[app_state.frame.quad_count];
	app_state.frame.quad_count += 1;

	verts[0].pos = (world_to_clip * Vector4{positions[0].x, positions[0].y, 0.0, 1.0}).xy
	verts[1].pos = (world_to_clip * Vector4{positions[1].x, positions[1].y, 0.0, 1.0}).xy
	verts[2].pos = (world_to_clip * Vector4{positions[2].x, positions[2].y, 0.0, 1.0}).xy
	verts[3].pos = (world_to_clip * Vector4{positions[3].x, positions[3].y, 0.0, 1.0}).xy

	verts[0].col = colors[0]
	verts[1].col = colors[1]
	verts[2].col = colors[2]
	verts[3].col = colors[3]

    verts[0].uv = uvs[0]
    verts[1].uv = uvs[1]
    verts[2].uv = uvs[2]
    verts[3].uv = uvs[3]

    verts[0].tex_index = tex_indicies[0]
    verts[1].tex_index = tex_indicies[1]
    verts[2].tex_index = tex_indicies[2]
    verts[3].tex_index = tex_indicies[3]

    verts[0].color_override = col_overrides[0]
	verts[1].color_override = col_overrides[1]
	verts[2].color_override = col_overrides[2]
	verts[3].color_override = col_overrides[3]
}

draw_text :: proc(pos: Vector2, text: string, color:=COLOR_WHITE, scale:= 1.0, pivot:=Pivot.bottom_left) -> Vector2 {
	// loop thru and find the text size box thingo
	total_size : v2
	for char, i in text {

		advance_x: f32
		advance_y: f32
		q: stbtt.aligned_quad
		stbtt.GetBakedQuad(&font.char_data[0], font_bitmap_w, font_bitmap_h, cast(i32)char - 32, &advance_x, &advance_y, &q, false)
		// this is the the data for the aligned_quad we're given, with y+ going down
		// x0, y0,     s0, t0, // top-left
		// x1, y1,     s1, t1, // bottom-right

		size := v2{ abs(q.x0 - q.x1), abs(q.y0 - q.y1) }

		bottom_left := v2{ q.x0, -q.y1 }
		top_right := v2{ q.x1, -q.y0 }
		assert(bottom_left + size == top_right)

		if i == len(text)-1 {
			total_size.x += size.x
		} else {
			total_size.x += advance_x
		}

		total_size.y = max(total_size.y, top_right.y)
	}

	pivot_offset := total_size * -scale_from_pivot(pivot)

	debug_text := false
	if debug_text {
		draw_rect(make_rect(pos, total_size), pivot, color=COLOR_BLACK)
	}

	// draw glyphs one by one
	x: f32
	y: f32
	for char in text {

		advance_x: f32
		advance_y: f32
		q: stbtt.aligned_quad
		stbtt.GetBakedQuad(&font.char_data[0], font_bitmap_w, font_bitmap_h, cast(i32)char - 32, &advance_x, &advance_y, &q, false)
		// this is the the data for the aligned_quad we're given, with y+ going down
		// x0, y0,     s0, t0, // top-left
		// x1, y1,     s1, t1, // bottom-right

		size := v2{ abs(q.x0 - q.x1), abs(q.y0 - q.y1) }

		bottom_left := v2{ q.x0, -q.y1 }
		top_right := v2{ q.x1, -q.y0 }
		assert(bottom_left + size == top_right)

		offset_to_render_at := v2{x,y} + bottom_left

		offset_to_render_at += pivot_offset

		uv := UV{ q.s0, q.t1,
							q.s1, q.t0 }

		xform := Matrix4(1)
		xform *= xform_translate(pos)
		xform *= xform_scale(v2{auto_cast scale, auto_cast scale})
		xform *= xform_translate(offset_to_render_at)

		if debug_text {
			draw_rect_matrix(xform, size, color=Color{1,1,1,0.8})
		}

        draw_rect_matrix(xform, size, color=color, img_id=.font, uv=uv)
		x += advance_x
		y += -advance_y
	}

	return total_size
}

// INPUT
Input_State :: struct {
    mouse_scroll_y:   f32,
    mouse_move_delta: v2,
    mouse_position:   v2,
    key_states:       [Key_Code]Key_State_Pair,
    mouse_states:     #sparse [Mousebutton]Key_State_Pair,
}

Key_State :: enum {
    None,
    Pressed,
    Released,
    Blocked,
}

Key_State_Pair :: struct {
    current: Key_State,
    pressed: Key_State,
}

Mousebutton :: sapp.Mousebutton

reset_input_state :: proc() {
    app_state.input.mouse_scroll_y = 0

    for key in Key_Code {
        if app_state.input.key_states[key].current == .Released {
            app_state.input.key_states[key].current = .None
        }
        if app_state.input.key_states[key].pressed == .Pressed {
            app_state.input.key_states[key].pressed = .Blocked
        }
    }

     for btn in Mousebutton {
        if app_state.input.mouse_states[btn].current == .Released {
            app_state.input.mouse_states[btn].current = .None
        }
        if app_state.input.mouse_states[btn].pressed == .Pressed {
            app_state.input.mouse_states[btn].pressed = .Blocked
        }
    }
}

key_pressed_mod :: proc(mod, key: Key_Code) -> bool {
    return #force_inline key_down(mod) && #force_inline key_pressed(key)
}

key_pressed :: proc(key: Key_Code) -> bool {
    return app_state.input.key_states[key].pressed == .Pressed
}

key_released :: proc(key: Key_Code) -> bool {
    return app_state.input.key_states[key].current == .Released
}

key_down :: proc(key: Key_Code) -> bool {
    return app_state.input.key_states[key].current == .Pressed
}

mouse_pressed :: proc(btn: Mousebutton) -> bool {
    return app_state.input.mouse_states[btn].pressed == .Pressed
}

mouse_released :: proc(btn: Mousebutton) -> bool {
    return app_state.input.mouse_states[btn].current == .Released
}

mouse_down :: proc(btn: Mousebutton) -> bool {
    return app_state.input.mouse_states[btn].current == .Pressed
}

mouse_position_screen :: proc() -> Vector2 {
    return app_state.input.mouse_position
}

Key_Code :: enum {
    // Numeric keys
    Alpha_0,
    Alpha_1,
    Alpha_2,
    Alpha_3,
    Alpha_4,
    Alpha_5,
    Alpha_6,
    Alpha_7,
    Alpha_8,
    Alpha_9,

    // Function keys
    F1,
    F2,
    F3,
    F4,
    F5,
    F6,
    F7,
    F8,
    F9,
    F10,
    F11,
    F12,

    // Alphabetic keys
    A,
    B,
    C,
    D,
    E,
    F,
    G,
    H,
    I,
    J,
    K,
    L,
    M,
    N,
    O,
    P,
    Q,
    R,
    S,
    T,
    U,
    V,
    W,
    X,
    Y,
    Z,

    // Arrow keys
    Up,
    Down,
    Left,
    Right,

    // Navigation keys
    Insert,
    Delete,
    Home,
    End,
    Page_Up,
    Page_Down,

    // Symbol keys
    Back_Quote,
    Comma,
    Period,
    Forward_Slash,
    Back_Slash,
    Semicolon,
    Apostrophe,
    Left_Bracket,
    Right_Bracket,
    Minus,
    Equals,

    // Modifier keys
    Control_Left,
    Control_Right,
    Alt_Left,
    Alt_Right,
    Super_Left,
    Super_Right,

    // Special keys
    Tab,
    Capslock,
    Shift_Left,
    Shift_Right,
    Enter,
    Space,
    Backspace,
    Escape,

    // Numpad keys
    Num_0,
    Num_1,
    Num_2,
    Num_3,
    Num_4,
    Num_5,
    Num_6,
    Num_7,
    Num_8,
    Num_9,
    Num_Equal,
    Num_Decimal,
    Num_Enter,
    Num_Add,
    Num_Subtract,
    Num_Multiply,
    Num_Divide,

    INVALID,
}

remap_sokol_key :: proc(key: sapp.Keycode) -> Key_Code {
    #partial switch key {
        // Numeric keys
        case ._0: return .Alpha_0
        case ._1: return .Alpha_1
        case ._2: return .Alpha_2
        case ._3: return .Alpha_3
        case ._4: return .Alpha_4
        case ._5: return .Alpha_5
        case ._6: return .Alpha_6
        case ._7: return .Alpha_7
        case ._8: return .Alpha_8
        case ._9: return .Alpha_9

        // Function keys
        case .F1:  return .F1
        case .F2:  return .F2
        case .F3:  return .F3
        case .F4:  return .F4
        case .F5:  return .F5
        case .F6:  return .F6
        case .F7:  return .F7
        case .F8:  return .F8
        case .F9:  return .F9
        case .F10: return .F10
        case .F11: return .F11
        case .F12: return .F12

        // Alphabetic keys
        case .A: return .A
        case .B: return .B
        case .C: return .C
        case .D: return .D
        case .E: return .E
        case .F: return .F
        case .G: return .G
        case .H: return .H
        case .I: return .I
        case .J: return .J
        case .K: return .K
        case .L: return .L
        case .M: return .M
        case .N: return .N
        case .O: return .O
        case .P: return .P
        case .Q: return .Q
        case .R: return .R
        case .S: return .S
        case .T: return .T
        case .U: return .U
        case .V: return .V
        case .W: return .W
        case .X: return .X
        case .Y: return .Y
        case .Z: return .Z

        // Arrow keys
        case .UP:    return .Up
        case .DOWN:  return .Down
        case .LEFT:  return .Left
        case .RIGHT: return .Right

        // Navigation keys
        case .INSERT:    return .Insert
        case .DELETE:    return .Delete
        case .HOME:      return .Home
        case .END:       return .End
        case .PAGE_UP:   return .Page_Up
        case .PAGE_DOWN: return .Page_Down

        // Symbol keys
        case .GRAVE_ACCENT:  return .Back_Quote
        case .COMMA:         return .Comma
        case .PERIOD:        return .Period
        case .SLASH:         return .Forward_Slash
        case .BACKSLASH:     return .Back_Slash
        case .SEMICOLON:     return .Semicolon
        case .APOSTROPHE:    return .Apostrophe
        case .LEFT_BRACKET:  return .Left_Bracket
        case .RIGHT_BRACKET: return .Right_Bracket
        case .MINUS:         return .Minus
        case .EQUAL:         return .Equals

        // Modifier keys
        case .LEFT_CONTROL:  return .Control_Left
        case .RIGHT_CONTROL: return .Control_Right
        case .LEFT_ALT:      return .Alt_Left
        case .RIGHT_ALT:     return .Alt_Right
        case .LEFT_SUPER:    return .Super_Left
        case .RIGHT_SUPER:   return .Super_Right

        // Special keys
        case .TAB:         return .Tab
        case .CAPS_LOCK:   return .Capslock
        case .LEFT_SHIFT:  return .Shift_Left
        case .RIGHT_SHIFT: return .Shift_Right
        case .ENTER:       return .Enter
        case .SPACE:       return .Space
        case .BACKSPACE:   return .Backspace
        case .ESCAPE:      return .Escape

        // Numpad keys
        case .KP_0:        return .Num_0
        case .KP_1:        return .Num_1
        case .KP_2:        return .Num_2
        case .KP_3:        return .Num_3
        case .KP_4:        return .Num_4
        case .KP_5:        return .Num_5
        case .KP_6:        return .Num_6
        case .KP_7:        return .Num_7
        case .KP_8:        return .Num_8
        case .KP_9:        return .Num_9
        case .KP_EQUAL:    return .Num_Equal
        case .KP_DECIMAL:  return .Num_Decimal
        case .KP_ENTER:    return .Num_Enter
        case .KP_ADD:      return .Num_Add
        case .KP_SUBTRACT: return .Num_Subtract
        case .KP_MULTIPLY: return .Num_Multiply
        case .KP_DIVIDE:   return .Num_Divide

        case .INVALID: fallthrough
        case: return .INVALID  // Default case, you might want to handle this differently
    }
}


@(deferred_in=_profile_buffer_end)
@(disabled=!PROFILE_ENABLE)
PROFILE :: proc(name: string, args: string = "", location := #caller_location) {
    spall._buffer_begin(&spall_ctx, &spall_buffer, name, args, location)
}

@(private)
@(disabled=!PROFILE_ENABLE)
_profile_buffer_end :: proc(_, _: string, _ := #caller_location) {
	spall._buffer_end(&spall_ctx, &spall_buffer)
}


begin_debug_text_frame :: proc() {
    sdtx.canvas(sapp.widthf() * 0.6, sapp.heightf() * 0.6)
    sdtx.origin(2.0, 2.0)
    sdtx.home()
}

draw_debug_text :: proc(text: string, color: [3]u8 = 255) {
    sdtx.font(3)
    sdtx.color3b(color.r, color.g, color.b)
    sdtx.puts(cstr_clone(text))
    sdtx.crlf()
    sdtx.crlf()
}

// ASSET LOADING
Image :: struct {
    width:     i32,
    height:    i32,
	tex_index: u8,
	sg_img:    sg.Image,
	data:      [^]byte,
	atlas_uvs: UV,
}

atlas_image: Image

get_image_size :: proc(img_id: Image_Name) -> Vector2 {
    return {f32(IMAGE_INFO[img_id].width), f32(IMAGE_INFO[img_id].height)}
}

load_image :: proc(path: string) -> bool {
    png_data, succ := os.read_entire_file(path)
    if !succ {
        fmt.eprintln("Failed to read image file:", path)
        return false
    }

    width, height, channels: i32
    img_data := stbi.load_from_memory(raw_data(png_data), auto_cast len(png_data), &width, &height, &channels, 4)
    if img_data == nil {
        fmt.eprintln("stbi load failed, invalid image?")
        return false
    }

    atlas_image = Image{
        width = width,
        height = height,
        data = img_data,
        atlas_uvs = {0, 0, 1, 1}, // Full texture coordinates
        tex_index = 0, // Assuming single texture
    }

    // Create GPU texture
    desc : sg.Image_Desc
	desc.width = auto_cast atlas_image.width
	desc.height = auto_cast atlas_image.height
	desc.pixel_format = .RGBA8
	desc.data.subimage[0][0] = {ptr=img_data, size=auto_cast (atlas_image.width*atlas_image.height*4)}
    atlas_image.sg_img = sg.make_image(desc)

    return true
}


// FONT

font_bitmap_w :: 512
font_bitmap_h :: 512
char_count    :: 96
Font :: struct {
	char_data: [char_count]stbtt.bakedchar,
	img_id: Image_Name,
	sg_img: sg.Image
}
font: Font

init_fonts :: proc() {
	bitmap, _ := mem.alloc(font_bitmap_w * font_bitmap_h)
	font_height := 12 // for some reason this only bakes properly at 15 ? it's a 16px font dou...
	path := "res/fonts/dogicapixel.ttf"
	ttf_data, err := os.read_entire_file(path)
	assert(ttf_data != nil && err, "failed to read font")

	ret := stbtt.BakeFontBitmap(raw_data(ttf_data), 0, auto_cast font_height, auto_cast bitmap, font_bitmap_w, font_bitmap_h, 32, char_count, &font.char_data[0])
	assert(ret > 0, "not enough space in bitmap")

	stbi.write_png("font.png", auto_cast font_bitmap_w, auto_cast font_bitmap_h, 1, bitmap, auto_cast font_bitmap_w)

	// setup font atlas so we can use it in the shader
	desc : sg.Image_Desc
	desc.width = auto_cast font_bitmap_w
	desc.height = auto_cast font_bitmap_h
	desc.pixel_format = .R8
	desc.data.subimage[0][0] = {ptr=bitmap, size=auto_cast (font_bitmap_w*font_bitmap_h)}
	sg_img := sg.make_image(desc)
	if sg_img.id == sg.INVALID_ID {
		log_error("failed to make image")
	}
    font.sg_img = sg_img
	font.img_id = .font
}

draw_debug :: proc(delta_time: f32) {
    if !app_state.debug {
        return
    }

    frame_time := delta_time * 1000
    mouse_screen_pos := mouse_pos_screen()
    mouse_world_pos := mouse_pos_world_space()
    mouse_screen_space_pos := mouse_pos_screen_space()

    frame_time_text := tstrf("Frame Time: {:.2f} | FPS: {}", frame_time, fps)
    screen_res_text := tstrf("Screen Res: {}x{}", screen_width_i(), screen_height_i())
    render_res_text := tstrf("Render Res: {}x{}", int(app_state.frame.camera.res.x), int(app_state.frame.camera.res.y))
    screen_mouse_pos_text := tstrf("Mouse Screen Pos: (x:%v, y:%v)", int(mouse_screen_pos.x),int( mouse_screen_pos.y))
    screen_space_mouse_pos_text := tstrf("Mouse Screen Space Pos: (x:%v, y:%v)", int(mouse_screen_space_pos.x),int( mouse_screen_space_pos.y))
    screen_world_pos_text := tstrf("Mouse World Pos: (x:%v, y:%v)", int(mouse_world_pos.x),int( mouse_world_pos.y))
    quads_text := tstrf("Qauds Drawn: {}/{}", app_state.frame.quad_count, MAX_QUADS)

    draw_debug_text(frame_time_text)
    draw_debug_text(screen_res_text)
    draw_debug_text(render_res_text)
    draw_debug_text(screen_mouse_pos_text)
    draw_debug_text(screen_space_mouse_pos_text)
    draw_debug_text(screen_world_pos_text)
    draw_debug_text(quads_text)

}