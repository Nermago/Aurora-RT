// =====================================================================================
// Aurora RT - LUCES (lamparas del juego: antorchas, faroles, varas del End...)
// v41: todo lo de las lamparas vive aqui, separado del agua, el cielo y el End.
// =====================================================================================

// ---------------- Ajustes ----------------
#define AR_POINT_LIGHTS       256    // cuantas lamparas de la lista del juego se revisan
#define AR_POINT_SHADOWS      4      // lamparas con sombra por pixel (las que mas iluminan). Antes 10.
#define AR_POINT_STRENGTH     600.0  // fuerza de las lamparas
#define AR_POINT_RANGE        22.0   // v49: antes 15 (se veia un circulo de luz)
#define AR_LAMP_FILL          0.25   // v49: luz que rebota y llena el cuarto (paredes lejanas, rincones)
#define AR_LAMP_FILL_LEAK     0.15   // v49: cuanto de ese relleno pasa aunque la lampara no se vea directo
#define AR_GLASS_LIGHT_TINT   0.90   // cuanto tine el vidrio de color la luz de las lamparas (0 = nada, 1 = todo)
#define AR_GLASS_LIGHT_LOSS   0.10   // cuanta luz se pierde al cruzar un bloque de vidrio
#define AR_LEAF_LIGHT_PASS    0.45   // cuanta luz de lampara pasa entre hojas, flores, rejas
#define AR_LAMP_MAX_CANDIDATES 12    // hojas/vidrios revisados por rayo de sombra; despues se da por bloqueado

// Tinte del vidrio para la luz: color del vidrio con su brillo completo (claro, no oscuro).
// Cada bloque tiene 2 caras que el rayo cruza, asi que cada cara pone la raiz del tinte del bloque:
// el color queda aplicado UNA vez por bloque (antes se aplicaba dos veces y la luz salia apagada).
float3 ARGlassFaceTint(float3 glassColor, float alpha)
{
    float3 c = ToLinear(glassColor);
    c /= max(Max3(c), 0.05);                                   // mismo color, brillo completo
    float a = saturate(alpha);
    float3 block = lerp(1.0.xxx, c, a * AR_GLASS_LIGHT_TINT) * (1.0 - a * AR_GLASS_LIGHT_LOSS);
    return sqrt(saturate(block));
}

// Sombra de una lampara: un solo rayo que se detiene en el PRIMER bloque solido que encuentra
// (no busca el mas cercano: para una sombra da igual y es mas rapido). Hojas dejan pasar algo de luz
// y el vidrio de color la tine.
float3 ARLampShadow(float3 origin, float3 dir, float tMax)
{
    RayDesc r;
    r.Origin = origin;
    r.Direction = dir;
    r.TMin = 0.0;
    r.TMax = tMax;
    float3 transmit = 1.0;
    uint mask = INSTANCE_MASK_OPAQUE_OR_ALPHA_TEST_SECONDARY;
#if AR_GLASS_TINT
    mask |= INSTANCE_MASK_ALPHA_BLEND_SECONDARY;
#endif
    RayQuery<RAY_FLAG_NONE> q;
    q.TraceRayInline(SceneBVH, RAY_FLAG_SKIP_PROCEDURAL_PRIMITIVES | RAY_FLAG_ACCEPT_FIRST_HIT_AND_END_SEARCH, mask, r);
    int cand = 0;
    while (q.Proceed())
    {
        if (++cand > AR_LAMP_MAX_CANDIDATES) { q.CommitNonOpaqueTriangleHit(); q.Abort(); continue; }
        HitInfo hitInfo = GetCandidateHitInfo(q);
        if (hitInfo.materialType == MATERIAL_TYPE_ALPHA_TEST)
            transmit *= AR_LEAF_LIGHT_PASS;
        else if (hitInfo.materialType == MATERIAL_TYPE_ALPHA_BLEND)
        {
            ObjectInstance obj = objectInstances[hitInfo.objectInstanceIndex];
            GeometryInfo geo = GetGeometryInfo(hitInfo, obj);
            SurfaceInfo surf = MaterialVanilla(hitInfo, geo, obj);
            transmit *= ARGlassFaceTint(surf.color, surf.alpha);
        }
        else
        {
            q.CommitNonOpaqueTriangleHit();
            q.Abort();
            continue;
        }
        if (Max3(transmit) < 0.03) { q.CommitNonOpaqueTriangleHit(); q.Abort(); }
    }
    if (q.CommittedStatus() == COMMITTED_TRIANGLE_HIT) return 0.0;
    return transmit;
}

// Luz de una lampara del juego en un punto (sin sombra).
// v49: ademas de la luz directa devuelve "fill": luz rebotada falsa que baja mas despacio con la distancia
// y no depende de hacia donde mira la cara (asi el cuarto entero se ilumina, no solo un circulo)
float3 ARPointContrib(LightInfo li, float3 pos, float3 n, out float3 lDir, out float lDist, out float3 fill)
{
    fill = 0;
    lDir = li.position - pos;
    lDist = max(length(lDir), 0.35);
    lDir /= lDist;
    if (lDist > AR_POINT_RANGE) return 0;
    float ndl = saturate(dot(n, lDir));
    LightData ld = UnpackLight(li.packedData);
    float x = lDist / AR_POINT_RANGE;
    float range = saturate(1.0 - x * x);   // v49: borde mas suave (antes x^4: se cortaba de golpe)
    float3 lc = ToLinear(ld.color);
    lc /= max(Max3(lc), 0.05);
    float warm = saturate((lc.r - max(lc.g, lc.b)) * 2.0);   // las rojas un poco menos; las frias mas
    lc *= lerp(1.35, 0.75, warm);
    float3 base = AR_POINT_STRENGTH * range * range * ld.intensity * lc;
    fill = base * AR_LAMP_FILL * (0.6 + 0.4 * ndl) / (lDist * lDist * 0.35 + 6.0);
    return base * ndl / (lDist * lDist + 1.0);
}

// Todas las lamparas cercanas: se eligen las que MAS iluminan este punto (no las primeras de la lista),
// asi la luz no cambia de golpe al moverte ni se "apagan" lamparas cuando hay muchas
#define AR_SEL_MAX 12
float3 ARPointLights(float3 pos, float3 shadePos, float3 n, int maxSel)
{
    maxSel = clamp(maxSel, 1, AR_SEL_MAX);
    int selIdx[AR_SEL_MAX];
    float selImp[AR_SEL_MAX];
    [unroll] for (int k = 0; k < AR_SEL_MAX; k++) { selIdx[k] = -1; selImp[k] = 0; }
    int cnt = min(AR_POINT_LIGHTS, (int)ARLightCount());
    for (int i = 0; i < cnt; i++)
    {
        LightInfo li = ARGetLight(i);
        float3 dd = li.position - pos;
        if (dot(dd, dd) > AR_POINT_RANGE * AR_POINT_RANGE) continue;
        float3 lDir; float lDist; float3 fill;
        float3 dc = ARPointContrib(li, pos, n, lDir, lDist, fill);
        float imp = Luma(dc + fill);
        if (imp <= 0.002 || imp <= selImp[maxSel - 1]) continue;
        // insertar ordenado (de mayor a menor)
        int at = maxSel - 1;
        [unroll] for (int k2 = AR_SEL_MAX - 1; k2 > 0; k2--)
        {
            if (k2 < maxSel && k2 <= at && imp > selImp[k2 - 1])
            {
                selImp[k2] = selImp[k2 - 1];
                selIdx[k2] = selIdx[k2 - 1];
                at = k2 - 1;
            }
        }
        selImp[at] = imp;
        selIdx[at] = i;
    }
    float3 sum = 0;
    [unroll] for (int j = 0; j < AR_SEL_MAX; j++)
    {
        if (j >= maxSel || selIdx[j] < 0) continue;
        LightInfo li = ARGetLight(selIdx[j]);
        float3 lDir; float lDist; float3 fill;
        float3 c = ARPointContrib(li, pos, n, lDir, lDist, fill);
        float3 sh = ARLampShadow(shadePos, lDir, max(lDist - 0.3, 0.01));   // sombra (el vidrio de color la tine)
        sum += c * sh + fill * lerp(AR_LAMP_FILL_LEAK.xxx, 1.0.xxx, sh);
    }
    return sum;
}
