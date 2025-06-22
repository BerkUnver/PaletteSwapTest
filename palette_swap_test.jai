#import "raylib";
#import "Basic";
#import "Math";
#import "File";
#import "File_Watcher";


WINDOW_X :: 1920;
WINDOW_Y :: 1080;

main_texture:    Texture;
palette_texture: Texture;
light_day_texture: Texture;
light_night_texture: Texture;

main :: () {
    SetConfigFlags(.FLAG_WINDOW_RESIZABLE);
    InitWindow(WINDOW_X, WINDOW_Y, "Palette Swap Test");
    SetTargetFPS(60);

    watcher: File_Watcher();
    watcher_callback := (watcher: *File_Watcher(), change: *File_Change, user_data: *void) {
        if !(change.events & .REMOVED) {
            if change.full_path == {
                case "./main.bmp";
                    UnloadTexture(main_texture);
                    main_texture = load_bmp("main.bmp");

                case "./palette.png";
                    UnloadTexture(palette_texture);
                    palette_texture = LoadTexture("palette.png");

                case "./light_day.png";
                    UnloadTexture(light_day_texture);
                    light_day_texture = LoadTexture("light.png");
                    SetTextureFilter(light_day_texture, .TEXTURE_FILTER_POINT);

                case;
                    return;
            }

            print("Hotloaded '%'\n", change.full_path);
        }
    }

    assert(init(*watcher, watcher_callback, watch_recursively=false));
    assert(add_directories(*watcher, "."));

    main_texture = load_bmp("main.bmp");

    palette_texture = LoadTexture("palette.png");

    light_day_texture = LoadTexture("light_day.png");
    SetTextureFilter(light_day_texture, .TEXTURE_FILTER_POINT);

    light_night_texture = LoadTexture("light_night.png");
    SetTextureFilter(light_night_texture, .TEXTURE_FILTER_POINT);




    shader := LoadShaderFromMemory(PALETTE_SWAP_VERTEX_SHADER, PALETTE_SWAP_FRAGMENT_SHADER);

    projection_loc          := GetShaderLocation(shader, "projection");
    time_loc                := GetShaderLocation(shader, "time");
    main_texture_loc        := GetShaderLocation(shader, "main_texture");
    palette_texture_loc     := GetShaderLocation(shader, "palette_texture");
    light_day_texture_loc   := GetShaderLocation(shader, "light_day_texture");
    light_night_texture_loc := GetShaderLocation(shader, "light_night_texture");
    
    rlDisableBackfaceCulling();
    
    // Represents the current time-of-day of the scene. Ranges from 0 to 1, where 0 is midnight at
    // the beginning of the day and 1 midnight at the end of the day.
    time := 0.5;

    while !WindowShouldClose() {
        process_changes(*watcher);

        dt := GetFrameTime();

        TIME_RATE :: 1;
        
        if IsKeyPressed(.KEY_LEFT_BRACKET) || IsKeyPressedRepeat(xx KeyboardKey.KEY_LEFT_BRACKET) {
            time -= dt * TIME_RATE;
            time = fmod_cycling(time, 1);
        }

        if IsKeyPressed(.KEY_RIGHT_BRACKET) || IsKeyPressedRepeat(xx KeyboardKey.KEY_RIGHT_BRACKET) {
            time += dt * TIME_RATE;
            time = fmod_cycling(time, 1);
        }


        BeginDrawing();
        defer EndDrawing();

        ClearBackground(BLACK);
        
        BeginShaderMode(shader);

        projection := Matrix4_Identity;
       
        render_width := GetRenderWidth();
        render_height := GetRenderHeight();
    
        main_width := render_width / 480 * 480;
        main_height := render_height / 270 * 270;
        
        if cast(float)main_texture.height / cast(float)main_texture.width > cast(float)main_height / cast(float)main_width {
            // Window is too wide. Make the projection less wide.
            projection._22 = cast(float)main_height / cast(float)render_height;
            projection._11 = cast(float)(main_height * 16 / 9) / cast(float)render_width;
        } else {
            // Window is too narrow. Make the projection less tall.
            projection._11 = cast(float)main_width / cast(float)render_width;
            projection._22 = cast(float)(main_width * 9 / 16) / cast(float)render_height;
        }

        projection._22 *= -1;
        
        SetShaderValue       (shader, time_loc,                *time, .SHADER_UNIFORM_FLOAT);
        SetShaderValueMatrix (shader, projection_loc,          projection);
        SetShaderValueTexture(shader, main_texture_loc,        main_texture);
        SetShaderValueTexture(shader, palette_texture_loc,     palette_texture);
        SetShaderValueTexture(shader, light_day_texture_loc,   light_day_texture);
        SetShaderValueTexture(shader, light_night_texture_loc, light_night_texture);

        rlBegin(RL_TRIANGLES);
        
        rlTexCoord2f(0, 0);
        rlVertex3f(-1, -1, 0);
        rlTexCoord2f(0, 1);
        rlVertex3f(-1, 1, 0);
        rlTexCoord2f(1, 1);
        rlVertex3f(1, 1, 0);

        rlTexCoord2f(0, 0);
        rlVertex3f(-1, -1, 0);
        rlTexCoord2f(1, 1);
        rlVertex3f(1, 1, 0);
        rlTexCoord2f(1, 0);
        rlVertex3f(1, -1, 0);

        rlEnd();

        reset_temporary_storage();
    }
}


load_bmp :: (path: string) -> Texture {
    str, success := read_entire_file(path);
    assert(success);

    header_1 := get(*str, u8);
    header_2 := get(*str, u8);
    assert(header_1 == #char "B" && header_2 == #char "M");

    size := get(*str, u32);
    // Not sure what this actually corresponds to.
    // I am ignoring this for now.

    reserved_1 := get(*str, u16);
    reserved_2 := get(*str, u16);

    offset := get(*str, u32);

    BITMAPINFOHEADER :: struct {
        biSize:          u32;
        biWidth:         s32;
        biHeight:        s32;
        biPlanes:        u16;
        biBitCount:      u16;
        biCompression:   u32;
        biSizeImage:     u32;
        biXPelsPerMeter: s32;
        biYPelsPerMeter: s32;
        biClrUsed:       u32;
        biClrImportant:  u32;
    }

    assert(str.count >= size_of(u32));
    header_biSize := (cast(*u32)str.data).*;
    assert(header_biSize == size_of(BITMAPINFOHEADER)); // Only accepting these ones for now
    
    header := get(*str, BITMAPINFOHEADER);

    assert(header.biHeight >= 0); // Bottom in lower-left corner. Not accepting other ones for now.

    assert(header.biPlanes == 1); // The only valid value
    
    assert(header.biBitCount == 8); // Only accepting this for now.

    assert(header.biCompression == 0); // No compression
    
    assert(header.biClrUsed <= 256);
    
    assert(header.biClrImportant <= header.biClrUsed);

    RGBQUAD :: struct {
        a, b, g, r: u8;
    }

    palette_size := header.biClrUsed * size_of(RGBQUAD);
    advance(*str, palette_size);
   
    
    buffer := NewArray(header.biWidth * header.biHeight, u8,, temp);
    
    stride: int;
    if header.biWidth % 4 == 0 {
        stride = header.biWidth;
    } else {
        stride = (header.biWidth & ~0b11) + 4;
    }
    
    // We will load the image top-down for now.
    for 1..header.biHeight {
        memcpy(*buffer[header.biWidth * (header.biHeight - it)], str.data, header.biWidth);
        advance(*str, stride);
    }

    assert(str.count == 0); // I don't know if this is correct. Is there padding at the end?

    // This should be in the R8_UI format, but raylib doesn't let you do that.

    id := rlLoadTexture(buffer.data, header.biWidth, header.biHeight, .PIXELFORMAT_UNCOMPRESSED_GRAYSCALE, 1);
    
    texture := Texture.{
        id = id,
        width = header.biWidth,
        height = header.biHeight,
        format = .PIXELFORMAT_UNCOMPRESSED_GRAYSCALE,
    };
    SetTextureFilter(texture, .TEXTURE_FILTER_POINT);
    return texture;
}

// Little-endian
#assert OS == .WINDOWS;
get :: (str: *string, $T: Type) -> T {
    ptr: *T = xx str.data;
    advance(str, size_of(T));
    return ptr.*;
}


PALETTE_SWAP_VERTEX_SHADER :: #string END
#version 330 core
in vec3 vertexPosition;
in vec2 vertexTexCoord;

uniform mat4 projection;

out vec2 uv;

void main() {
    uv = vertexTexCoord;
    gl_Position = projection * vec4(vertexPosition, 1.0);
}
END



PALETTE_SWAP_FRAGMENT_SHADER :: #string END
#version 330 core

in vec2 uv;
out vec4 color;

uniform float time;
uniform sampler2D main_texture;
uniform sampler2D palette_texture;
uniform sampler2D light_day_texture;
uniform sampler2D light_night_texture;

void main() {
    bool is_day = 0.25 <= time && time <= 0.75;
    int palette_index = int(texture(main_texture, uv).r * 255.0);

    float light_intensity = texture(is_day ? light_day_texture : light_night_texture, uv).a;
    ivec2 palette_size = textureSize(palette_texture, 0);

    float palette_x = (float(palette_index) + 0.5) / palette_size.x;
    float palette_y = (0.5 + light_intensity * (palette_size.y - 1)) / palette_size.y;
    palette_y /= 2; // Each palette takes up half of the texture.
    palette_y += float(is_day) * 0.5; // The day palette is in the second half of the texture.

    vec2 palette_uv = vec2(palette_x, palette_y);

    color = texture(palette_texture, palette_uv);
}
END
