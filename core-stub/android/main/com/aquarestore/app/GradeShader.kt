package com.aquarestore.app

/** The basic grade as a GLSL fragment shader; matches [ColorGrade.pixel]. Every uniform must stay in use. */
internal object GradeShader {
    const val FRAGMENT = """
        precision highp float;
        uniform sampler2D uTexture;
        uniform vec4 uA;
        uniform vec4 uB;
        uniform vec4 uBlack;
        uniform vec4 uWhite;
        uniform float uLevels;
        uniform float uStrength;
        uniform float uCoolProtection;
        uniform int uHdr;
        uniform float uClarity;
        uniform vec2 uTexel;
        uniform float uRadius;
        varying vec2 vUv;
        // HDR arrives as linear light (1.0 = 1000 nits) and is graded on the HLG curve.
        const float HLG_A = 0.17883277;
        const float HLG_B = 0.28466892;
        const float HLG_C = 0.55991073;
        vec3 encodeHlg(vec3 linear) {
            vec3 e = max(linear, vec3(0.0));
            return mix(sqrt(3.0*e), HLG_A*log(max(12.0*e-HLG_B, vec3(1e-6)))+HLG_C, step(vec3(1.0/12.0), e));
        }
        vec3 decodeHlg(vec3 x) {
            return mix(x*x/3.0, (exp((x-HLG_C)/HLG_A)+HLG_B)/12.0, step(vec3(0.5), x));
        }
        float lumaAt(vec2 offset) {
            vec3 s = texture2D(uTexture, vUv + offset * uTexel).rgb;
            return uHdr == 1 ? dot(clamp(encodeHlg(s), 0.0, 1.5), vec3(0.2627,0.6780,0.0593))
                : dot(s, vec3(0.2126,0.7152,0.0722));
        }
        void main() {
            vec4 tex = texture2D(uTexture, vUv);
            if (uStrength <= 0.0) { gl_FragColor = tex; return; }
            float top = uHdr == 1 ? 1.5 : 1.0;
            vec3 original = clamp(uHdr == 1 ? encodeHlg(tex.rgb) : tex.rgb, 0.0, top);
            vec3 c = original;
            if (uHdr == 0) c = mix(c, clamp((c-uBlack.rgb)/(uWhite.rgb-uBlack.rgb), 0.0, 1.0), uLevels);
            c *= vec3((1.0+0.5*uA.x)*(1.0+0.2*uA.y), 1.0-0.2*uA.z, 1.0-0.2*uA.y) * exp2(uA.w);
            c = (c-0.5)*(1.0+uB.y+0.5*uB.x)+0.5;
            float luma = dot(c, uHdr == 1 ? vec3(0.2627,0.6780,0.0593) : vec3(0.2126,0.7152,0.0722));
            float lift = uB.w*0.2*pow(1.0-clamp(luma,0.0,1.0),2.0);
            c = vec3(luma)+(c-luma)*(1.0+uB.z)+lift;
            c.r += (min(c.r,c.g)-c.r)*uCoolProtection*0.5;
            if (uClarity != 0.0) {
                float blur = (lumaAt(vec2(uRadius,0.0))+lumaAt(vec2(-uRadius,0.0))+
                    lumaAt(vec2(0.0,uRadius))+lumaAt(vec2(0.0,-uRadius)))/4.0;
                c += uClarity*2.0*(lumaAt(vec2(0.0))-blur);
            }
            c = mix(original,clamp(c,0.0,top),uStrength);
            gl_FragColor = vec4(uHdr == 1 ? decodeHlg(c) : c,tex.a);
        }
    """
}
