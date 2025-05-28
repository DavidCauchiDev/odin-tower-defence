package main

import "core:fmt"
import "core:math/linalg"
import "core:math"
import "core:math/rand"

MAX_DAY_LEN :: 24
initialized := false

Game_State :: struct {
    entities:      [1024]Entity,
    entity_count:  int,
    player_handle: Entity_Handle,
    base_handle:   Entity_Handle,

    camera_pos: Vector2,

    resources: Resource_Data,

    ux_mode:         UX_Mode,
    menu_mode:       Menu_Mode,
    menu_mode_queue: [16]Menu_Mode,
    menu_mode_index: int,
    splash_start_time: f32,

    simulation_speed: f32,
    game_time: f32,

    stamina:     int,
    max_stamina: int,

    unlocked_towers:  bit_set[Tower_Type],
    placing_tower: bool,
    selected_tower_type: Tower_Type,

    // Used for one shot frame data. Cleared at the start of the frame
    frame: struct {
        hovered_entity:   Entity_Handle,
        hovered_tile:     int,
        hovered_tile_pos: v2,
        input:            Game_Input,
    },

    time_of_day:  f32,
    current_day:  int,

    wave: struct {
        stage:            Game_Stage,
        grace_timer:      f32,
        enemies_left:     int,
        enemies_to_spawn: int,
        data:             [AI_Type]Wave_Enemy_Data,
        spawn_timer:      f32,
    },

}

Game_Input :: struct {
    movement: v2,
}

Resource_Data :: struct {
    rock:     int,
    wood:     int,
    food:     int,
    currency: int,
}

Game_Stage :: enum {
    Day,
    EOD_Cooldown,
    Wave,
    EOW_Cooldown,
    Game_Over,
}

UX_Mode :: enum {
    Splash_Logo,
    Splash_FMod,
    Main_Menu,
    Game,
}

Menu_Mode :: enum {
    None,
    Splash_Logo,
    Main,
    Settings,
    Paused,
    Game_Over,
}

Tower_Type :: enum {
    Basic,
    Sniper,
    Frost,
    Tesla,
    Laser,
    Flamethrower,
    Poison,
    Morter,
    Missile,
    Teleporter,
    Mind_Control,
    Gravity,
    Swarm,
}

AI_Type :: enum {
    Goomba,
    Bomber,
    Mage,
    Boss,
}

Wave_Enemy_Data :: struct {
    ai_type: AI_Type,
    count:   int,
}

game_state: Game_State

TOWER_DEFAULTS := [Tower_Type]Entity {
    .Basic = {
        flags               = {.Damageable},
        sprite              = .tower_basic,
        max_health          = 25,
        damage              = 7,
        attack_range        = 300,
        attack_rate         = 1.5,
        target_flags        = {.AI},
        speed               = 160,
        price               = {rock=3, wood=3, food=0, currency=0},
    },
    .Sniper = {
        flags               = {.Damageable},
        sprite              = .tower_sniper,
        max_health          = 20,
        damage              = 30,
        attack_range        = 600,
        attack_rate         = 3.0,
        speed               = 200,
        target_flags        = {.AI},
        price               = {rock=5, wood=2, food=0, currency=15},
    },
    .Frost = {
        flags               = {.Damageable},
        sprite              = .tower_frost,
        max_health          = 30,
        damage              = 3,
        attack_range        = 100,
        attack_rate         = 1.0,
        target_flags = {.AI},
        price               = {rock=4, wood=3, food=2, currency=10},
    },
    .Tesla = {
        flags               = {.Damageable},
        sprite              = .tower_tesla,
        max_health          = 22,
        damage              = 15,
        attack_range        = 150,
        attack_rate         = 0.8,
        target_flags = {.AI},
        price               = {rock=6, wood=1, food=0, currency=20},
    },
    .Laser = {
        flags               = {.Damageable},
        sprite              = .tower_laser,
        max_health          = 18,
        damage              = 20,
        attack_range        = 200,
        attack_rate         = 0.5,
        target_flags = {.AI},
        price               = {rock=4, wood=4, food=0, currency=25},
    },
    .Flamethrower = {
        flags               = {.Damageable},
        sprite              = .tower_flamethrower,
        max_health          = 28,
        damage              = 10,
        attack_range        = 80,
        attack_rate         = 0.3,
        target_flags = {.AI},
        price               = {rock=3, wood=5, food=1, currency=15},
    },
    .Poison = {
        flags               = {.Damageable},
        sprite              = .tower_poison,
        max_health          = 24,
        damage              = 5,
        attack_range        = 120,
        attack_rate         = 1.2,
        target_flags = {.AI},
        price               = {rock=2, wood=4, food=3, currency=12},
    },
    .Morter = {
        flags               = {.Damageable},
        sprite              = .tower_morter,
        max_health          = 35,
        damage              = 25,
        attack_range        = 300,
        attack_rate         = 4.0,
        target_flags = {.AI},
        price               = {rock=7, wood=3, food=0, currency=30},
    },
    .Missile = {
        flags               = {.Damageable},
        sprite              = .tower_missile,
        max_health          = 22,
        damage              = 18,
        attack_range        = 250,
        attack_rate         = 2.5,
        target_flags = {.AI},
        price               = {rock=5, wood=4, food=0, currency=22},
    },
    .Teleporter = {
        flags               = {.Damageable},
        sprite              = .tower_teleporter,
        max_health          = 20,
        damage              = 0,
        attack_range        = 100,
        attack_rate         = 5.0,
        target_flags = {.AI},
        price               = {rock=3, wood=3, food=5, currency=35},
    },
    .Mind_Control = {
        flags               = {.Damageable},
        sprite              = .tower_mind_control,
        max_health          = 15,
        damage              = 0,
        attack_range        = 150,
        attack_rate         = 8.0,
        target_flags = {.AI},
        price               = {rock=2, wood=2, food=8, currency=40},
    },
    .Gravity = {
        flags               = {.Damageable},
        sprite              = .tower_gravity,
        max_health          = 30,
        damage              = 2,
        attack_range        = 180,
        attack_rate         = 1.0,
        target_flags = {.AI},
        price               = {rock=6, wood=2, food=3, currency=28},
    },
    .Swarm = {
        flags               = {.Damageable},
        sprite              = .tower_swarm,
        max_health          = 18,
        damage              = 1,
        attack_range        = 200,
        attack_rate         = 0.2,
        target_flags = {.AI},
        price               = {rock=3, wood=5, food=4, currency=18},
    },
}


AI_DEFAULTS := [AI_Type]Entity {
    .Goomba = {
        flags               = {},
        sprite              = .goomba_walk_0,
        max_health          = 10,
        damage              = 4,
        attack_range        = 32,
        attack_rate         = 3,
        speed               = 40,
        target_flags        = {.Human, .Base, .Tower},
        drops               = {rock=1, wood=1, food=1, currency=1},
        walk_anim           = {frames={.goomba_walk_0, .goomba_walk_1}, rate=8}
    },
    .Bomber = {
        flags               = {},
        sprite              = .goomba,
        max_health          = 10,
        damage              = 1,
        attack_range        = 24,
        attack_rate         = 4,
        speed               = 30,
        target_flags = {.Human, .Base, .Tower},
        drops               = {rock=3, wood=1, food=0, currency=1},
    },
    .Mage = {
        flags               = {},
        sprite              = .goomba,
        max_health          = 10,
        damage              = 1,
        attack_range        = 24,
        attack_rate         = 1,
        speed               = 30,
        target_flags = {.Human, .Base, .Tower},
        drops               = {rock=3, wood=1, food=0, currency=1},
    },
    .Boss = {
        flags               = {},
        sprite              = .goomba,
        max_health          = 10,
        damage              = 1,
        attack_range        = 24,
        attack_rate         = 1,
        speed               = 30,
        target_flags = {.Human, .Base, .Tower},
        drops               = {rock=3, wood=1, food=0, currency=1},
    },
}


_main :: proc() -> bool {
    open_window("experiment", 1280, 720)
    return true
}

game_init :: proc() {
    audio_init()

    when ODIN_DEBUG {
        new_game()
    } else {
        goto_splash_screen()
    }

    initialized = true
}

new_game :: proc() {
    game_state = {}
    game_state.simulation_speed = 1
    game_state.camera_pos = 0
    game_state.ux_mode          = .Game
    game_state.simulation_speed = 1

    game_state.current_day = 1
    game_state.time_of_day = 0
    game_state.wave.stage  = .Day
    game_state.stamina = 20
    game_state.max_stamina = 20

    //Spawn Main Base
    base_handle, base : = entity_create({.Base, .Drawn, .Damageable, .Collision}, 0)
    game_state.base_handle = base_handle

    base.sprite     = .base
    base.pivot      = .center
    base.health     = 100
    base.max_health = 100

    // handle, player : = entity_create({.Human, .Player_Controlled, .Drawn }, 0)
    // game_state.player_handle = handle

    // player.sprite   = .player
    // player.pivot    = .bottom_center
    // player.speed    = 90
    // player.position = {0, -64}

    clear_menu_modes()
}

goto_splash_screen :: proc() {
    game_state.ux_mode          = .Splash_Logo
    push_menu_mode(.Splash_Logo)
    game_state.simulation_speed = 1
    game_state.splash_start_time = get_time_alive()
}

goto_menu :: proc() {
    game_state.ux_mode          = .Main_Menu
    game_state.simulation_speed = 1
    game_state.camera_pos = 0
    push_menu_mode(.Main)
}

update_input :: proc() {
    PROFILE(#procedure)
    if key_pressed(.F1) {
        goto_menu()
    }

    if key_pressed(.F2) {
        new_game()
    }

    if key_pressed(.F3) {
        game_state.time_of_day = MAX_DAY_LEN
        game_state.wave.stage = .EOD_Cooldown
        game_state.wave.grace_timer = 5
    }

    if mouse_pressed(.RIGHT) || key_pressed(.Escape) {
        game_state.placing_tower = false
    }

    if key_pressed(.F4) {
        game_state.resources.rock     = 10000
        game_state.resources.food     = 10000
        game_state.resources.wood     = 10000
        game_state.resources.currency = 10000

        game_state.unlocked_towers = ~{}
    }

    if key_pressed(.F11) || key_pressed_mod(.Alt_Left, .Enter) {
        toggle_fullscreen()
    }

    if game_state.ux_mode == .Main_Menu {
        if key_pressed(.Escape) {
            if game_state.menu_mode != .Main {
                pop_menu_mode()
            }
        }
    }

    input_dir: Vector2 = {0, 0}
    if key_down(.W) {
        input_dir.y += 1
    }
    if key_down(.S) {
        input_dir.y -= 1
    }
    if key_down(.A) {
        input_dir.x -= 1
    }
    if key_down(.D) {
        input_dir.x += 1
    }

    game_state.frame.input.movement = input_dir

    if game_state.ux_mode == .Game && key_pressed(.Escape) {
        if game_state.menu_mode == .None {
            push_menu_mode(.Paused)
        } else if game_state.menu_mode != .Game_Over {
            pop_menu_mode()
        }
    }
}

game_update :: proc(dt: f32) {
    if !initialized {
        return
    }

    // INIT FRAME
    next_button = 0
    game_state.frame = {}
    game_state.game_time += get_sim_speed()

    // INPUT
    update_input()

    // ENTITIES

    // CAMERA
    update_camera(dt)

    // AUDIO
    audio_update(game_state.camera_pos)

    if game_state.ux_mode == .Game {
        push_camera({640, 380}, 0.7, game_state.camera_pos, .Center)

        for &entity in game_state.entities {
            if .Is_Valid not_in entity.flags {
                continue
            }

            calculate_entity_bounds(&entity)

            for flag in entity.flags {
                #partial switch flag {
                    case .AI:         update_AI(&entity, dt)
                    case .Tower:      update_tower(&entity, dt)
                    case .Projectile: update_projectile(&entity, dt)
                }
            }
        }

        if game_state.placing_tower && mouse_pressed(.LEFT) && is_valid_placement(game_state.selected_tower_type) {
            game_state.placing_tower = false

            t := TOWER_DEFAULTS[game_state.selected_tower_type]

            game_state.resources.rock     -= t.price.rock
            game_state.resources.food     -= t.price.food
            game_state.resources.wood     -= t.price.wood
            game_state.resources.currency -= t.price.currency
            spawn_tower_entity(game_state.selected_tower_type, mouse_pos_world_space())
        }

        if game_state.wave.stage == .Day {
            game_state.time_of_day += get_sim_speed()
            if game_state.time_of_day >= MAX_DAY_LEN {
                game_state.wave.stage = .EOD_Cooldown
                game_state.wave.grace_timer = 0
                fmt.println("Day finished, starting grace timer")
            }
        }

        if game_state.wave.stage == .EOD_Cooldown {
            game_state.wave.grace_timer += get_sim_speed()
            if game_state.wave.grace_timer >= 5 {
                fmt.println("Grace Time Finished, starting wave")
                game_state.wave.stage = .Wave
                setup_wave()
            }
        }

        if game_state.wave.stage == .Wave {
            update_wave(dt)
        }

         if game_state.wave.stage == .EOW_Cooldown {
            game_state.wave.grace_timer += get_sim_speed()
            if game_state.wave.grace_timer >= 5 {
                fmt.println("Grace Time Finished, ending wave")
                game_state.wave.stage = .Day
                game_state.time_of_day = 0
                game_state.current_day += 1
            }
        }
    }
}

update_camera :: proc(dt: f32) {
    move_dir :=  game_state.frame.input.movement

    if !almost_equals(linalg.length(move_dir), 0) {
        move_dir = linalg.normalize(move_dir)
    }

    game_state.camera_pos += (move_dir) *  get_sim_speed() * 120
    set_camera_pos(game_state.camera_pos)
}

ai_weights := [AI_Type]int{.Goomba = 70, .Bomber = 40, .Mage = 50, .Boss = 5}

setup_wave :: proc() {
    PROFILE(#procedure)
    max_enemy_types := len(AI_Type)
    enemy_types_unlocked := math.min(game_state.current_day / 3 + 1, max_enemy_types)
    game_state.wave.enemies_left = 10 + int(math.pow(f64(game_state.current_day), 1.6))
    game_state.wave.enemies_to_spawn = game_state.wave.enemies_left

    total_weight := 0

    for i in 0..<enemy_types_unlocked {
        total_weight += ai_weights[AI_Type(i)]
    }

    remaining_enemies := game_state.wave.enemies_left

    for i in 0..<enemy_types_unlocked {
        ai_type := AI_Type(i)
        weight := ai_weights[ai_type]
        count := (weight * game_state.wave.enemies_left) / total_weight

        if ai_type == .Boss {
            count = min(count, 1)
        } else if ai_type == .Bomber || ai_type == .Mage {
            count = max(1, count / 3)
        }

        if i == enemy_types_unlocked - 1 {
            count = remaining_enemies
        }

        game_state.wave.data[ai_type] = {ai_type, count}
        remaining_enemies -= count
    }

    game_state.wave.spawn_timer = 0
}

update_wave :: proc(dt: f32) {
    PROFILE(#procedure)
    game_state.wave.spawn_timer += get_sim_speed()
    spawn_interval := 1.0 - (f32(game_state.current_day) * 0.05)
    spawn_interval = math.max(spawn_interval, 0.2)

    if game_state.wave.spawn_timer >= spawn_interval {
        spawn_enemy()
        game_state.wave.spawn_timer = 0
    }

    if game_state.wave.enemies_left < 1 {
        fmt.println("Wave Finished, coolong down before next day")
        game_state.wave.grace_timer = 0
        game_state.wave.stage = .EOW_Cooldown
    }
}

spawn_enemy :: proc() {
    PROFILE(#procedure)
    if game_state.wave.enemies_to_spawn <= 0 {
        return
    }

    // Choose a random AI type from the available types in the wave
    available_types := make([dynamic]AI_Type, context.temp_allocator)

    for ai_type in AI_Type {
        if game_state.wave.data[ai_type].count > 0 {
            append(&available_types, ai_type)
        }
    }

    if len(available_types) == 0 {
        return
    }

    chosen_type := available_types[rand.int_max(len(available_types))]

    game_state.wave.data[chosen_type].count -= 1

    game_state.wave.enemies_to_spawn -= 1

    // Generate a random spawn location
    radius :: 512
    angle := rand.float32_range(0, 2 * math.PI)
    pos := Vector2{
        radius * math.cos(angle),
        radius * math.sin(angle),
    }

    // Spawn the enemy
    spawn_ai_entity(chosen_type, pos)
}

can_afford_tower :: proc(tower_type: Tower_Type) -> bool {
    tower := &TOWER_DEFAULTS[game_state.selected_tower_type]
    return compare_resource_data(game_state.resources, tower.price)
}

is_valid_placement :: proc(tower_type: Tower_Type) -> bool {
    // this_tower := TOWER_DEFAULTS[tower_type]
    // calculate_entity_bounds(&this_tower)

    // for &entity in game_state.entities {
    //     if .Is_Valid not_in entity.flags || .Collision not_in entity.flags {
    //         continue
    //     }

    //     collided, _ := aabb_collide_aabb(this_tower.bounds, entity.bounds)

    //     if collided {
    //         return false
    //     }
    // }
    return true
}

did_collide :: proc(e_handle: Entity_Handle, test_bounds: AABB, target_types:  bit_set[Entity_Flags]) -> (hit: bool, point: v2, entity_h: Entity_Handle) {
    PROFILE(#procedure)
    col_loop: for &entity in game_state.entities {
        if .Is_Valid not_in entity.flags || entity.id == e_handle {
            continue
        }

        for flag in target_types {
            if flag in entity.flags {
                hit, point = aabb_collide_aabb(test_bounds, entity.bounds)

                if hit {
                    fmt.println(target_types)

                    entity_h = entity.id
                    break col_loop
                }
            }
        }
    }

    return
}

// if greater/equal returns true
compare_resource_data :: proc(left, right: Resource_Data)-> bool {
    return (
        left.rock     >= right.rock     &&
        left.food     >= right.food     &&
        left.wood     >= right.wood     &&
        left.currency >= right.currency
    )
}

unlock_tower :: proc(type: Tower_Type) -> bool {
    tower_unlock_cost := get_tower_unlock_cost(type)
    if type in game_state.unlocked_towers || !compare_resource_data(game_state.resources, tower_unlock_cost) {
        return false
    }

    game_state.resources.rock -= tower_unlock_cost.rock
    game_state.resources.food -= tower_unlock_cost.food
    game_state.resources.wood -= tower_unlock_cost.wood
    game_state.resources.currency -= tower_unlock_cost.currency

    game_state.unlocked_towers += {type}
    return true
}

get_tower_unlock_cost :: proc(type: Tower_Type) -> (price: Resource_Data) {
    switch type {
        case .Basic:        price = { rock=3,  wood=3, food=0,  currency=0 }
        case .Sniper:       price = { rock=3,  wood=3, food=0,  currency=0 }
        case .Frost:        price = { rock=3,  wood=3, food=0,  currency=0 }
        case .Tesla:        price = { rock=3,  wood=3, food=0,  currency=0 }
        case .Laser:        price = { rock=3,  wood=3, food=0,  currency=0 }
        case .Flamethrower: price = { rock=3,  wood=3, food=0,  currency=0 }
        case .Poison:       price = { rock=3,  wood=3, food=0,  currency=0 }
        case .Morter:       price = { rock=3,  wood=3, food=0,  currency=0 }
        case .Missile:      price = { rock=3,  wood=3, food=0,  currency=0 }
        case .Teleporter:   price = { rock=3,  wood=3, food=0,  currency=0 }
        case .Mind_Control: price = { rock=3,  wood=3, food=0,  currency=0 }
        case .Gravity:      price = { rock=3,  wood=3, food=0,  currency=0 }
        case .Swarm:        price = { rock=3,  wood=3, food=0,  currency=0 }
    }

    return
}

game_shutdown :: proc() {
    audio_shutdown()
}

get_sim_speed :: proc() -> f32 {
    if  game_state.menu_mode != .None {
        return 0
    }

    return get_dt() * game_state.simulation_speed
}

draw_menu : : proc() {
    app_state.frame.clear_color = hex(HEX_SKY_BLUE)

    draw_text({0, 40}, "Noct 01", scale=1, pivot=Pivot.center)

    if button({0, -10, 150, 20}, "New Game") {
        new_game()
    }

    if button({0, -40, 150, 20}, "Settings") {
        push_menu_mode(.Settings)
    }

    if button({0, -70, 150, 20}, "Exit Game") {
        quit()
    }
}

draw_pause_menu :: proc() {
    draw_text({0, 40}, "Paused", scale=1, pivot=Pivot.center)

    if button({0, -10, 150, 20}, "Resume") {
        pop_menu_mode()
    }

    if button({0, -40, 150, 20}, "Settings") {
        push_menu_mode(.Settings)
    }

    if button({0, -70, 150, 20}, "Return To Menu") {
        clear_menu_modes()
        goto_menu()
    }

    if button({0, -100, 150, 20}, "Exit") {
        quit()
    }
}

draw_settings_menu :: proc() {
    draw_text({0, 40}, "Settings", scale=1, pivot=.center)

    if button({0, -10, 150, 20}, "Back") {
        pop_menu_mode()
    }
}

draw_game_over_menu:: proc() {
    draw_rect({0,0, screen_width(), screen_height()}, .center, {0,0,0, 0.3})
    draw_text({0, 40}, "Game Over", scale=1, pivot=.center)

    if button({0, -10, 150, 20}, "New Game") {
        new_game()
    }

    if button({0, -40, 150, 20}, "Return To Menu") {
        clear_menu_modes()
        goto_menu()
    }

    if button({0, -70, 150, 20}, "Exit") {
        quit()
    }
}

draw_hud :: proc() {
    PROFILE(#procedure)
    draw_health_bar :: proc(rect: Rect, min, max: int) {
        if max == 0 {
            return
        }
        green_width := f64(min) / f64(max) * 30.0
        draw_rect({rect.x, rect.y + 16,  30, 3},  .bottom_center, hex(HEX_LIGHT_MAROON))
        draw_rect({rect.x - 15, rect.y + 16, f32(green_width), 3}, .bottom_left, hex(HEX_LIGHT_GREEN))
    }

    for &e in game_state.entities {
        if .Is_Valid not_in e.flags {
            continue
        }

        damageable_ui: if .Damageable in e.flags {
            if (.Tower in e.flags || .AI in e.flags) && e.health == e.max_health {
                break damageable_ui
            }

            size := get_image_size(e.sprite)
            rect := make_rect(e.position + {0, size.y /2}, {30, 3})
            draw_health_bar(rect, e.health, e.max_health)
        }
    }

    push_camera({screen_width(), screen_height()}, 1, origin=.Bottom_Left)


    res_x := app_state.frame.camera.res.x
    res_y := app_state.frame.camera.res.y

    screen_rect   :=  make_rect(0, {res_x, res_y})
    screen_rect    = inset_rect(&screen_rect, 16, 16)
    left_hud      := cut_rect_left(&screen_rect, res_x / 3, 0)
    right_hud     := cut_rect_right(&screen_rect, res_x / 5, 0)
    res_area_rect := cut_rect_top(&left_hud,res_y * 0.05, 0)
    tower_area_rect    := cut_rect_bottom(&left_hud, left_hud.height - 16, 0)
    tower_area_rect     = cut_rect_left(&tower_area_rect, left_hud.width / 3, 0)
    controls_area_rect := cut_rect_top(&right_hud, res_y * 0.04, 0)

    time_slider := controls_area_rect
    time_slider.width = linalg.lerp(f32(0.0), controls_area_rect.width, game_state.time_of_day/MAX_DAY_LEN)

    if app_state.debug {
        draw_rect(left_hud, .bottom_left, hex(HEX_PINKISH_INDIGO))
        draw_rect(right_hud, .bottom_left, hex(HEX_PINKISH_INDIGO))
    }

    //RES
    //draw_rect(res_area_rect, .bottom_left, hex(HEX_TAN))

    ICON_Y_OFFSET  :: 2
    res_icon_size  := res_area_rect.height - 2

    draw_res :: proc(rect: ^Rect, image: Image_Name, value: int, size: f32) {
        food_rect, right := split_rect_left(rect^, size, size)
        draw_sprite_in_rect({food_rect.x, food_rect.y + size / 2, food_rect.width, food_rect.width}, image, .center_left)
        last_text_size := draw_text({food_rect.x + size + 4, food_rect.y + 5}, tstr(value), scale=1)
        cut_rect_left(&right, last_text_size.x, 2)
        rect^ = right
    }

    draw_res(&res_area_rect, .icon_food, game_state.resources.food, res_icon_size)
    draw_res(&res_area_rect, .icon_wood, game_state.resources.wood, res_icon_size)
    draw_res(&res_area_rect, .icon_rock, game_state.resources.rock, res_icon_size)
    draw_res(&res_area_rect, .icon_currency, game_state.resources.currency, res_icon_size)

    // CONTROLS
    draw_rect(controls_area_rect, .bottom_left, hex(HEX_TAN))
    draw_rect(time_slider, .bottom_left, hex(HEX_LIGHT_TAN))
    draw_text({controls_area_rect.x + 4, controls_area_rect.y + controls_area_rect.height / 2}, tstrf("Day: {}", game_state.current_day),  pivot=.center_left, scale=1)

    if game_state.wave.stage == .EOD_Cooldown || game_state.wave.stage == .EOW_Cooldown {
        if game_state.wave.grace_timer < 5 {
            time_left := math.max(1, math.ceil(5 - game_state.wave.grace_timer))
            if time_left <= 5 {
                day_text: string

                if game_state.wave.stage == .EOD_Cooldown {
                     day_text = tstrf("NEXT WAVE STARTS IN: %.0f", time_left)
                } else {
                    day_text = tstrf("NEXT DAY STARTS IN: %.0f", time_left)
                }

                draw_text({controls_area_rect.x + 2, controls_area_rect.y - 20}, day_text)
            }
        }
    } else if game_state.wave.stage == .Wave {
         day_text := tstrf("Enemies Left {}", game_state.wave.enemies_left)
        draw_text({controls_area_rect.x + 2, controls_area_rect.y - 20}, day_text)
    }

    // TOWER AREA
    draw_rect(tower_area_rect, .bottom_left, hex(HEX_TAN))
    col_rect := tower_area_rect
    rows := 6
    cols := 2
    margin : f32 = 4

    cell_size : f32 = tower_area_rect.width / 2
    cell_width := cell_size
    cell_height := cell_size

    grid_x := col_rect.x + (col_rect.width - (f32(cols) * cell_width + f32(cols + 1) * margin)) / 2;
    // Adjust grid_y to start from the top
    grid_y :f32= col_rect.height - cell_size

    for row in 0..<rows {
        for col in 0..<cols {
            if row * cols + col < len(Tower_Type) {
                tower_type := Tower_Type(row * cols + col)
                tower := &TOWER_DEFAULTS[tower_type]
                cell_rect := make_rect(
                    {grid_x + margin + f32(col) * (cell_width + margin), grid_y - f32(row) * (cell_height + margin)},
                    {cell_width, cell_height}
                )

                col := Color{.2, .2, .2, 1}

                if tower_type in game_state.unlocked_towers {
                    col = 0

                    if can_afford_tower(tower_type) {
                        if button(cell_rect, "", .bottom_left, hex(HEX_LIGHT_TAN)) {
                            game_state.selected_tower_type = tower_type
                            game_state.placing_tower = true
                        }
                    } else {
                        draw_rect(cell_rect, .bottom_left, hex(HEX_BRIGHT_RED))
                    }
                }
                draw_sprite_in_rect(cell_rect, tower.sprite, color_override=col, pivot=.bottom_left)
            }
        }
    }
}

fade_in_duration      :f32: 1.0
full_opacity_duration :f32: 2.0
fade_out_duration     :f32: 1.0

Splash_Screen :: struct {
    image: Image_Name,
    fade_in_duration: f32,
    full_opacity_duration: f32,
    fade_out_duration: f32,
    position: Vector2,
    scale: Vector2,
}

splash_screens: [2]Splash_Screen = {
    {
        image = .nocturnum_games_logo,
        fade_in_duration = 1.0,
        full_opacity_duration = 2.0,
        fade_out_duration = 1.0,
        position = {0, 0},
        scale = {1/1.2, 1/1.2},
    },
    {
        image = .fmod_logo,
        fade_in_duration = 1.0,
        full_opacity_duration = 2.0,
        fade_out_duration = 1.0,
        position = {0, 0},
        scale = {1, 1},
    },
}

current_splash_index := 0

draw_splash :: proc() {
    PROFILE(#procedure)
    push_camera({screen_width(), screen_height()}, 1, origin=.Center)

    app_state.frame.clear_color = COLOR_BLACK

    if current_splash_index >= len(splash_screens) {
        game_state.ux_mode = .Main_Menu
        clear_menu_modes()
        push_menu_mode(.Main)
        return
    }

    splash := &splash_screens[current_splash_index]
    total_duration := splash.fade_in_duration + splash.full_opacity_duration + splash.fade_out_duration

    current_time := get_time_alive() - game_state.splash_start_time
    splash_alpha: f32

    if current_time < splash.fade_in_duration {
        splash_alpha = 1 - (current_time / splash.fade_in_duration)
    } else if current_time < splash.fade_in_duration + splash.full_opacity_duration {
        splash_alpha = 0
    } else if current_time < total_duration {
        splash_alpha = (current_time - splash.fade_in_duration - splash.full_opacity_duration) / splash.fade_out_duration
    } else {
        splash_alpha = 1
    }

    splash_alpha = clamp(splash_alpha, 0.0, 1.0)


    logo_size := get_image_size(splash.image)
    width := logo_size.x * splash.scale.x
    height := logo_size.y * splash.scale.y

    draw_sprite_in_rect({splash.position.x, splash.position.y, width, height},
        splash.image,
        .center,
        color_override = {0, 0, 0, splash_alpha})

    if current_time > total_duration + 1 {
        current_splash_index += 1
        if current_splash_index < len(splash_screens) {
            game_state.splash_start_time = get_time_alive()
        }
    }
}

game_render :: proc() {
    if !initialized {
        return
    }

    if game_state.ux_mode == .Splash_Logo {
        app_state.frame.clear_color = COLOR_BLACK
    } else {
        app_state.frame.clear_color = hex(HEX_SKY_BLUE)
    }

    if game_state.ux_mode == .Game {
        app_state.frame.clear_color = hex(HEX_FOREST_GREEN)
        for &entity in game_state.entities {
            if .Is_Valid not_in entity.flags {
                continue
            }
            if app_state.debug {
                bounds := entity.bounds
                width  := bounds.x - bounds.z
                height := bounds.y - bounds.w
                draw_rect(make_rect(entity.position, {width, height}), entity.pivot, {1, 0 , 0, 0.2})
            }

            if .Drawn in entity.flags {

                draw_sprite(entity.position, entity.sprite, entity.pivot)
            }
        }

        if game_state.placing_tower {
            tower := &TOWER_DEFAULTS[game_state.selected_tower_type]
            draw_sprite(mouse_pos_world_space(), tower.sprite, .center)
        }

        draw_hud()

    }

    push_camera({640, 380}, 1, origin=.Center)

    if game_state.menu_mode != .None && game_state.ux_mode == .Game {
        draw_rect({0,0, screen_width(), screen_height()}, .center, {0,0,0, 0.3})
    }

    #partial switch game_state.menu_mode {
        case .Splash_Logo: draw_splash()
        case .Main:        draw_menu()
        case .Paused:      draw_pause_menu()
        case .Settings:    draw_settings_menu()
        case .Game_Over:   draw_game_over_menu()
    }

    push_camera({screen_width(), screen_height()}, 1, origin=.Bottom_Left)
    commit  :: #load("../commit_hash.txt", string)
    version :: #load("../version.txt", string)
    draw_text(10, tstrf("Build: {} -  {}", commit, version), scale=0.8)

    when ODIN_DEBUG {
        draw_text({10, 30}, "DEBUG", scale=0.8)
    }
}

// ENTITY
Entity_Flags :: enum {
    Is_Valid,
    Player_Controlled,
    Drawn,
    AI,
    Human,
    Tower,
    Base,
    Damageable,
    Projectile,
    Collision,
}

Attack_State :: enum {
    None,
    Charging,
    Attacking,
    Recovering,
}

Entity :: struct {
    id:    Entity_Handle,
    flags: bit_set[Entity_Flags],

    position: Vector2,
    rotation: f32,
    sprite:   Image_Name,
    pivot:    Pivot,
    bounds:   AABB,

    speed: f32,

    health:     int,
    max_health: int,

    damage:              int,
    attack_range:        f32, // Use for radius or length
    attack_rate:         f32,
    last_attack_time:    f32,
    last_damage_time:    f32, // damage flashes?
    attack_state:        Attack_State,
    original_position:   Vector2,
    charge_position:     Vector2,
    price: Resource_Data,
    drops: Resource_Data,

    tower_type: Tower_Type,
    target_flags: bit_set[Entity_Flags],

    // Animations
    walk_anim:   Animation,
    attack_anim: Animation,
    idle_anim:   Animation,
    death_anim:  Animation,
}

Animation :: struct {
    frames:        []Image_Name,
    current_frame: int,
    rate:          f32,
    end_time:      f32,
}

anim_get_next_frame :: proc(anim: ^Animation) -> Image_Name {
    reached_end_time := game_state.game_time >= anim.end_time

     if reached_end_time {
        anim.current_frame += 1
        if anim.current_frame >= len(anim.frames) {
            anim.current_frame = 0
        }
        frame_duration := 1.0 / anim.rate
        anim.end_time = game_state.game_time + frame_duration
    }

    return anim.frames[anim.current_frame]
}

Entity_Handle :: distinct u64
ID_MASK  :: (1 << 32) - 1
GEN_MASK :: ((1 << 32) - 1) << 32

get_entity_id :: proc(handle: Entity_Handle) -> u32 {
    return u32(handle & ID_MASK)
}

get_entity_generation :: proc(handle: Entity_Handle) -> u32 {
    return u32((handle & GEN_MASK) >> 32)
}

calculate_entity_bounds :: proc(entity: ^Entity) {
    sprite_size := get_image_size(entity.sprite)
    entity.bounds = aabb_make_with_pos(entity.position, sprite_size, entity.pivot)
}

get_nearest_point_on_entity :: proc(entity: ^Entity, position: Vector2) -> Vector2 {
    //calculate_entity_bounds(entity)
    // Clamp the position to the bounds
    bounds := entity.bounds
    nearest_x := math.clamp(position.x, bounds.x, bounds.z)
    nearest_y := math.clamp(position.y, bounds.y, bounds.w)

    return {nearest_x, nearest_y}
}

entity_create :: proc(flags: bit_set[Entity_Flags], location: v2, pivot := Pivot.bottom_center, sprite := Image_Name.nil) -> (handle: Entity_Handle, entity: ^Entity) {
    for i := 0; i < len(game_state.entities); i += 1 {
        entity = &game_state.entities[i]
        if .Is_Valid not_in entity.flags {
            old_handle := entity.id
            old_gen := (old_handle & GEN_MASK) >> 32
            new_gen := (old_gen + 1) & ((1 << 32) - 1)

            entity^ = {}

            entity.flags |= { .Is_Valid }
            entity.flags |= flags
            entity.id = Entity_Handle((u64(new_gen) << 32) | u64(i))
            entity.position = location
            entity.sprite = sprite
            calculate_entity_bounds(entity)

            handle = entity.id

            game_state.entity_count += 1

            break
        }
    }

    if handle == 0 {
        log_error("Failed to create entity: Ran out of space")
    }
    return
}

entity_delete :: proc(handle: Entity_Handle) -> (success: bool) {
    if entity := entity_get_ptr(handle); entity != nil {
        entity.flags &~= {.Is_Valid}
        game_state.entity_count -= 1
        success = true
    }
    return
}

entity_get_ptr :: proc(handle: Entity_Handle) -> ^Entity {
    id := handle & ID_MASK
    gen := (handle & GEN_MASK) >> 32

    if id >= len(game_state.entities) {
        return nil
    }

    entity := &game_state.entities[id]
    if .Is_Valid not_in entity.flags || (entity.id & GEN_MASK) >> 32 != gen {
        return nil
    }
    return entity
}

entity_get :: proc(handle: Entity_Handle) -> (e: Entity, valid: bool) {
    if entity := entity_get_ptr(handle); entity != nil {
        e = entity^
        valid = true
    }
    return
}

entity_take_damage :: proc(e, attacker: Entity_Handle, damage: int) {
    entity := entity_get_ptr(e)

    died := false
    if entity != nil {
        entity.health -= damage

        if entity.health <= 0 {
            entity.health = 0
            died = true
        }
    }

    if died {
        if .Base in entity.flags {
            game_state.wave.stage = .Game_Over
            push_menu_mode(.Game_Over)
            game_state.simulation_speed = 0
        }

        game_state.resources.rock     += entity.drops.rock
        game_state.resources.food     += entity.drops.food
        game_state.resources.wood     += entity.drops.wood
        game_state.resources.currency += entity.drops.currency

        if .AI in entity.flags {
            game_state.wave.enemies_left -= 1
        }

        entity_delete(e)
    }
}

spawn_projectile :: proc(location, dir: v2, speed: f32, damage: int, sprite: Image_Name, targets: bit_set[Entity_Flags]) {
    log_info("Spawning Projectile: at location {}", location)
    _, e := entity_create({.Projectile, .Drawn }, location, .center, sprite)
    e.rotation = math.atan2(dir.y, dir.x)
    e.speed    = speed
    e.damage   = damage
    e.target_flags = targets
}

spawn_ai_entity :: proc(type: AI_Type,  location: v2) {
    log_info("Spawning AI: {} at location {}", type, location)
    base_entity := AI_DEFAULTS[type]

    _, e := entity_create({.AI, .Drawn, .Damageable, .Collision} + base_entity.flags, location, .bottom_center, base_entity.sprite)
    e.speed               = base_entity.speed
    e.max_health          = base_entity.max_health
    e.health              = base_entity.max_health
    e.damage              = base_entity.damage
    e.attack_range        = base_entity.attack_range
    e.attack_rate         = base_entity.attack_rate
    e.target_flags        = base_entity.target_flags
    e.drops               = base_entity.drops
    e.walk_anim           = base_entity.walk_anim
    e.attack_anim         = base_entity.attack_anim
    e.idle_anim           = base_entity.idle_anim
    e.death_anim          = base_entity.death_anim
}

spawn_tower_entity :: proc(type: Tower_Type,  location: v2) {
    log_info("Spawning Tower: {} at location {}", type, location)
    t := TOWER_DEFAULTS[type]

    _, e := entity_create({.Tower, .Drawn, .Collision } + t.flags, location, .center, t.sprite)
    e.speed               = t.speed
    e.max_health          = t.max_health
    e.health              = t.max_health
    e.damage              = t.damage
    e.attack_range        = t.attack_range
    e.attack_rate         = t.attack_rate
    e.target_flags        = t.target_flags

    e.tower_type          = type
}

// AI
find_nearest_target :: proc (target_flags: bit_set[Entity_Flags], location: v2, range: f32) -> (handle: Entity_Handle, ok: bool) {
    PROFILE(#procedure)
    closest_dist :f32= 999999999

    for &e in game_state.entities {
        if .Is_Valid in e.flags &&  e.flags > target_flags  && e.health > 0 {
            dist := linalg.distance(location, e.position)
            if dist < closest_dist {
                closest_dist = dist
                handle = e.id
                ok = true
            }
        }
    }

    return
}

update_projectile :: proc(e: ^Entity, dt:f32) {
    PROFILE(#procedure)
    dir :v2= {math.cos(e.rotation), math.sin(e.rotation)}

    if linalg.length(dir) != 0 {
        dir = linalg.normalize(dir)
    }

    e.position += dir * e.speed *  get_sim_speed()
    calculate_entity_bounds(e)

    if  hit, point, entity_h := did_collide(e.id, e.bounds, e.target_flags); hit {
        hit_entity, _  := entity_get(entity_h)
        log_info("Projectile hit an entity at location {}. Handle: {}. Entity had the flags: {}", point, entity_h, hit_entity.flags)
        entity_delete(e.id)
        entity_take_damage(entity_h, e.id, e.damage)
    }
}

update_tower :: proc(e: ^Entity, dt:f32) {
    PROFILE(#procedure)
    target, has_target := find_nearest_target(e.target_flags, e.position, e.attack_range)

    target_e: ^Entity
    in_dist: bool
    if has_target {
        target_e = entity_get_ptr(target)
        dir := target_e.position - e.position

        if linalg.length(dir) != 0 {
            dir = linalg.normalize(dir)
        }

        closest_pos_to_target := get_nearest_point_on_entity(target_e, e.position)
        distance_to_target := linalg.distance(e.position, closest_pos_to_target)

        if distance_to_target <= target_e.attack_range {
            in_dist = true
        }
    }

    can_attack: bool
    if in_dist {
        time_since_last_attack := game_state.game_time - target_e.last_attack_time
        if time_since_last_attack > target_e.attack_rate {
            can_attack = true
            target_e.last_attack_time = game_state.game_time
            log_info("attacking: {}", game_state.game_time - target_e.last_attack_time)
        }
    }

    if can_attack {
        switch e.tower_type {
            // generic projectile
            case .Basic, .Sniper: spawn_projectile(e.position, target_e.position - e.position, e.speed, e.damage, .projectile, {.AI})
            case .Frost:
            case .Tesla:
            case .Laser:
            case .Flamethrower:
            case .Poison:
            case .Morter:
            case .Missile:
            case .Teleporter:
            case .Mind_Control:
            case .Gravity:
            case .Swarm:
        }
    }
}

update_AI :: proc(e: ^Entity, dt: f32) {
    PROFILE(#procedure)
    target: Entity_Handle

    new_target, found := find_nearest_target(e.target_flags, e.position, e.attack_range)

    if found {
        target = new_target
    } else if .AI in e.flags {
        target = game_state.base_handle
    }

    if target_entity := entity_get_ptr(target); target_entity != nil {
        dir := target_entity.position - e.position

        if linalg.length(dir) != 0 {
            dir = linalg.normalize(dir)
        }

        closest_pos_to_target := get_nearest_point_on_entity(target_entity, e.position)
        distance_to_target := linalg.distance(e.position, closest_pos_to_target)
        switch e.attack_state {
            case .None:
            if distance_to_target <= e.attack_range {
                e.attack_state = .Charging
                e.original_position = e.position
            } else {
                e.position += (dir * e.speed * get_sim_speed())
                e.sprite = anim_get_next_frame(&e.walk_anim)
            }

            case .Charging:
                e.attack_state = .Attacking
                // animation for charging attack?

            case .Attacking:
            if game_state.game_time - e.last_attack_time > e.attack_rate {
                reached := animate_to_target_v2(&e.position, closest_pos_to_target, get_sim_speed(), 100)
                if reached {
                    e.last_attack_time = game_state.game_time
                    entity_take_damage(target, e.id, e.damage)
                    e.attack_state = .Recovering
                }
            }

            case .Recovering:
            reached := animate_to_target_v2(&e.position, e.original_position, get_sim_speed(), 50)
            if reached {
                e.attack_state = .None
            }
        }
    }
}


// Color Palette

HEX_DEEP_NAVY       :: 0x172038
HEX_DARK_BLUE       :: 0x253a5e
HEX_MIDNIGHT_BLUE   :: 0x3c5e8b
HEX_SKY_BLUE        :: 0x4f8fba
HEX_LIGHT_SKY_BLUE  :: 0x73bed3
HEX_PALE_CYAN       :: 0xa4dddb
HEX_FOREST_GREEN    :: 0x19332d
HEX_DARK_GREEN      :: 0x25562e
HEX_MID_GREEN       :: 0x468232
HEX_LIGHT_GREEN     :: 0x75a743
HEX_PALE_GREEN      :: 0xa8ca58
HEX_BEIGE_GREEN     :: 0xd0da91
HEX_BROWN           :: 0x4d2b32
HEX_DARK_TAN        :: 0x7a4841
HEX_TAN             :: 0xad7757
HEX_LIGHT_TAN       :: 0xc09473
HEX_BEIGE           :: 0xd7b594
HEX_LIGHT_BEIGE     :: 0xe7d5b30
HEX_DEEP_PURPLE     :: 0x341c27
HEX_DARK_PURPLE     :: 0x602c2c
HEX_MID_PURPLE      :: 0x884b2b
HEX_LIGHT_PURPLE    :: 0xbe772b
HEX_PINKISH_PURPLE  :: 0xde9e41
HEX_PALE_PURPLE     :: 0xe8c170
HEX_DEEP_MAROON     :: 0x241527
HEX_DARK_MAROON     :: 0x411d31
HEX_MAROON          :: 0x752438
HEX_LIGHT_MAROON    :: 0xa53030
HEX_BRIGHT_RED      :: 0xcf573c
HEX_ORANGE_RED      :: 0xda863e
HEX_DEEP_INDIGO     :: 0x1e1d39
HEX_INDIGO          :: 0x402751
HEX_MID_INDIGO      :: 0x7a367b
HEX_LIGHT_INDIGO    :: 0xa23e8c
HEX_PINKISH_INDIGO  :: 0xc65197
HEX_PALE_INDIGO     :: 0xdf84a5
HEX_VERY_DARK_GRAY  :: 0x090a14
HEX_DARK_GRAY       :: 0x10141f
HEX_MID_GRAY        :: 0x151d28
HEX_LIGHT_GRAY      :: 0x202e37
HEX_SKY_GRAY        :: 0x394a50
HEX_PALE_GRAY       :: 0x577277
HEX_BLUE_GRAY       :: 0x819796
HEX_LIGHT_BLUE_GRAY :: 0xa8b5b2
HEX_BEIGE_GRAY      :: 0xc7cfcc
HEX_PALE_BEIGE_GRAY :: 0xebede9

// UI elements

next_button := 0
active_button := -1
button :: proc(rect: Rect, text: string, pivot:=Pivot.center, col_normal := COLOR_ZERO, col_hover := COLOR_ZERO) -> (pressed: bool) {
    PROFILE(#procedure)
    id := next_button
    next_button += 1
    col: Color = col_normal

    if col == 0 {
        col = hex(HEX_PALE_GRAY)
    }
    aabb := aabb_make({rect.x, rect.y}, v2{rect.width, rect.height}, pivot=pivot)
    if aabb_contains(aabb, mouse_pos_world_space()) {
        if active_button != id {
            audio_play("SFX/ui/select")
        }

        active_button = id

        col = col_hover

        if col == 0 {
            col = hex(HEX_BLUE_GRAY)
        }

        if mouse_pressed(.LEFT) {
            pressed = true
            audio_play("SFX/ui/press")
        }
    } else if active_button == id {
        active_button = -1
    }

    draw_rect(rect, pivot, col)
    draw_text({rect.x, rect.y}, text, scale=0.5, pivot=pivot )
    return pressed
}

push_menu_mode :: proc(new_mode: Menu_Mode) {
    if game_state.menu_mode_index < len(game_state.menu_mode_queue) - 1 {
        game_state.menu_mode_index += 1
        game_state.menu_mode_queue[game_state.menu_mode_index] = new_mode
        game_state.menu_mode = new_mode

    } else {
        fmt.println("Warning: Menu mode queue is full. Cannot push new mode.")
    }
}

pop_menu_mode :: proc() -> Menu_Mode {
    if game_state.menu_mode_index > 0 {
        game_state.menu_mode_index -= 1
        game_state.menu_mode = game_state.menu_mode_queue[game_state.menu_mode_index]
        return game_state.menu_mode
    } else {
        game_state.menu_mode = .None
        return .None
    }
}

clear_menu_modes :: proc() {
    game_state.menu_mode_index = 0
    game_state.menu_mode = .None
    for i in 0..<len(game_state.menu_mode_queue) {
        game_state.menu_mode_queue[i] = .None
    }
}
