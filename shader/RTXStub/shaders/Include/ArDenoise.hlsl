// Aurora RT - limpieza de la luz rebotada en varios pasos (estilo SVGF)
//  denoisingOutputs[0] / [1] : luz filtrada (rgb) + varianza (a)  (se alternan)
//  denoisingOutputs[4]       : valor de la cache de la cara (rgb) + confianza (a)
//  denoisingOutputs[5]       : luz recien calculada este frame (rgb) + 1 si se calculo
//  denoisingOutputs[6] / [7] : momentos para la varianza + largo del historial (se alternan por frame)
//  outputPrimaryWorldPosition: donde se calcula la luz (xyz) + 1 si hay luz rebotada
#ifndef AR_DENOISE_HLSL
#define AR_DENOISE_HLSL

#define AR_GI_CHECKER     1      // la luz rebotada se calcula en medio pixel por frame (alternando): mas FPS
#define AR_DIFFUSE_RAYS   3      // rayos por pixel calculado
#define AR_MAX_HISTORY    32.0   // frames que se promedian como maximo
#define AR_MIN_ALPHA      0.045  // peso minimo del frame nuevo (luz que cambia se actualiza rapido)
#define AR_ATROUS_ITERS   4      // pasadas del filtro espacial (radio ~30 px)
#define AR_PHI_COLOR      4.0
#define AR_PHI_PLANE      6.0
#define AR_PHI_NORMAL     64.0
#define AR_SUN_GLARE      1      // halo y reflejos de lente del sol

float3 ArDecodeNormal(float2 o)
{
    float3 n = float3(o, 1.0 - abs(o.x) - abs(o.y));
    if (n.z < 0) n.xy = (1.0 - abs(n.yx)) * float2(n.x >= 0 ? 1 : -1, n.y >= 0 ? 1 : -1);
    return normalize(n);
}

float2 ArEncodeNormal(float3 n)
{
    float3 nn = n / (abs(n.x) + abs(n.y) + abs(n.z));
    return nn.z >= 0 ? nn.xy : (1.0 - abs(nn.yx)) * float2(nn.x >= 0 ? 1 : -1, nn.y >= 0 ? 1 : -1);
}

bool ArFinite3(float3 v) { return !any(isnan(v)) && !any(isinf(v)); }
bool ArFinite4(float4 v) { return !any(isnan(v)) && !any(isinf(v)); }

#endif
