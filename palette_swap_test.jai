#import "raylib";
#import "Basic";
#import "Math";
#import "File_Watcher";

WINDOW_X :: 1920;
WINDOW_Y :: 1080;

main_texture:    Texture;
palette_texture: Texture;
light_texture:   Texture;

main :: () {
    SetConfigFlags(.FLAG_WINDOW_RESIZABLE);
    InitWindow(WINDOW_X, WINDOW_Y, "Palette Swap Test");
    SetTargetFPS(60);

    watcher: File_Watcher();
    watcher_callback := (watcher: *File_Watcher(), change: *File_Change, user_data: *void) {
        if !(change.events & .REMOVED) {
            if change.full_path == {
                case "./main.png";
                    UnloadTexture(main_texture);
                    main_texture = LoadTexture("main.png");
                    SetTextureFilter(main_texture, .TEXTURE_FILTER_POINT);

                case "./palette.png";
                    UnloadTexture(palette_texture);
                    palette_texture = LoadTexture("palette.png");
                    SetTextureFilter(palette_texture, .TEXTURE_FILTER_BILINEAR);
                    SetTextureWrap(palette_texture, .TEXTURE_WRAP_CLAMP);

                case "./light.png";
                    UnloadTexture(light_texture);
                    light_texture = LoadTexture("light.png");
                    SetTextureFilter(light_texture, .TEXTURE_FILTER_POINT);

                case;
                    return;
            }

            print("Hotloaded '%'\n", change.full_path);
        }
    }

    assert(init(*watcher, watcher_callback, watch_recursively=false));
    assert(add_directories(*watcher, "."));

    // @Copypaste from the watcher callback
    main_texture = LoadTexture("main.png");
    SetTextureFilter(main_texture, .TEXTURE_FILTER_POINT);

    palette_texture = LoadTexture("palette.png");
    SetTextureFilter(palette_texture, .TEXTURE_FILTER_BILINEAR);
    SetTextureWrap(palette_texture, .TEXTURE_WRAP_CLAMP);

    light_texture = LoadTexture("light.png");
    SetTextureFilter(light_texture, .TEXTURE_FILTER_POINT);




    shader := LoadShaderFromMemory(PALETTE_SWAP_VERTEX_SHADER, PALETTE_SWAP_FRAGMENT_SHADER);

    projection_loc      := GetShaderLocation(shader, "projection");
    main_texture_loc    := GetShaderLocation(shader, "main_texture");
    palette_texture_loc := GetShaderLocation(shader, "palette_texture");
    light_texture_loc   := GetShaderLocation(shader, "light_texture");
    
    rlDisableBackfaceCulling();

    while !WindowShouldClose() {
        process_changes(*watcher);

        BeginDrawing();

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
        
        SetShaderValueMatrix (shader, projection_loc,      projection);
        SetShaderValueTexture(shader, main_texture_loc,    main_texture);
        SetShaderValueTexture(shader, palette_texture_loc, palette_texture);
        SetShaderValueTexture(shader, light_texture_loc,   light_texture);
        
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

        EndShaderMode();

        EndDrawing();

        reset_temporary_storage();
    }
}


Bmp :: struct {
    width: s32;
    height: s32;
    id: s32;
    palette_count: s32;
    palette: [256] Vector4;
}


load_bmp :: (path: string) -> Bmp {
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
    palette: *RGBQUAD = xx advance(*str, palette_size);
    
    assert(header.biWidth % 4 == 0);
    // Apparently they insert padding bits to round up to 4 bytes per row.
    // I don't want to deal with that right now so I am just doing this.

    image_data := advance(*str, image.biWidth * header.biHeight);

    assert(str.count == 0); // I don't know if this is correct. Is there padding at the end?

    id := rlLoadTexture(image_data, image.biWidth, image.biHeight, .PIXELFORMAT_UNCOMPRESSED_GRAYSCALE, 0);

    bmp: Bmp;
    bmp.width = header.biWidth;
    bmp.height = heaer.biHeight;
    bmp.id = id;
    bmp.palette_count = palette_count;
    for 0..palette_count-1 {
        using q := palette[it];
        bmp.palette[it_index] = .{
            cast(float)r/255,
            cast(float)g/255,
            cast(float)b/255,
            1
        };
    }

    return bmp;
}

set_bmp_uniform :: (shader: Shader, loc: u32, bmp: *Bmp) {
    BeginShaderMode(shader);
    rlSetUniformSampler(loc, bmp.id);
    rlSetUniform(loc + 1, bmp.palette_count, 
    EndShaderMode(shader);
}


// Little-endian
#assert OS == .WINDOWS;
get :: (str: *string, type: $T) -> T {
    ptr := advance(str, size_of(T));
    i: T = ---;
    memcpy(*i, ptr, size_of(T));
    return i;
}

advance :: (str: *string, count: int) -> *u8 {
    ptr := str.data;
    assert(str.count >= count);
    str.data += count;
    str.count -= count;
    return ptr;
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


struct Bmp {
    uniform sampler2D sampler;
    uniform uint palette_count;
    uniform uint palette[256];
};


uniform Bmp main_bmp;
uniform sampler2D palette_texture;
uniform sampler2D light_texture;


void main() {
    vec4 original_color = texture(main_texture, uv);

    ivec2 texture_size = textureSize(palette_texture, 0);

    int index = -1;
    for (int i = 0; i < texture_size.x; i++) {
        if (texelFetch(palette_texture, ivec2(i, 0), 0) == original_color) {
            index = i;
            break;
        }
    }

    if (index == -1) {
        color = vec4(0, 1, 0, 1); // Make it a hideous green so we notice right away
        return;
    }

    float light_intensity = texture(light_texture, uv).a;
    
    // The + 0.5 is so we end up in the middle of the texel in the palette so we aren't
    // affected by bilinear filtering.
    vec2 palette_uv = vec2((float(index) + 0.5) / float(texture_size.x), light_intensity);


    vec4 palette_color = texture(palette_texture, palette_uv);
    if (palette_color.x < 0.001 && palette_color.y < 0.001 && palette_color.z < 0.001 && palette_color.a > 0.999) {
        // If the palette color is really close to black, that means we haven't filled it in yet.
        // The program should let us know by making the pixels a hideous blue;
        color = vec4(0, 1, 1, 1);
        return;
    }

    color = palette_color;
}
END
