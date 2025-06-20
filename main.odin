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

WINDOW_WIDTH :: 900
WINDOW_HEIGHT :: 960 / 2

PLAYER_SPEED : f64 : 250

LASER_SPEED : f64 : 500
NUM_OF_LASERS : int : 100 
LASER_COOLDOWN_TIMER: f64 : TARGET_DELTA_TIME * (FRAMES_PER_SECOND / 2) // 0.5 second

DRONE_SPEED: f64 : 200
DRONE_SPAWN_COOLDOWN_TIMER : f64 : TARGET_DELTA_TIME * FRAMES_PER_SECOND * 1 // 1 second
NUM_OF_DRONES :: 5

DRONE_LASER_SPEED: f64 : 200
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

    // load assets 
    create_entities()

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

	// Update and Render 
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

	// render drone
	respawn: for &drone in &game.drones {
	    if drone.health == 0 && !(game.drone_spawn_cooldown > 0) {
		// respawn drone
		drone.dest.x = WINDOW_WIDTH
		drone.dest.y = i32(rand.float32_range(120, WINDOW_HEIGHT - 120))
		drone.health = 1
		game.drone_spawn_cooldown = DRONE_SPAWN_COOLDOWN_TIMER

		break respawn
	    
	    }

	}

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

	    if laser.health.x > WINDOW_WIDTH {
		laser.health = 0
	    }

	    if laser.health > 0 {

		SDL.RenderCopy(game.renderer, game.laser_tex, nil, &laser.dest)

		if laser.dest.x > WINDOW_WIDTH {
		    laser.health = 0
		}
	    }	    
	}


	for &drone in &game.drones {

	    if drone.health > 0 {
		// move drone
		drone.dest.x -= i32(get_delta_motion(drone.dx))		
		SDL.RenderCopy(game.renderer, game.drone_tex, nil, &drone.dest)

		if drone.dest.x < -drone.dest.w {
		    drone.health = 0
		}
	    }
	}

	// decrement timer 
	game.laser_cooldown -= get_delta_motion(LASER_COOLDOWN_TIMER)
	game.drone_spawn_cooldown -= get_delta_motion(DRONE_SPAWN_COOLDOWN_TIMER)


	// Player Dead
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

}

get_delta_motion :: proc(speed: f64) -> f64 {
    return speed * TARGET_DELTA_TIME / 1000
}


collision :: proc(x1, y1, w1, h1, x2, y2, w2, h2: i32) -> bool {
    return (max(x1, x2) < min(x1 + w1, x2 + w2)) && (max(y1, y2) < min(y1 + h1, y2 + h2))
}
