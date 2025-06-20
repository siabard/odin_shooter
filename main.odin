package main

import "core:fmt"
import SDL "vendor:sdl2"
import SDL_Image "vendor:sdl2/image"
import "core:math/rand"

// constants
WINDOW_FLAGS :: SDL.WINDOW_SHOWN
RENDER_FLAGS :: SDL.RENDERER_PRESENTVSYNC | SDL.RENDERER_ACCELERATED
FRAMES_PER_SECOND : f64 : 60;
TARGET_DELTA_TIME :: f64(1000) / FRAMES_PER_SECOND

HITBOXES_VISIBLE :: false 

WINDOW_WIDTH :: 900
WINDOW_HEIGHT :: 960 / 2

PLAYER_SPEED : f64 : 250

LASER_SPEED : f64 : 500
NUM_OF_LASERS : int : 100 
LASER_COOLDOWN_TIMER: f64 : TARGET_DELTA_TIME * (FRAMES_PER_SECOND / 2) // 0.5 second

DRONE_SPEED: f64 : 200
DRONE_SPAWN_COOLDOWN_TIMER : f64 : TARGET_DELTA_TIME * FRAMES_PER_SECOND * 1 // 1 second
NUM_OF_DRONES :: 5

DRONE_LASER_SPEED: f64 : 300
DRONE_LASER_COOLDOWN_TIMER_SINGLE : f64 : TARGET_DELTA_TIME * (FRAMES_PER_SECOND * 2)
DRONE_LASER_COOLDOWN_TIMER_ALL : f64 : TARGET_DELTA_TIME * 5
NUM_OF_DRONE_LASERS :: 2

STAGE_RESET_TIMER : f64 : TARGET_DELTA_TIME * FRAMES_PER_SECOND * 3


Game :: struct {
    stage_reset_timer: f64,
    perf_frequency: f64,
    renderer: ^SDL.Renderer,

    player: Entity,

    // player movement
    player_tex: ^SDL.Texture,
    left: bool,
    right: bool,
    up: bool,
    down: bool,

    // laser 
    laser_cooldown: f64,
    laser_tex: ^SDL.Texture,
    lasers: [NUM_OF_LASERS]Entity,
    fire: bool,

    // drone
    drone_tex: ^SDL.Texture,
    drones: [NUM_OF_DRONES]Entity,
    drone_spawn_cooldown: f64,

    // drone laser
    drone_laser_tex: ^SDL.Texture,
    drone_lasers: [NUM_OF_DRONE_LASERS]Entity,
    drone_laser_cooldown: f64,
}

Entity :: struct {
    source: SDL.Rect,
    dest: SDL.Rect,
    dx: f64,
    dy: f64,
    health: int,
    ready: f64,
}


game := Game{}

main :: proc() {
    assert(SDL.Init(SDL.INIT_VIDEO) == 0, SDL.GetErrorString())
    assert(SDL_Image.Init(SDL_Image.INIT_PNG) != nil, SDL.GetErrorString())
    defer SDL.Quit()

    window := SDL.CreateWindow(
	"Space shooter",
	SDL.WINDOWPOS_CENTERED,
	SDL.WINDOWPOS_CENTERED,
	WINDOW_WIDTH,
	WINDOW_HEIGHT,
	WINDOW_FLAGS
    )
    assert(window != nil, SDL.GetErrorString())
    defer SDL.DestroyWindow(window)


    game.renderer = SDL.CreateRenderer(window, -1, RENDER_FLAGS)
    assert(game.renderer != nil, SDL.GetErrorString())
    defer SDL.DestroyRenderer(game.renderer)

    SDL.RenderSetLogicalSize(game.renderer, WINDOW_WIDTH, WINDOW_HEIGHT)

    
    // load assets 
    reset_stage()

    game.perf_frequency = f64(SDL.GetPerformanceFrequency())
    start: f64
    end: f64

    event: SDL.Event
    state: [^]u8
    
    game_loop: for {
	start = get_time()

	// 1. Get Keyboard State 
	state = SDL.GetKeyboardState(nil)

	game.left = state[SDL.Scancode.A] > 0
	game.right = state[SDL.Scancode.D] > 0
	game.up = state[SDL.Scancode.W] > 0
	game.down = state[SDL.Scancode.S] > 0
	game.fire = state[SDL.Scancode.SPACE] > 0 

	if SDL.PollEvent(&event) {
	    if event.type == SDL.EventType.QUIT {
		break game_loop
	    }

	    if event.type == SDL.EventType.KEYDOWN {
		#partial switch event.key.keysym.scancode {
		    case .ESCAPE:
		    break game_loop
		}
	    }
	}


	// Player Laser: check collision => render  

	for &laser in &game.lasers {
	    if laser.health == 0 {
		continue
	    }

	    detect_collision: for &drone in &game.drones {
		if drone.health == 0 {
		    continue
		}
		hit := collision(
		    laser.dest.x,
		    laser.dest.y,
		    laser.dest.w,
		    laser.dest.h,

		    drone.dest.x,
		    drone.dest.y,
		    drone.dest.w,
		    drone.dest.h,
		)

		if hit {
		    laser.health = 0
		    drone.health = 0

		    break detect_collision
		}
	    }

	    laser.dest.x += i32(get_delta_motion(laser.dx))

	    if laser.dest.x > WINDOW_WIDTH {
		laser.health = 0
	    }

	    if laser.health > 0 {

		when HITBOXES_VISIBLE do render_hitbox(&laser.dest)
		SDL.RenderCopy(game.renderer, game.laser_tex, nil, &laser.dest)
	    }	    
	}


	// Drone lasers -- check collisions -> render 
	for &laser, idx in &game.drone_lasers {
	    if laser.health == 0 {
		continue
	    }

	    // check collisions on previous frame's rendered position 
	    hit := collision(
		game.player.dest.x, 
		game.player.dest.y,
		game.player.dest.w,
		game.player.dest.h,

		laser.dest.x,
		laser.dest.y,
		laser.dest.w,
		laser.dest.h,
	    )

	    if hit {
		laser.health = 0
		game.player.health = 0
	    }

	    laser.dest.x += i32(get_delta_motion(laser.dx))
	    laser.dest.y += i32(get_delta_motion(laser.dy))

	    // reset laser if it's offscreen
	    // checking x and y b/c these drone
	    // lasers go in different directions 
	    if laser.dest.x <= 0 ||
		laser.dest.x > WINDOW_WIDTH ||
		laser.dest.y <= 0 ||
		laser.dest.y >= WINDOW_HEIGHT {
		    laser.health = 0
		}

	    
	    if laser.health > 0 {
		when HITBOXES_VISIBLE do render_hitbox(&laser.dest)
		SDL.RenderCopy(game.renderer, game.drone_laser_tex, &laser.source, &laser.dest)
	    }
	}



	// At this point we've checked out collision
	// and we've figured out our active Player Lasers,
	// Drones, and Drone lasers,
	// Render active drones and fire new lasers 
	
	// render active drones and fire new lasers 
	respawned := false
	for &drone in &game.drones {
	    if !respawned && drone.health == 0 && !(game.drone_spawn_cooldown > 0) {
		drone.dest.x = WINDOW_WIDTH
		drone.dest.y = i32(rand.float32_range(120, WINDOW_HEIGHT - 120))
		drone.health = 1
		drone.ready = DRONE_LASER_COOLDOWN_TIMER_SINGLE / 10 // ready to fire quickly
		
		game.drone_spawn_cooldown = DRONE_SPAWN_COOLDOWN_TIMER

		respawned = true
	    }

	    if drone.health == 0 {
		continue
	    }

	    drone.dest.x -= i32(get_delta_motion(drone.dx))
	    
	    if drone.dest.x <= 0 {
		drone.health = 0
		continue
	    }

	    if drone.health > 0 {

		
		SDL.RenderCopy(game.renderer, game.drone_tex, nil, &drone.dest)

		// For each active drone, fire a laser if cooldown time reached 
		// and the drone isn't moving offscreen 
		// without this 300 pixel buffer, it looks like lasers 
		// are coming from offscreen 

		if drone.dest.x > 30 && 
		    drone.dest.x < (WINDOW_WIDTH - 30) &&
		    drone.ready <= 0 &&
		    game.drone_laser_cooldown <= 0 {
			// fire a drone laser:
			fire_drone_laser: for &laser, idx in &game.drone_lasers {
			    // find first one
			    if laser.health == 0 {
				laser.dest.x = drone.dest.x
				laser.dest.y = drone.dest.y
				laser.health = 1

				new_dx, new_dy := calc_slope(
				    laser.dest.x,
				    laser.dest.y,
				    game.player.dest.x,
				    game.player.dest.y
				)

				laser.dx = new_dx * DRONE_LASER_SPEED
				laser.dy = new_dy * DRONE_LASER_SPEED

				// reset the cooldown to prevent firing too rapidly
				drone.ready = DRONE_LASER_COOLDOWN_TIMER_SINGLE
				game.drone_laser_cooldown = DRONE_LASER_COOLDOWN_TIMER_ALL

				SDL.RenderCopy(game.renderer, game.drone_laser_tex, &laser.source, &laser.dest)

				break fire_drone_laser
			    }
			}
		    }
		
		// decrement 'ready' timer 
		// to help distribute laser more evenly 

		drone.ready -= TARGET_DELTA_TIME
	    }
	}
	


	// Update and Render 
	if game.player.health > 0 {
	    delta_motion_x := get_delta_motion(game.player.dx)
	    delta_motion_y := get_delta_motion(game.player.dy)

	    if game.left {
		move_player(-delta_motion_x, 0)
	    }
	    if game.right {
		move_player(delta_motion_x, 0)
	    }
	    if game.up {
		move_player(0, -delta_motion_y)
	    }
	    if game.down {
		move_player(0, delta_motion_y)
	    }
	    
	    when HITBOXES_VISIBLE do render_hitbox(&game.player.dest)
	    
	    
	    // render updated entity:
	    SDL.RenderCopy(game.renderer, game.player_tex, nil, &game.player.dest)


	    // laser fire 
	    if game.fire && game.laser_cooldown <= 0 {

		reload : for &laser in &game.lasers {
		    if laser.health == 0 {
			laser.dest.x = game.player.dest.x + 30
			laser.dest.y = game.player.dest.y
			laser.health = 1

			game.laser_cooldown = LASER_COOLDOWN_TIMER

			break reload
		    }
		}
	    }
	}


	// player dead 
	if game.player.health == 0 {
	    game.stage_reset_timer -= TARGET_DELTA_TIME

	    if game.stage_reset_timer < 0 {
		reset_stage()
	    }
	}

	// TIMERS 
	game.laser_cooldown -= TARGET_DELTA_TIME
	game.drone_spawn_cooldown -= TARGET_DELTA_TIME
	game.drone_laser_cooldown -= TARGET_DELTA_TIME

	// end LOOP 

	end = get_time()
	for end - start < TARGET_DELTA_TIME {
	    end = get_time()
	}


	// actual flipping / presentation of the copy
	SDL.RenderPresent(game.renderer)

	//  background is black
	SDL.SetRenderDrawColor(game.renderer, 0, 0, 0, 100)
	
	// clear after presentation so we remain free to call RenderCopy
	SDL.RenderClear(game.renderer)

    }
}


get_time :: proc() -> f64 {
    return f64(SDL.GetPerformanceCounter()) * 1000 / game.perf_frequency
}

move_player :: proc(x, y: f64) {
    game.player.dest.x = clamp(game.player.dest.x + i32(x), 0, WINDOW_WIDTH - game.player.dest.w);
    game.player.dest.y = clamp(game.player.dest.y + i32(y), 0, WINDOW_HEIGHT - game.player.dest.h)
}

create_entities :: proc () {

    player_texture := SDL_Image.LoadTexture(game.renderer, "assets/player.png")
    assert(player_texture != nil, SDL.GetErrorString())

    // init with starting position
    destination := SDL.Rect{x = 20, y = WINDOW_HEIGHT / 2}
    SDL.QueryTexture(player_texture, nil, nil, &destination.w, &destination.h)

    // reduce size by 10x
    destination.w /= 10
    destination.h /= 10
    game.player_tex = player_texture

    game.player = Entity {
	dest = destination,
	dx = PLAYER_SPEED,
	dy = PLAYER_SPEED,
	health = 1,
    }

    // Laser
    laser_texture := SDL_Image.LoadTexture(game.renderer, "assets/bullet_red_2.png")
    assert(laser_texture != nil, SDL.GetErrorString())
    

    laser_w: i32
    laser_h: i32

    SDL.QueryTexture(laser_texture, nil, nil, &laser_w, &laser_h)
    game.laser_tex = laser_texture


    for index in 0..<NUM_OF_LASERS {
	d := SDL.Rect {
	    x = WINDOW_WIDTH + 20,
	    y = 0,
	    w = laser_w / 3,
	    h = laser_h / 3
	}
	game.lasers[index] = Entity{
	    dest = d,
	    dx = LASER_SPEED,
	    dy = LASER_SPEED,
	    health = 0,
	    
	}
    }

    // drone
    drone_texture := SDL_Image.LoadTexture(game.renderer, "assets/drone_1.png")
    assert(drone_texture != nil, SDL.GetErrorString())

    drone_w: i32
    drone_h: i32

    SDL.QueryTexture(drone_texture, nil, nil, &drone_w, &drone_h)
    game.drone_tex = drone_texture

    for index in 0..<NUM_OF_DRONES {
	max := DRONE_SPEED * 1.2
	min := DRONE_SPEED * 0.5 

	random_speed := rand.float64_range(min, max)
	
	d := SDL.Rect {
	    x = -(drone_w),
	    w = drone_w / 5, 
	    h = drone_h / 5,
	}

	game.drones[index] = Entity {
	    dest = d,
	    dx = random_speed,
	    dy = random_speed,
	    health = 0,
	}
    }

    drone_laser_texture := SDL_Image.LoadTexture(game.renderer, "assets/drone_laser_1.png")
    assert(drone_laser_texture != nil, SDL.GetErrorString())
    drone_laser_width: i32
    drone_laser_height: i32

    SDL.QueryTexture(drone_laser_texture, nil, nil, &drone_laser_width, &drone_laser_height)

    game.drone_laser_tex = drone_laser_texture

    for index in 0..<NUM_OF_DRONE_LASERS {
	destination := SDL.Rect{
	    w = drone_laser_width / 8,
	    h = drone_laser_height /  6,
	    }
	source := SDL.Rect{54, 28, 62, 28}

	game.drone_lasers[index] = Entity{
	    source = source,
	    dest = destination,
	    dx = DRONE_LASER_SPEED,
	    dy = DRONE_LASER_SPEED,
	    health = 0,
	}
    }

}

get_delta_motion :: proc(speed: f64) -> f64 {
    return speed * TARGET_DELTA_TIME / 1000
}


collision :: proc(x1, y1, w1, h1, x2, y2, w2, h2: i32) -> bool {
    return (max(x1, x2) < min(x1 + w1, x2 + w2)) && (max(y1, y2) < min(y1 + h1, y2 + h2))
}

calc_slope :: proc(from_x, from_y, to_x, to_y: i32) -> (f64, f64) {
    steps := f64(max(abs(to_x - from_x), abs(to_y - from_y)))

    if steps == 0 {
	return 0, 0
    }

    new_dx := f64(to_x) - f64(from_x)
    new_dx /= steps

    new_dy := f64(to_y) - f64(from_y)
    new_dy /= steps

    // ensure values 0.5 -> 0.9 will be truncated to 1 AND 
    // ensure values -0.5 -> 0.9 will be truncated to -1 
    
    return new_dx, new_dy
}


reset_stage :: proc () {
    create_entities()

    game.laser_cooldown = LASER_COOLDOWN_TIMER
    game.drone_spawn_cooldown = DRONE_SPAWN_COOLDOWN_TIMER
    game.drone_laser_cooldown = DRONE_LASER_COOLDOWN_TIMER_ALL

    game.stage_reset_timer = STAGE_RESET_TIMER
}

render_hitbox:: proc(dest: ^SDL.Rect) {
    r := SDL.Rect { dest.x, dest.y, dest.w, dest.h }

    SDL.SetRenderDrawColor(game.renderer, 255, 0, 0, 100)
    SDL.RenderDrawRect(game.renderer, &r)
}
