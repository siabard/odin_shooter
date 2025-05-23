package main

import "core:fmt"
import SDL "vendor:sdl2"
import SDL_Image "vendor:sdl2/image"

// constants
WINDOW_FLAGS :: SDL.WINDOW_SHOWN
RENDER_FLAGS :: SDL.RENDERER_PRESENTVSYNC | SDL.RENDERER_ACCELERATED
TARGET_DT :: 1000 / 60

WINDOW_WIDTH :: 1600
WINDOW_HEIGHT :: 960

Game :: struct {
    perf_frequency: f64,
    renderer: ^SDL.Renderer,

    player: Entity,
}

Entity :: struct {
    tex: ^SDL.Texture,
    dest: SDL.Rect,
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
    player_texture := SDL_Image.LoadTexture(game.renderer, "assets/player.png")
    assert(player_texture != nil, SDL.GetErrorString())

    // init with starting position
    destination := SDL.Rect{x = 20, y = WINDOW_HEIGHT / 2}
    SDL.QueryTexture(player_texture, nil, nil, &destination.w, &destination.h)

    // reduce size by 10x
    destination.w /= 10
    destination.h /= 10

    game.player = Entity {
	tex = player_texture,
	dest = destination,
    }

    game.perf_frequency = f64(SDL.GetPerformanceFrequency())
    start: f64
    end: f64

    event: SDL.Event
    state: [^]u8
    
    game_loop: for {
	start = get_time()

	// 1. Get Keyboard State 
	state = SDL.GetKeyboardState(nil)

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
	SDL.RenderCopy(game.renderer, game.player.tex, nil, &game.player.dest)

	end = get_time()
	for end - start < TARGET_DT {
	    end = get_time()
	}


	SDL.RenderPresent(game.renderer)

	SDL.SetRenderDrawColor(game.renderer, 0, 0, 0, 100)
	
	// clear after presentation so we remain free to call RenderCopy
	SDL.RenderClear(game.renderer)

    }
}


get_time :: proc() -> f64 {
    return f64(SDL.GetPerformanceCounter()) * 1000 / game.perf_frequency
}
