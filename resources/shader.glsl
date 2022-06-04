#version 330

// For reasons unclear we have to use a sampler2D instead of a isampler2D
// to read the texture. Raylib stores this internally as a R8G8B8A8
// and passes to OGL as 
// *glInternalFormat = GL_RGBA8; *glFormat = GL_RGBA; *glType = GL_UNSIGNED_BYTE
// so I'm not sure why we can't use an [iu]sampler2D to get the byte values directly.
// for now we can get the floats and scale/round them.
// ivec4 usr = ivec4(texelFetch(texture1, ivec2(1,0), 0));

// Input vertex attributes (from vertex shader)
in vec2 fragTexCoord;
in vec4 fragColor;

// Input uniform values
uniform sampler2D texture0;

uniform sampler2D user_texture;
uniform sampler2D rand_texture;
uniform vec4 colDiffuse;

uniform int mode;
uniform int current_user;

// Output fragment color
out vec4 finalColor;

vec3 hsv2rgb(vec3 c)
{
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}


vec4 statusClr(int status, ivec2 scramble) {
    if (status > 2) return vec4(0.9, 0.16, 0.22, 1.0);

    vec4 rand = texelFetch(rand_texture, scramble, 0);
    float v = (rand.r*0.15) + 0.6;
    float s = (rand.g*0.45) + 0.35;
    float h = 0.0;
    if (status == 0) {
      h = 0.35;
    } else if (status == 1) {
      h = 0.60;
    } else if (status == 2) {
       h += 0.14;
    }

    vec3 clr = hsv2rgb(vec3(h, s, v));
    return vec4(clr, 1.0);
}

vec4 jidClr(int jid) {
    int jid_x = jid % 128;
    int jid_y = jid / 128;
    vec4 clr = texelFetch(rand_texture, ivec2(jid_x, jid_y), 0);
    clr.a = 1.0;
    return clr;
}
vec4 ownerClr(int owner) {
    int owner_x = owner % 128;
    int owner_y = owner / 128;
    vec4 clr = texelFetch(rand_texture, ivec2(owner_x, owner_y), 0);
    clr.a = 1.0;
    return clr;
}
vec4 ownerDeptClr(int owner, int x, ivec2 scramble) {
    ivec4 usr_limits = ivec4(round(texelFetch(user_texture, ivec2(127,127), 0)*255));
    vec4 rand = texelFetch(rand_texture, scramble, 0);
    int owner_x = owner % 128;
    int owner_y = owner / 128;
    ivec4 usr = ivec4(round(texelFetch(user_texture, ivec2(owner_x, owner_y), 0)*255));
    float h = float(usr[x]) / float(usr_limits[x]);
    float v = (rand.r*0.15) + 0.6;
    float s = (rand.g*0.45) + 0.35;
    vec3 clr = hsv2rgb(vec3(h, s, v));
    return vec4(clr, 1.0);
}

vec4 currentUserClr(int owner, ivec2 scramble) {
    vec4 rand = texelFetch(rand_texture, scramble, 0);
    float h = 0.0;
    float v = (rand.r*0.15) + 0.1;
    float s = 0.0;
    if (owner == current_user) {
        h = 0.15;
        v = (rand.r*0.15) + 0.6;
        s = (rand.g*0.25) + 0.55;
    }
    vec3 clr = hsv2rgb(vec3(h, s, v));
    return vec4(clr, 1.0);
}

void main()
{
    vec4 texelColor = texture(texture0, fragTexCoord);

    ivec4 msg = ivec4(round(texelColor * 255));

    int status = (int(msg.b) >> 6) & 255;

    int active = int(msg.r) & 1;

    // 0b0011_1111 = 63
    int owner = msg.a | ((msg.b & 63) << 8);

    // 0b0011_1110 = 62
    int jid = msg.g | ((msg.r & 31) << 7);

    ivec2 scramble = ivec2(msg.r ^ msg.g, msg.r ^ msg.b);
    
// modes:
//  status
//  jid
//  usr
//  dept
//  sub
//  unit
//  div
    if (mode==0) {
        finalColor = statusClr(status, scramble);
    } else if (mode == 1) {
        finalColor = jidClr(jid);
    } else if (mode == 2) {
        finalColor = ownerClr(owner);
    } else if (mode > 2 && mode < 7) {
        finalColor = ownerDeptClr(owner, mode-3, scramble);
    } else if (mode == 7) {
        finalColor = currentUserClr(owner, scramble);
    }
    finalColor.a = 1.0;
    finalColor = pow(finalColor, vec4(0.4545)) * active;
    vec4 white = vec4(1.0);
    if (texelColor == white) {
      finalColor = vec4(0.7,0.7,0.7,1.0);
    }
}
