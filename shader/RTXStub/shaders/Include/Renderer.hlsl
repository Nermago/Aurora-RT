/* MIT License
 * 
 * Copyright (c) 2025 veka0
 * 
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 * 
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 * 
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

#ifndef __RENDERER_HLSL__
#define __RENDERER_HLSL__

#include "Generated/Signature.hlsl"
#include "Material.hlsl"

struct LightData
{
    float3 color;
    float intensity;
    bool isLarge;
};

LightData UnpackLight(uint packedData)
{
    LightData lightData;
    lightData.isLarge = (packedData >> 24) & 0x80;
    lightData.color = float3(
        (float)((packedData >> 24) & 0x7f) / 127.0,
        (float)((packedData >> 16) & 0xff) / 255.0,
        (float)((packedData >> 8) & 0xff) / 255.0);
    lightData.intensity = (float)((packedData >> 0) & 0xff) / 255.0;
    return lightData;
}

static uint g_arPrimaryMask = 0xff;   // v74: mascara del primer rayo (en el mundo normal sin las mallas del cielo del juego)
struct RayState
{
    RayDesc rayDesc;

    float3 color;
    float3 throughput;

    float distance;
    float3 motion;

    uint instanceMask; // 8 bits, see INSTANCE_MASK macros in Constants.hlsl
    float waterEnterT; // Aurora: distancia donde el rayo entro al agua (-1 = no)
    bool giDone;       // Aurora: ya se calculo iluminacion global para este pixel
    float3 giColor;    // Aurora: parte de la imagen que viene de la iluminacion global (se acumula aparte)
    float tOffset;     // Aurora: distancia recorrida antes de una refraccion
    float3 waterTint;  // Aurora: color del agua del bioma

    void Init()
    {
        color = 0;
        throughput = 1;
        distance = 0;
        motion = 0;
        instanceMask = g_arPrimaryMask;   // v74 hibrido: el pase final pone las mismas mascaras que la camara del juego
        waterEnterT = -1;
        giDone = false;
        giColor = 0;
        tOffset = 0;
        waterTint = 1;
    }
};

// ======================================================================
//  PRESET "Aurora RT" v3 - ajustes rapidos (todo en espacio lineal)
// ======================================================================
#define AR_EXPOSURE           1.10   // brillo general de la imagen
#define AR_AMBIENT_STRENGTH   0.75   // luz del cielo en las sombras
#define AR_AMBIENT_MIN        0.02   // solo donde se ve el cielo (cuartos cerrados quedan oscuros)
#define AR_SKY_DARK           1      // v47: oscuridad real: sin cielo a la vista (cuartos, cuevas) no llega luz del cielo
#define AR_SKY_RAYS           2      // v47: rayos por pixel para saber cuanto cielo se ve
#define AR_SKY_DIST           48.0   // v47: hasta donde buscan techo/paredes esos rayos
#define AR_SKY_CURVE          1.6    // v48: >1 = lo medio tapado (cuevas, bajo techos) se ve mas oscuro
#define AR_NORMAL_LIGHT       0.5    // v49: cuanto cuenta el relieve de la textura en la luz (1 = todo; menos = sin rayas negras)
#define AR_PUDDLE_ROUGH       0.14   // v48: reflejo de los charcos un poco borroso (0 = espejo perfecto)
#define AR_NIGHT_FILL         float3(0.008, 0.011, 0.020)   // v48: antes (0.012, 0.016, 0.028)  // luz minima de noche/lluvia (que no quede negro)
#define AR_NIGHT_EXPOSURE     0.20   // v48: antes 0.30 (noche mas oscura)   // de noche la "camara" abre un poco mas (como el ojo)
#define AR_PUDDLES            1       // charcos cuando llueve
#define AR_PUDDLE_THRESHOLD   0.56   // v47: antes 0.61 (casi no salian charcos)   // cuantos charcos hay (0.50 = muchos, 0.70 = pocos)
#define AR_CACHE_BLEND        0.25   // cuanto de la luz rebotada viene de la cache estable (quita los "granitos de arena")
#define AR_BIOME_WATER        0.75   // cuanto cambia el color del agua segun el bioma (0 = nada)
#define AR_CLOUDS_ABOVE       1      // nubes vistas desde arriba y niebla blanca al atravesarlas
#define AR_CLOUD_SIZE         3.5    // tamano de las nubes (mas alto = nubes mas grandes)
#define AR_LIGHT_DEBUG        0      // con efecto de vision nocturna se ven las luces que manda el juego (rojo/verde)
#define AR_SUN_STRENGTH       1.55
#define AR_MOON_STRENGTH      0.12   // luz de luna (de noche se ve)
#define AR_BOUNCE_STRENGTH    0.30   // luz rebotada del suelo (GI falso)
#define AR_AO_STRENGTH        0.55
#define AR_LEAF_TRANSMIT      0.12
#define AR_LEAF_EXACT         2      // hojas revisadas una por una en cada sombra (menos = mas FPS)
// (los ajustes de lamparas AR_POINT_... estan en AuroraLights.hlsl)
#define AR_FOG_DENSITY        0.6
#define AR_HAZE               0.0    // bruma azulada a media distancia (profundidad, estilo shaders de Java)
#define AR_METAL_MIRROR       1      // metales (hierro, oro...) reflejan como espejo
#define AR_LIGHTNING          1       // destello de los rayos que recorre las nubes en tormenta
#define AR_SATURATION         1.15
#define AR_GLINT_STRENGTH     0.25
#define AR_GODRAYS            1 
#define AR_GODRAY_STEPS       5      // v45: 4 en todos los pixeles (v44: 7 en la mitad; cada paso es un rayo)
#define AR_GODRAY_DENSITY     0.011   // fuerza de los rayos de sol
#define AR_GODRAY_PACK        1.5
#define AR_GODRAY_MAX         0.35    // brillo maximo de los rayos (para que no se vea todo blanco)     // cuanto suma la niebla del pack de texturas
#define AR_GODRAY_MAXDIST     320.0   // hasta donde se ven los rayos de sol
#define AR_CLOUDS             1       // nubes volumetricas (reemplazan las planas)
// v80: la capa de nubes se repite cada 10,000 bloques de altura: debajo de 10,000 esta a 800-1050 (se ve desde abajo y,
// al pasarla, queda debajo de ti); arriba de 10,000 aparece otra a 10,800-11,050, y asi
#define AR_CLOUD_REPEAT       1.0e9    // v84: sin repeticion (las nubes se quedan siempre en 1000-1300)
#define AR_CLOUD_BASE         (AR_CLOUD_BASE0 + ArCloudOff())
#define AR_CLOUD_TOP          (AR_CLOUD_TOP0 + ArCloudOff())
#define AR_CLOUD_BASE0        700.0   // v88: plan B del usuario: 700-1000
#define AR_CLOUD_TOP0         1000.0
#define AR_CLOUD_COVERAGE     0.58   // v79: un poco mas juntas (v78 0.50 se veian muy separadas)   // 0 = cielo despejado, 1 = nublado
#define AR_CLOUD_STEPS        24
#define AR_CLOUD_SHADOWS      1      // las nubes tapan el sol en el suelo
#define AR_WATER_WAVES        1       // agua con olas y reflejos
#define AR_WATER_ABSORB       float3(0.80, 0.24, 0.17)   // v49: antes (0.42, 0.11, 0.075): lo hondo casi no se ve // agua azul cristalina (mas alto = mas oscura)
#define AR_WATER_COLOR        float3(0.0015, 0.012, 0.024)   // v49: agua honda mas oscura
#define AR_WATER_TEXTURE      0.12   // cuanto se nota la textura del agua
#define AR_WAVE_SCALE         2.3
#define AR_WATER_REFRACTION   1       // el fondo se deforma con las olas
#define AR_CAUSTICS           1       // dibujos de luz en el fondo del agua
#define AR_UNDERWATER_ABSORB  float3(0.30, 0.10, 0.11) // neblina bajo el agua (mas alto = se ve menos)
#define AR_UNDERWATER_FOG     float3(0.010, 0.046, 0.042) // color de dentro del agua (verde azulado claro)
#define AR_RAIN_FOG           0.30   // neblina cuando llueve (0 = nada)
#define AR_HORROR_FOG         0      // 1 = neblina densa de terror cuando llueve (guardada para un preset de terror)
#define AR_GLASS_TINT         1      // la luz que pasa por vidrios de color se tine
#define AR_PBR_SPECULAR       1      // brillos y reflejos en metales, cuarzo, diamante, piso pulido
#define AR_SPEC_ROUGH_LITE    0.20   // v46: sin luz rebotada, solo lo mas pulido refleja
#define AR_SPEC_ROUGH_MAX     0.45   // a partir de esta rugosidad ya no refleja    // tamano de las olas
#define AR_EMISSIVE_BOOST     14.0    // brillo de antorchas, lava, glowstone
#define AR_GI                 0       // iluminacion global real (luz que rebota y tine)
#define AR_GI_SAMPLES         6      // rayos de rebote por pixel
#define AR_GI_STRENGTH        1.15
#define AR_GI_SKY             1.5    // cuanta luz del cielo entra por ventanas/huecos
#define AR_GI_EMISSIVE        45.0    // cuanto iluminan los bloques emisivos a su alrededor
#define AR_GI_CLAMP           1.5    // evita "particulas" brillantes (fireflies)
#define AR_HYB_NO_SUNMESH     1       // v72 hibrido: sol y luna propios de Aurora (no los del juego)
#define AR_RAIN_WETNESS       1       // suelo mojado y con reflejos cuando llueve
#define AR_NETHER_FOG         0.018
#define AR_END_FOG            0.0
#define AR_FACE_CACHE         0       // FASE 1: luz rebotada guardada por cara de bloque (rapida y limpia)
#define AR_CACHE_RAYS         8       // rayos por cara en cada actualizacion
#define AR_CACHE_LIGHTS       8      // luces del juego evaluadas por cara
#define AR_VERTEX_CACHE       0       // luz guardada por esquina (suave, sin cuadros de luz)
#define AR_VERTEX_RAYS        4      // rayos por esquina cada vez que se actualiza
#define AR_CACHE_MIN_HIST     6.0    // frames que necesita una cara nueva antes de confiar en su cache
#define AR_CACHE_EMISSIVE     2.2    // cuanto iluminan los bloques que brillan (piedra luminosa, linterna marina, luces de rana...)
#define AR_GATHER_RAYS        2      // rayos por pixel que leen la cache
#define AR_ACCUMULATE         1      // acumulacion temporal (quita el ruido)
#define AR_ACCUM_ALPHA        0.035
#define AR_BLOOM              1      // resplandor alrededor de lo que brilla
#define AR_BLOOM_STRENGTH     0.06
#define AR_SUNSET_FOG         1.0    // rayos de sol extra al amanecer/atardecer

// Lluvia: el juego a veces deja rainLevel en 0 si entras a un mundo donde ya llueve;
// la humedad de superficies del juego sirve de respaldo
float ArRainLevel()
{
    float r = g_view.rainLevel;
    float w = g_view.surfaceWetness;
    if (isnan(r)) r = 0;
    if (isnan(w) || w > 1.5) w = 0;
    return saturate(max(r, w));
}

float Luma(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }
uint PcgHashEarly(uint v) { uint st = v * 747796405u + 2891336453u; uint w = ((st >> ((st >> 28u) + 4u)) ^ st) * 277803737u; return (w >> 22u) ^ w; }
float Max3(float3 c) { return max(max(c.x, c.y), c.z); }
float3 ToLinear(float3 c) { return pow(max(c, 0), 2.2); }

float Hash13(float3 p)
{
    p = frac(p * 0.1031);
    p += dot(p, p.zyx + 31.32);
    return frac((p.x + p.y) * p.z);
}

float Hash12(float2 p)
{
    float3 p3 = frac(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return frac((p3.x + p3.y) * p3.z);
}

float ValueNoise(float2 p)
{
    float2 i = floor(p);
    float2 f = frac(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = Hash12(i);
    float b = Hash12(i + float2(1, 0));
    float c = Hash12(i + float2(0, 1));
    float d = Hash12(i + float2(1, 1));
    return lerp(lerp(a, b, u.x), lerp(c, d, u.x), u.y);
}

float Fbm(float2 p)
{
    float s = 0;
    float a = 0.5;
    [unroll]
    for (int i = 0; i < 4; i++)
    {
        s += a * ValueNoise(p);
        p = p * 2.03 + float2(17.1, 9.7);
        a *= 0.5;
    }
    return s;
}

static uint2 g_arPixel = uint2(0, 0);
static float3 g_arGI = float3(0, 0, 0);
static float g_arSkyHits = 0;
static float g_arEmisScale = 1.0;   // los rayos por pixel usan menos emisivo (la cache lo aporta sin granitos)
static float g_arRadClamp = 30.0;
// Luz rebotada SIN el color de la textura (se filtra aparte y luego se multiplica por el color: limpia y sin borrar texturas)
static float3 g_arIrr = float3(0, 0, 0);
static float3 g_arAlb = float3(0, 0, 0);
static float3 g_arN = float3(0, 1, 0);
static float g_arGRJitter = -1.0;   // v50: desplazamiento fijo de los rayos de sol (-1 = patron por pixel)
static float g_arReflSky = 1.0;   // v48: cuanta luz del cielo reciben los reflejos (0 en cuartos cerrados)
static int g_arCloudSteps = AR_CLOUD_STEPS;   // menos pasos de nubes dentro de los reflejos (mas FPS)
static float3 g_arGodRays = float3(0, 0, 0);   // rayos de sol de este pixel (se suavizan aparte)
// Luz rebotada calculada en pasos aparte (como el RTX del juego): el paso principal solo guarda donde hay que calcularla
#define AR_DEFER_GI 0
static float3 g_arGIPos = float3(0, 0, 0);
static float4 g_arGICache = float4(0, 0, 0, 0);
static bool g_arGIValid = false;
// v40: limites de seguridad para que la GPU nunca se quede trabada en un cuadro (eGPU por Thunderbolt)
#define AR_MAX_CANDIDATES   16   // hojas/vidrios revisados por rayo; despues se da por bloqueado
#define AR_MAX_CAND_PRIMARY 32   // lo mismo para el rayo de la camara (mas alto: se nota mas)
#define AR_MAX_LAYERS       16   // capas transparentes por pixel (antes 100)
#define AR_FULL_LAYERS      3    // solo las primeras capas transparentes llevan la luz mas cara
static int g_arLayer = 0;
static bool g_arInCache = false; // true en el paso que actualiza la cache por cara

float ArIGN(uint2 p) { return frac(52.9829189 * frac(0.06711056 * p.x + 0.00583715 * p.y)); }
float Bayer4(uint2 p)
{
    const float m[16] = { 0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5 };
    return (m[(p.x & 3) + (p.y & 3) * 4] + 0.5) / 16.0;
}

// Posicion "mundo" aproximada (para nubes y olas)
float3 ToWorld(float3 steveSpacePos)
{
    return steveSpacePos - g_view.waveWorksOriginInSteveSpace;
}

bool HasSun()
{
    // El color del sol puede quedar en 0 unos segundos tras /time set; las mallas del sol/luna no.
    // skyBackgroundType: 0 = mundo normal, 1 = Nether, 2 = End (medido en el juego)
    return g_view.skyBackgroundType == 0;
}

// Nether: niebla rojiza. End: niebla oscura/morada.
bool IsNether() { return g_view.skyBackgroundType == 1; }
bool IsEnd() { return g_view.skyBackgroundType == 2; }

// End: agujero negro grande con disco de luz (de ahi viene la luz calida del End)
#define AR_END_BH_DIR     normalize(float3(0.75, 1.0, 0.75))
#define AR_END_LIGHT      float3(1.0, 0.80, 0.58) * 2.4   // luz calida del agujero negro
#define AR_END_AMBIENT    float3(0.075, 0.062, 0.050)     // relleno calido (sin morado)
float BHHash(float2 i)
{
    uint2 q = uint2(int2(i) + 32768);
    uint h = q.x * 1597334677u ^ q.y * 3812015801u;
    h = (h ^ (h >> 16)) * 2246822519u;
    h ^= h >> 13;
    return float(h & 0xffffffu) / 16777215.0;
}

// ruido suave (curva de 5o grado: sin cuadros aunque hagas zoom con el catalejo)
float BHNoise(float2 p)
{
    float2 i = floor(p), f = frac(p);
    float a = BHHash(i);
    float b = BHHash(i + float2(1, 0));
    float c = BHHash(i + float2(0, 1));
    float d = BHHash(i + float2(1, 1));
    f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    return lerp(lerp(a, b, f.x), lerp(c, d, f.x), f.y);
}

// varias capas de ruido giradas entre si (detalle fino sin patron de cuadricula)
float PFbm(float2 p, int oct)
{
    float s = 0, a = 0.5, n = 0;
    for (int i = 0; i < oct; i++)
    {
        s += BHNoise(p) * a;
        n += a;
        p = float2(p.x * 1.6 - p.y * 1.2, p.x * 1.2 + p.y * 1.6) + 3.7;
        a *= 0.5;
    }
    return s / n;
}

float3 BlackHoleSky(float3 dir)
{
    float3 B = normalize(float3(0.75, 1.0, 0.75));            // misma direccion que la luz del End
    float3 up = abs(B.y) < 0.95 ? float3(0, 1, 0) : float3(1, 0, 0);
    float3 X = normalize(cross(up, B));
    float3 Y = cross(B, X);
    // coordenadas en el cielo alrededor del agujero (angulos)
    float3 rel = dir - B * dot(dir, B);
    float facing = dot(dir, B);
    float2 q = float2(dot(dir, X), dot(dir, Y)) / max(facing, 0.25);
    float nearFade = smoothstep(0.25, 0.55, facing);          // sin cortes en las puntas
    float tilt = 0.18;                                        // disco casi de canto
    float r = length(q);
    float t = g_view.time;
    float3 col = 0;

    // estrellas (con lente: se estiran alrededor del agujero)
    float3 sd = floor(normalize(dir + B * 0.06 / max(r * r, 0.01) * step(0.0, dot(dir, B))) * 460.0);
    float st = frac(sin(dot(sd, float3(12.9898, 78.233, 37.719))) * 43758.5453);
    col += step(0.997, st) * (0.4 + 0.6 * frac(st * 91.7));

    // banda del disco que cruza todo el cielo (continua, sin lineas)
    if (facing > 0.25)
    {
        float3 colIn = 0;
        const float Rs = 0.32;                                // tamano de la sombra (grande)
        // disco plano: distancia al plano y radio dentro del disco
        float h = q.y / tilt;                                 // aplastado: se ve como elipse
        float rd = length(float2(q.x, h));
        float ang = atan2(h, q.x);
        float swirl = BHNoise(float2(ang * 5.0 - t * 2.2 + rd * 3.0, rd * 6.0)) * 0.55 + BHNoise(float2(ang * 12.0 - t * 3.6, rd * 16.0)) * 0.45;
        swirl = swirl * 0.8 + BHNoise(float2(ang * 30.0 - t * 5.0, rd * 45.0)) * 0.2;   // vetas finas
        swirl = pow(swirl, 1.6) * 1.6;   // vetas con mas contraste: se nota el giro
        float doppler = 0.55 + 0.45 * sin(ang);              // un lado mas brillante (gira hacia nosotros)
        float diskMask = smoothstep(Rs * 1.05, Rs * 1.25, rd) * exp(-max(rd - Rs * 1.25, 0.0) * 0.55) * exp(-abs(q.y) * 5.5);   // disco mas grande
        float3 hot = lerp(float3(1.0, 0.55, 0.22), float3(1.0, 0.93, 0.82), saturate(1.4 - rd * 1.6));
        float3 diskCol = hot * diskMask * (0.6 + 1.2 * swirl) * (0.5 + doppler) * 3.0;
        // la mitad cercana del disco pasa POR DELANTE de la sombra (como en Interstellar)
        float frontW = smoothstep(0.004, -0.01, q.y);
        float3 diskFront = diskCol * frontW;
        colIn += diskCol * (1.0 - frontW);
        // disco doblado por la gravedad: arco que pasa por arriba y por abajo de la sombra
        float upness = q.y / max(r, 1e-3);
        float lensTop = exp(-pow((r - Rs * 1.20) * 7.0, 2.0)) * smoothstep(-0.25, 0.55, upness);          // arco grueso arriba
        float lensBot = exp(-pow((r - Rs * 1.10) * 22.0, 2.0)) * smoothstep(0.1, -0.6, upness) * 0.7;    // arco fino abajo
        float lensSw = BHNoise(float2(atan2(q.y, q.x) * 10.0 - t * 2.5, r * 20.0));
        colIn += float3(1.0, 0.86, 0.66) * (lensTop + lensBot) * (0.6 + 0.9 * lensSw) * 2.6 * (0.7 + 0.5 * doppler);
        // anillo de fotones (fino y muy brillante)
        float ringAng = atan2(q.y, q.x);
        float streak = BHNoise(float2(ringAng * 18.0 + t * 2.2, r * 40.0)) * 0.7 + BHNoise(float2(ringAng * 40.0 - t * 3.5, 3.0)) * 0.3;
        float dopRing = 0.6 + 0.4 * sin(ringAng + 0.6);
        colIn += float3(1.0, 0.97, 0.92) * exp(-pow((r - Rs * 1.025) * 110.0, 2.0)) * 6.0 * dopRing;
        colIn += float3(1.0, 0.82, 0.55) * exp(-pow((r - Rs * 1.07) * 35.0, 2.0)) * (0.8 + 1.6 * streak) * dopRing;
        // resplandor grande alrededor
        colIn += float3(0.95, 0.78, 0.58) * exp(-max(r - Rs, 0.0) * 2.2) * 0.45;
        // banda del disco que cruza el cielo
        colIn *= nearFade;
        // sombra negra
        float shadow = smoothstep(Rs * 0.97, Rs * 1.0, r);
        col = (col + colIn) * lerp(1.0, shadow, nearFade) + diskFront * nearFade;
    }
    return col;
}

// Portal del End: espacio con estrellas en capas (se mueven con la vista, con profundidad)
float3 PortalSpace(float3 wp, float3 viewDir)
{
    float3 c = float3(0.004, 0.010, 0.016);
    float2 par = viewDir.xz / max(-viewDir.y, 0.15);
    float t = g_view.time;
    [unroll] for (int k = 0; k < 4; k++)
    {
        float depth = 1.5 + k * 3.0;
        float2 p = wp.xz + par * depth + float2(t * 0.02, t * 0.013) * (k + 1);
        float sc = 6.0 + k * 3.0;
        float2 cell = floor(p * sc);
        float h = Hash12(cell + k * 31.7);
        float2 sp = frac(p * sc) - 0.5;
        float star = step(0.93, h) * exp(-dot(sp, sp) * 60.0) * (0.6 + 0.4 * sin(t * 3.0 + h * 50.0));
        float3 sc3 = lerp(float3(0.6, 0.85, 1.0), float3(1.0, 0.85, 0.6), frac(h * 13.0));
        c += sc3 * star * (1.6 - k * 0.3);
        // nebulosa suave en el fondo
        c += float3(0.05, 0.18, 0.20) * pow(BHNoise(p * 0.8 + k), 3.0) * 0.25;
    }
    c += float3(0.12, 0.05, 0.20) * pow(BHNoise(wp.xz * 0.5 + par * 6.0 + t * 0.05), 4.0) * 0.4;
    return c;
}

// Planetas lejanos del End: giran sobre si mismos, se mueven despacio alrededor del agujero negro y tienen lunas
void EndBasis(float3 C, out float3 X, out float3 Y)
{
    X = normalize(cross(abs(C.y) < 0.95 ? float3(0, 1, 0) : float3(1, 0, 0), C));
    Y = cross(C, X);
}

// Esfera iluminada por el agujero negro. spin = vueltas por segundo de la textura
// Planetas reales y famosos (tipo):
// 0 Jupiter  1 Saturno  2 Tierra  3 Marte  4 gigante de hielo (Neptuno/Urano)  5 Venus
// 6 55 Cancri e (mundo de lava)  7 TrES-2b (el planeta mas oscuro)  8 HD 189733b (azul cobalto, lluvia de vidrio)  9 luna rocosa
float3 PlanetSurface(int type, float lon, float lat, float lit, float seed, float3 colA, float3 colB, out float3 glow)
{
    glow = 0;
    float2 uv = float2(lon, lat);
    float t = g_view.time;
    if (type == 0 || type == 1)
    {
        // bandas con bordes turbulentos
        float turb = PFbm(float2(lon * 2.0, lat * 9.0) + seed, 6);
        float fine = PFbm(float2(lon * 7.0, lat * 30.0) - seed, 5);
        float b = lat * (type == 0 ? 11.0 : 15.0) + turb * 2.2 + fine * 0.4;
        float3 cream = type == 0 ? float3(0.94, 0.88, 0.76) : float3(0.93, 0.86, 0.66);
        float3 tan   = type == 0 ? float3(0.82, 0.60, 0.40) : float3(0.84, 0.72, 0.50);
        float3 brown = type == 0 ? float3(0.52, 0.33, 0.22) : float3(0.70, 0.58, 0.40);
        float3 c = lerp(cream, tan, 0.5 + 0.5 * sin(b));
        c = lerp(c, brown, pow(saturate(0.5 + 0.5 * sin(b * 0.5 + 1.3)), 3.0) * (type == 0 ? 0.8 : 0.35));
        c *= 0.88 + 0.25 * fine;
        if (type == 0)
        {
            // Gran Mancha Roja (con remolino)
            float2 sp = float2(frac((lon + 1.2) / 6.2832) * 6.2832 - 3.1416, (lat + 0.38) * 2.6);
            float r = length(sp * float2(1.0, 1.6));
            float sw = PFbm(float2(atan2(sp.y, sp.x) * 2.0 + r * 6.0, r * 8.0), 4);
            float spot = (1.0 - smoothstep(0.18, 0.30, r)) ;
            c = lerp(c, lerp(float3(0.78, 0.36, 0.22), float3(0.90, 0.55, 0.35), sw), spot);
        }
        return c;
    }
    if (type == 2)
    {
        // Tierra: oceanos, continentes, desiertos, hielo en los polos y nubes que giran
        float land = PFbm(uv * float2(1.4, 2.4) + seed, 7);
        float det = PFbm(uv * float2(6.0, 10.0) + seed * 1.7, 5);
        float3 ocean = lerp(float3(0.02, 0.10, 0.30), float3(0.04, 0.22, 0.45), det);
        float3 green = lerp(float3(0.12, 0.30, 0.10), float3(0.30, 0.38, 0.16), det);
        float3 desert = float3(0.70, 0.58, 0.38);
        float dry = smoothstep(0.45, 0.65, PFbm(uv * 3.0 - seed, 4)) * (1.0 - smoothstep(0.35, 0.7, abs(lat)));
        float3 ground = lerp(green, desert, dry);
        float isLand = smoothstep(0.53, 0.56, land);
        float3 c = lerp(ocean, ground, isLand);
        c = lerp(c, float3(0.92, 0.95, 1.0), smoothstep(0.80, 0.88, abs(lat) + det * 0.06));
        float cl = PFbm(float2(lon * 2.5 + t * 0.006, lat * 4.5) + seed * 3.0, 6);
        c = lerp(c, float3(0.97, 0.97, 0.97), smoothstep(0.52, 0.72, cl) * 0.85);
        // luces de ciudades en el lado de noche
        float city = step(0.86, BHNoise(uv * float2(60.0, 90.0))) * isLand * (1.0 - smoothstep(0.5, 0.75, cl));
        glow = float3(1.0, 0.70, 0.35) * city * saturate(1.0 - lit * 4.0) * 0.6;
        return c;
    }
    if (type == 3)
    {
        // Marte: rojo oxido, zonas oscuras, casquete polar
        float n = PFbm(uv * float2(2.5, 4.0) + seed, 7);
        float3 c = lerp(float3(0.42, 0.20, 0.12), float3(0.78, 0.40, 0.22), smoothstep(0.35, 0.65, n));
        c *= 0.85 + 0.3 * PFbm(uv * 14.0, 4);
        c = lerp(c, float3(0.95, 0.93, 0.90), smoothstep(0.86, 0.92, lat + n * 0.05));
        return c;
    }
    if (type == 4 || type == 8)
    {
        // gigantes de hielo / HD 189733b: color profundo, nubes alargadas por el viento
        float b = PFbm(float2(lon * 1.5, lat * 6.0) + seed, 5);
        float3 c = lerp(colA, colB, b * 0.6);
        float streak = PFbm(float2(lon * 1.2 + t * 0.01, lat * 40.0) + seed * 2.0, 5);
        c = lerp(c, float3(0.92, 0.96, 1.0), smoothstep(0.62, 0.80, streak) * (type == 8 ? 0.55 : 0.35));
        if (type == 4)
        {
            float2 sp = float2(frac((lon + seed) / 6.2832) * 6.2832 - 3.1416, (lat + 0.25) * 3.0);
            c = lerp(c, colA * 0.35, 1.0 - smoothstep(0.15, 0.26, length(sp * float2(1.0, 1.4))));   // gran mancha oscura
        }
        return c;
    }
    if (type == 5)
    {
        // Venus: nubes amarillentas en forma de V
        float n = PFbm(float2(lon * 3.0 + abs(lat) * 2.5, lat * 5.0) + seed, 7);
        return lerp(float3(0.82, 0.66, 0.40), float3(0.98, 0.90, 0.68), n);
    }
    if (type == 6)
    {
        // 55 Cancri e: corteza oscura partida y lava que brilla aunque sea de noche
        float n = PFbm(uv * float2(3.0, 5.0) + seed, 6);
        float ridge = 1.0 - abs(PFbm(uv * float2(5.0, 8.0) - seed, 6) * 2.0 - 1.0);
        float lava = pow(saturate(ridge), 10.0);
        glow = lerp(float3(1.0, 0.25, 0.04), float3(1.0, 0.75, 0.30), lava) * lava * (1.4 + 0.4 * sin(t * 0.8 + n * 12.0));
        return lerp(float3(0.06, 0.05, 0.05), float3(0.16, 0.10, 0.08), n);
    }
    if (type == 7)
    {
        // TrES-2b: casi negro (refleja menos del 1% de la luz), brillo rojizo tenue
        float n = PFbm(uv * float2(2.0, 6.0) + seed, 5);
        glow = float3(0.06, 0.012, 0.008) * (0.6 + 0.4 * n);
        return float3(0.018, 0.016, 0.02) * (0.8 + 0.4 * n);
    }
    // luna rocosa con crateres
    float n = PFbm(uv * float2(4.0, 6.0) + seed, 6);
    float cr = 1.0 - abs(PFbm(uv * 12.0 + seed * 3.0, 4) * 2.0 - 1.0);
    float3 c = lerp(colA, colB, n) * (0.85 + 0.25 * cr);
    return c;
}

float4 EndSphere(float3 dir, float3 C, float rad, int type, float3 colA, float3 colB, float spin, float seed)
{
    float f = dot(dir, C);
    if (f < 0.9) return 0;
    float3 X, Y;
    EndBasis(C, X, Y);
    float2 q = float2(dot(dir, X), dot(dir, Y)) / f / rad;
    float r2 = dot(q, q);
    float3 B = AR_END_BH_DIR;
    float3 atm = type == 2 ? float3(0.45, 0.70, 1.0) : (type == 3 ? float3(0.9, 0.55, 0.40) : (type == 6 ? float3(1.0, 0.45, 0.15) : lerp(colB, float3(0.9, 0.95, 1.0), 0.5)));
    if (r2 >= 1.0)
    {
        // halo de atmosfera (del lado iluminado)
        if (r2 > 1.35 || rad < 0.02 || type == 9 || type == 7) return 0;
        float3 nE = normalize(X * q.x + Y * q.y);
        float h = saturate(dot(nE, B) * 0.7 + 0.3);
        float g = pow(saturate(1.0 - (sqrt(r2) - 1.0) / 0.14), 2.2) * h;
        return float4(atm * 0.5, g * 0.35);
    }
    float z = sqrt(1.0 - r2);
    float3 nrm = normalize(X * q.x + Y * q.y - C * z);
    float ndl = dot(nrm, B);
    float lit = smoothstep(-0.10, 0.55, ndl) * 0.95 + 0.02;   // terminador suave
    float lon = atan2(q.x, z) + g_view.time * spin;           // gira sobre su eje
    float lat = q.y;
    float3 glow;
    float3 tex = PlanetSurface(type, lon, lat, lit, seed, colA, colB, glow);
    float limb = pow(z, 0.35);
    float3 pc = tex * (lit * 0.62 * limb + 0.008) + glow;
    if (type == 2) pc += float3(1.0, 0.95, 0.85) * pow(saturate(dot(nrm, normalize(B - C))), 60.0) * 0.25 * saturate(ndl);   // brillo del oceano
    pc += atm * pow(1.0 - z, 3.0) * saturate(ndl + 0.2) * (type == 9 ? 0.0 : 0.22);
    return float4(pc, 1.0 - smoothstep(0.985, 1.0, r2));
}

// Anillos. style: 0 Saturno (con division de Cassini)  1 finos (Urano)  2 gigantes (J1407b)
float4 EndRing(float3 dir, float3 C, float rad, float ringR, float tilt, int style, float spin, float seed, float front)
{
    float f = dot(dir, C);
    if (f < 0.85 || ringR <= 0.0) return 0;
    float3 X, Y;
    EndBasis(C, X, Y);
    float2 q = float2(dot(dir, X), dot(dir, Y)) / f / rad;
    if ((q.y <= 0.0) != (front > 0.5)) return 0;
    float2 rq = float2(q.x, q.y / tilt);
    float rr = length(rq) / ringR;                 // 0..1 dentro del sistema de anillos
    float inner = style == 2 ? 0.18 : 0.60;
    if (rr < inner || rr > 1.0) return 0;
    float u = (rr - inner) / (1.0 - inner);
    float ang = atan2(rq.y, rq.x) + g_view.time * spin;
    float fineB = PFbm(float2(u * 60.0, 0.5 + seed), 4);
    float dens, a;
    float3 col;
    if (style == 0)
    {
        dens = 0.55 + 0.45 * fineB;
        dens *= 1.0 - (1.0 - smoothstep(0.0, 0.025, abs(u - 0.62))) * 0.92;   // division de Cassini
        dens *= lerp(0.45, 1.0, smoothstep(0.0, 0.35, u));                     // anillo C (tenue)
        col = lerp(float3(0.75, 0.66, 0.52), float3(0.95, 0.88, 0.74), fineB);
        a = 0.85;
    }
    else if (style == 1)
    {
        dens = 0;
        [unroll] for (int k = 0; k < 4; k++) dens += exp(-pow((u - (0.25 + k * 0.22)) * 90.0, 2.0));
        col = float3(0.55, 0.60, 0.65);
        a = 0.6;
    }
    else
    {
        dens = (0.35 + 0.65 * fineB) * (0.6 + 0.4 * sin(u * 70.0 + seed));
        dens *= 1.0 - (1.0 - smoothstep(0.0, 0.03, abs(u - 0.45))) * 0.95;   // hueco que abrio una luna
        dens *= 1.0 - (1.0 - smoothstep(0.0, 0.02, abs(u - 0.72))) * 0.9;
        col = lerp(float3(0.85, 0.55, 0.35), float3(0.95, 0.85, 0.70), u);
        a = 0.55;
    }
    dens *= 0.85 + 0.15 * BHNoise(float2(ang * 6.0, u * 30.0));
    float lightR = saturate(dot(normalize(X * q.x + Y * q.y), AR_END_BH_DIR) * 0.4 + 0.6);
    return float4(col * 0.42 * lightR, saturate(dens * a));
}

// colores de las lunas (Io, Europa, Ganimedes, Calisto, Titan, Triton...)
void MoonColors(int idx, out float3 a, out float3 b)
{
    if (idx == 0) { a = float3(0.85, 0.75, 0.35); b = float3(0.95, 0.88, 0.55); }        // Io (azufre)
    else if (idx == 1) { a = float3(0.80, 0.76, 0.68); b = float3(0.95, 0.93, 0.88); }   // Europa (hielo)
    else if (idx == 2) { a = float3(0.45, 0.42, 0.38); b = float3(0.70, 0.66, 0.60); }   // Ganimedes
    else if (idx == 3) { a = float3(0.25, 0.23, 0.22); b = float3(0.45, 0.42, 0.40); }   // Calisto
    else if (idx == 4) { a = float3(0.75, 0.50, 0.20); b = float3(0.90, 0.68, 0.35); }   // Titan (neblina naranja)
    else if (idx == 5) { a = float3(0.70, 0.66, 0.68); b = float3(0.90, 0.85, 0.85); }   // Triton
    else if (idx == 6) { a = float3(0.45, 0.35, 0.30); b = float3(0.60, 0.50, 0.42); }   // Fobos / Deimos
    else { a = float3(0.50, 0.50, 0.50); b = float3(0.78, 0.78, 0.76); }                 // Luna
}

float3 EndPlanetSystem(float3 dir, float3 c, float3 C0, float rad, int type, float3 colA, float3 colB,
                       float ringR, float tilt, int ringStyle, float seed, int moons, int moonSet)
{
    rad *= 1.25;
    float t = g_view.time;
    // dan la vuelta despacio a tu alrededor (eje vertical)
    float orb = t * 0.004 * (0.6 + frac(seed * 0.37));
    float3 A = float3(0, 1, 0);
    float co = cos(orb), so = sin(orb);
    float3 C = normalize(C0 * co + cross(A, C0) * so + A * dot(A, C0) * (1.0 - co));
    if (dot(dir, C) < 0.80) return c;
    float3 X, Y;
    EndBasis(C, X, Y);
    float spin = 0.02 + 0.02 * frac(seed * 0.71);
    float4 m;
    float3 ma3, mb3;
    // lunas que pasan por detras
    for (int i = 0; i < moons; i++)
    {
        float ma = t * (0.05 + 0.03 * i) + seed * 2.0 + i * 2.1;
        float mr = rad * (2.2 + 1.0 * i);
        if (sin(ma) > 0.0)
        {
            float3 MC = normalize(C + (X * cos(ma) + Y * sin(ma) * 0.30) * mr);
            MoonColors(moonSet + i, ma3, mb3);
            m = EndSphere(dir, MC, rad * (0.17 - 0.02 * i), 9, ma3, mb3, 0.03, seed + i * 5.0);
            c = lerp(c, m.rgb, m.a);
        }
    }
    m = EndRing(dir, C, rad, ringR, tilt, ringStyle, 0.04, seed, 0.0);  c = lerp(c, m.rgb, m.a);
    m = EndSphere(dir, C, rad, type, colA, colB, spin, seed);           c = lerp(c, m.rgb, m.a);
    m = EndRing(dir, C, rad, ringR, tilt, ringStyle, 0.04, seed, 1.0);  c = lerp(c, m.rgb, m.a);
    // lunas que pasan por delante
    for (int j = 0; j < moons; j++)
    {
        float ma = t * (0.05 + 0.03 * j) + seed * 2.0 + j * 2.1;
        float mr = rad * (2.2 + 1.0 * j);
        if (sin(ma) <= 0.0)
        {
            float3 MC = normalize(C + (X * cos(ma) + Y * sin(ma) * 0.30) * mr);
            MoonColors(moonSet + j, ma3, mb3);
            m = EndSphere(dir, MC, rad * (0.17 - 0.02 * j), 9, ma3, mb3, 0.03, seed + j * 5.0);
            c = lerp(c, m.rgb, m.a);
        }
    }
    return c;
}

// Nebulosa de fondo (nubes de gas de colores, tenues)
float3 EndNebula(float3 dir)
{
    float t = g_view.time * 0.012;
    float2 w = float2(sin(t * 0.7), cos(t * 0.5)) * 0.6;
    float n1 = Fbm(float2(dir.x * 2.2 + dir.y * 0.7, dir.z * 2.2 - dir.y * 0.9) + 3.1 + w);
    float n2 = Fbm(float2(dir.y * 2.6 + dir.z * 0.8, dir.x * 2.4 - dir.z * 0.5) + 8.7 - w * 0.8);
    float n3 = Fbm(float2(dir.z * 3.5 - dir.x, dir.y * 3.5 + dir.x * 0.6) + 1.7 + float2(t, -t) * 0.9);
    float h = t * 0.35;
    float3 cA = lerp(float3(0.10, 0.32, 0.45), float3(0.12, 0.40, 0.30), 0.5 + 0.5 * sin(h));
    float3 cB = lerp(float3(0.42, 0.14, 0.32), float3(0.25, 0.12, 0.45), 0.5 + 0.5 * sin(h * 1.3 + 2.0));
    float3 cC = lerp(float3(0.50, 0.26, 0.10), float3(0.45, 0.12, 0.10), 0.5 + 0.5 * sin(h * 0.8 + 4.0));
    float3 c = cA * pow(saturate(n1 * 1.25 - 0.15), 3.0)
             + cB * pow(saturate(n2 * 1.25 - 0.20), 3.0)
             + cC * pow(saturate(n3 * 1.2 - 0.25), 3.0) * 0.7;
    c *= 0.55 + 0.45 * saturate(Fbm(float2(dir.x * 5.0 - dir.z, dir.y * 5.0 + dir.z * 2.0) - w * 0.5) * 1.6);
    return c * 0.35;
}

// Galaxia lejana: quieta en el cielo, solo gira sobre su eje (como un spinner)
float3 EndGalaxy(float3 dir)
{
    float3 G = normalize(float3(-0.707, 0.45, -0.707));
    float f = dot(dir, G);
    if (f < 0.40) return 0;
    float3 X, Y;
    EndBasis(G, X, Y);
    float2 q = float2(dot(dir, X), dot(dir, Y)) / f;
    float ca = cos(0.6), sa = sin(0.6);
    q = float2(q.x * ca - q.y * sa, q.x * sa + q.y * ca);
    q.y /= 0.45;
    float rr = length(q) / 0.78;
    if (rr > 1.6) return 0;
    // gira sobre si misma (como un spinner)
    float spn = g_view.time * 0.06;
    float cs = cos(spn), sn = sin(spn);
    float2 qr = float2(q.x * cs + q.y * sn, -q.x * sn + q.y * cs) / 0.78;
    float ang = atan2(qr.y, qr.x);
    float spiral = 2.0 * ang - log(rr + 0.04) * 4.5;
    float arms = pow(saturate(0.5 + 0.5 * cos(spiral)), 2.0);
    float lane = pow(saturate(0.5 + 0.5 * cos(spiral - 0.75)), 7.0) * saturate(rr * 3.0);
    float clump = BHNoise(qr * 22.0) * 0.7 + BHNoise(qr * 60.0) * 0.3;
    float disk = exp(-rr * 2.4) * (0.22 + 1.0 * arms * (0.75 + 0.35 * clump)) * (1.0 - 0.5 * lane);
    float core = exp(-rr * rr * 45.0) * 1.8 + exp(-rr * 8.0) * 0.35;
    // v47: estrellas redondas y difuminadas (con catalejo se veian cuadradas)
    float2 sgp = qr * 300.0;
    float2 scell = floor(sgp);
    float2 soff = float2(Hash12(scell + 7.13), Hash12(scell + 3.71)) * 0.5 + 0.25;
    float2 sdv = frac(sgp) - soff;
    float stars = step(0.93, Hash12(scell)) * exp(-dot(sdv, sdv) * 14.0) * 2.2 * (0.3 + arms) * exp(-rr * 1.5);
    float3 c = float3(0.50, 0.66, 1.0) * disk + float3(1.0, 0.84, 0.62) * (core + disk * 0.35)
             + float3(0.9, 0.95, 1.0) * stars * 0.8;   // v46: sin nudos rosas (de lejos parecian cuadros)
    return c * 0.55 * saturate(1.6 - rr);
}

// Sombra del agujero negro (1 = dentro de la parte negra)
float BHShadow(float3 dir)
{
    float3 B = AR_END_BH_DIR;
    float facing = dot(dir, B);
    if (facing <= 0.25) return 0;
    float3 X, Y;
    X = normalize(cross(float3(0, 1, 0), B));
    Y = cross(B, X);
    float r = length(float2(dot(dir, X), dot(dir, Y)) / facing);
    return 1.0 - smoothstep(0.32 * 0.97, 0.32, r);
}

// Direccion en el cielo del lado opuesto al agujero negro (ax, ay = separacion del centro)
float3 EndOpp(float ax, float ay)
{
    float3 A = -AR_END_BH_DIR;
    float3 X, Y;
    EndBasis(A, X, Y);
    return normalize(A + X * ax + Y * ay);
}

float3 EndSky(float3 dir)
{
    float3 c = BlackHoleSky(dir) * 1.2;
    float bhS = BHShadow(dir);
    c += EndNebula(dir) * (1.0 - saturate(Luma(c) * 2.0)) * (1.0 - bhS);   // nebulosa detras (nunca dentro de la sombra)
    c += EndGalaxy(dir) * (1.0 - bhS);
    // planetas reales y famosos, repartidos por todo el cielo (lejos del agujero negro)
    //                                 direccion                 tamano tipo  color A                    color B                  anillo  inclin. estilo semilla lunas grupo
    c = EndPlanetSystem(dir, c, float3( 0.00,  0.82, -0.57), 0.064, 0, 0, 0, 0.0, 1.0, 0, 21.0, 4, 0);   // Jupiter + Io, Europa, Ganimedes, Calisto
    c = EndPlanetSystem(dir, c, float3(-0.41, -0.77, -0.49), 0.060, 1, 0, 0, 2.3, 0.30, 0, 23.0, 2, 4);  // Saturno + Titan
    c = EndPlanetSystem(dir, c, float3(-0.47,  0.87,  0.17), 0.026, 1, 0, 0, 7.0, 0.42, 2, 1.0, 0, 0);   // J1407b (anillos gigantes)
    c = EndPlanetSystem(dir, c, float3( 0.60, -0.77, -0.22), 0.034, 4, float3(0.10, 0.22, 0.75), float3(0.30, 0.50, 0.95), 0.0, 1.0, 0, 3.0, 1, 5);   // Neptuno + Triton
    c = EndPlanetSystem(dir, c, float3(-0.77, -0.57,  0.28), 0.024, 3, 0, 0, 0.0, 1.0, 0, 5.0, 2, 6);   // Marte + Fobos, Deimos
    c = EndPlanetSystem(dir, c, float3(-0.34,  0.00, -0.94), 0.044, 2, 0, 0, 0.0, 1.0, 0, 7.0, 1, 7);   // Tierra + Luna
    c = EndPlanetSystem(dir, c, float3( 0.33, -0.26,  0.91), 0.024, 7, 0, 0, 0.0, 1.0, 0, 9.0, 0, 0);   // TrES-2b (el mas oscuro)
    c = EndPlanetSystem(dir, c, float3( 0.78,  0.42, -0.45), 0.040, 4, float3(0.45, 0.78, 0.82), float3(0.65, 0.90, 0.92), 1.9, 0.65, 1, 11.0, 0, 0);   // Urano (anillos finos)
    c = EndPlanetSystem(dir, c, float3(-0.49,  0.17,  0.85), 0.034, 5, 0, 0, 0.0, 1.0, 0, 13.0, 0, 0);  // Venus
    c = EndPlanetSystem(dir, c, float3(-0.97,  0.17, -0.17), 0.026, 6, 0, 0, 0.0, 1.0, 0, 15.0, 0, 0);  // 55 Cancri e (lava)
    c = EndPlanetSystem(dir, c, float3( 0.48, -0.26, -0.84), 0.036, 8, float3(0.06, 0.18, 0.62), float3(0.15, 0.35, 0.85), 0.0, 1.0, 0, 17.0, 0, 0);  // HD 189733b (azul cobalto)
    return c;
}

float DayFactor()
{
    return saturate((getTrueDirectionToSun().y + 0.12) / 0.38);
}

float SunsetFactor()
{
    float y = getTrueDirectionToSun().y;
    return saturate(1.0 - abs(y) * 4.0) * saturate((y + 0.25) * 4.0);
}

// Color de la luz principal (sol o luna), en lineal, ya con intensidad
float3 PrimaryLightColor(out float3 L)
{
    L = normalize(g_view.directionToSun);
    if (IsEnd()) { L = AR_END_BH_DIR; return AR_END_LIGHT; }
    if (!HasSun()) return 0;
    float elev = smoothstep(-0.02, 0.18, L.y);
    if (isMoonPrimaryLight())
        return float3(0.55, 0.68, 1.0) * AR_MOON_STRENGTH * elev;
    float warm = smoothstep(0.0, 0.45, L.y);
    float3 c = lerp(float3(1.0, 0.45, 0.16), float3(1.0, 0.94, 0.85), warm);
    return c * AR_SUN_STRENGTH * elev * (1.0 - ArRainLevel() * 0.85);
}

// Destello de rayo: el juego aclara el color del cielo cuando cae un rayo en tormenta
float LightningFlash()
{
#if AR_LIGHTNING
    if (!HasSun() || ArRainLevel() < 0.3) return 0.0;
    float sky = Luma(min(g_view.skyColor, 1.0));
    float base = lerp(0.05, 0.30, DayFactor());
    return saturate((sky - base - 0.08) * 5.0) * ArRainLevel();
#else
    return 0.0;
#endif
}

// Luz del rayo dentro de la nube: una franja brillante que barre el cielo
float3 LightningCloudLight(float3 wp, float3 camW)
{
    float f = LightningFlash();
    if (f <= 0.0) return 0;
    float t = g_view.time;
    float ang = floor(t * 0.5) * 2.3999;            // cada destello viene de otra direccion
    float2 dirF = float2(cos(ang), sin(ang));
    float sweep = frac(t * 1.7) * 1400.0 - 700.0;   // la luz recorre el cielo
    float d = dot(wp.xz - camW.xz, dirF) - sweep;
    float band = exp(-d * d / 60000.0);
    return float3(0.75, 0.80, 1.0) * f * (0.4 + 3.0 * band) * 6.0;
}

// ---------------------------------------------------------------------
// Nubes volumetricas
// v82: la altura que da ToWorld() "da la vuelta" cada 1024 bloques (medido con la v81: a la altura real 1045 daba 22).
// El pase final calcula la altura real una vez (rayo hacia abajo hasta el suelo) y deja aqui el desplazamiento de la capa
// de nubes, en las mismas coordenadas que usa ToWorld().
static float g_arCloudOff = 0.0;
float ArCloudOff()
{
    return g_arCloudOff;
}

float CloudDensity(float3 wp)
{
    float h = saturate((wp.y - AR_CLOUD_BASE) / (AR_CLOUD_TOP - AR_CLOUD_BASE));
    float profile = saturate(h * 5.0) * saturate((1.0 - h) * 2.2);
    // El reloj g_view.time se reinicia al reaparecer; la hora del dia no. Se usan los dos
    // para que las nubes no vuelvan siempre a la misma posicion y tamano.
    float3 sd = getTrueDirectionToSun();
    float dayAngle = atan2(sd.x, sd.y); // salta solo a medianoche
    float2 wind = float2(1.0, 0.35) * (dayAngle * 320.0);   // solo hora del mundo: al morir no se reinician
    float coverage = saturate(AR_CLOUD_COVERAGE + 0.12 * sin(dayAngle * 3.0 + 1.3) + ArRainLevel() * 0.22);
    float base = Fbm((wp.xz + wind) * (0.0045 / AR_CLOUD_SIZE));
    float shape = saturate((base - (1.0 - coverage)) * 3.6);
    float detail = Fbm((wp.xz + wind * 1.7) * (0.03 / AR_CLOUD_SIZE) + wp.y * 0.008);
    return saturate(shape * profile * 1.4 - detail * 0.35);
}

float CloudShadow(float3 wp, float3 L)
{
#if AR_CLOUDS && AR_CLOUD_SHADOWS
    if (!HasSun() || L.y < 0.03) return 1.0;
    float midY = lerp(AR_CLOUD_BASE, AR_CLOUD_TOP, 0.4);
    float t = (midY - wp.y) / L.y;
    if (t < 0) return 1.0;
    float d = CloudDensity(wp + L * t);
    return lerp(1.0, 0.18, saturate(d * 2.5));
#else
    return 1.0;
#endif
}

float3 SkyAmbientColor(float3 n)
{
    float day = DayFactor();
    float sunset = SunsetFactor();
    float3 dayUp = float3(0.30, 0.42, 0.68);
    float3 nightUp = float3(0.011, 0.015, 0.032);   // v48: noche mas oscura
    float3 up = lerp(nightUp, dayUp, day) + float3(0.20, 0.08, 0.02) * sunset;
    up *= (1.0 - ArRainLevel() * lerp(0.15, 0.40, DayFactor()));   // de noche la lluvia ya no oscurece tanto
    float3 down = up * 0.40;
    float3 c = lerp(down, up, saturate(n.y * 0.5 + 0.5));
    if (!HasSun())
    {
        // Nether: luz rojiza de la niebla. End: luz morada tenue.
        if (IsNether())
            c = ToLinear(min(g_view.skyColor, 1.0)) * 0.9 + float3(0.04, 0.018, 0.01);
        else
            c = AR_END_AMBIENT * lerp(0.6, 1.0, saturate(n.y * 0.5 + 0.5));
    }
    return c;
}

// v78: biomas nevados. El Aurora Pack pone en la niebla de esos biomas una absorcion azul diminuta
// (0, 0, 0.00031) que no se nota a la vista: es la "senal" para dibujar auroras boreales.
float ArSnowBiome()
{
    float3 a = g_view.primaryMediaAbsorption;
    return smoothstep(0.00018, 0.00026, a.b) * (1.0 - smoothstep(0.00036, 0.00044, a.b)) * step(a.r + a.g, 0.00005);
}

#define AR_AURORA_K   0.045   // v78: brillo de la aurora boreal
float3 ArAurora(float3 dir)
{
    if (dir.y < 0.02) return 0;
    float t = g_view.time;
    float3 sum = 0;
    [loop]
    for (int i = 0; i < 10; i++)
    {
        float h = (i + 0.5) / 10.0;
        float2 p = dir.xz / dir.y * (1.0 + h * 0.9) * 2.2;
        float warp = Fbm(p * 0.45 + float2(t * 0.015, -t * 0.01)) * 7.0;
        float rib = 1.0 - abs(sin(p.x * 0.9 + p.y * 0.35 + warp));
        rib = pow(rib, 10.0) * (0.55 + 0.9 * Fbm(p * 1.6 + t * 0.03));
        float3 c = lerp(float3(0.10, 1.00, 0.45), float3(0.55, 0.20, 0.95), smoothstep(0.35, 1.0, h));
        sum += c * rib * pow(1.0 - h, 1.5);
    }
    return sum / 10.0 * AR_AURORA_K * smoothstep(0.02, 0.25, dir.y);
}

// v78: arcoiris con lluvia de dia (a 42 grados del punto opuesto al sol)
float3 ArRainbow(float3 dir, float3 sunDir)
{
    float rain = ArRainLevel();
    if (rain < 0.05 || sunDir.y < 0.0 || dir.y < 0.0) return 0;
    float ang = degrees(acos(clamp(dot(dir, -sunDir), -1.0, 1.0)));
    float x = (ang - 40.0) / 3.0;            // 0 = violeta (adentro), 1 = rojo (afuera)
    if (x < 0.0 || x > 1.0) return 0;
    float hh = 1.0 - x;
    float3 spec = saturate(float3(abs(hh * 6.0 - 3.0) - 1.0, 2.0 - abs(hh * 6.0 - 2.0), 2.0 - abs(hh * 6.0 - 4.0)));
    float band = sin(x * 3.14159);
    return spec * band * 0.75 * smoothstep(0.05, 0.6, rain) * saturate(sunDir.y * 6.0) * saturate(dir.y * 8.0);
}

// Cielo base (sin nubes), en lineal
float3 SkyBase(float3 dir)
{
    float3 sunDir = getTrueDirectionToSun();
    float3 moonDir = getTrueDirectionToMoon();
    float day = DayFactor();
    float sunset = SunsetFactor();

    float h = saturate(dir.y);
    float grad = pow(1.0 - h, 3.2);

    float3 zenithDay  = ToLinear(float3(0.22, 0.45, 0.92));
    float3 horizonDay = ToLinear(float3(0.66, 0.82, 1.00));
    float3 zenithNight  = float3(0.0014, 0.0028, 0.0085);   // v48: cielo de noche mas oscuro
    float3 horizonNight = float3(0.0056, 0.0085, 0.020);

    float3 col = lerp(lerp(zenithNight, horizonNight, grad), lerp(zenithDay, horizonDay, grad), day);

    float sunDot = saturate(dot(dir, sunDir));
    float3 sunsetCol = float3(1.0, 0.30, 0.07);
    float horizonBand = pow(1.0 - h, 5.0);
    col += sunsetCol * sunset * (horizonBand * (0.30 + 0.9 * pow(sunDot, 4.0)) + pow(sunDot, 24.0) * 0.5);
    col += float3(1.0, 0.80, 0.50) * pow(sunDot, 64.0) * 0.25 * day;

    float moonDot = saturate(dot(dir, moonDir));
    col += float3(0.10, 0.16, 0.35) * pow(moonDot, 64.0) * 0.25 * (1.0 - day);

    if (dir.y > 0.02)
    {
        float3 cell = floor(dir * 220.0);
        float s = Hash13(cell);
        float star = step(0.9965, s) * (0.5 + 0.5 * Hash13(cell + 7.7));
        col += star * (1.0 - day) * saturate(dir.y * 4.0) * float3(0.8, 0.85, 1.0);
    }
    if (HasSun() && day < 0.6) { float snow = ArSnowBiome(); if (snow > 0.0) col += ArAurora(dir) * snow * (1.0 - day / 0.6) * (1.0 - ArRainLevel()); }

#if AR_HYB_NO_SUNMESH
    // v72: discos propios del sol y la luna, "en el infinito" (no cambian de tamano al subir)
    if (dir.y > -0.05)
    {
        float sd = dot(dir, sunDir);
        col += float3(1.0, 0.92, 0.80) * 60.0 * smoothstep(0.99985, 0.99992, sd) * saturate(sunDir.y * 20.0 + 1.0);
        float md = dot(dir, moonDir);
        float mdisk = smoothstep(0.99975, 0.99983, md);
        // poco de textura en la luna (manchas)
        float3 mt = normalize(cross(moonDir, float3(0.31, 0.95, 0.07)));
        float3 mb = cross(moonDir, mt);
        float2 muv = float2(dot(dir, mt), dot(dir, mb)) * 900.0;
        float maria = Fbm(muv * 0.7 + 3.1);
        col += float3(0.80, 0.84, 0.95) * lerp(1.1, 0.6, smoothstep(0.45, 0.7, maria)) * 1.6 * mdisk;
        col += float3(0.10, 0.14, 0.25) * pow(saturate(md), 400.0) * 0.4 * (1.0 - day);   // halo de la luna
    }
#endif
    // Lluvia: cielo gris
    col = lerp(col, Luma(col).xxx * float3(0.85, 0.9, 1.0), ArRainLevel() * 0.7);
    col *= (1.0 - ArRainLevel() * 0.35);   // con lluvia el cielo se oscurece
    if (HasSun()) col += ArRainbow(dir, sunDir) * max(Luma(col), 0.08) * 4.0;   // v80: arcoiris mucho mas visible (antes x2.5, 0.22)

    // Por debajo del horizonte
    col = lerp(col, horizonDay * 0.25 * day + horizonNight, saturate(-dir.y * 3.0));

    if (!HasSun())
        col = IsNether() ? ToLinear(min(g_view.skyColor, 1.0)) * 1.2 : EndSky(dir);
    return col;
}

float3 RenderClouds(float3 origin, float3 dir, float3 background)
{
#if AR_CLOUDS
    if (!HasSun()) return background;
    float3 camW = ToWorld(origin);
#if AR_CLOUDS_ABOVE
    float dy = abs(dir.y) < 0.002 ? (dir.y < 0 ? -0.002 : 0.002) : dir.y;
#else
    if (dir.y < 0.01) return background;
    float dy = dir.y;
#endif
    float t0 = (AR_CLOUD_BASE - camW.y) / dy;
    float t1 = (AR_CLOUD_TOP - camW.y) / dy;
    float tEnter = max(min(t0, t1), 0.0);
    float tExit = min(min(max(t0, t1), 60000.0), tEnter + 2200.0);   // v78: tramo corto = pasos mas finos (sin rayas)
    if (tExit <= tEnter) return background;

    float3 L;
    float3 lightCol = PrimaryLightColor(L);
    float3 amb = SkyAmbientColor(float3(0, 1, 0));
    float cosT = dot(dir, L);
    float phase = 0.55 + 1.6 * pow(saturate(cosT), 8.0);

    float stepLen = (tExit - tEnter) / g_arCloudSteps;
    float t = tEnter + stepLen * ArIGN(g_arPixel);
    float T = 1.0;
    float3 scat = 0;
    [loop]
    for (int i = 0; i < g_arCloudSteps; i++)
    {
        float3 p = camW + dir * t;
        float d = CloudDensity(p);
        if (d > 0.001)
        {
            float dl = CloudDensity(p + L * 45.0) + CloudDensity(p + L * 110.0);
            float lightT = exp(-dl * 2.2);
            float sigma = d * 0.045;
            float stepT = exp(-sigma * stepLen);
            float hh = saturate((p.y - AR_CLOUD_BASE) / (AR_CLOUD_TOP - AR_CLOUD_BASE));
            float powder = 1.0 - exp(-d * 6.0);   // bordes brillantes, interior con volumen
            float3 S = lightCol * lightT * phase * (1.4 + 1.6 * powder) + amb * (0.35 + 0.8 * hh);
            S += LightningCloudLight(p, camW) * (0.3 + powder);
            scat += T * S * (1.0 - stepT);
            T *= stepT;
            if (T < 0.02) break;
        }
        t += stepLen;
    }
    float fade = exp(-tEnter / 30000.0);   // v79: antes 4000 (desde muy arriba se desvanecian)
    return lerp(background, background * T + scat, fade);
#else
    return background;
#endif
}

// Version para el modo hibrido: devuelve la luz de las nubes y la transmitancia por separado
float3 CloudsMarch(float3 origin, float3 dir, float tLimit, out float T)
{
    T = 1.0;
    float3 scat = 0;
    float3 camW = ToWorld(origin);
    float dy = abs(dir.y) < 0.002 ? (dir.y < 0 ? -0.002 : 0.002) : dir.y;
    float t0 = (AR_CLOUD_BASE - camW.y) / dy;
    float t1 = (AR_CLOUD_TOP - camW.y) / dy;
    float tEnter = max(min(t0, t1), 0.0);
    float tExit = min(min(min(max(t0, t1), 60000.0), tLimit), tEnter + 2200.0);   // v78
    if (tExit <= tEnter) return scat;

    float3 L;
    float3 lightCol = PrimaryLightColor(L);
    float3 amb = SkyAmbientColor(float3(0, 1, 0));
    float cosT = dot(dir, L);
    float phase = 0.55 + 1.6 * pow(saturate(cosT), 8.0);

    float stepLen = (tExit - tEnter) / AR_CLOUD_STEPS;
    float t = tEnter + stepLen * ArIGN(g_arPixel);
    [loop]
    for (int i = 0; i < AR_CLOUD_STEPS; i++)
    {
        float3 p = camW + dir * t;
        float d = CloudDensity(p);
        if (d > 0.001)
        {
            float dl = CloudDensity(p + L * 45.0) + CloudDensity(p + L * 110.0);
            float lightT = exp(-dl * 2.2);
            float sigma = d * 0.045;
            float stepT = exp(-sigma * stepLen);
            float hh = saturate((p.y - AR_CLOUD_BASE) / (AR_CLOUD_TOP - AR_CLOUD_BASE));
            float powder = 1.0 - exp(-d * 6.0);   // bordes brillantes, interior con volumen
            float3 S = lightCol * lightT * phase * (1.4 + 1.6 * powder) + amb * (0.35 + 0.8 * hh);
            S += LightningCloudLight(p, camW) * (0.3 + powder);
            scat += T * S * (1.0 - stepT);
            T *= stepT;
            if (T < 0.02) break;
        }
        t += stepLen;
    }
    float fade = exp(-tEnter / 30000.0);   // v79: antes 4000 (desde muy arriba se desvanecian)
    T = lerp(1.0, T, fade);
    return scat * fade;
}

// Luz del cielo para la luz rebotada: en el End el agujero negro NO ilumina como un cielo entero (seria demasiado)
float3 SkyGI(float3 dir)
{
    if (IsEnd()) return AR_END_AMBIENT * 1.4;
    return SkyBase(dir);
}

float3 SkyRadiance(float3 origin, float3 dir)
{
    return RenderClouds(origin, dir, SkyBase(dir));
}

void RenderSky(inout RayState rayState)
{
    if (all(rayState.throughput == 0)) return;
    rayState.color += rayState.throughput * SkyRadiance(rayState.rayDesc.Origin, rayState.rayDesc.Direction);
}

// ---------------------------------------------------------------------
bool AlphaTestHitLogic(HitInfo hitInfo)
{
#if CULL_GLASS_BACK_FACES
    if (hitInfo.materialType == MATERIAL_TYPE_ALPHA_BLEND && !hitInfo.frontFacing)
        return false;
#endif
    if (hitInfo.materialType != MATERIAL_TYPE_ALPHA_TEST)
        return true;

    ObjectInstance obj = objectInstances[hitInfo.objectInstanceIndex];
    GeometryInfo geometryInfo = GetGeometryInfo(hitInfo, obj);
    // Rapido para bloques (hojas, pasto): solo se lee la transparencia de la textura
    if ((obj.flags & kObjectInstanceFlagChunk) && obj.colourTextureIdx != 0xffff
        && !(obj.flags & kObjectInstanceFlagTextureAlphaControlsVertexColor))
    {
        float a = textures[obj.colourTextureIdx].SampleLevel(pointSampler, geometryInfo.uv0, AuroraTexLod(hitInfo)).a;
        return a >= 0.5;
    }
    SurfaceInfo surfaceInfo = MaterialVanilla(hitInfo, geometryInfo, obj);

    return !surfaceInfo.shouldDiscard;
}

// Version estadistica para rayos de luz rebotada: las hojas cuentan como ~60% solidas
// sin leer texturas (la luz rebotada es suave, no se nota y es mucho mas rapido)
bool CheapAlphaHit(HitInfo hitInfo)
{
    if (hitInfo.materialType != MATERIAL_TYPE_ALPHA_TEST)
        return AlphaTestHitLogic(hitInfo);
    uint h = PcgHashEarly(hitInfo.primitiveId * 747796405u + hitInfo.objectInstanceIndex * 2891336453u + g_view.frameCount * 277803737u + g_arPixel.x * 1664525u + g_arPixel.y * 22695477u);
    return (h & 1023u) < 614u;
}

// Sombra rapida para luces puntuales y cache: hojas dejan pasar parte de la luz sin leer texturas
float3 TraceLightTransmittanceFast(float3 origin, float3 dir, float tMax)
{
    RayDesc r;
    r.Origin = origin;
    r.Direction = dir;
    r.TMin = 0.0;
    r.TMax = tMax;
    float3 transmit = 1.0;
    int leafTests = 0;
    RayQuery<RAY_FLAG_NONE> q;
    uint mask = INSTANCE_MASK_OPAQUE_OR_ALPHA_TEST_SECONDARY;
#if AR_GLASS_TINT
    mask |= INSTANCE_MASK_ALPHA_BLEND_SECONDARY;
#endif
    q.TraceRayInline(SceneBVH, RAY_FLAG_SKIP_PROCEDURAL_PRIMITIVES, mask, r);
    int arCand = 0;
    while (q.Proceed())
    {
        if (++arCand > AR_MAX_CANDIDATES) { q.CommitNonOpaqueTriangleHit(); q.Abort(); continue; }
        HitInfo hitInfo = GetCandidateHitInfo(q);
        if (hitInfo.materialType == MATERIAL_TYPE_ALPHA_TEST)
            transmit *= 0.45;
        else if (hitInfo.materialType == MATERIAL_TYPE_ALPHA_BLEND)
        {
            ObjectInstance obj = objectInstances[hitInfo.objectInstanceIndex];
            GeometryInfo geo = GetGeometryInfo(hitInfo, obj);
            SurfaceInfo surf = MaterialVanilla(hitInfo, geo, obj);
            float a = saturate(surf.alpha);
            transmit *= saturate(lerp(1.0.xxx, ToLinear(surf.color) * 1.6, a)) * (1.0 - a * 0.2);
        }
        else
        {
            q.CommitNonOpaqueTriangleHit();
            q.Abort();
        }
        if (Max3(transmit) < 0.03)
        {
            q.CommitNonOpaqueTriangleHit();
            q.Abort();
        }
    }
    if (q.CommittedStatus() == COMMITTED_TRIANGLE_HIT) return 0.0;
    return transmit;
}

// La lluvia solo cae donde hay cielo directo arriba (techos, vidrio, hojas la detienen)
float TraceRainVisibility(float3 origin)
{
    RayDesc r;
    r.Origin = origin;
    r.Direction = float3(0, 1, 0);
    r.TMin = 0.0;
    r.TMax = 512.0;
    // v47: las nubes cuadradas del juego (invisibles con Aurora) ya no cuentan como techo: antes dejaban
    // el suelo seco en cuadros que se movian como sombras de nubes
    RayQuery<RAY_FLAG_NONE> q;
    q.TraceRayInline(SceneBVH, RAY_FLAG_SKIP_PROCEDURAL_PRIMITIVES,
        INSTANCE_MASK_OPAQUE_OR_ALPHA_TEST_SECONDARY | INSTANCE_MASK_OPAQUE_OR_ALPHA_TEST_CHUNKS | INSTANCE_MASK_ALPHA_BLEND_SECONDARY, r);
    int cand = 0;
    while (q.Proceed())
    {
        if (++cand > AR_MAX_CANDIDATES) { q.CommitNonOpaqueTriangleHit(); q.Abort(); continue; }
        HitInfo h = GetCandidateHitInfo(q);
        if ((objectInstances[h.objectInstanceIndex].flags & kObjectInstanceFlagClouds) != 0) continue;
        q.CommitNonOpaqueTriangleHit();   // hojas, vidrio: tapan la lluvia
        q.Abort();
    }
    if (q.CommittedStatus() != COMMITTED_TRIANGLE_HIT) return 1.0;
    HitInfo ch = GetCommittedHitInfo(q);
    return (objectInstances[ch.objectInstanceIndex].flags & kObjectInstanceFlagClouds) != 0 ? 1.0 : 0.0;
}

// Lista de luces: la lista "reducida" del juego (la que usa el RTX original, incluye mas tipos de lampara)
uint ARLightCount()
{
    return g_view.reducedLightsCount > 0 ? min(g_view.reducedLightsCount, 4096u) : g_view.cpuLightsCount;
}
LightInfo ARGetLight(uint i)
{
    if (g_view.reducedLightsCount > 0) return inputReducedLightsBuffer[i];
    return inputLightsBuffer[i];
}

float TraceVisibility(float3 origin, float3 dir, float tMax)
{
    RayDesc r;
    r.Origin = origin;
    r.Direction = dir;
    r.TMin = 0.0;
    r.TMax = tMax;

    RayQuery<RAY_FLAG_NONE> q;
    q.TraceRayInline(SceneBVH,
        RAY_FLAG_SKIP_PROCEDURAL_PRIMITIVES | RAY_FLAG_ACCEPT_FIRST_HIT_AND_END_SEARCH,
        INSTANCE_MASK_OPAQUE_OR_ALPHA_TEST_SECONDARY, r);
    int tests = 0;
    // (ya limitado por AR_LEAF_EXACT)
    while (q.Proceed())
    {
        HitInfo hitInfo = GetCandidateHitInfo(q);
        if (++tests > AR_LEAF_EXACT || AlphaTestHitLogic(hitInfo))
            q.CommitNonOpaqueTriangleHit();
    }
    return q.CommittedStatus() == COMMITTED_TRIANGLE_HIT ? 0.0 : 1.0;
}

float3 TraceSunTransmittance(float3 origin, float3 dir, float tMax)
{
    RayDesc r;
    r.Origin = origin;
    r.Direction = dir;
    r.TMin = 0.0;
    r.TMax = tMax;

    float3 transmit = 1.0;
    int leafTests = 0;
    RayQuery<RAY_FLAG_NONE> q;
    uint mask = INSTANCE_MASK_OPAQUE_OR_ALPHA_TEST_SECONDARY;
#if AR_GLASS_TINT
    mask |= INSTANCE_MASK_ALPHA_BLEND_SECONDARY;
#endif
    q.TraceRayInline(SceneBVH, RAY_FLAG_SKIP_PROCEDURAL_PRIMITIVES, mask, r);
    int arCand = 0;
    while (q.Proceed())
    {
        if (++arCand > AR_MAX_CANDIDATES) { q.CommitNonOpaqueTriangleHit(); q.Abort(); continue; }
        HitInfo hitInfo = GetCandidateHitInfo(q);
        if (hitInfo.materialType == MATERIAL_TYPE_ALPHA_TEST)
        {
            // hojas: solo las primeras se revisan con su textura; despues la copa cuenta como sombra llena (mucho mas rapido)
            if (++leafTests > AR_LEAF_EXACT)
            {
                q.CommitNonOpaqueTriangleHit();
                q.Abort();
            }
            else if (AlphaTestHitLogic(hitInfo))
                transmit *= AR_LEAF_TRANSMIT;
        }
        else if (hitInfo.materialType == MATERIAL_TYPE_ALPHA_BLEND)
        {
            // Vidrio (de color): deja pasar la luz tinendola con su color
            ObjectInstance obj = objectInstances[hitInfo.objectInstanceIndex];
            if ((obj.flags & kObjectInstanceFlagClouds) != 0) continue;   // v47: nubes cuadradas del juego: sin sombra
            GeometryInfo geo = GetGeometryInfo(hitInfo, obj);
            SurfaceInfo surf = MaterialVanilla(hitInfo, geo, obj);
            float a = saturate(surf.alpha);
            float3 tint = lerp(1.0.xxx, ToLinear(surf.color) * 1.6, a);
            transmit *= saturate(tint) * (1.0 - a * 0.2);
        }
        else
        {
            q.CommitNonOpaqueTriangleHit();
            q.Abort();
        }
        if (Max3(transmit) < 0.03)
        {
            q.CommitNonOpaqueTriangleHit();
            q.Abort();
        }
    }
    if (q.CommittedStatus() == COMMITTED_TRIANGLE_HIT) return 0.0;
    return transmit;
}

void BuildBasis(float3 n, out float3 t, out float3 b)
{
    float3 up = abs(n.y) < 0.99 ? float3(0, 1, 0) : float3(1, 0, 0);
    t = normalize(cross(up, n));
    b = cross(n, t);
}

float AmbientOcclusion(float3 pos, float3 n)
{
    float3 t, b;
    BuildBasis(n, t, b);
    float vis = 0;
    [unroll]
    for (int k = 0; k < 4; k++)
    {
        float a = 0.7853982 + k * 1.5707963;
        float3 d = normalize(n * 0.75 + (t * cos(a) + b * sin(a)) * 0.66);
        vis += TraceVisibility(pos, d, 1.6);
    }
    vis += TraceVisibility(pos, n, 3.0);
    return vis * 0.2;
}

// Olas: devuelve la normal perturbada del agua
float3 WaterNormal(float3 wp)
{
    float t = g_view.time;
    float2 p = wp.xz;
    float2 grad = 0;
    const float2 dirs[4] = { float2(0.8, 0.6), float2(-0.5, 0.86), float2(0.2, -0.98), float2(-0.95, -0.3) };
    const float freqs[4] = { 0.55, 0.9, 1.6, 2.7 };
    const float amps[4]  = { 0.050, 0.030, 0.016, 0.008 };
    const float speeds[4] = { 1.1, 1.5, 2.1, 2.9 };
    [unroll]
    for (int i = 0; i < 4; i++)
    {
        float ph = dot(dirs[i], p) * freqs[i] + t * speeds[i];
        grad += dirs[i] * (amps[i] * AR_WAVE_SCALE * freqs[i] * cos(ph));
    }
    // pequeno detalle de ruido para que no se vea repetitivo
    float n1 = ValueNoise(p * 1.7 + t * 0.6);
    float n2 = ValueNoise(p * 1.7 + float2(5.2, 1.3) - t * 0.5);
    grad += (float2(n1, n2) - 0.5) * 0.06 * AR_WAVE_SCALE;
    return normalize(float3(-grad.x, 1.0, -grad.y));
}

uint PcgHash(uint v)
{
    uint state = v * 747796405u + 2891336453u;
    uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return (word >> 22u) ^ word;
}

float Rand(inout uint seed)
{
    seed = PcgHash(seed);
    return (seed & 0x00ffffffu) / 16777216.0;
}

float3 CosineSampleHemisphere(float3 n, float2 u)
{
    float3 t, b;
    BuildBasis(n, t, b);
    float r = sqrt(u.x);
    float phi = 2.0 * PI * u.y;
    return normalize(t * (r * cos(phi)) + b * (r * sin(phi)) + n * sqrt(max(0.0, 1.0 - u.x)));
}

// Iluminacion global: 1 rebote real. Devuelve la luz que llega (sin multiplicar por el color del bloque)
// Tinte acumulado de todos los vidrios que cruza un rayo (la luz toma su color)
float3 GlassTint(float3 origin, float3 dir, float tMax)
{
    RayDesc r;
    r.Origin = origin;
    r.Direction = dir;
    r.TMin = 0.0;
    r.TMax = tMax;
    float3 t = 1.0;
    RayQuery<RAY_FLAG_NONE> q;
    q.TraceRayInline(SceneBVH, RAY_FLAG_SKIP_PROCEDURAL_PRIMITIVES, INSTANCE_MASK_ALPHA_BLEND_SECONDARY, r);
    int arCand = 0;
    while (q.Proceed())
    {
        if (++arCand > AR_MAX_CANDIDATES) { q.Abort(); continue; }
        HitInfo h = GetCandidateHitInfo(q);
        if (h.materialType != MATERIAL_TYPE_ALPHA_BLEND) continue;
        ObjectInstance obj = objectInstances[h.objectInstanceIndex];
        GeometryInfo geo = GetGeometryInfo(h, obj);
        SurfaceInfo surf = MaterialVanilla(h, geo, obj);
        float a = saturate(surf.alpha);
        // cada cara del bloque cuenta: tinte suave por cara
        t *= saturate(lerp(1.0.xxx, ToLinear(surf.color) * 1.8, a * 0.75));
    }
    return t;
}

// v47: cuanto cielo se ve desde un punto (1 = al aire libre, 0 = encerrado). Pocos rayos al azar por frame;
// el ruido lo quita la acumulacion temporal y el filtro de CopyToFinal (igual que la luz rebotada)
float ARSkyVisibility(float3 pos, float3 n)
{
    // v48: se usa la cara plana del bloque (no el relieve de la textura). Con el relieve, en el cuarzo
    // los rayos chocaban con su propio bloque y salian rayas negras como de cebra
    float3 an = abs(n);
    float3 fn = (an.x > an.y && an.x > an.z) ? float3(sign(n.x), 0, 0) : (an.y > an.z ? float3(0, sign(n.y), 0) : float3(0, 0, sign(n.z)));
    float3 o = pos + fn * 0.03;
    uint seed = PcgHash(g_arPixel.x * 73856093u + g_arPixel.y * 19349663u + g_view.frameCount * 83492791u);
    float vis = 0;
    [unroll]
    for (int k = 0; k < AR_SKY_RAYS; k++)
    {
        float2 u = float2((k + Rand(seed)) / AR_SKY_RAYS, Rand(seed));
        vis += TraceVisibility(o, CosineSampleHemisphere(fn, u), AR_SKY_DIST);
    }
    return pow(vis / AR_SKY_RAYS, AR_SKY_CURVE);   // v48: lo medio tapado mas oscuro
}

float3 IndirectDiffuse(float3 pos, float3 n, float3 L, float3 lightCol)
{
    uint seed = PcgHash(g_arPixel.x + g_arPixel.y * 4096u + g_view.frameCount * 16777619u);
    float3 sum = 0;
    [loop]
    for (int s = 0; s < AR_GI_SAMPLES; s++)
    {
        float2 u = float2(Rand(seed), Rand(seed));
        float3 dir = CosineSampleHemisphere(n, u);

        RayDesc r;
        r.Origin = pos;
        r.Direction = dir;
        r.TMin = 0.0;
        r.TMax = 96.0;

        RayQuery<RAY_FLAG_NONE> q;
        q.TraceRayInline(SceneBVH, RAY_FLAG_SKIP_PROCEDURAL_PRIMITIVES, INSTANCE_MASK_OPAQUE_OR_ALPHA_TEST_SECONDARY, r);
        int arCand = 0;
        while (q.Proceed())
        {
            if (++arCand > AR_MAX_CANDIDATES) { q.CommitNonOpaqueTriangleHit(); q.Abort(); continue; }
            HitInfo cand = GetCandidateHitInfo(q);
            if (AlphaTestHitLogic(cand))
                q.CommitNonOpaqueTriangleHit();
        }

        if (q.CommittedStatus() == COMMITTED_TRIANGLE_HIT)
        {
            HitInfo h = GetCommittedHitInfo(q);
            ObjectInstance obj = objectInstances[h.objectInstanceIndex];
            GeometryInfo geo = GetGeometryInfo(h, obj);
            SurfaceInfo surf = MaterialVanilla(h, geo, obj);
            float3 hn = surf.normal;
            if (dot(hn, hn) < 0.0001) hn = -dir;
            hn = normalize(hn);
            if (dot(hn, dir) > 0) hn = -hn;
            float3 hp = surf.position + hn * 0.02;
            float3 albedo = ToLinear(surf.color);

            // Luz del cielo en el punto rebotado SOLO si ese punto ve el cielo (cuartos cerrados = oscuros)
            float skyVis = TraceVisibility(hp, normalize(hn + float3(0, 1.5, 0)), 96.0);
            float3 hitLight = SkyAmbientColor(hn) * 0.35 * (0.15 + 0.85 * skyVis);
            if (Max3(lightCol) > 0.0)
            {
                float ndl = saturate(dot(hn, L));
                if (ndl > 0.0)
                    hitLight += lightCol * ndl * TraceVisibility(hp, L, 256.0) * CloudShadow(ToWorld(hp), L);
            }
            float3 smp = albedo * hitLight;
            smp *= min(1.0, AR_GI_CLAMP / max(Luma(smp), 1e-4));
            // La luz de bloques emisivos tiene su propio limite (mucho mas alto): ilumina de verdad
            float3 em = albedo * surf.emissive * AR_GI_EMISSIVE;
            em *= min(1.0, 25.0 / max(Luma(em), 1e-4));
            float3 add = smp + em;
            if (Max3(add) > 0.0005) add *= GlassTint(pos, dir, h.rayT);
            sum += add;
        }
        else
        {
            // Luz del cielo que entra
            float3 sky = SkyGI(dir);
            sky *= GlassTint(pos, dir, 96.0);
            sum += sky * AR_GI_SKY * (dir.y > 0 ? CloudShadow(ToWorld(pos), normalize(float3(dir.x, max(dir.y, 0.05), dir.z))) * 0.5 + 0.5 : 1.0);
        }
    }
    return sum / AR_GI_SAMPLES;
}

// Reflejo real del agua: montanas, arboles y cielo
float3 TraceReflectionFull(float3 pos, float3 dir, float3 L, float3 lightCol);
float3 TraceReflection(float3 pos, float3 dir, float3 L, float3 lightCol)
{
    g_arCloudSteps = 10;
    float3 r = TraceReflectionFull(pos, dir, L, lightCol);
    g_arCloudSteps = AR_CLOUD_STEPS;
    return r;
}

float3 TraceReflectionFull(float3 pos, float3 dir, float3 L, float3 lightCol)
{
    RayDesc r;
    r.Origin = pos;
    r.Direction = dir;
    r.TMin = 0.0;
    r.TMax = 256.0;
    // v49: solo lo que la camara ve (antes tambien objetos ocultos del juego) y se salta lo pegado a la camara:
    // en los charcos aparecia una "cosa verde" debajo del jugador
    HitInfo h;
    bool found = false;
    [loop]
    for (int tries = 0; tries < 2 && !found; tries++)
    {
        RayQuery<RAY_FLAG_NONE> q;
        q.TraceRayInline(SceneBVH, RAY_FLAG_SKIP_PROCEDURAL_PRIMITIVES, INSTANCE_MASK_OPAQUE_OR_ALPHA_TEST_PRIMARY, r);
        int arCand = 0;
        while (q.Proceed())
        {
            if (++arCand > AR_MAX_CANDIDATES) { q.CommitNonOpaqueTriangleHit(); q.Abort(); continue; }
            HitInfo cand = GetCandidateHitInfo(q);
            if (AlphaTestHitLogic(cand))
                q.CommitNonOpaqueTriangleHit();
        }
        if (q.CommittedStatus() != COMMITTED_TRIANGLE_HIT)
            return SkyRadiance(pos, dir);
        h = GetCommittedHitInfo(q);
        if ((objectInstances[h.objectInstanceIndex].flags & kObjectInstanceFlagChunk) == 0 && length(pos + dir * h.rayT) < 1.2)
            r.TMin = h.rayT + 0.05;   // objeto pegado a la camara: seguir de largo
        else
            found = true;
    }
    if (!found) return SkyRadiance(pos, dir);
    ObjectInstance obj = objectInstances[h.objectInstanceIndex];
    GeometryInfo geo = GetGeometryInfo(h, obj);
    SurfaceInfo surf = MaterialVanilla(h, geo, obj);
    float3 hn = surf.normal;
    if (dot(hn, hn) < 0.0001) hn = -dir;
    hn = normalize(hn);
    if (dot(hn, dir) > 0) hn = -hn;
    float3 hp = surf.position + hn * 0.02;
    float3 lightAtHit = SkyAmbientColor(hn) * 0.7 * g_arReflSky + surf.emissive * AR_EMISSIVE_BOOST;
    if (Max3(lightCol) > 0.0)
    {
        float ndl = saturate(dot(hn, L));
        if (ndl > 0.0)
            lightAtHit += lightCol * ndl * TraceVisibility(hp, L, 256.0) * CloudShadow(ToWorld(hp), L);
    }
    float3 c = ToLinear(surf.color) * lightAtHit;
    // neblina en reflejos lejanos
    float f = saturate(h.rayT / 256.0);
    return lerp(c, SkyBase(normalize(float3(dir.x, 0.05, dir.z))), f * f);
}

// ---------------------------------------------------------------------
// Color del agua del bioma (el juego lo manda en el color de vertice del agua)
float3 BiomeWaterTint(float3 vc)
{
    if (Max3(vc) - min(min(vc.r, vc.g), vc.b) < 0.05) return 1.0;   // sin tinte (pack de texturas)
    float3 r = ToLinear(vc) / ToLinear(float3(0.247, 0.463, 0.894));   // relativo al agua normal
    r /= max(Luma(r), 1e-3);
    return lerp(1.0.xxx, clamp(r, 0.25, 3.0), AR_BIOME_WATER);
}

// Cache de luz por cara (misma indexacion que el RTX original)
uint FaceCacheIndex(ObjectInstance obj, uint primitiveId)
{
    return (obj.vertexOffsetInParallelVertices >> 2) + (primitiveId >> 1);
}

bool UsesFaceCache(ObjectInstance obj)
{
    return (obj.flags & kObjectInstanceFlagUsesIrradianceCache) != 0;
}

// Cache de luz por ESQUINA (vertice): se mezcla entre las 4 esquinas de cada cara -> la luz sale suave, sin cuadros
uint3 QuadTriVertices(uint primitiveId)
{
    uint first = (primitiveId / 2) * 4;
    return first + (primitiveId & 1 ? uint3(2, 3, 0) : uint3(0, 1, 2));
}

// rgb = luz indirecta que llega (rebotes + bloques que brillan), a = historial minimo de las 3 esquinas
float4 LoadVertexIrradiance(ObjectInstance obj, uint primitiveId, float3 bary)
{
    uint3 v = QuadTriVertices(primitiveId) + obj.vertexOffsetInParallelVertices;
    float3 sum = 0;
    float minH = 1e9;
    [unroll] for (int i = 0; i < 3; i++)
    {
        VertexIrradianceCache c = vertexIrradianceCache[obj.vbIdx][v[i]];
        float3 irr = float3(c.incomingFrontAndHistoryLength.rgb);
        float h = c.incomingFrontAndHistoryLength.a;
        if (isnan(h) || any(isnan(irr)) || any(isinf(irr))) { irr = 0; h = 0; }
        sum += max(irr, 0.0) * bary[i];
        minH = min(minH, h);
    }
    return float4(sum, minH);
}

// Luz indirecta guardada de una superficie: esquinas (suave) si ya estan listas, si no la de la cara
float4 SurfaceCacheInfo(ObjectInstance obj, uint primitiveId, float3 bary)
{
    if (!UsesFaceCache(obj)) return 0;
#if AR_VERTEX_CACHE
    float4 vc = LoadVertexIrradiance(obj, primitiveId, bary);
    if (vc.a >= 6.0) return float4(vc.rgb, saturate((vc.a - 6.0) / 10.0) + 1.0);   // a > 1 => viene de las esquinas
#endif
    FaceIrradianceCache fc = faceIrradianceCache[obj.vbIdx][FaceCacheIndex(obj, primitiveId)];
    float hist = fc.outgoingFrontAndHistoryLength.a;
    float3 ci = fc.outgoingFrontAndHistoryLength.rgb;
    if (!isnan(hist) && hist >= 8.0 && !any(isnan(ci)) && !any(isinf(ci)))
        return float4(ci, saturate((hist - 8.0) / 12.0));
    return 0;
}

// Radiancia que sale de la cara (rgb) y su historial (a)
float4 LoadFaceRadiance(ObjectInstance obj, uint primitiveId, bool front)
{
    FaceIrradianceCache c = faceIrradianceCache[obj.vbIdx][FaceCacheIndex(obj, primitiveId)];
    float4 v = front ? float4(c.outgoingFrontAndHistoryLength) : float4(c.outgoingBackAndPad.rgb, c.outgoingFrontAndHistoryLength.a);
    if (any(isnan(v)) || any(isinf(v))) v = 0;
    return max(v, 0);
}

// Luz que llega a un punto desde una direccion: cielo, o la cara que golpea (leyendo su cache)
float3 DirectLightAt(float3 pos, float3 n, float3 L, float3 lightCol, int maxLights);
float3 GatherRadiance(float3 pos, float3 dir, float tMax, float3 L, float3 lightCol, bool useCache)
{
    RayDesc r;
    r.Origin = pos;
    r.Direction = dir;
    r.TMin = 0.0;
    r.TMax = tMax;
    RayQuery<RAY_FLAG_NONE> q;
    q.TraceRayInline(SceneBVH, RAY_FLAG_SKIP_PROCEDURAL_PRIMITIVES, INSTANCE_MASK_OPAQUE_OR_ALPHA_TEST_SECONDARY, r);
    int arCand = 0;
    while (q.Proceed())
    {
        if (++arCand > AR_MAX_CANDIDATES) { q.CommitNonOpaqueTriangleHit(); q.Abort(); continue; }
        HitInfo cand = GetCandidateHitInfo(q);
        if (CheapAlphaHit(cand))
            q.CommitNonOpaqueTriangleHit();
    }
    if (q.CommittedStatus() != COMMITTED_TRIANGLE_HIT)
    {
        g_arSkyHits += 1.0;
        float3 sky = SkyGI(dir) * AR_GI_SKY;
        if (dir.y > 0) sky *= CloudShadow(ToWorld(pos), normalize(float3(dir.x, max(dir.y, 0.05), dir.z))) * 0.5 + 0.5;
        return sky * GlassTint(pos, dir, tMax);
    }
    HitInfo h = GetCommittedHitInfo(q);
    ObjectInstance obj = objectInstances[h.objectInstanceIndex];
    float3 rad = 0;
    if (useCache && UsesFaceCache(obj))
    {
        // La cache guarda la luz que LLEGA a la cara; aqui se le aplica el color del bloque golpeado
        FaceIrradianceCache c = faceIrradianceCache[obj.vbIdx][FaceCacheIndex(obj, h.primitiveId)];
        float3 irr = float3(c.outgoingFrontAndHistoryLength.rgb) + float3(c.outgoingBackAndPad.rgb);
        float hist = c.outgoingFrontAndHistoryLength.a;
        if (any(isnan(irr)) || any(isinf(irr))) irr = 0;
        GeometryInfo geo = GetGeometryInfo(h, obj);
        SurfaceInfo surf = MaterialVanilla(h, geo, obj);
#if AR_VERTEX_CACHE
        {
            float4 vc = LoadVertexIrradiance(obj, h.primitiveId, geo.barycentric);
            float3 vb = float3(c.outgoingBackAndPad.rgb);
            if (vc.a >= 6.0 && !any(isnan(vb))) { irr = vc.rgb + max(vb, 0.0); hist = max(hist, vc.a); }
        }
#endif
        if (isnan(hist) || hist < AR_CACHE_MIN_HIST)
        {
            // cara recien reconstruida (abriste una puerta, pusiste un bloque...): la cache aun esta vacia.
            // En vez de leer "negro" (el cuarto se oscurecia de golpe) se calcula su luz directa aqui mismo
            float3 hn = surf.normal;
            hn = dot(hn, hn) > 1e-4 ? normalize(hn) : -dir;
            if (dot(hn, dir) > 0) hn = -hn;
            float3 fresh = DirectLightAt(surf.position + hn * 0.02, hn, L, lightCol, g_arInCache ? 1 : 4) + SkyAmbientColor(hn) * 0.35;
            float w = saturate((isnan(hist) ? 0.0 : hist) / AR_CACHE_MIN_HIST);
            irr = lerp(fresh, irr, w);
        }
        float3 alb = ToLinear(surf.color);
        rad = alb * max(irr, 0) + alb * surf.emissive * AR_GI_EMISSIVE * g_arEmisScale;
        rad *= min(1.0, g_arRadClamp / max(Luma(rad), 1e-4));
    }
    else
    {
        // Objetos sin cache (mobs, items): estimacion simple
        GeometryInfo geo = GetGeometryInfo(h, obj);
        SurfaceInfo surf = MaterialVanilla(h, geo, obj);
        rad = ToLinear(surf.color) * (SkyAmbientColor(float3(0, 1, 0)) * 0.3 + surf.emissive * AR_GI_EMISSIVE);
    }
    if (Max3(rad) > 0.0005) rad *= GlassTint(pos, dir, h.rayT);
    return rad;
}

float3 GatherIrradiance(float3 pos, float3 n, float3 L, float3 lightCol, uint seed, int count)
{
    float3 sum = 0;
    [loop]
    for (int s = 0; s < count; s++)
    {
        float2 u = float2(Rand(seed), Rand(seed));
        sum += GatherRadiance(pos, CosineSampleHemisphere(n, u), 96.0, L, lightCol, true);
    }
    return sum / count;
}

#include "AuroraLights.hlsl"   // v41: lamparas (antorchas, faroles, varas del End) y sus ajustes

float3 DirectLightAt(float3 pos, float3 n, float3 L, float3 lightCol, int maxLights)
{
    float3 d = 0;
    if (Max3(lightCol) > 0.0)
    {
        float ndl = saturate(dot(n, L));
        if (ndl > 0.0)
            d += lightCol * ndl * TraceLightTransmittanceFast(pos, L, 160.0) * CloudShadow(ToWorld(pos), L);
    }
    d += ARPointLights(pos, pos, n, min(maxLights, AR_SEL_MAX));
    return d;
}

// Luz ambiente/rebotada en un punto: rayos que leen la cache de luz + cache propia de la cara + rellenos
float3 ComputeAmbientGI(float3 shadePos, float3 n, float3 L, float3 lightCol, float4 cacheInfo, uint gseed, int rays)
{
    g_arSkyHits = 0;
    bool warm = cacheInfo.a > 0.0;
    bool smoothCache = cacheInfo.a > 1.0;   // esquinas: suave, se puede confiar mucho mas
    if (smoothCache) cacheInfo.a -= 1.0;
    g_arEmisScale = warm ? 0.2 : 0.7;   // menos brillo directo de bloques emisivos por pixel (la cache lo aporta sin granitos)
    g_arRadClamp = warm ? 4.0 : 10.0;
    float3 gi = GatherIrradiance(shadePos, n, L, lightCol, gseed, rays);
    g_arEmisScale = 1.0;
    g_arRadClamp = 30.0;
    float skyVis = saturate(g_arSkyHits / (float)rays * 2.0);
    if (warm)
    {
        float3 ci = cacheInfo.rgb;
        gi = min(gi, ci * 2.5 + 0.05);
        float nearEm = saturate((Luma(ci) - Luma(gi)) / (Luma(ci) + 0.05));
        float wC = smoothCache ? (0.70 + 0.25 * nearEm) : (AR_CACHE_BLEND + 0.35 * nearEm);
        gi = lerp(gi, ci, saturate(wC) * cacheInfo.a);
    }
    float3 ambient = gi * AR_GI_STRENGTH + AR_AMBIENT_MIN * skyVis + 0.002 + g_view.nightVisionLevel * 0.4;
    if (HasSun()) ambient += AR_NIGHT_FILL * skyVis * (1.0 - DayFactor()) * saturate(n.y * 0.4 + 0.6);
    ambient += float3(0.6, 0.65, 0.8) * LightningFlash() * skyVis * 0.6;
    return ambient;
}

void RenderVanilla(HitInfo hitInfo, inout RayState rayState)
{
    ObjectInstance objectInstance = objectInstances[hitInfo.objectInstanceIndex];

    const bool isClouds = (objectInstance.flags & kObjectInstanceFlagClouds) != 0;
#if AR_CLOUDS
    if (isClouds && HasSun())
    {
        // Las nubes planas del juego se reemplazan por las volumetricas
        rayState.rayDesc.TMin = hitInfo.rayT + 0.01;
        return;
    }
#endif

    GeometryInfo geometryInfo = GetGeometryInfo(hitInfo, objectInstance);
    SurfaceInfo surfaceInfo = MaterialVanilla(hitInfo, geometryInfo, objectInstance);

    if (hitInfo.materialType == MATERIAL_TYPE_OPAQUE || hitInfo.materialType == MATERIAL_TYPE_ALPHA_TEST) surfaceInfo.alpha = 1;

    const bool isSun = (objectInstance.flags & kObjectInstanceFlagSun) != 0;
    const bool isMoon = (objectInstance.flags & kObjectInstanceFlagMoon) != 0;
    const bool isBlockBreakingOverlay = objectInstance.flags == (kObjectInstanceFlagAlphaTestThresholdHalf | kObjectInstanceFlagTextureAlphaControlsVertexColor);
    if ((IsEnd() || AR_HYB_NO_SUNMESH) && (isSun || isMoon))   // v72 hibrido: la luna/sol del juego estan a ~100 bloques y crecian al subir
    {
        // End: el destello/mancha morada del cielo vanilla no se dibuja (el cielo es el agujero negro)
        rayState.rayDesc.TMin = hitInfo.rayT + 0.01;
        return;
    }
    const bool isWater = hitInfo.materialType == MATERIAL_TYPE_WATER;

    float3 viewDir = rayState.rayDesc.Direction;
    float3 n = surfaceInfo.normal;
    if (dot(n, n) < 0.0001) n = float3(0, 1, 0);
    n = normalize(n);
    if (dot(n, viewDir) > 0) n = -n;

    float3 wp = ToWorld(surfaceInfo.position);
    float3 L;
    float3 lightCol = PrimaryLightColor(L);

    float arPuddle = 0;
#if AR_RAIN_WETNESS
    // Lluvia: superficies expuestas al cielo se oscurecen y reflejan como charcos
    // nada de charcos bajo el agua (ni viendo a traves del agua, ni con la camara sumergida)
    if (ArRainLevel() > 0.01 && HasSun() && n.y > 0.3 && !isWater && !isClouds && rayState.waterEnterT < 0 && g_view.cameraIsUnderWater == 0)
    {
        float3 baseCol = surfaceInfo.color;   // color original (antes de mojarse) para saber que bloque es
        float baseRough = surfaceInfo.roughness;   // v47: para distinguir nieve (aspera) de cuarzo/metal (lisos)
        float baseMetal = surfaceInfo.metalness;
        float wet = ArRainLevel() * saturate((n.y - 0.3) * 2.0) * TraceRainVisibility(surfaceInfo.position + n * 0.02);
        surfaceInfo.roughness = max(surfaceInfo.roughness, lerp(surfaceInfo.roughness, 0.55, wet));   // mojado: mas oscuro, sin reflejo con ruido (solo los charcos reflejan)
        surfaceInfo.color *= lerp(1.0, 0.75, wet);
#if AR_PUDDLES
        // Charcos: manchas planas de agua que reflejan como espejo (crecen con la lluvia)
        if (n.y > 0.9)
        {
            // forma suave y grande, borde definido (como charcos reales)
            float pn = Fbm(wp.xz * 0.11) * 0.85 + Fbm(wp.xz * 0.45) * 0.15;
            float th = AR_PUDDLE_THRESHOLD - 0.07 * ArRainLevel();   // mas alto = menos charcos
            float puddle = smoothstep(th, th + 0.025, pn) * wet;
            // la arena absorbe el agua: sin charcos (arena y arena roja)
            float3 bc = baseCol;
            float lb = Luma(bc);
            {
                // arena: clara y amarillenta/beige; arena roja: naranja
                float sand = step(0.48, lb) * step(bc.b, bc.g) * step(bc.g, bc.r * 1.03) * step(0.10, bc.r - bc.b);
                float redSand = step(0.30, lb) * step(0.30, bc.r - bc.b) * step(bc.g, bc.r * 0.80);
                // v47: pasto y tierra SI llevan charcos. No en: arena, nieve, arena/tierra de alma.
                // Metal y cuarzo siempre pueden (lisos). Se reconocen por color y rugosidad del pack.
                float sat = Max3(bc) - min(min(bc.r, bc.g), bc.b);
                float snow = step(0.70, lb) * step(sat, 0.10) * step(0.75, baseRough);              // nieve (blanca y aspera)
                float soulSand = step(lb, 0.30) * step(0.04, bc.r - bc.b) * step(bc.g, bc.r) * step(sat, 0.22) * step(0.06, lb);
                float absorbs = saturate(sand + redSand + snow + soulSand);
                if (baseMetal > 0.5) absorbs = 0;                                                  // oro, hierro...: el agua se queda
                puddle *= 1.0 - absorbs;
            }
            // cerca del fuego, lava o fogatas el agua se evapora
            if (puddle > 0.0)
            {
                for (int pl = 0; pl < min(16, (int)ARLightCount()); pl++)
                {
                    LightInfo li = ARGetLight(pl);
                    float3 lc = ToLinear(UnpackLight(li.packedData).color);
                    float warmL = saturate((lc.r - lc.b) / max(Max3(lc), 0.01));
                    float dl = length(li.position - surfaceInfo.position);
                    puddle *= lerp(1.0, smoothstep(1.5, 3.0, dl), warmL);
                }
            }
            arPuddle = puddle;
            surfaceInfo.roughness = lerp(surfaceInfo.roughness, AR_PUDDLE_ROUGH, puddle);   // v48: antes 0 (espejo)
            surfaceInfo.metalness = lerp(surfaceInfo.metalness, 0.0, puddle);
            // tierra (cafe oscuro): la capa de agua se ve mas gruesa, por encima del bloque
            float dirt = step(lb, 0.48) * step(0.08, bc.r - bc.b) * step(bc.b, bc.g) * step(bc.g, bc.r);
            surfaceInfo.color *= lerp(1.0, lerp(0.22, 0.10, dirt), puddle);   // agua: el suelo de abajo se ve oscuro, domina el reflejo
            // gotas de lluvia: ondas circulares que se abren (dos capas)
            float tt = g_view.time * 6.0;
            float2 rip = 0;
            [unroll] for (int ly = 0; ly < 2; ly++)
            {
                float sc = ly == 0 ? 1.6 : 2.7;
                float2 gp = wp.xz * sc + ly * 17.3;
                float2 cell = floor(gp);
                float rnd = frac(sin(dot(cell, float2(12.9898, 78.233))) * 43758.5453);
                float2 ctr = 0.3 + 0.4 * float2(rnd, frac(rnd * 7.13));
                float ph = frac(tt * (0.22 + 0.1 * ly) + rnd);
                float2 dv = frac(gp) - ctr;
                float dd = length(dv);
                float rr = dd - ph * 0.42;
                float ring = exp(-rr * rr * 700.0) * (1.0 - ph) * sin(rr * 120.0);
                rip += dv / max(dd, 1e-3) * ring;
            }
            rip *= 0.10 * ArRainLevel();
            n = normalize(lerp(n, float3(0, 1, 0), puddle) + float3(rip.x, 0, rip.y) * puddle);
        }
#endif
    }
#endif
    float cloudSh = CloudShadow(wp, L);

    float3 light;
    float3 giLight = 0;
    float3 specExtra = 0;
    bool refracted = false;
    bool usedGI = false;
    bool arPrimarySurf = false;   // v46: primera superficie solida del pixel (para reflejos)
    bool arSkyGI = false;         // v47: la luz del cielo de este punto pasa por la limpieza (acumulacion + filtro)
    float arSkyVis = 1.0;         // v47: cuanto cielo se ve desde este punto (0 = cuarto cerrado)
    float sunVisDirect = 0;
    if (isClouds)
    {
        light = ToLinear(geometryInfo.color.rgb);
        surfaceInfo.alpha = 0.72;
    }
    else
    {
        // v49: cara plana del bloque. El relieve de la textura inclinaba la normal y algunos pixeles
        // se tapaban la luz a si mismos (rayas negras en cuarzo, piedra, paredes junto al vidrio)
        float3 arFaceN = n;
        if ((objectInstance.flags & kObjectInstanceFlagChunk) != 0)
        {
            float3 an = abs(n);
            arFaceN = (an.x > an.y && an.x > an.z) ? float3(sign(n.x), 0, 0) : (an.y > an.z ? float3(0, sign(n.y), 0) : float3(0, 0, sign(n.z)));
        }
        float3 nL = normalize(lerp(arFaceN, n, AR_NORMAL_LIGHT));   // normal para la luz: relieve suave
        float3 shadePos = surfaceInfo.position + arFaceN * 0.02;

        // --- Ambiente del cielo ---
        float3 ambient = SkyAmbientColor(n) * AR_AMBIENT_STRENGTH + AR_AMBIENT_MIN + g_view.nightVisionLevel * 0.4;

        float ao = 1.0;
#if AR_GI
#if AR_GI
        if (hitInfo.materialType == MATERIAL_TYPE_ALPHA_BLEND && !rayState.giDone && g_arLayer < AR_FULL_LAYERS)
        {
            // Vidrio: recibe la luz de lamparas y bloques brillantes cercanos (vidrio de color que brilla)
            // El vidrio recibe luz de los dos lados (una lampara debajo lo hace brillar entero)
#if AR_FACE_CACHE
            uint gs2 = PcgHash(g_arPixel.x * 31u + g_arPixel.y * 7919u + g_view.frameCount * 2654435761u);
            float3 gGlass = (GatherIrradiance(shadePos, n, L, lightCol, gs2, 2) + GatherIrradiance(surfaceInfo.position - n * 0.02, -n, L, lightCol, gs2 + 17u, 2)) * AR_GI_STRENGTH;
#else
            float3 gGlass = (IndirectDiffuse(shadePos, n, L, lightCol) + IndirectDiffuse(surfaceInfo.position - n * 0.02, -n, L, lightCol)) * AR_GI_STRENGTH;
#endif
            ambient += gGlass;
            giLight += gGlass;
        }
#endif
        if (!rayState.giDone && !isWater && hitInfo.materialType != MATERIAL_TYPE_ALPHA_BLEND)
        {
#if AR_FACE_CACHE
            {
                // valor estable de la cache de la cara (se usa al calcular la luz en el paso aparte)
                float4 cacheInfo = SurfaceCacheInfo(objectInstance, hitInfo.primitiveId, geometryInfo.barycentric);
#if AR_DEFER_GI
                g_arGIPos = shadePos;
                g_arGICache = cacheInfo;
                g_arGIValid = true;
                ambient = 0;   // se suma despues (paso DiffuseRayGen + limpieza)
#else
                uint gseed = PcgHash(g_arPixel.x + g_arPixel.y * 4096u + g_view.frameCount * 16777619u);
                ambient = ComputeAmbientGI(shadePos, n, L, lightCol, cacheInfo, gseed, AR_GATHER_RAYS);
#endif
            }
#else
            ambient = IndirectDiffuse(shadePos, n, L, lightCol) * AR_GI_STRENGTH + AR_AMBIENT_MIN + g_view.nightVisionLevel * 0.4;
#endif
#if AR_DEFER_GI
            giLight = 1.0;   // factor: niebla, metal y transparencia se aplican igual a la luz calculada despues
#else
            giLight = ambient;
#endif
            rayState.giDone = true;
            usedGI = true;
        }
#endif
        arPrimarySurf = usedGI;
#if !AR_GI
        // v46: sin luz rebotada, la primera superficie solida tambien puede reflejar (antes los charcos quedaban negros)
        if (!rayState.giDone && !isWater && hitInfo.materialType != MATERIAL_TYPE_ALPHA_BLEND)
        {
            arPrimarySurf = true;
            rayState.giDone = true;
        }
#endif
        if (!usedGI)
        {
            if (AR_AO_STRENGTH > 0.0 && !isWater)
                ao = lerp(1.0 - AR_AO_STRENGTH, 1.0, AmbientOcclusion(shadePos, n));
            ambient *= ao;
        }
#if !AR_GI && AR_SKY_DARK
        // v47: oscuridad real. Si desde aqui no se ve el cielo, la luz del cielo no llega (la vision nocturna si)
        if (HasSun() && arPrimarySurf && hitInfo.materialType != MATERIAL_TYPE_ALPHA_BLEND)
        {
            arSkyVis = ARSkyVisibility(surfaceInfo.position, n);
            float nv = g_view.nightVisionLevel * 0.4 * ao;
            ambient = max(ambient - nv, 0.0) * arSkyVis + nv;
            arSkyGI = true;
        }
#endif

        // --- Sol / luna con sombras ---
        float3 direct = 0;
        if (Max3(lightCol) > 0.0)
        {
            float ndl = dot(nL, L);
            float wrap = max(surfaceInfo.subsurface * 0.35, hitInfo.materialType == MATERIAL_TYPE_ALPHA_TEST ? 0.6 : 0.0);
            float lit = saturate((ndl + wrap) / (1.0 + wrap));
            if (wrap <= 0.0) lit *= saturate(dot(arFaceN, L) * 8.0);   // v49: si la cara no mira al sol, no hay luz
            if (lit > 0.0)
            {
                float3 vis = TraceSunTransmittance(shadePos, L, 160.0) * cloudSh;   // sombras de muy lejos no llegan
                sunVisDirect = Luma(vis);
                direct = lightCol * lit * vis;
#if AR_CAUSTICS
                if (rayState.waterEnterT >= 0 || g_view.cameraIsUnderWater != 0)
                {
                    float tt = g_view.time;
                    float v = ValueNoise(wp.xz * 0.9 + float2(tt * 0.35, tt * 0.2)) + ValueNoise(wp.xz * 1.4 - float2(tt * 0.25, -tt * 0.3));
                    float caustic = 0.35 + 2.6 * pow(saturate(1.0 - abs(v - 1.0) * 2.5), 3.0);
                    direct *= caustic;
                }
#endif
            }
            // Luz rebotada (GI falso)
            if (!usedGI)
                ambient += lightCol * cloudSh * AR_BOUNCE_STRENGTH * saturate(0.6 - n.y * 0.4) * ao * arSkyVis;   // v47: el rebote del sol tampoco entra a cuartos cerrados
        }

        light = ambient + direct;
#if !AR_GI
        if (arSkyGI) giLight = ambient;   // v47: esta parte se limpia con la acumulacion y el filtro final (sin granitos)
#endif

        // --- Luces puntuales ---
        light += ARPointLights(surfaceInfo.position, shadePos, nL, (g_arLayer < AR_FULL_LAYERS || surfaceInfo.alpha >= 0.999) ? AR_POINT_SHADOWS : 2);

        // Emisivos (antorchas, lava, glowstone...) brillan de verdad
        light += surfaceInfo.emissive * AR_EMISSIVE_BOOST;
    }

    float3 albedo = ToLinear(surfaceInfo.color);

    float3 throughput;
    float3 emission;
    if (isSun || isMoon)
    {
        throughput = 1;
        emission = albedo * ((isSun ? g_view.sunMeshIntensity : g_view.moonMeshIntensity) * surfaceInfo.alpha) * cloudSh;
    }
    else if (isBlockBreakingOverlay)
    {
        throughput = surfaceInfo.color;
        emission = 0;
    }
    else
    {
        throughput = 1 - surfaceInfo.alpha;
        emission = albedo * surfaceInfo.alpha * light;
        // portal del End (bloque negro plano): se ve como el espacio con estrellas
        // v46: la superficie del portal esta a 3/4 de altura del bloque; la obsidiana termina en el borde (no lleva estrellas)
        if (!isWater && hitInfo.materialType == MATERIAL_TYPE_OPAQUE && n.y > 0.9 && Max3(surfaceInfo.color) < 0.05
            && (objectInstance.flags & kObjectInstanceFlagChunk) != 0
            && abs(frac(wp.y + 0.5) - 0.5) > 0.06)
            emission = PortalSpace(wp, viewDir);
        if (hitInfo.materialType == MATERIAL_TYPE_ALPHA_BLEND)
        {
            // Vidrio de color: lo que se ve (y la luz) a traves toma el color del vidrio
            float a = saturate(surfaceInfo.alpha);
            throughput = saturate(lerp(1.0.xxx, albedo * 1.6, a)) * (1.0 - a * 0.2);
        }

#if AR_PBR_SPECULAR
        // v46: sin luz rebotada solo reflejan charcos, metales y lo muy pulido (para no bajar los FPS)
        if (arPrimarySurf && !isWater && surfaceInfo.roughness < AR_SPEC_ROUGH_MAX
            && (AR_GI || arPuddle > 0.01 || surfaceInfo.metalness > 0.5 || surfaceInfo.roughness < AR_SPEC_ROUGH_LITE))
        {
            float metal = saturate(surfaceInfo.metalness);
            float rough = max(surfaceInfo.roughness, 0.03);
#if AR_METAL_MIRROR
            if (metal > 0.5) rough = 0.02;   // hierro, oro, cobre pulido: espejo
#endif
            float3 F0 = lerp(0.04.xxx, albedo, metal);
            float cosV = saturate(dot(-viewDir, n));
            float3 F = F0 + (1.0 - F0) * pow(1.0 - cosV, 5.0);
            F = max(F, arPuddle * 0.50);   // v48: antes 0.58   // charcos: reflejan como espejo de agua (tierra, pasto, piedra...)
            float smoothF = saturate(1.0 - rough / AR_SPEC_ROUGH_MAX);

            // Los metales casi no tienen color difuso
            float diffScale = (1.0 - metal * (metal > 0.5 ? 0.7 : 0.45));
            emission *= diffScale;
            giLight *= diffScale;

            // Reflejo (con un poco de dispersion segun la rugosidad)
            uint seed = PcgHash(g_arPixel.x * 7919u + g_arPixel.y * 104729u + g_view.frameCount * 2654435761u);
            float3 jitter = float3(Rand(seed), Rand(seed), Rand(seed)) * 2.0 - 1.0;
            float jr = rough * saturate(1.3 - length(surfaceInfo.position) / 40.0);   // v49: de lejos sin dispersion (sin puntitos)
            float3 rdir = normalize(reflect(viewDir, n) + jitter * jr * jr * 1.5);
            if (dot(rdir, n) < 0.01) rdir = reflect(viewDir, n);
            float3 shadePosS = surfaceInfo.position + n * 0.02;
            g_arReflSky = arSkyVis;
            float3 refl = TraceReflection(shadePosS, rdir, L, lightCol);
            g_arReflSky = 1.0;
            specExtra = refl * F * smoothF;
            specExtra *= min(1.0, lerp(0.3, 3.0, arSkyVis) / max(Luma(specExtra), 1e-4));   // v49: en lo oscuro sin destellos sueltos

            // Brillo del sol (GGX)
            if (sunVisDirect > 0.0)
            {
                float3 H = normalize(L - viewDir);
                float a = rough * rough;
                float nh = saturate(dot(n, H));
                float d = nh * nh * (a * a - 1.0) + 1.0;
                float D = (a * a) / (PI * d * d);
                float ndl = saturate(dot(n, L));
                float3 sunSpec = lightCol * D * F * ndl * sunVisDirect * 0.25 / max(cosV, 0.15);
                emission += min(sunSpec, 30.0);
            }
            emission += specExtra;
        }
#endif

#if AR_WATER_WAVES
        if (isWater && n.y < -0.5 && g_view.cameraIsUnderWater != 0)
        {
            // Desde abajo: la superficie refleja el fondo (de cabeza) salvo justo arriba (ventana de Snell)
            rayState.waterTint = BiomeWaterTint(geometryInfo.color.rgb);
            float3 nd = -WaterNormal(wp);
            float3 rr = refract(viewDir, nd, 1.33);
            float cosV = saturate(dot(-viewDir, nd));
            float F = dot(rr, rr) < 0.5 ? 1.0 : (0.02 + 0.98 * pow(1.0 - cosV, 5.0));
            float3 rdir = reflect(viewDir, nd);
            float3 under = TraceReflection(surfaceInfo.position - float3(0, 0.05, 0), rdir, L, lightCol);
            float3 hitDistTint = exp(-20.0 * AR_UNDERWATER_ABSORB);
            under = under * hitDistTint + AR_UNDERWATER_FOG * (Luma(SkyAmbientColor(float3(0, 1, 0))) * 2.0) * (1.0 - hitDistTint);
            emission = emission * (1.0 - F) + under * F;
            throughput *= (1.0 - F);
        }
        else if (isWater && n.y > 0.5)
        {
            // menos textura, el color lo da la profundidad
            emission *= AR_WATER_TEXTURE;
            throughput = 1.0 - surfaceInfo.alpha * AR_WATER_TEXTURE;
            if (g_view.cameraIsUnderWater == 0 && viewDir.y < 0)
                rayState.waterEnterT = hitInfo.rayT;
            rayState.waterTint = BiomeWaterTint(geometryInfo.color.rgb);
            float3 nw = WaterNormal(wp);
            float cosV = saturate(dot(-viewDir, nw));
            float F = 0.04 + 0.96 * pow(1.0 - cosV, 5.0);
            float3 refl = reflect(viewDir, nw);
            refl.y = max(refl.y, 0.02);
            refl = normalize(refl);

            float3 shadePos = surfaceInfo.position + float3(0, 0.05, 0);
            float3 reflCol = TraceReflection(shadePos, refl, L, lightCol);

            // Brillo del sol sobre el agua
            float rl = saturate(dot(refl, L));
            // Destellos: puntos de luz que brillan y se apagan sobre las olas
            float sparkle = step(0.93, ValueNoise(wp.xz * 9.0 + g_view.time * 2.5)) * 8.0;
            float spec = pow(rl, 900.0) * 140.0 + pow(rl, 120.0) * (3.0 + sparkle * 6.0) + pow(rl, 20.0) * 0.35;
            float sunVis = Max3(lightCol) > 0.0 ? TraceVisibility(shadePos, L, 256.0) * cloudSh : 0.0;
            reflCol += lightCol * spec * sunVis;

            emission = emission * (1.0 - F) + reflCol * F;
            throughput *= (1.0 - F);

#if AR_WATER_REFRACTION
            if (g_view.cameraIsUnderWater == 0 && viewDir.y < 0)
            {
                float3 rd = refract(viewDir, nw, 1.0 / 1.33);
                if (dot(rd, rd) > 0.5)
                {
                    rayState.tOffset += hitInfo.rayT;
                    rayState.rayDesc.Origin = surfaceInfo.position;
                    rayState.rayDesc.Direction = normalize(rd);
                    rayState.rayDesc.TMin = 0.001;
                    rayState.waterEnterT = 0.0;
                    refracted = true;
                }
            }
#endif
        }
#endif

        // Neblina atmosferica
        if (AR_FOG_DENSITY > 0.0 && g_view.renderDistance > 1.0)
        {
            float d = hitInfo.rayT / g_view.renderDistance;
            float f = smoothstep(0.80, 1.0, d) * 0.95;   // solo en la orilla donde terminan los chunks
            float3 fogCol = SkyBase(normalize(float3(viewDir.x, 0.05, viewDir.z)));
            if (!HasSun())
            {
                bool nether = IsNether();
                f = saturate(1.0 - exp(-hitInfo.rayT * (nether ? AR_NETHER_FOG : AR_END_FOG))) * 0.9;
                fogCol = nether ? ToLinear(min(g_view.skyColor, 1.0)) * 1.2 : float3(0.03, 0.018, 0.05);
            }
            if (HasSun() && AR_HAZE > 0.0)
            {
                // bruma de profundidad azulada (como los shaders de Java): lo lejano se aclara y se azula
                float hz = saturate(1.0 - exp(-max(hitInfo.rayT - 16.0, 0.0) * 0.006)) * AR_HAZE;
                hz *= lerp(0.35, 1.0, DayFactor());
                f = max(f, hz);
                fogCol = lerp(fogCol, fogCol * float3(0.80, 0.90, 1.10), 0.6);
            }
            if (HasSun() && AR_RAIN_FOG > 0.0)
            {
                // Lluvia/tormenta: neblina gris que cubre todo pero deja ver
#if AR_HORROR_FOG
                float fr = ArRainLevel() * saturate(1.0 - exp(-hitInfo.rayT * 0.03)) * 0.65;   // neblina de terror
#else
                // lluvia: neblina suave solo a lo lejos (de cerca se ve claro y los charcos se distinguen)
                float fr = ArRainLevel() * smoothstep(0.55, 1.0, d) * AR_RAIN_FOG;   // solo en las orillas lejanas
#endif
                f = max(f, fr);
            }
            emission = lerp(emission, fogCol * surfaceInfo.alpha, f);
            giLight *= (1.0 - f);
        }
    }

    if (objectInstance.flags & kObjectInstanceFlagGlint)
        emission += (sin(3.0 * g_view.time) * 0.5 + 0.5) * ToLinear(float3(077, 23, 255) / 255.0) * AR_GLINT_STRENGTH;

    if (rayState.waterEnterT >= 0 && !isWater)
    {
        float wd = max(hitInfo.rayT - rayState.waterEnterT, 0.0);
        float3 absorb = exp(-wd * AR_WATER_ABSORB / lerp(1.0.xxx, rayState.waterTint, 0.5));
        float lightLevel = Luma(SkyAmbientColor(float3(0, 1, 0))) * 2.0 + Luma(lightCol) * 0.6;
        rayState.color += rayState.throughput * AR_WATER_COLOR * rayState.waterTint * lightLevel * (1.0 - absorb);
        rayState.throughput *= absorb;
        rayState.waterEnterT = -1;
    }

    if (!refracted)
        rayState.rayDesc.TMin = hitInfo.rayT;
    rayState.color += emission * rayState.throughput;
    if (!isSun && !isMoon && !isBlockBreakingOverlay)
    {
        if (usedGI || arSkyGI)
        {
            g_arIrr = giLight * surfaceInfo.alpha;
            g_arAlb = albedo * rayState.throughput;
            g_arN = n;
            rayState.giColor += specExtra * rayState.throughput;
        }
        else
            rayState.giColor += (albedo * surfaceInfo.alpha * giLight + specExtra) * rayState.throughput;
    }
    rayState.throughput *= throughput;
    rayState.distance = hitInfo.rayT + (refracted ? 0.0 : rayState.tOffset);
    rayState.motion = surfaceInfo.position - surfaceInfo.prevPosition;
}

#ifndef CULL_GLASS_BACK_FACES
#define CULL_GLASS_BACK_FACES 0
#endif

float3 GodRays(float3 origin, float3 dir, float dist)
{
    if (!HasSun()) return 0;
    float3 L;
    float3 lightCol = PrimaryLightColor(L);
    if (Max3(lightCol) <= 0.0) return 0;
    bool under = g_view.cameraIsUnderWater != 0;

    float cosT = dot(dir, L);
    const float g = 0.72;
    float phase = (1.0 - g * g) / (4.0 * PI * pow(abs(1.0 + g * g - 2.0 * g * cosT), 1.5));
    phase = phase * 7.0 + 0.012;

    float maxD = min(dist, AR_GODRAY_MAXDIST);
    float stepLen = maxD / AR_GODRAY_STEPS;
    // Variacion por frame: se acumula en el filtro temporal (rayos suaves, sin "crayon")
    // v45: desplazamiento FIJO por pixel (patron 4x4); antes cambiaba al azar cada frame y parpadeaba
    float jitter = g_arGRJitter >= 0.0 ? g_arGRJitter : Bayer4(g_arPixel);   // v50: en el hibrido fijo (no hay filtro despues)
    if (under) { maxD = min(dist, 40.0); stepLen = maxD / AR_GODRAY_STEPS; }
    float accum = 0;
    // pasos mas juntos cerca y mas separados lejos: rayos cercanos finos y rayos lejanos visibles
    float prevT = 0;
    for (int i = 0; i < AR_GODRAY_STEPS; i++)
    {
        float u = (i + jitter) / AR_GODRAY_STEPS;
        // v48: pasos repartidos mas parejo (antes u*u: casi todos cerca) -> los rayos lejanos tambien se ven
        float t = maxD * pow(u, 1.5);
        float tNext = maxD * pow(saturate((i + 1.0 + jitter) / AR_GODRAY_STEPS), 1.5);
        float segLen = max(tNext - prevT, 0.0);
        prevT = tNext;
        float3 p = origin + dir * t;
        float a = TraceVisibility(p, L, 160.0) * CloudShadow(ToWorld(p), L);   // v44: 160 como las sombras del sol
        if (under) a *= exp(-t * 0.08);
        accum += a * segLen * exp(-t * 0.0012);   // v48: antes 0.003 (los rayos lejanos se apagaban)
    }
    stepLen = 1.0;   // accum ya es longitud iluminada
    float density = AR_GODRAY_DENSITY * ((1.0 - ArRainLevel() * 0.7) + SunsetFactor() * AR_SUNSET_FOG);   // con lluvia casi no hay rayos (sin neblina blanca)
    // la niebla del pack de texturas (Cinematic Fog/Pop) hace los rayos mas fuertes
    float packFog = Luma(max(g_view.primaryMediaScattering, 0.0));
    if (!isnan(packFog)) density += min(packFog * AR_GODRAY_PACK, 0.02);
    float3 col = lightCol;
    if (under) { density *= 9.0; col *= float3(0.45, 0.95, 0.85); }
    float3 gr = col * phase * accum * stepLen * density;
    float gl = Luma(gr);
    return gr / (1.0 + gl / AR_GODRAY_MAX);   // tope suave: nunca se ve todo blanco
}

float3 AuroraTonemap(float3 color)
{
    color = max(color, 0) * AR_EXPOSURE;
    if (HasSun())
    {
        color *= (1.0 - ArRainLevel() * 0.10 * DayFactor());   // lluvia de dia: un poco mas oscuro
        color *= 1.0 + AR_NIGHT_EXPOSURE * (1.0 - DayFactor());  // de noche se adapta la vista
    }
    color = (color * (2.51 * color + 0.03)) / (color * (2.43 * color + 0.59) + 0.14);
    color = saturate(color);
    float l = dot(color, float3(0.2126, 0.7152, 0.0722));
    color = saturate(lerp(l.xxx, color, AR_SATURATION));
    return pow(color, 1.0 / 2.2);
}

float3 RenderRay(RayDesc rayDesc, out float outputDistance, out float3 outputMotion)
{
    RayQuery<RAY_FLAG_NONE> q;

    RayState rayState;
    rayState.Init();
    rayState.rayDesc = rayDesc;
    g_arIrr = 0; g_arAlb = 0; g_arN = float3(0, 1, 0); g_arGodRays = 0; g_arGIValid = false; g_arGIPos = 0; g_arGICache = 0;

    // v40: maximo AR_MAX_LAYERS superficies transparentes encimadas (antes 100)
    for (int i = 0; i < AR_MAX_LAYERS; i++)
    {
        g_arLayer = i;
        q.TraceRayInline(SceneBVH, RAY_FLAG_SKIP_PROCEDURAL_PRIMITIVES, rayState.instanceMask, rayState.rayDesc);
        int arCand = 0;
        while (q.Proceed())
        {
            if (++arCand > AR_MAX_CAND_PRIMARY) { q.CommitNonOpaqueTriangleHit(); q.Abort(); continue; }
            HitInfo hitInfo = GetCandidateHitInfo(q);
            if (AlphaTestHitLogic(hitInfo))
            {
                q.CommitNonOpaqueTriangleHit();
            }
        }

        if (q.CommittedStatus() == COMMITTED_TRIANGLE_HIT)
        {
            HitInfo hitInfo = GetCommittedHitInfo(q);
            RenderVanilla(hitInfo, rayState);
        }
        else
        {
            break;
        }

        // Terminate rays that can't contribute anymore.
        if (all(rayState.throughput == 0))
            break;
    }

#if AR_CLOUDS && AR_CLOUDS_ABOVE
    // Nubes entre la camara y el suelo (estando arriba de ellas o dentro de una)
    if (HasSun() && all(rayState.throughput == 0))
    {
        float Tc;
        float3 sc = CloudsMarch(rayDesc.Origin, rayDesc.Direction, rayState.distance, Tc);
        rayState.color = rayState.color * Tc + sc;
        rayState.giColor *= Tc;
        g_arAlb *= Tc;
    }
#endif
    const float maxDistance = 65504; // Maximum value depth buffer can contain.
    if (all(rayState.throughput == 0)) {
        // Eventually hit solid object
        outputDistance = min(rayState.distance, maxDistance);
        outputMotion = rayState.motion;
    } else {
        // Eventually hit sky
        outputDistance = maxDistance;
        outputMotion = 0;
    }

    RenderSky(rayState);
    if (g_view.cameraIsUnderWater != 0)
    {
        // Bajo el agua: el agua se vuelve azul y absorbe la luz con la distancia
        float wd = min(outputDistance, 128.0);
        float3 absorb = exp(-wd * AR_UNDERWATER_ABSORB / lerp(1.0.xxx, rayState.waterTint, 0.5));
        float3 L;
        float3 lc = PrimaryLightColor(L);
        float lightLevel = Luma(SkyAmbientColor(float3(0, 1, 0))) * 2.0 + Luma(lc) * 0.6;
        float3 waterFog = AR_UNDERWATER_FOG * lerp(1.0.xxx, rayState.waterTint, 0.35) * lightLevel;
        rayState.color = rayState.color * absorb + waterFog * (1.0 - absorb);
        rayState.giColor *= absorb;
        g_arAlb *= absorb;
    }
    g_arGI = rayState.giColor;
#if AR_LIGHT_DEBUG
    // Diagnostico: con vision nocturna, cada luz de la lista del juego se marca con un punto
    // rojo = lista completa, verde = lista reducida (la que usa Aurora)
    if (g_view.nightVisionLevel > 0.0)
    {
        float tHit = outputDistance;
        float3 mark = 0;
        for (uint li = 0; li < min(g_view.cpuLightsCount, 2048u); li++)
        {
            float3 lp = inputLightsBuffer[li].position - rayDesc.Origin;
            float t = dot(lp, rayDesc.Direction);
            if (t > 0 && t < tHit + 0.5 && length(lp - rayDesc.Direction * t) < 0.10) mark = float3(4, 0, 0);
        }
        for (uint lj = 0; lj < min(g_view.reducedLightsCount, 4096u); lj++)
        {
            float3 lp = inputReducedLightsBuffer[lj].position - rayDesc.Origin;
            float t = dot(lp, rayDesc.Direction);
            float dd = length(lp - rayDesc.Direction * t);
            if (t > 0 && t < tHit + 0.5 && dd < 0.18 && dd > 0.11) mark = float3(0, 4, 0);
        }
        if (Max3(mark) > 0) { rayState.color = mark; rayState.giColor = 0; g_arGI = 0; }
    }
#endif
#if AR_GODRAYS
    {
        // v45: en TODOS los pixeles, sin turnarse (al alternar 2 grupos de pixeles los rayos parpadeaban)
        bool doGR = true;
        if (doGR)
        {
            float3 gr = GodRays(rayDesc.Origin, rayDesc.Direction, outputDistance);
            g_arGodRays = gr;
            rayState.color += gr;
        }
        else
            g_arGodRays = -1.0;
    }
#endif
    return rayState.color;
}

#endif