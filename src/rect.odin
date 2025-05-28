package main


Rect :: struct {
	x: f32,
	y: f32,
	width: f32,
	height: f32,
}

// We do Y up
cut_rect_bottom :: proc(r: ^Rect, y: f32, m: f32) -> Rect {
	res := r^
	res.y += m
	res.height = y
	r.y += y + m
	r.height -= y + m
	return res
}

cut_rect_top :: proc(r: ^Rect, h: f32, m: f32) -> Rect {
	res := r^
	res.height = h
	res.y = r.y + r.height - h - m
	r.height -= h + m
	return res
}

cut_rect_left :: proc(r: ^Rect, x, m: f32) -> Rect {
	res := r^
	res.x += m
	res.width = x
	r.x += x + m
	r.width -= x + m
	return res
}

cut_rect_right :: proc(r: ^Rect, w, m: f32) -> Rect {
	res := r^
	res.width = w
	res.x = r.x + r.width - w - m
	r.width -= w + m
	return res
}

split_rect_top :: proc(r: Rect, y: f32, m: f32) -> (top, bottom: Rect) {
	top = r
	bottom = r
	top.y += m
	top.height = y
	bottom.y += y + m
	bottom.height -= y + m
	return
}

split_rect_left :: proc(r: Rect, x: f32, m: f32) -> (left, right: Rect) {
	left = r
	right = r
	left.width = x
	right.x += x + m
	right.width -= x +m
	return
}

split_rect_bottom :: proc(r: Rect, y: f32, m: f32) -> (top, bottom: Rect) {
	top = r
	top.height -= y + m
	bottom = r
	bottom.y = top.y + top.height + m
	bottom.height = y
	return
}

split_rect_right :: proc(r: Rect, x: f32, m: f32) -> (left, right: Rect) {
	left = r
	right = r
	right.width = x
	left.width -= x + m
	right.x = left.x + left.width
	return
}

inset_rect :: proc(r: ^Rect, inset_x: f32, inset_y: f32) -> Rect {
    res := r^
    res.x += inset_x
    res.y += inset_y
    res.width -= 2 * inset_x
    res.height -= 2 * inset_y
    return res
}

make_rect :: proc(pos, size: Vector2) -> Rect {
    return {pos.x, pos.y, size.x, size.y}
}

AABB :: Vector4
aabb_collide_aabb :: proc(a: AABB, b: AABB) -> (bool, Vector2) {
    // Calculate centers
    a_center_x := (a.z + a.x) / 2
    a_center_y := (a.w + a.y) / 2
    b_center_x := (b.z + b.x) / 2
    b_center_y := (b.w + b.y) / 2

    // Calculate sizes
    a_width := a.z - a.x
    a_height := a.w - a.y
    b_width := b.z - b.x
    b_height := b.w - b.y

    // Debug drawing
    if app_state.debug {
        // Draw AABB A
        draw_rect(
            make_rect({a_center_x, a_center_y}, {a_width, a_height}),
            .center,
            {1, 0, 0, 0.5}  // Red with 50% opacity
        )

        // Draw AABB B
        draw_rect(
            make_rect({b_center_x, b_center_y}, {b_width, b_height}),
            .center,
            {0, 1, 0, 0.5}  // Green with 50% opacity
        )
    }

    // Calculate overlap on each axis
    dx := (a.z + a.x) / 2 - (b.z + b.x) / 2
    dy := (a.w + a.y) / 2 - (b.w + b.y) / 2

    overlap_x := (a.z - a.x) / 2 + (b.z - b.x) / 2 - abs(dx)
    overlap_y := (a.w - a.y) / 2 + (b.w - b.y) / 2 - abs(dy)

    // If there is no overlap on any axis, there is no collision
    if overlap_x <= 0 || overlap_y <= 0 {
        return false, Vector2{}
    }

    // Find the penetration vector
    penetration := Vector2{}
    if overlap_x < overlap_y {
        penetration.x = overlap_x if dx > 0 else -overlap_x
    } else {
        penetration.y = overlap_y if dy > 0 else -overlap_y
    }

    // Debug drawing for collision area
    if app_state.debug {
        overlap_center_x := max(a.x, b.x) + overlap_x / 2
        overlap_center_y := max(a.y, b.y) + overlap_y / 2

        draw_rect(
            make_rect({overlap_center_x, overlap_center_y}, {overlap_x, overlap_y}),
            .center,
            {1, 1, 0, 0.7}  // Yellow with 70% opacity
        )
    }

    return true, penetration
}


aabb_get_center :: proc(a: Vector4) -> Vector2 {
	min := a.xy;
	max := a.zw;
	return { min.x + 0.5 * (max.x-min.x), min.y + 0.5 * (max.y-min.y) };
}

aabb_make_with_pos :: proc(pos: Vector2, size: Vector2, pivot:= Pivot.bottom_left) -> Vector4 {
	aabb := (Vector4){0,0,size.x,size.y};
	aabb = aabb_shift(aabb, pos - scale_from_pivot(pivot) * size);
	return aabb;
}
aabb_make_with_size :: proc(size: Vector2, pivot: Pivot) -> Vector4 {
	return aabb_make({}, size, pivot);
}

aabb_make :: proc{
	aabb_make_with_pos,
	aabb_make_with_size
}

aabb_shift :: proc(aabb: Vector4, amount: Vector2) -> Vector4 {
	return {aabb.x + amount.x, aabb.y + amount.y, aabb.z + amount.x, aabb.w + amount.y};
}

aabb_contains :: proc(aabb: Vector4, p: Vector2) -> bool {
	return (p.x >= aabb.x) && (p.x <= aabb.z) &&
           (p.y >= aabb.y) && (p.y <= aabb.w);
}

aabb_size :: proc(aabb: AABB) -> Vector2 {
	return { abs(aabb.x - aabb.z), abs(aabb.y - aabb.w) }
}