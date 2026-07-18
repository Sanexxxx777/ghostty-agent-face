// Ghostty "living face" agent-status background shader.
// Signal channel = terminal background color set via OSC 11 (invisible to the eye).
// Visible background is ALWAYS forced back to BASE_BG; only the face changes.
// custom-shader-animation = always   (needed for continuous breathing/blink)

// BASE_BG MUST equal your real Ghostty background-color (default #282c34).
// If you change theme, update this constant.
const vec3 BASE_BG = vec3(40.0, 44.0, 52.0) / 255.0;

float luma(vec3 c){ return dot(c, vec3(0.299, 0.587, 0.114)); }
vec3  darker(vec3 a, vec3 b){ return mix(a, b, step(luma(b), luma(a))); }
float hash21(vec2 p){ p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float sdRoundBox(vec2 p, vec2 b, float r){ vec2 d = abs(p) - b + r; return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - r; }

void mainImage(out vec4 fragColor, in vec2 fragCoord){
    vec2 R  = iResolution.xy;
    vec2 uv = fragCoord / R;

    // ---------- 1. sample signal color from darkest corner (avoid text) ----------
    vec3 c0 = texture(iChannel0, vec2(0.03, 0.03)).rgb;
    vec3 c1 = texture(iChannel0, vec2(0.97, 0.03)).rgb;
    vec3 c2 = texture(iChannel0, vec2(0.03, 0.97)).rgb;
    vec3 c3 = texture(iChannel0, vec2(0.97, 0.97)).rgb;
    vec3 bg = darker(darker(c0, c1), darker(c2, c3));

    // ---------- 2. classify by channel RATIOS (branchless one-hot) ----------
    float eps  = 0.001;
    float sum  = bg.r + bg.g + bg.b + eps;
    float rn   = bg.r / sum;              // red fraction
    float gn   = bg.g / sum;              // green fraction
    float bn   = bg.b / sum;              // blue fraction (small for RUN/ATTN, big for neutral themes)
    float rg   = bg.r / (bg.g + eps);     // red / green
    float gb   = bg.g / (bg.b + eps);     // green / blue

    float blueSmall = 1.0 - smoothstep(0.14, 0.24, bn);
    float wDone  = smoothstep(0.42, 0.52, gn) * smoothstep(1.15, 1.5, gb);
    float wAttn  = smoothstep(2.0, 2.6, rg) * blueSmall * (1.0 - wDone);
    float wRun   = smoothstep(1.2, 1.4, rg) * (1.0 - smoothstep(2.0, 2.6, rg)) * blueSmall * (1.0 - wDone);
    float wWork  = (1.0 - smoothstep(0.09, 0.14, rn)) * smoothstep(0.36, 0.44, bn) * (1.0 - wDone); // cyan signal
    float wDizzy = (1.0 - smoothstep(0.10, 0.15, gn)) * smoothstep(0.40, 0.46, bn);                 // purple signal
    float wIdle = clamp(1.0 - wRun - wDone - wAttn - wWork - wDizzy, 0.0, 1.0);
    float wsum  = wIdle + wRun + wDone + wAttn + wWork + wDizzy + eps;
    wIdle /= wsum; wRun /= wsum; wDone /= wsum; wAttn /= wsum; wWork /= wsum; wDizzy /= wsum;
    float signalActive = 1.0 - wIdle;     // 0 in IDLE -> pass-through

    // ---------- 3. per-state colors & morph parameters (blended) ----------
    vec3 cIdle  = vec3(0.45, 0.55, 0.72);
    vec3 cRun   = vec3(0.98, 0.72, 0.22);
    vec3 cDone  = vec3(0.30, 0.95, 0.52);
    vec3 cAttn  = vec3(1.00, 0.42, 0.18);
    vec3 cWork  = vec3(0.95, 0.82, 0.35);
    vec3 cDizzy = vec3(0.72, 0.45, 0.95);
    vec3 faceCol = wIdle*cIdle + wRun*cRun + wDone*cDone + wAttn*cAttn + wWork*cWork + wDizzy*cDizzy;

    float eyeAsp   = wIdle*0.42 + wRun*0.95 + wDone*0.80 + wAttn*1.10 + wWork*0.30 + wDizzy*0.95;
    float arcAmt   = wDone;                                            // eyes -> "^" arcs
    float oAmt     = wAttn;                                            // mouth -> "o"
    float smile    = wDone*0.11;                                       // smile depth
    float mouthW   = wIdle*0.13 + wRun*0.15 + wDone*0.30 + wAttn*0.10 + wWork*0.10 + wDizzy*0.20;
    float pupilAmt = wRun*0.9 + wAttn*0.7 + wIdle*0.35 + wWork*0.85;
    float faceAmp  = wIdle*0.55 + wRun*0.90 + wDone*1.00 + wAttn*1.00 + wWork*0.85 + wDizzy*1.00;

    // blink (mostly IDLE), Gaussian dip, ~5.5s cycle -> no pow() with negative base
    float bt = fract(iTime * 0.18);
    float bz = (bt - 0.5) / 0.02;
    float blink = 1.0 - 0.92 * exp(-bz * bz);
    float eyeBlink = mix(1.0, blink, wIdle*0.9 + 0.1);

    // life: breathe, float, RUN pulse & pupil scan
    float breathe = 1.0 + 0.02 * sin(iTime * 1.1);
    vec2  flo     = vec2(sin(iTime*0.50)*0.03, sin(iTime*0.37 + 1.3)*0.02);
    float pulse   = 1.0 + wRun*0.05*sin(iTime*3.0);
    vec2  scan    = vec2(sin(iTime*1.7)*0.03, cos(iTime*1.3)*0.015) * (wRun + wAttn*0.3)
                  + vec2(sin(iTime*0.23), 0.4*sin(iTime*0.31)) * 0.03 * wIdle   // idle: slow look-around
                  + vec2(0.3*sin(iTime*6.0), -0.5) * 0.03 * wWork;              // work: eyes down, typing jitter

    // ---------- 4. ASCII cell grid; evaluate face at CELL CENTER (blocky) ----------
    float cellH = R.y / 72.0;
    vec2  cell  = vec2(cellH * 0.5, cellH);
    vec2  cid   = floor(fragCoord / cell);
    vec2  cc    = (cid + 0.5) * cell;

    // face anchor: upper-right corner, compact size
    vec2 anchor = vec2(0.74, 0.26) * R;   // fraction of screen (x right, y from top)
    float faceScale = 0.5;
    vec2 n = (cc - anchor) / R.y;
    n.y = -n.y;                      // Metal: origin top-left -> flip so face is upright
    n -= flo;
    n /= breathe;
    n /= faceScale;

    // --- eyes ---
    float eyeW = 0.13 * pulse;
    vec2  eL = vec2(-0.22, 0.15);
    vec2  eR = vec2( 0.22, 0.15);

    vec2 pL = n - eL;
    vec2 dLe = vec2(pL.x / eyeW, pL.y / (eyeW * eyeAsp * eyeBlink));
    float discL = 1.0 - smoothstep(0.85, 1.05, length(dLe));
    float holeL = (1.0 - smoothstep(0.7, 1.0, length((pL - scan) / (eyeW * 0.45)))) * pupilAmt;
    discL *= (1.0 - holeL);
    float lxL = pL.x / eyeW;
    float arcYL = 0.05 * (0.5 - lxL * lxL);
    float arcL = (1.0 - smoothstep(0.015, 0.045, abs(pL.y - arcYL))) * (1.0 - smoothstep(0.95, 1.05, abs(lxL)));
    float eyeLv = mix(discL, arcL, arcAmt);

    vec2 pR = n - eR;
    vec2 dRe = vec2(pR.x / eyeW, pR.y / (eyeW * eyeAsp * eyeBlink));
    float discR = 1.0 - smoothstep(0.85, 1.05, length(dRe));
    float holeR = (1.0 - smoothstep(0.7, 1.0, length((pR - scan) / (eyeW * 0.45)))) * pupilAmt;
    discR *= (1.0 - holeR);
    float lxR = pR.x / eyeW;
    float arcYR = 0.05 * (0.5 - lxR * lxR);
    float arcR = (1.0 - smoothstep(0.015, 0.045, abs(pR.y - arcYR))) * (1.0 - smoothstep(0.95, 1.05, abs(lxR)));
    float eyeRv = mix(discR, arcR, arcAmt);

    // DIZZY: spinner eyes (ring with a rotating gap) replace normal eyes
    float srL = length(pL) / (eyeW * 0.9);
    float saL = atan(pL.y, pL.x);
    float gapL = step(0.5, abs(mod(saL - iTime*2.5 + 3.14159, 6.28318) - 3.14159));
    float spinL = (1.0 - smoothstep(0.85, 1.05, srL)) * smoothstep(0.55, 0.75, srL) * gapL;
    float srR = length(pR) / (eyeW * 0.9);
    float saR = atan(pR.y, pR.x);
    float gapR = step(0.5, abs(mod(saR + iTime*2.5 + 3.14159, 6.28318) - 3.14159));
    float spinR = (1.0 - smoothstep(0.85, 1.05, srR)) * smoothstep(0.55, 0.75, srR) * gapR;
    eyeLv = mix(eyeLv, spinL, wDizzy);
    eyeRv = mix(eyeRv, spinR, wDizzy);

    // --- mouth: smile stroke <-> "o" ring ---
    vec2 pM = n - vec2(0.0, -0.19);
    float lxM = pM.x / mouthW;
    float smileY = smile * (lxM * lxM - 0.33);
    float smileStroke = (1.0 - smoothstep(0.015, 0.045, abs(pM.y - smileY))) * (1.0 - smoothstep(0.95, 1.05, abs(lxM)));
    float md = length(pM);
    float oRing = (1.0 - smoothstep(0.05, 0.065, md)) * smoothstep(0.025, 0.04, md);
    float mouthV = mix(smileStroke, oRing, oAmt);

    // DIZZY: wavy mouth
    float wavyY = 0.025 * sin(lxM * 4.0 + iTime * 2.0);
    float wavy = (1.0 - smoothstep(0.015, 0.045, abs(pM.y - wavyY))) * (1.0 - smoothstep(0.95, 1.05, abs(lxM)));
    mouthV = mix(mouthV, wavy, wDizzy);

    // --- "?" beside face (RUN only), gently bobbing ---
    vec2 qp = (n - vec2(0.47, 0.12 + 0.03*sin(iTime*2.0))) / 0.16;
    float qr = length(qp - vec2(0.0, 0.5));
    float qband = (1.0 - smoothstep(0.46, 0.54, qr)) * smoothstep(0.34, 0.42, qr);
    float qa = atan(qp.y - 0.5, qp.x);
    float lower = step(-2.95, qa) * step(qa, -1.5);      // open the lower-left -> "?" hook
    float qv = qband * (1.0 - lower);
    qv = max(qv, 1.0 - smoothstep(0.09, 0.15, length(qp - vec2(0.0, -0.5)))); // dot
    qv *= wRun;

    // --- "!" beside face (ATTN only), pulsing ---
    vec2 xp = (n - vec2(0.47, 0.12)) / 0.16;
    float xbar = (1.0 - smoothstep(0.10, 0.16, abs(xp.x))) * (1.0 - smoothstep(0.55, 0.65, abs(xp.y - 0.35)));
    float xdot = 1.0 - smoothstep(0.10, 0.16, length(xp - vec2(0.0, -0.55)));
    float xv = max(xbar, xdot) * wAttn * (0.75 + 0.25*sin(iTime*5.0));

    // --- "..." beside face (WORK only), dots pulsing in sequence ---
    float dots = (1.0 - smoothstep(0.030, 0.050, length(n - vec2(0.40, -0.02)))) * (0.35 + 0.65*max(0.0, sin(iTime*3.0)));
    dots = max(dots, (1.0 - smoothstep(0.030, 0.050, length(n - vec2(0.50, -0.02)))) * (0.35 + 0.65*max(0.0, sin(iTime*3.0 - 1.1))));
    dots = max(dots, (1.0 - smoothstep(0.030, 0.050, length(n - vec2(0.60, -0.02)))) * (0.35 + 0.65*max(0.0, sin(iTime*3.0 - 2.2))));
    dots *= wWork;

    float field = max(max(eyeLv, eyeRv), max(mouthV, max(qv, max(xv, dots))));
    field = clamp(field, 0.0, 1.0);

    // ---------- 5. mini-glyph inside the actual pixel's cell ----------
    vec2 lp = (fragCoord - cid * cell) / cell;
    vec2 g  = lp - 0.5;
    float ob = sdRoundBox(g, vec2(0.30, 0.36), 0.12);
    float ib = sdRoundBox(g, vec2(0.16, 0.20), 0.07);
    float aa = 0.03;
    float gRing  = 1.0 - smoothstep(0.0, aa, max(ob, -ib)); // "0"
    float gBlock = 1.0 - smoothstep(0.0, aa, ob);           // block
    float gDot   = 1.0 - smoothstep(0.14, 0.18, length(g)); // dot
    float h = hash21(cid);
    float gv = mix(gRing, gBlock, step(0.55, h));
    gv = mix(gv, gDot, step(0.82, h));

    // core cells + sparse edge "dust" halo
    float core = step(0.34, field);
    float dust = step(0.10, field) * (1.0 - step(0.34, field)) * step(0.86, h);
    gv = mix(gv, gDot, dust);
    float lit = gv * (core * field + dust * 0.55);

    // DONE: sparse fireflies twinkling across the background
    float sparkle = step(0.965, h) * wDone * max(0.0, sin(iTime * 2.5 + h * 80.0));
    lit += gDot * sparkle * 0.5;

    // readability: a cell that contains terminal text goes dark
    vec3 t1 = texture(iChannel0, (cc + vec2(-0.35, -0.25) * cell) / R).rgb;
    vec3 t2 = texture(iChannel0, (cc + vec2( 0.35,  0.25) * cell) / R).rgb;
    vec3 t3 = texture(iChannel0, cc / R).rgb;
    float textIn = max(max(smoothstep(0.06, 0.15, distance(t1, bg)),
                           smoothstep(0.06, 0.15, distance(t2, bg))),
                           smoothstep(0.06, 0.15, distance(t3, bg)));
    lit *= 1.0 - 0.85 * textIn;

    // ---------- 6. compose: force BASE_BG on signal, protect text, draw face ----------
    vec3 term = texture(iChannel0, uv).rgb;
    float bgd = distance(term, bg);                 // distance to SAMPLED corner color
    float bgMask = 1.0 - smoothstep(0.05, 0.16, bgd);

    vec3 base = mix(term, BASE_BG, bgMask * signalActive); // repaint bg back to #282c34
    float bright = 0.34;
    vec3 add = faceCol * lit * bgMask * faceAmp * bright;

    fragColor = vec4(base + add, 1.0);
}
