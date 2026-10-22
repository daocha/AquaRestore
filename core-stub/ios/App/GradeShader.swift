/// The basic grade as a Metal compute kernel; `MetalGrader` fills its `Params`.
enum GradeShader {
    // Public stand-in for the private grading core; matches `ColorGrade.pixel` in core-stub.
    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct Params {
        float4 a; float4 b; float4 black; float4 white;
        float levels; float strength; int mode; float coolProtection;
        float4 m0; float4 m1; float2 displaySize; float2 naturalSize;
        int taps; int3 pad2;
        float clarity; float radius; float2 pad3;
    };

    constant float HLG_A = 0.17883277;
    constant float HLG_B = 0.28466892;
    constant float HLG_C = 0.55991073;
    float3 encodeHlg(float3 lin) {
        float3 e = max(lin, float3(0.0));
        return select(HLG_A * log(max(12.0 * e - HLG_B, float3(1e-6))) + HLG_C, sqrt(3.0 * e), e < float3(1.0 / 12.0));
    }
    float3 decodeHlg(float3 x) {
        return select(x * x / 3.0, (exp((x - HLG_C) / HLG_A) + HLG_B) / 12.0, x >= float3(0.5));
    }
    constant float PQ_M1 = 0.1593017578125;
    constant float PQ_M2 = 78.84375;
    constant float PQ_C1 = 0.8359375;
    constant float PQ_C2 = 18.8515625;
    constant float PQ_C3 = 18.6875;
    float3 pqToLinear(float3 x) {
        float3 p = pow(clamp(x, 0.0, 1.0), float3(1.0 / PQ_M2));
        return pow(max(p - PQ_C1, float3(0.0)) / (PQ_C2 - PQ_C3 * p), float3(1.0 / PQ_M1)) * 10.0;
    }
    float3 linearToPq(float3 lin) {
        float3 y = clamp(lin / 10.0, 0.0, 1.0);
        float3 p = pow(y, float3(PQ_M1));
        return pow((PQ_C1 + PQ_C2 * p) / (1.0 + PQ_C3 * p), float3(PQ_M2));
    }

    // Luma of the ungraded source in the grading encoding, as in `Clarity.detail` on the CPU.
    // `d` is in display coordinates; `step` is one output pixel.
    float lumaAt(texture2d<float, access::sample> src, sampler smp, constant Params& P, float2 d) {
        float2 s = float2(P.m0.x * d.x + P.m0.y * d.y + P.m0.z, P.m1.x * d.x + P.m1.y * d.y + P.m1.z);
        float3 t = src.sample(smp, s / P.naturalSize).rgb;
        if (P.mode == 2) { t = encodeHlg(pqToLinear(t)); }
        return dot(clamp(t, 0.0, P.mode != 0 ? 1.5 : 1.0),
                   P.mode != 0 ? float3(0.2627, 0.6780, 0.0593) : float3(0.2126, 0.7152, 0.0722));
    }
    kernel void grade(texture2d<float, access::sample> src [[texture(0)]],
                      texture2d<float, access::write> dst [[texture(1)]],
                      constant Params& P [[buffer(0)]],
                      uint2 gid [[thread_position_in_grid]]) {
        uint w = dst.get_width(), h = dst.get_height();
        if (gid.x >= w || gid.y >= h) return;
        constexpr sampler smp(filter::linear, address::clamp_to_edge, coord::normalized);
        float4 tex = float4(0.0);
        int n = max(P.taps, 1);
        for (int j = 0; j < n; j++) {
            for (int i = 0; i < n; i++) {
                float2 sub = (float2(i, j) + 0.5) / float(n);
                float2 d = (float2(gid) + sub) / float2(w, h) * P.displaySize;
                float2 s = float2(P.m0.x * d.x + P.m0.y * d.y + P.m0.z, P.m1.x * d.x + P.m1.y * d.y + P.m1.z);
                tex += src.sample(smp, s / P.naturalSize);
            }
        }
        tex /= float(n * n);
        if (P.strength <= 0.0) { dst.write(tex, gid); return; }

        bool hdr = P.mode != 0;
        float top = hdr ? 1.5 : 1.0;
        float3 lin = float3(0.0);
        float3 original = tex.rgb;
        if (P.mode == 1) { lin = decodeHlg(tex.rgb); }
        else if (P.mode == 2) { lin = pqToLinear(tex.rgb); original = encodeHlg(lin); }
        original = clamp(original, 0.0, top);
        float3 c = hdr ? encodeHlg(lin) : original;
        if (!hdr) { c = mix(c, clamp((c - P.black.rgb) / (P.white.rgb - P.black.rgb), 0.0, 1.0), P.levels); }
        c *= float3((1.0 + 0.5 * P.a.x) * (1.0 + 0.2 * P.a.y), 1.0 - 0.2 * P.a.z, 1.0 - 0.2 * P.a.y) * exp2(P.a.w);
        c = (c - 0.5) * (1.0 + P.b.y + 0.5 * P.b.x) + 0.5;
        float luma = dot(c, hdr ? float3(0.2627, 0.6780, 0.0593) : float3(0.2126, 0.7152, 0.0722));
        float lift = P.b.w * 0.2 * pow(1.0 - clamp(luma, 0.0, 1.0), 2.0);
        c = float3(luma) + (c - luma) * (1.0 + P.b.z) + lift;
        c.r += (min(c.r, c.g) - c.r) * P.coolProtection * 0.5;
        if (P.clarity != 0.0) {
            float2 step = P.displaySize / float2(w, h);
            float2 d = (float2(gid) + 0.5) * step;
            float blur = (lumaAt(src, smp, P, d + float2(P.radius, 0.0) * step) + lumaAt(src, smp, P, d - float2(P.radius, 0.0) * step) +
                          lumaAt(src, smp, P, d + float2(0.0, P.radius) * step) + lumaAt(src, smp, P, d - float2(0.0, P.radius) * step)) / 4.0;
            c += P.clarity * 2.0 * (lumaAt(src, smp, P, d) - blur);
        }
        c = mix(original, clamp(c, 0.0, top), P.strength);
        float3 result = c;
        if (P.mode == 1) { result = clamp(c, 0.0, 1.0); }
        else if (P.mode == 2) { result = linearToPq(decodeHlg(c)); }
        dst.write(float4(result, tex.a), gid);
    }
    """
}
