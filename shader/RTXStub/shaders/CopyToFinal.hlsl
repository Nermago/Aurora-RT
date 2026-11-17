#include "Include/Renderer.hlsl"
#include "Include/Util.hlsl"
#include "Include/ArDenoise.hlsl"

// Aurora RT - pase final (CopyToFinal). Se aplica encima de un preset de BetterRTX.
// Aurora RT v88 (nubes 700-1000 + altura real por la niebla del juego) / v86 (manda la memoria, no el rayo) / v85 (memoria de la altura entre cuadros para las nubes) / v84 (el rayo al suelo ignora al jugador) / v83 (nubes 1000-1300, repeticion cada 5000, rayo al suelo arreglado) / v82 (altura real de la camara para las nubes) / v81 DIAGNOSTICO sobre v80 HIBRIDO (nubes cada 10000, arcoiris fuerte, alfombra negra sin estrellas) / v77 HIBRIDO (preset Aurora Base 3 = BetterRTX de fabrica) (preset Aurora Base 2: charcos rugosidad 0.05, sin Transmission For Specular) sobre el preset propio "Aurora Base" de BetterRTX (v74 sin charcos propios) (v73 + sin circulos del cielo del juego + portal del End con estrellas) (v72 + sin rayos de sol propios + brillo del cielo solo con puntos de cielo) (v71 + cielo sin parpadeo, sol/luna propios, cielo a traves del vidrio) (base: v50; v70 + cielo con un solo brillo + charcos sin cuadros)
// Todo lo demas es el RTX original del juego (luz, sombras, oscuridad, luz rebotada, limpieza).
// Este ultimo paso toma la imagen terminada del juego y le pone encima lo de Aurora:
//   - mundo normal: cielo propio con nubes volumetricas (solo donde se ve cielo), rayos de sol, destello del sol
//   - v70: el sol y la luna del juego ya no tapan el cielo con un cuadro: se dibujan con el cielo de Aurora
//   - v70: charcos con reflejo y suelo mojado cuando llueve (encima de la imagen del juego)
//   - End: se dibuja completo con Aurora (agujero negro, galaxia, planetas, luz que sale del agujero negro)
//   - Nether: el RTX original tal cual
// =====================================================================================
#define AR_DIAG_NUMBERS   0      // v81: numeros de diagnostico con vision nocturna (1 = mostrar)
#define AR_WORLD_WRAP     1024.0 // v82: cada cuanto "da la vuelta" la altura de ToWorld()
#define AR_HYB_SKY        1      // cielo y nubes de Aurora en el mundo normal
#define AR_HYB_GODRAYS    0      // v73: apagados a peticion del usuario (prefiere los rayos de sol del RTX original)
#define AR_HYB_GLARE      1      // destello y reflejos de lente del sol
#define AR_HYB_END        1      // End completo de Aurora
#define AR_HYB_PUDDLES    0    // v75: charcos de BetterRTX (preset Aurora Base)      // v70: charcos y suelo mojado con lluvia
#define AR_HYB_GODRAY_K   1.0    // fuerza de los rayos de sol y el destello (ajustar con capturas)
#define AR_HYB_END_K      1.0    // brillo del End (ajustar con capturas)
#define AR_HYB_SUNQUAD_COS 0.86  // v70: puntos a menos de ~30 grados del sol/luna no sirven para medir el brillo del cielo
#define AR_HYB_WET_DARK   0.80   // v70: suelo mojado (sin charco) un poco mas oscuro
#define AR_HYB_PUDDLE_DARK 0.50  // v70: el suelo bajo el charco se ve oscuro (domina el reflejo)
#define AR_HYB_GLASS_SKY  1.0    // v72: cielo visto a traves del vidrio (Aurora ya dibuja el vidrio encima)
#define AR_HYB_PORTAL_K   1.0    // v74: brillo del portal del End en el mundo normal
#define AR_PUDDLE_F_MIN   0.30   // reflejo minimo del charco mirando de frente (v59: asi no se ven manchas negras)

// La imagen del juego viene codificada (PQ) cuando hay TAA; aqui se pasa a luz lineal igual que el juego
float3 ArPQDecode(float3 c)
{
    float3 e = pow(max(c, 0.0), 1.0 / 78.84375);
    float3 x = max((e - 0.8359375) / (18.8515625 - 18.6875 * e), 0.0);
    return pow(x, 1.0 / 0.1593017578125) * 10000.0;
}

float3 ArVanillaColor(int2 q)
{
    float3 c = inputThisFrameTAAHistory[q].rgb;
    if (g_view.enableTAA != 0) return ArPQDecode(c);
    float rx = g_view.renderResolution.x;
    if (g_view.renderMethod != 2) rx = floor(rx * 0.5) * 2.0;
    if (rx < g_view.displayResolution.x)
    {
        float4 e = inputIncidentLight[0];
        c = max((c - 0.1) * (e.y / e.x), 0.0);
    }
    return c;
}

float3 ArCameraDir(float2 px)
{
    float2 ndc = (px + 0.5) * g_view.recipDisplayResolution;
    ndc = mad(ndc, float2(2, -2), float2(-1, 1));
    return rayDirFromNDC(ndc);
}

// Pixel de pantalla donde se ve un punto (steve space). false = fuera de pantalla / detras
bool ArProject(float3 pos, out int2 q)
{
    float4 c = mul(float4(pos, 1), g_view.viewProj);
    q = 0;
    if (c.w <= 0.0) return false;
    float2 uv = (c.xy / c.w) * float2(0.5, -0.5) + 0.5;
    if (any(uv < 0.0) || any(uv >= 1.0)) return false;
    q = int2(uv * g_view.displayResolution);
    return true;
}

// Rayo de camara: sabe si en este pixel se ve el cielo y, si no, que se ve.
// v70: el sol y la luna del juego cuentan como cielo (antes se quedaban y se veian como un cuadro grande)
bool ArHybTrace(float3 o, float3 d, float tMax, out float dist, out HitInfo hit)
{
    RayDesc r;
    r.Origin = o;
    r.Direction = d;
    r.TMin = 0.0;
    r.TMax = tMax;
    RayQuery<RAY_FLAG_NONE> q;
    q.TraceRayInline(SceneBVH, RAY_FLAG_SKIP_PROCEDURAL_PRIMITIVES,
        INSTANCE_MASK_OPAQUE_OR_ALPHA_TEST_PRIMARY | INSTANCE_MASK_ALPHA_BLEND_PRIMARY | INSTANCE_MASK_WATER, r);
    int cand = 0;
    while (q.Proceed())
    {
        if (++cand > 24) { q.CommitNonOpaqueTriangleHit(); q.Abort(); continue; }
        HitInfo h = GetCandidateHitInfo(q);
        uint fl = objectInstances[h.objectInstanceIndex].flags;
        if ((fl & (kObjectInstanceFlagClouds | kObjectInstanceFlagSun | kObjectInstanceFlagMoon)) != 0) continue;
        if (h.materialType == MATERIAL_TYPE_ALPHA_BLEND || AlphaTestHitLogic(h))
            q.CommitNonOpaqueTriangleHit();
    }
    dist = tMax;
    hit = (HitInfo)0;
    if (q.CommittedStatus() != COMMITTED_TRIANGLE_HIT) return true;
    hit = GetCommittedHitInfo(q);
    uint cf = objectInstances[hit.objectInstanceIndex].flags;
    if ((cf & (kObjectInstanceFlagClouds | kObjectInstanceFlagSun | kObjectInstanceFlagMoon)) != 0) return true;
    dist = hit.rayT;
    return false;
}

// Brillo del juego comparado con el cielo de Aurora alrededor de un pixel:
// asi el cielo de Aurora queda a la misma "exposicion" que el resto de la imagen del juego.
// v70: 16 puntos en 2 anillos; se ignoran los que caen cerca del sol o la luna (el cuadro del juego los aclara)
// v71: UN SOLO valor para toda la pantalla (rejilla fija de 8x6 puntos, igual para todos los pixeles).
// En la v70 cada pixel media alrededor de si mismo: donde un punto caia en una casa o un arbol, la silueta
// se copiaba en el cielo como "fantasmas" en circulo alrededor del sol.
// v72: el cielo "parpadeaba" porque con pocos puntos el valor saltaba cuando uno entraba o salia del cielo.
// Ahora 256 puntos (16x16), uno por hilo del grupo, con pesos suaves (horizonte y cercania al sol/luna entran
// poco a poco) y promedio en escala logaritmica de los puntos que de verdad parecen cielo (los mas claros).
groupshared float gs_lr[256];
groupshared float gs_w[256];
groupshared float gs_scale;

void ArSkyScaleGroup(uint gi)
{
    int2 res = int2(g_view.displayResolution);
    float2 g = float2(gi & 15, gi >> 4) + 0.5;
    int2 q = clamp(int2(g / 16.0 * float2(res)), int2(0, 0), res - 1);
    float3 dq = ArCameraDir(float2(q));
    float w = smoothstep(0.0, 0.12, dq.y);
    float3 sunD = getTrueDirectionToSun();
    float3 moonD = getTrueDirectionToMoon();
    w *= 1.0 - smoothstep(AR_HYB_SUNQUAD_COS - 0.06, AR_HYB_SUNQUAD_COS, max(dot(dq, sunD), dot(dq, moonD)));
    float v = 0;
    // v73: solo cuentan puntos donde de verdad se ve cielo (bajo un techo o entre hojas el cielo se oscurecia)
    if (w > 0.0)
    {
        float sdist; HitInfo sh;
        if (!ArHybTrace(g_view.viewOriginSteveSpace, dq, 10000.0, sdist, sh)) w = 0;
    }
    if (w > 0.0)
    {
        v = Luma(ArVanillaColor(q)) / max(Luma(SkyBase(dq)), 1e-4);
        if (!(v > 1e-6) || isinf(v)) w = 0;
    }
    gs_lr[gi] = w > 0.0 ? log(v) : 0.0;
    gs_w[gi] = w;
    GroupMemoryBarrierWithGroupSync();
    if (gi == 0)
    {
        // 1) promedio de todos; 2) promedio solo de los que estan arriba del promedio - 0.4 (cielo, no arboles)
        float sw = 0, sl = 0;
        for (int i = 0; i < 256; i++) { sw += gs_w[i]; sl += gs_w[i] * gs_lr[i]; }
        float m = sw > 0.01 ? sl / sw : 0.0;
        float sw2 = 0, sl2 = 0;
        for (int j = 0; j < 256; j++)
        {
            float k = gs_w[j] * smoothstep(m - 0.6, m - 0.2, gs_lr[j]);
            sw2 += k; sl2 += k * gs_lr[j];
        }
        gs_scale = sw2 > 0.01 ? exp(sl2 / sw2) : (sw > 0.01 ? exp(m) : 1.0);
    }
    GroupMemoryBarrierWithGroupSync();
}

float ArSkyScale(int2 pUnused)
{
    return gs_scale;
}

float ArSkyScaleOld(int2 pUnused)
{
    int2 res = int2(g_view.displayResolution);
    float3 sunD = getTrueDirectionToSun();
    float3 moonD = getTrueDirectionToMoon();
    float r[48];
    int n = 0;
    float fallback = 1e30;   // si todo cae cerca del sol: el mas bajo (el cuadro del juego solo aclara)
    [loop] for (int i = 0; i < 48; i++)
    {
        float2 g = float2(i & 7, i >> 3) + 0.5;
        int2 q = clamp(int2(g / float2(8, 6) * float2(res)), int2(0, 0), res - 1);
        float3 dq = ArCameraDir(float2(q));
        if (dq.y < 0.03) continue;                  // bajo el horizonte casi siempre es suelo
        float vl = Luma(ArVanillaColor(q));
        float al = Luma(SkyBase(dq));
        float v = vl / max(al, 1e-4);
        if (!(v >= 0.0) || isinf(v)) continue;
        fallback = min(fallback, v);
        if (dot(dq, sunD) > AR_HYB_SUNQUAD_COS || dot(dq, moonD) > AR_HYB_SUNQUAD_COS) continue;
        r[n] = v;
        n++;
    }
    if (n == 0) return fallback < 1e29 ? fallback : 1.0;
    // mediana de los validos (orden por insercion)
    [loop] for (int x = 1; x < n; x++)
    {
        float key = r[x];
        int y = x - 1;
        [loop] while (y >= 0 && r[y] > key) { r[y + 1] = r[y]; y--; }
        r[y + 1] = key;
    }
    return r[(n * 2) / 3];   // v71: un poco arriba de la mitad (arboles/cerros que tapan el cielo son mas oscuros)
}

// Fuerza de la luz del sol del juego comparada con la de Aurora (para rayos de sol, destello y End)
float ArSunScale()
{
    float3 L;
    float al = Luma(PrimaryLightColor(L));
    float vl = Luma(max(g_view.sunColour, 0.0));
    if (al <= 1e-4 || vl <= 1e-4) return 1.0;
    return vl / al;
}

#if AR_HYB_PUDDLES
// v71: la lluvia llega aunque haya pasto alto, flores o helechos encima del bloque (antes dejaban el bloque seco
// y los charcos salian en cuadros). Hojas y plantas a mas de 1.5 bloques si tapan.
float ArHybRainVis(float3 origin)
{
    RayDesc r;
    r.Origin = origin;
    r.Direction = float3(0, 1, 0);
    r.TMin = 0.0;
    r.TMax = 512.0;
    RayQuery<RAY_FLAG_NONE> q;
    q.TraceRayInline(SceneBVH, RAY_FLAG_SKIP_PROCEDURAL_PRIMITIVES | RAY_FLAG_FORCE_NON_OPAQUE,
        INSTANCE_MASK_OPAQUE_OR_ALPHA_TEST_SECONDARY | INSTANCE_MASK_OPAQUE_OR_ALPHA_TEST_CHUNKS | INSTANCE_MASK_ALPHA_BLEND_SECONDARY, r);
    int cand = 0;
    while (q.Proceed())
    {
        if (++cand > 24) { q.CommitNonOpaqueTriangleHit(); q.Abort(); continue; }
        HitInfo h = GetCandidateHitInfo(q);
        uint fl = objectInstances[h.objectInstanceIndex].flags;
        if ((fl & kObjectInstanceFlagClouds) != 0) continue;
        if ((fl & kObjectInstanceFlagChunk) == 0) continue;
        if (h.materialType == MATERIAL_TYPE_ALPHA_TEST && h.rayT < 1.5) continue;
        q.CommitNonOpaqueTriangleHit();
        q.Abort();
    }
    return q.CommittedStatus() == COMMITTED_TRIANGLE_HIT ? 0.0 : 1.0;
}

// Charcos y suelo mojado encima de la imagen del juego (reglas de la Aurora normal v47-v66)
float3 ArHybRain(float3 col, int2 p, float3 o, float3 d, HitInfo hit)
{
    float rain = ArRainLevel();
    if (rain <= 0.01) return col;
    if (hit.materialType == MATERIAL_TYPE_WATER || hit.materialType == MATERIAL_TYPE_ALPHA_BLEND) return col;
    ObjectInstance obj = objectInstances[hit.objectInstanceIndex];
    if ((obj.flags & kObjectInstanceFlagChunk) == 0) return col;   // solo bloques del mundo

    GeometryInfo gi = GetGeometryInfo(hit, obj);
    float3 gn = normalize(gi.modelSpaceGeometryNormal);
    if (dot(gn, d) > 0) gn = -gn;
    if (gn.y < 0.3) return col;

    float3 pos = o + d * hit.rayT;
    float wet = rain * saturate((gn.y - 0.3) * 2.0) * ArHybRainVis(pos + gn * 0.02);
    if (wet <= 0.0) return col;

    float puddle = 0;
    float3 wp = ToWorld(pos);
    if (gn.y > 0.9 && hit.materialType != MATERIAL_TYPE_ALPHA_TEST)   // sin charcos en hojas, flores, rejas
    {
        float pn = Fbm(wp.xz * 0.11) * 0.85 + Fbm(wp.xz * 0.45) * 0.15;
        float th = AR_PUDDLE_THRESHOLD - 0.07 * rain;
        puddle = smoothstep(th, th + 0.025, pn) * wet;
        if (puddle > 0.0)
        {
            SurfaceInfo si = MaterialVanilla(hit, gi, obj);
            float3 bc = si.color;
            float lb = Luma(bc);
            float sat = Max3(bc) - min(min(bc.r, bc.g), bc.b);
            float sand = step(0.48, lb) * step(bc.b, bc.g) * step(bc.g, bc.r * 1.03) * step(0.10, bc.r - bc.b);
            float redSand = step(0.30, lb) * step(0.30, bc.r - bc.b) * step(bc.g, bc.r * 0.80);
            float snow = step(0.70, lb) * step(sat, 0.10) * step(0.75, si.roughness);
            float soulSand = step(lb, 0.30) * step(0.04, bc.r - bc.b) * step(bc.g, bc.r) * step(sat, 0.22) * step(0.06, lb);
            float absorbs = saturate(sand + redSand + snow + soulSand);
            if (si.metalness > 0.5) absorbs = 0;
            puddle *= 1.0 - absorbs;
            // cerca del fuego, lava o fogatas el agua se evapora
            [loop] for (int pl = 0; pl < min(16, (int)ARLightCount()); pl++)
            {
                LightInfo li = ARGetLight(pl);
                float3 lc = ToLinear(UnpackLight(li.packedData).color);
                float warmL = saturate((lc.r - lc.b) / max(Max3(lc), 0.01));
                puddle *= lerp(1.0, smoothstep(1.5, 3.0, length(li.position - pos)), warmL);
            }
        }
    }

    // suelo mojado: un poco mas oscuro
    col *= lerp(1.0, AR_HYB_WET_DARK, wet * (1.0 - puddle));
    if (puddle <= 0.001) return col;

    // gotas: ondas circulares (dos capas)
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
    rip *= 0.10 * rain;
    float3 pn3 = normalize(float3(rip.x, 1.0, rip.y));
    float3 rd = reflect(d, pn3);
    if (rd.y < 0.01) rd = normalize(float3(rd.x, 0.01, rd.z));

    // que se refleja: cielo de Aurora, o lo que el juego ya dibujo en pantalla
    float3 ro = pos + float3(0, 0.02, 0);
    float rt; HitInfo rh;
    float3 refl;
    bool rsky = ArHybTrace(ro, rd, 512.0, rt, rh);
    int2 q;
    if (rsky)
    {
        // brillo del cielo medido donde ese cielo se ve en pantalla (o arriba al centro si no se ve)
        int2 qs;
        if (!ArProject(o + rd * 1000.0, qs)) qs = int2(g_view.displayResolution.x * 0.5, 8);
        refl = SkyBase(rd) * ArSkyScale(qs);
    }
    else
    {
        float3 hp = ro + rd * rt;
        float3 toH = hp - o;
        float lh = length(toH);
        if (ArProject(hp, q) && TraceVisibility(o, toH / lh, lh - 0.05) > 0.5)
            refl = ArVanillaColor(q);             // lo reflejado se ve en pantalla: se copia del juego
        else
            refl = col * 0.6;                     // no se ve: aproximado con la luz de este mismo punto
    }
    float cosV = saturate(dot(-d, pn3));
    float F = max(0.02 + 0.98 * pow(1.0 - cosV, 5.0), AR_PUDDLE_F_MIN);
    float3 under = col * AR_HYB_PUDDLE_DARK;
    float3 wetCol = under * (1.0 - F) + refl * F;
    if (any(isnan(wetCol)) || any(isinf(wetCol))) return col;
    return lerp(col, wetCol, puddle);
}
#endif


// v81 DIAGNOSTICO: con vision nocturna muestra numeros arriba a la izquierda (fila 1: altura que usa Aurora para las nubes,
// fila 2: origen del agua del juego (y), fila 3: camara en "steve space" (y), filas 4-5: X y Z que usa Aurora)
static const uint kArFont[11] = { 0x7B6F, 0x2C97, 0x73E7, 0x73CF, 0x5BC9, 0x79CF, 0x79EF, 0x7249, 0x7BEF, 0x7BCF, 0x01C0 };
bool ArDiagNumber(int2 p, int2 org, float v)
{
    const int cs = 6;                       // tamano de cada cuadrito
    int2 q = p - org;
    if (q.y < 0 || q.y >= 5 * cs || q.x < 0 || q.x >= 9 * 4 * cs) return false;
    int ci = q.x / (4 * cs);                // caracter
    int cx = (q.x % (4 * cs)) / cs;         // columna 0..3 (3 = espacio)
    int cy = q.y / cs;
    if (cx >= 3) return false;
    int iv = (int)round(abs(v));
    bool neg = v < -0.5;
    // caracter 0 = signo, 1..8 = digitos
    uint glyph = 0;
    if (ci == 0) { if (!neg) return false; glyph = kArFont[10]; }
    else
    {
        int pos = 8 - ci;                   // potencia de 10
        int pw = 1; for (int k = 0; k < pos; k++) pw *= 10;
        if (iv < pw && pos > 0) return false;   // sin ceros a la izquierda
        glyph = kArFont[(iv / pw) % 10];
    }
    uint bit = 14 - (cy * 3 + cx);
    return ((glyph >> bit) & 1) != 0;
}

// v82: altura real de la camara. ToWorld().y se repite cada 1024 bloques; el suelo del mundo normal esta entre -64 y 320,
// asi que con la distancia al suelo justo debajo se sabe cuantas "vueltas" hay.
void ArComputeCloudOffset()
{
    // v88: altura REAL con la niebla por altura del juego. ToWorld().y da la vuelta cada 1024 bloques, pero
    // heightToFogBias / heightToFogScale sube parejo con la altura real (medido con la v87: 450 -> 1854, 1196 -> 7328,
    // escala 0.007353; la diferencia con la altura real es una constante de unos -200 bloques, menor a media vuelta).
    float aurY = ToWorld(g_view.viewOriginSteveSpace).y;
    float k = 0.0;
    if (abs(g_view.heightToFogScale) > 1e-7)
    {
        float fogY = (g_view.viewOriginSteveSpace.y * g_view.heightToFogScale + g_view.heightToFogBias) / g_view.heightToFogScale;
        k = max(round((fogY - aurY) / AR_WORLD_WRAP), 0.0);
    }
    float realY = aurY + k * AR_WORLD_WRAP;
    g_arCloudOff = max(floor(realY / AR_CLOUD_REPEAT), 0.0) * AR_CLOUD_REPEAT - k * AR_WORLD_WRAP;
}
// v89: nubes volumetricas de Aurora dentro de los reflejos (agua, hielo, metales, vidrio liso).
// El reflejo lo dibuja el RTX del juego con su propio cielo (sin nuestras nubes); aqui, si el rayo reflejado
// ve cielo, se ponen encima las nubes de Aurora con la fuerza del reflejo de esa superficie.
#define AR_HYB_REFL_CLOUDS 1
#define AR_HYB_REFL_ROUGH  0.30   // superficies mas asperas que esto no reciben nubes en el reflejo
float3 ArHybReflClouds(float3 col, float3 o, float3 d, HitInfo hit, float dist)
{
    if (dist > 400.0) return col;
    ObjectInstance obj = objectInstances[hit.objectInstanceIndex];
    bool water = hit.materialType == MATERIAL_TYPE_WATER;
    if (!water && (obj.flags & kObjectInstanceFlagChunk) == 0) return col;
    GeometryInfo gi = GetGeometryInfo(hit, obj);
    float3 n = water ? float3(0, 1, 0) : normalize(gi.modelSpaceGeometryNormal);
    if (dot(n, d) > 0) n = -n;
    float rough = 0, metal = 0; float3 alb = 1;
    if (!water)
    {
        SurfaceInfo si = MaterialVanilla(hit, gi, obj);
        rough = si.roughness; metal = si.metalness; alb = si.color;
        if (rough > AR_HYB_REFL_ROUGH) return col;
    }
    float3 R = reflect(d, n);
    if (R.y < 0.03) return col;
    float3 pos = o + d * dist + n * 0.03;
    float rt; HitInfo rh;
    if (!ArHybTrace(pos, R, 10000.0, rt, rh)) return col;    // lo reflejado no es cielo
    float T;
    float3 scat = CloudsMarch(pos, R, 10000.0, T);
    float cosV = saturate(dot(-d, n));
    float fres = 0.02 + 0.98 * pow(1.0 - cosV, 5.0);
    float F = lerp(fres, 1.0, metal) * saturate(1.0 - rough / AR_HYB_REFL_ROUGH) * (water ? 1.0 : 0.9);
    float3 tint = lerp(1.0.xxx, alb, metal);
    float3 res = col * lerp(1.0, T, F) + scat * gs_scale * F * tint;
    return (any(isnan(res)) || any(isinf(res))) ? col : res;
}

[numthreads(16, 16, 1)]
void CopyToFinal(
    uint3 dispatchThreadID : SV_DispatchThreadID,
    uint3 groupThreadID : SV_GroupThreadID,
    uint groupIndex : SV_GroupIndex,
    uint3 groupID : SV_GroupID
    )
{
    if (HasSun()) ArComputeCloudOffset();   // v82: antes de todo lo que dibuja nubes
    gs_scale = 1.0;
    if (HasSun()) ArSkyScaleGroup(groupIndex);   // v72: todos los hilos del grupo (antes de salir)
    if (any(dispatchThreadID.xy >= g_view.displayResolution)) return;
    int2 p = int2(dispatchThreadID.xy);
    g_arPixel = dispatchThreadID.xy;
    g_arGRJitter = 0.5;   // sin filtro despues: rayos de sol sin patron de puntos

    float3 col = ArVanillaColor(p);   // imagen terminada del RTX original

    float3 o = g_view.viewOriginSteveSpace;
    float3 d = ArCameraDir(float2(p));
    bool under = g_view.cameraIsUnderWater != 0 || g_view.cameraIsUnderLava != 0;

    bool isEnd = AR_HYB_END && IsEnd();
    bool overworld = HasSun() && !under;
    float sunK = ArSunScale();
    float dist = 10000.0;
    bool sky = false;
    HitInfo hit = (HitInfo)0;
    if (overworld) sky = ArHybTrace(o, d, 10000.0, dist, hit);
    // v72: vidrio que el juego dibuja negro (vidrio de Patrix): si detras del vidrio hay cielo, se pone el cielo de Aurora
    float glassK = 1.0;
    if (overworld && !sky && hit.materialType == MATERIAL_TYPE_ALPHA_BLEND && hit.rayT < 64.0)
    {
        float3 go = o + d * (hit.rayT + 0.02);
        float gd; HitInfo gh;
        bool gs = false;
        [loop] for (int gl = 0; gl < 3; gl++)
        {
            gs = ArHybTrace(go, d, 10000.0, gd, gh);
            if (gs || gh.materialType != MATERIAL_TYPE_ALPHA_BLEND) break;
            go += d * (gd + 0.02);
        }
        if (gs) { sky = true; glassK = AR_HYB_GLASS_SKY; }
    }

    // el render de Aurora se llama en UN solo lugar (End completo, o solo el cielo del mundo normal)
    if (isEnd || (AR_HYB_SKY && sky))
    {
        RayDesc rd;
        rd.Origin = o; rd.Direction = d; rd.TMin = 0; rd.TMax = 10000;
        float hd; float3 hm;
        // v74: en el mundo normal el rayo de Aurora ve lo mismo que la camara del juego; antes tambien chocaba con
        // mallas del cielo del juego (discos a cierta altura) que se veian como circulos al subir hacia las nubes
        if (!isEnd) g_arPrimaryMask = INSTANCE_MASK_OPAQUE_OR_ALPHA_TEST_PRIMARY | INSTANCE_MASK_ALPHA_BLEND_PRIMARY | INSTANCE_MASK_WATER;
        float3 s = RenderRay(rd, hd, hm);
        float k = isEnd ? sunK * AR_HYB_END_K : ArSkyScale(p);   // End: luz del agujero negro; cielo: exposicion del juego
        if (all(s >= 0.0) && !any(isinf(s)) && k > 0.0) col = s * k * glassK;
    }
    else if (overworld)
    {
        // v74: portal del End en el mundo normal: el juego lo dibuja negro; se pone el espacio con estrellas de Aurora
        if (hit.materialType == MATERIAL_TYPE_OPAQUE && dist < 256.0)
        {
            ObjectInstance pobj = objectInstances[hit.objectInstanceIndex];
            float3 ppos = o + d * dist;
            float3 pwp = ToWorld(ppos);
            if ((pobj.flags & kObjectInstanceFlagChunk) != 0 && d.y < -0.05 && abs(frac(pwp.y) - 0.75) < 0.03)
            {
                GeometryInfo pgi = GetGeometryInfo(hit, pobj);
                if (abs(pgi.modelSpaceGeometryNormal.y) > 0.9)
                {
                    SurfaceInfo psi = MaterialVanilla(hit, pgi, pobj);
                    if (Max3(psi.color) < 0.05) col = PortalSpace(pwp, d) * gs_scale * AR_HYB_PORTAL_K;
                }
            }
        }
#if AR_HYB_PUDDLES
        col = ArHybRain(col, p, o, d, hit);
#endif
#if AR_HYB_REFL_CLOUDS
        if (hit.materialType != MATERIAL_TYPE_ALPHA_TEST) col = ArHybReflClouds(col, o, d, hit, dist);
#endif
        // v79: nubes vistas desde arriba (o entre la camara y el suelo): antes solo se dibujaban donde se veia cielo,
        // asi que al subir encima de ellas desaparecian sobre el terreno y "reaparecian" mas arriba
        if (ToWorld(o).y > AR_CLOUD_BASE - 50.0)
        {
            float cT;
            float3 cs = CloudsMarch(o, d, dist, cT);
            if (all(cs >= 0.0) && !any(isinf(cs)) && cT >= 0.0) col = col * cT + cs * gs_scale;
        }
#if AR_HYB_GODRAYS
        float3 gr = GodRays(o, d, dist);
        if (all(gr >= 0.0) && !any(isinf(gr))) col += gr * sunK * AR_HYB_GODRAY_K;
#endif
    }

    if (overworld)
    {
#if AR_HYB_GLARE
        // destello del sol: halo suave + reflejos de lente, solo si el sol se ve desde la camara
        float3 Ls = getTrueDirectionToSun();
        float4 scs = mul(float4(o + Ls * 1000.0, 1), g_view.viewProj);
        if (scs.w > 0.0 && Ls.y > -0.02 && TraceVisibility(o, Ls, 10000.0) > 0.5)
        {
            float2 res = g_view.displayResolution;
            float2 sunUV = (scs.xy / scs.w) * float2(0.5, -0.5) + 0.5;
            float2 uv = (float2(p) + 0.5) / res;
            float2 asp = float2(res.x / res.y, 1.0);
            float dS = length((uv - sunUV) * asp);
            float3 L2; float3 lcs = PrimaryLightColor(L2);
            float glare = exp(-dS * 9.0) * 0.5 + exp(-dS * 3.0) * 0.15;
            float ghosts = 0;
            [unroll] for (int g = 1; g <= 3; g++)
            {
                float2 gp = 0.5 + (0.5 - sunUV) * (0.35 * g);
                float gd = length((uv - gp) * asp);
                ghosts += exp(-pow(gd * (18.0 + g * 6.0), 2.0)) * (0.12 / g);
            }
            col += lcs * (glare + ghosts) * 0.25 * (1.0 - ArRainLevel()) * sunK * AR_HYB_GODRAY_K;
        }
#endif
    }

    if (any(isnan(col)) || any(isinf(col))) col = ArVanillaColor(p);
#if AR_DIAG_NUMBERS
    if (g_view.nightVisionLevel > 0.0)
    {
        float3 cw = ToWorld(g_view.viewOriginSteveSpace);
        float vals[5] = { cw.y, g_view.waveWorksOriginInSteveSpace.y, g_view.viewOriginSteveSpace.y, cw.x, cw.z };
        [loop] for (int r = 0; r < 5; r++)
        {
            int2 org = int2(40, 300 + r * 44);
            int2 qq = p - org;
            if (qq.x >= -6 && qq.y >= -6 && qq.x < 9 * 24 + 6 && qq.y < 36) col = float3(0, 0, 0);   // fondo negro
            if (ArDiagNumber(p, org, vals[r])) col = r == 0 ? float3(4, 4, 0) : float3(4, 4, 4);
        }
    }
#endif
    outputBufferFinal[p] = float4(max(col, 0.0), 0);
}
