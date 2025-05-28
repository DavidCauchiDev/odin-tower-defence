package main

import "core:fmt"
import "core:log"
import "core:strings"
import "core:math"

ctstr :: fmt.ctprintf

tstr  :: fmt.tprint
tstrf :: fmt.tprintf

cstr_clone :: proc(text: string, allocator := context.allocator) -> cstring {
    return strings.clone_to_cstring(text, allocator)
}

// Logging
log_info  :: log.infof
log_warn  :: log.warnf
log_error :: log.errorf
printf    :: fmt.printfln

// Colors

rgb :: proc(r, g, b: u8, a: u8= 255) -> Color {
    return Color{
        f32(r) / 255.0,
        f32(g) / 255.0,
        f32(b) / 255.0,
        f32(a) / 255.0,
    }
}

hex :: proc(hex: u32, alpha: u8 = 255) -> Color {
    r, g, b, a: u8
    if hex <= 0xFFFFFF { // RGB only
        r = u8((hex >> 16) & 0xFF)
        g = u8((hex >> 8) & 0xFF)
        b = u8(hex & 0xFF)
        return rgb(r, g, b, alpha)
    } else { // RGBA
        r = u8((hex >> 24) & 0xFF)
        g = u8((hex >> 16) & 0xFF)
        b = u8((hex >> 8) & 0xFF)
        a = u8(hex & 0xFF)
        return rgb(r, g, b, a)
    }
}

COLOR_RED     :: Color { 1,   0,   0,   1 }
COLOR_WHITE   :: Color { 1,   1,   1,   1 }
COLOR_GREEN   :: Color { 0,   1,   0,   1 }
COLOR_BLUE    :: Color { 0,   0,   1,   1 }
COLOR_YELLOW  :: Color { 1,   1,   0,   1 }
COLOR_CYAN    :: Color { 0,   1,   1,   1 }
COLOR_MAGENTA :: Color { 1,   0,   1,   1 }
COLOR_ORANGE  :: Color { 1,   0.5, 0,   1 }
COLOR_PURPLE  :: Color { 0.5, 0,   0.5, 1 }
COLOR_BROWN   :: Color { 0.6, 0.4, 0.2, 1 }
COLOR_GRAY    :: Color { 0.5, 0.5, 0.5, 1 }
COLOR_BLACK   :: Color { 0,   0,   0,   1 }
COLOR_ZERO    :: Color { 0,   0,   0,   0 }


sine_breathe_alpha :: proc(p: $T) -> T where intrinsics.type_is_float(T) {
	return (math.sin((p - .25) * 2.0 * math.PI) / 2.0) + 0.5
}

animate_to_target_f32 :: proc(value: ^f32, target: f32, delta_t: f32, rate:f32= 15.0, good_enough:f32= 0.001) -> bool
{
	value^ += (target - value^) * (1.0 - math.pow_f32(2.0, -rate * delta_t));
	if almost_equals(value^, target, good_enough)
	{
		value^ = target;
		return true; // reached
	}
	return false;
}

animate_to_target_v2 :: proc(value: ^Vector2, target: Vector2, delta_t: f32, rate :f32= 15.0, good_enough:f32= 0.001) -> bool
{
	v_x := animate_to_target_f32(&value.x, target.x, delta_t, rate, good_enough)
	v_y := animate_to_target_f32(&value.y, target.y, delta_t, rate, good_enough)
	return v_x && v_y
}

almost_equals :: proc(a: f32, b: f32, epsilon: f32 = 0.001) -> bool
{
	return abs(a - b) <= epsilon;
}

float_alpha :: proc(x: f32, min: f32, max: f32, clamp_result: bool = true) -> f32
{
	res := (x - min) / (max - min);
	if clamp_result { res = clamp(res, 0, 1); }
	return res;
}