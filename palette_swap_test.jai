#import "raylib";
#import "Math";

WINDOW_X :: 1920;
WINDOW_Y :: 1080;

main :: () {
    InitWindow(WINDOW_X, WINDOW_Y, "Palette Swap Test");
    SetTargetFPS(60);

    main_texture := LoadTexture("main.png");
    SetTextureFilter(main_texture, .TEXTURE_FILTER_POINT);

    palette_texture := LoadTexture("palette.png");
    SetTextureFilter(palette_texture, .TEXTURE_FILTER_POINT);

    light_texture := LoadTexture("light.png");
    SetTextureFilter(light_texture, .TEXTURE_FILTER_POINT);

    shader := LoadShaderFromMemory(PALETTE_SWAP_VERTEX_SHADER, PALETTE_SWAP_FRAGMENT_SHADER);
    
    projection_loc := GetShaderLocation(shader, "projection");

    main_texture_loc    := GetShaderLocation(shader, "main_texture");
    palette_texture_loc := GetShaderLocation(shader, "palette_texture");
    light_texture_loc   := GetShaderLocation(shader, "light_texture");

    SetShaderValueTexture(shader, main_texture_loc,    main_texture);
    SetShaderValueTexture(shader, palette_texture_loc, palette_texture);
    SetShaderValueTexture(shader, light_texture_loc,   light_texture);

    while !WindowShouldClose() {
        BeginDrawing();
        defer EndDrawing();

        ClearBackground(BLACK);


        BeginShaderMode(shader);
        defer EndShaderMode();

        SetShaderValueMatrix(shader, projection_loc, Matrix4_Identity);
        SetShaderValueTexture(shader, main_texture_loc,    main_texture);
        SetShaderValueTexture(shader, palette_texture_loc, palette_texture);
        SetShaderValueTexture(shader, light_texture_loc,   light_texture);
        
        rlBegin(RL_TRIANGLES);
        defer rlEnd();
        
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
    }
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

uniform sampler2D main_texture;
uniform sampler2D palette_texture;
uniform sampler2D light_texture;

void main() {
    vec4 original_color = texture(main_texture, uv);

    ivec2 texture_size = textureSize(palette_texture, 0);

    int index = -1;
    for (int i = 0; i < texture_size.x; i++) {
        vec4 palette_color = texelFetch(palette_texture, ivec2(i, 0), 0);
        if (palette_color == original_color) {
            index = i;
            break;
        }
    }

    if (index == -1) {
        color = vec4(0, 1, 0, 1); // Make it a hideous green so we notice right away
        return;
    }

    float light_intensity = texture(light_texture, uv).r;

    color = texture(palette_texture, vec2(float(index), 1.0 - light_intensity));
}
END
