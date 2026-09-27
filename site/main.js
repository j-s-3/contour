// Contour site. No dependencies; everything degrades to a readable static page.
(() => {
  "use strict";

  const root = document.documentElement;
  root.classList.add("js");
  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const SVG = "http://www.w3.org/2000/svg";

  // ── The mark ───────────────────────────────────────────────────────────────
  // A port of mark() in scripts/generate-logo.py: nested organic rings whose centres
  // drift toward an off-centre summit, teal outside warming to amber at the peak.
  const TEAL = [0x3f, 0xc1, 0xc9], AMBER = [0xff, 0xc8, 0x57];
  const lerp = (a, b, t) => a + (b - a) * t;
  const mix = (t) => `rgb(${TEAL.map((c, i) => Math.round(lerp(c, AMBER[i], t))).join(",")})`;

  function ringPoints(cx, cy, radius, level, n = 120) {
    const w = lerp(1.0, 0.45, level), pts = [];
    for (let i = 0; i < n; i++) {
      const th = (2 * Math.PI * i) / n;
      const r = radius * (1
        + w * 0.16 * Math.sin(th + 0.6)
        + w * 0.13 * Math.sin(2 * th + 1.9 + level * 0.7)
        + w * 0.07 * Math.sin(3 * th + 0.4 - level * 0.9)
        + w * 0.035 * Math.sin(5 * th + 2.2 + level * 1.2));
      pts.push([cx + r * Math.cos(th), cy + r * Math.sin(th) * 0.9]);
    }
    return pts;
  }

  function smoothPath(pts) {
    const n = pts.length, f = (v) => v.toFixed(1);
    let d = `M${f(pts[0][0])},${f(pts[0][1])}`;
    for (let i = 0; i < n; i++) {
      const p0 = pts[(i - 1 + n) % n], p1 = pts[i], p2 = pts[(i + 1) % n], p3 = pts[(i + 2) % n];
      d += `C${f(p1[0] + (p2[0] - p0[0]) / 6)},${f(p1[1] + (p2[1] - p0[1]) / 6)} ` +
           `${f(p2[0] - (p3[0] - p1[0]) / 6)},${f(p2[1] - (p3[1] - p1[1]) / 6)} ${f(p2[0])},${f(p2[1])}`;
    }
    return d + "Z";
  }

  // `spread` > .75 spaces the inner rings more evenly (used where each ring carries a label).
  function rings(count, scale = 100, spread = 0.75) {
    const peak = [scale * 0.24, -scale * 0.2], out = [];
    for (let k = 0; k < count; k++) {
      const level = k / (count - 1);
      const radius = scale * lerp(1.0, 0.17, level ** spread);
      const t = level ** 0.45;
      out.push({ level, pts: ringPoints(lerp(0, peak[0], t), lerp(0, peak[1], t), radius, level) });
    }
    return { peak, rings: out };
  }

  function el(name, attrs, parent) {
    const node = document.createElementNS(SVG, name);
    for (const k in attrs) node.setAttribute(k, attrs[k]);
    if (parent) parent.appendChild(node);
    return node;
  }

  function drawMark(svg, { stroke = 4, animate = false } = {}) {
    const { peak, rings: rs } = rings(7);
    let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
    rs[0].pts.forEach(([x, y]) => { x0 = Math.min(x0, x); y0 = Math.min(y0, y); x1 = Math.max(x1, x); y1 = Math.max(y1, y); });
    const pad = stroke * 1.2, w = x1 - x0, h = y1 - y0, s = Math.max(w, h);
    svg.setAttribute("viewBox", `${(x0 + x1) / 2 - s / 2 - pad} ${(y0 + y1) / 2 - s / 2 - pad} ${s + pad * 2} ${s + pad * 2}`);
    const paths = rs.map(({ level, pts }) => el("path", {
      d: smoothPath(pts), fill: "none", stroke: mix(level ** 1.4),
      "stroke-opacity": lerp(0.55, 1, level).toFixed(2),
      "stroke-width": (stroke * lerp(0.8, 1.15, level)).toFixed(2), "stroke-linejoin": "round",
      pathLength: "1",
    }, svg));
    el("circle", { cx: peak[0], cy: peak[1], r: stroke * 2.4, fill: "#FFC857", "fill-opacity": ".18", class: "peak-halo" }, svg);
    const dot = el("circle", { cx: peak[0], cy: peak[1], r: stroke * 1.1, fill: "#FFC857" }, svg);
    if (animate && !reduce) {
      paths.forEach((p, i) => {
        p.style.strokeDasharray = "1"; p.style.strokeDashoffset = "1";
        p.style.transition = `stroke-dashoffset 1.6s cubic-bezier(.3,.6,.2,1) ${0.15 + i * 0.12}s`;
      });
      dot.style.opacity = "0"; dot.style.transition = "opacity .6s ease 1.3s";
      requestAnimationFrame(() => requestAnimationFrame(() => {
        paths.forEach((p) => (p.style.strokeDashoffset = "0"));
        dot.style.opacity = "1";
      }));
    }
  }

  document.querySelectorAll("[data-mark]").forEach((svg) => {
    const small = svg.classList.contains("mark--nav");
    drawMark(svg, { stroke: small ? 9 : 4.2, animate: svg.hasAttribute("data-animate") });
  });

  // Faint oversized rings behind the "shape" side of the hero stage.
  const stageRings = document.querySelector("[data-rings]");
  if (stageRings) {
    stageRings.setAttribute("viewBox", "-190 -130 380 260");
    stageRings.setAttribute("preserveAspectRatio", "xMidYMid slice");
    rings(9, 150).rings.forEach(({ level, pts }) =>
      el("path", { d: smoothPath(pts), fill: "none", stroke: mix(level ** 1.6), "stroke-opacity": lerp(0.25, 0.6, level).toFixed(2), "stroke-width": "0.7" }, stageRings));
  }

  // ── Topographic field (canvas, marching squares) ───────────────────────────
  const FIELDS = {
    hero: [[0.5, 0.2, 1.0, 0.2], [0.14, 0.55, 0.7, 0.16], [0.88, 0.48, 0.8, 0.2], [0.68, 0.02, 0.5, 0.12], [0.3, 0.9, 0.6, 0.2]],
    close: [[0.5, 0.45, 1.0, 0.2], [0.18, 0.2, 0.6, 0.18], [0.82, 0.75, 0.7, 0.2]],
  };

  function drawTopo(canvas) {
    const hills = FIELDS[canvas.dataset.topo] || FIELDS.hero;
    const rect = canvas.getBoundingClientRect();
    const W = rect.width, H = rect.height;
    if (!W || !H) return;
    const dpr = Math.min(devicePixelRatio || 1, 2);
    canvas.width = Math.round(W * dpr); canvas.height = Math.round(H * dpr);
    const ctx = canvas.getContext("2d");
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, W, H);

    const cell = W < 700 ? 9 : 11;
    const cols = Math.ceil(W / cell) + 1, rows = Math.ceil(H / cell) + 1;
    const unit = Math.max(W, 900);
    const f = new Float32Array(cols * rows);
    let max = 0;
    for (let j = 0; j < rows; j++) for (let i = 0; i < cols; i++) {
      const x = i * cell, y = j * cell;
      let v = 0.04 * Math.sin(x / 140 + y / 210) + 0.03 * Math.sin(y / 90 - x / 260);
      for (const [hx, hy, a, s] of hills) {
        const dx = (x - hx * W) / unit, dy = (y - hy * Math.min(H, 1100)) / unit;
        v += a * Math.exp(-(dx * dx + dy * dy * 1.3) / (2 * s * s));
      }
      f[j * cols + i] = v;
      if (v > max) max = v;
    }

    const levels = 26;
    for (let L = 1; L < levels; L++) {
      const iso = (L / levels) * max, t = L / levels;
      const index = L % 5 === 0;
      ctx.beginPath();
      for (let j = 0; j < rows - 1; j++) for (let i = 0; i < cols - 1; i++) {
        const a = f[j * cols + i], b = f[j * cols + i + 1], c = f[(j + 1) * cols + i + 1], d = f[(j + 1) * cols + i];
        const k = (a > iso ? 8 : 0) | (b > iso ? 4 : 0) | (c > iso ? 2 : 0) | (d > iso ? 1 : 0);
        if (k === 0 || k === 15) continue;
        const x = i * cell, y = j * cell;
        const top = [x + cell * ((iso - a) / (b - a)), y];
        const right = [x + cell, y + cell * ((iso - b) / (c - b))];
        const bottom = [x + cell * ((iso - d) / (c - d)), y + cell];
        const left = [x, y + cell * ((iso - a) / (d - a))];
        const seg = (p, q) => { ctx.moveTo(p[0], p[1]); ctx.lineTo(q[0], q[1]); };
        switch (k) {
          case 1: case 14: seg(left, bottom); break;
          case 2: case 13: seg(bottom, right); break;
          case 3: case 12: seg(left, right); break;
          case 4: case 11: seg(top, right); break;
          case 5: seg(left, top); seg(bottom, right); break;
          case 6: case 9: seg(top, bottom); break;
          case 7: case 8: seg(left, top); break;
          case 10: seg(left, bottom); seg(top, right); break;
        }
      }
      const warm = Math.max(0, (t - 0.6) / 0.4);
      ctx.strokeStyle = warm > 0 ? mix(warm).replace("rgb", "rgba").replace(")", `,${(0.14 + warm * 0.3).toFixed(2)})`)
                                 : `rgba(63,193,201,${index ? 0.17 : 0.085})`;
      ctx.lineWidth = index ? 1.1 : 0.7;
      ctx.stroke();
    }
  }

  // A few gentle isolines between sections.
  function drawRule(canvas) {
    const rect = canvas.getBoundingClientRect(), W = rect.width, H = rect.height;
    if (!W) return;
    const dpr = Math.min(devicePixelRatio || 1, 2);
    canvas.width = Math.round(W * dpr); canvas.height = Math.round(H * dpr);
    const ctx = canvas.getContext("2d");
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    const seed = [...document.querySelectorAll("[data-rule]")].indexOf(canvas) * 1.7;
    for (let n = 0; n < 5; n++) {
      ctx.beginPath();
      for (let x = 0; x <= W; x += 6) {
        const u = x / W;
        const bump = Math.exp(-((u - 0.5 - 0.15 * Math.sin(seed)) ** 2) / (0.012 + n * 0.004)) * (34 - n * 4);
        const y = H * 0.62 + (2 - n) * 8 - bump + 5 * Math.sin(u * 6 + seed + n * 0.4);
        x ? ctx.lineTo(x, y) : ctx.moveTo(x, y);
      }
      ctx.strokeStyle = n === 4 ? "rgba(255,200,87,.35)" : `rgba(63,193,201,${0.1 + n * 0.04})`;
      ctx.lineWidth = 0.8;
      ctx.stroke();
    }
  }

  const topo = [...document.querySelectorAll("[data-topo]")];
  const rules = [...document.querySelectorAll("[data-rule]")];
  const paint = () => { topo.forEach(drawTopo); rules.forEach(drawRule); };
  paint();
  let lastW = innerWidth, rt;
  addEventListener("resize", () => {
    if (innerWidth === lastW) return; // ignore mobile toolbar height changes
    lastW = innerWidth; clearTimeout(rt); rt = setTimeout(paint, 150);
  });

  // ── Nav ───────────────────────────────────────────────────────────────────
  const nav = document.querySelector(".nav");
  const onScroll = () => nav.classList.toggle("scrolled", scrollY > 24);
  onScroll();
  addEventListener("scroll", onScroll, { passive: true });

  // ── Reveal on scroll ──────────────────────────────────────────────────────
  const once = (els, fn, opts = { threshold: 0.2 }) => {
    if (!("IntersectionObserver" in window)) { els.forEach(fn); return; }
    const io = new IntersectionObserver((entries) => entries.forEach((e) => {
      if (e.isIntersecting) { io.unobserve(e.target); fn(e.target); }
    }), opts);
    els.forEach((e) => io.observe(e));
  };
  once([...document.querySelectorAll(".reveal")], (e) => e.classList.add("in"), { threshold: 0.12, rootMargin: "0px 0px -6% 0px" });

  // ── Hero stage: diff → shape ──────────────────────────────────────────────
  const stage = document.querySelector("[data-stage]");
  if (stage) {
    const buttons = stage.querySelectorAll("[data-stage-to]");
    const title = stage.querySelector("[data-stage-title]");
    let touched = false;
    const show = (view) => {
      stage.dataset.view = view;
      buttons.forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.stageTo === view)));
      stage.querySelector('[data-layer="diff"]').setAttribute("aria-hidden", String(view !== "diff"));
      stage.querySelector('[data-layer="shape"]').setAttribute("aria-hidden", String(view !== "shape"));
      title.innerHTML = view === "diff"
        ? 'src/input.rs <span class="dim">· sharkdp/bat #3877</span>'
        : 'sharkdp/bat #3877 <span class="dim">· the shape of the change</span>';
    };
    show("diff");
    buttons.forEach((b) => b.addEventListener("click", () => { touched = true; show(b.dataset.stageTo); }));
    if (reduce) show("shape");
    else once([stage], () => setTimeout(() => { if (!touched) show("shape"); }, 2200), { threshold: 0.55 });
  }

  // ── Before/After, attention funnel, evidence ladder ───────────────────────
  once([...document.querySelectorAll("[data-ba]")], (e) => setTimeout(() => e.classList.add("play"), 300), { threshold: 0.4 });
  once([...document.querySelectorAll("[data-funnel]")], (e) => setTimeout(() => e.classList.add("play"), reduce ? 0 : 900), { threshold: 0.5 });
  once([...document.querySelectorAll("[data-ladder]")], (ladder) => {
    [...ladder.children].forEach((li, i) => setTimeout(() => li.classList.add("lit"), reduce ? 0 : 200 + i * 260));
  }, { threshold: 0.4 });

  // ── Typed flow prompt ─────────────────────────────────────────────────────
  once([...document.querySelectorAll("[data-typed]")], (e) => {
    const text = e.dataset.typed;
    if (reduce) { e.textContent = text; return; }
    let i = 0;
    const tick = () => { e.textContent = text.slice(0, ++i); if (i < text.length) setTimeout(tick, 34 + Math.random() * 40); };
    setTimeout(tick, 400);
  }, { threshold: 0.6 });
  document.querySelectorAll("[data-typed]").forEach((e) => e.setAttribute("aria-label", e.dataset.typed));

  // ── Copy install commands ─────────────────────────────────────────────────
  document.querySelectorAll("[data-copy]").forEach((box) => {
    const btn = box.querySelector("[data-copy-btn]");
    // Copy only the commands, not the comment lines.
    const text = box.querySelector("[data-copy-src]").textContent
      .split("\n").filter((l) => l.trim() && !l.trim().startsWith("#")).join("\n");
    btn.addEventListener("click", async () => {
      try { await navigator.clipboard.writeText(text); } catch { return; }
      btn.textContent = "Copied"; btn.classList.add("done");
      setTimeout(() => { btn.textContent = "Copy"; btn.classList.remove("done"); }, 1600);
    });
  });

  // ── Hint at code that scrolls sideways ─────────────────────────────────────
  document.querySelectorAll(".term .code, .evidence-code .code").forEach((pre) => {
    const update = () => pre.classList.toggle("more-r", pre.scrollLeft + pre.clientWidth < pre.scrollWidth - 2);
    update();
    pre.addEventListener("scroll", update, { passive: true });
    addEventListener("resize", update);
  });

  // ── Decision verdict ──────────────────────────────────────────────────────
  const VERDICT = {
    good: "Accepted. The choice is now yours on the record, not the agent's.",
    question: "Flagged. The question goes to the author with the decision attached.",
    discuss: "Opened a conversation scoped to this decision, its flows and its code.",
  };
  document.querySelectorAll("[data-decision]").forEach((card) => {
    const out = card.querySelector("[data-verdict-out]");
    const initial = out.textContent;
    card.querySelectorAll("[data-verdict]").forEach((b) => {
      b.setAttribute("aria-pressed", "false");
      b.addEventListener("click", () => {
        const on = b.getAttribute("aria-pressed") !== "true";
        card.querySelectorAll("[data-verdict]").forEach((o) => o.setAttribute("aria-pressed", "false"));
        b.setAttribute("aria-pressed", String(on));
        out.textContent = on ? VERDICT[b.dataset.verdict] : initial;
      });
    });
  });

  // ── Altitude layers: rings resolve as you scroll through ──────────────────
  const layers = document.querySelector("[data-layers]");
  if (layers) {
    const svg = layers.querySelector("[data-layer-rings]");
    const labels = [...layers.querySelectorAll("[data-layer-i]")];
    const { peak, rings: rs } = rings(5, 190, 1.15);
    const paths = rs.map(({ level, pts }) => el("path", {
      d: smoothPath(pts), fill: "none", stroke: mix(level ** 1.2), "stroke-width": "1.4", opacity: "0.15",
    }, svg));
    el("circle", { cx: peak[0], cy: peak[1], r: 5, fill: "#FFC857" }, svg);
    // Park each label where its ring crosses the line straight down from the summit:
    // that's the gentle slope, where the rings sit furthest apart.
    const [vx, vy, vw, vh] = svg.getAttribute("viewBox").split(" ").map(Number);
    rs.forEach(({ pts }, i) => {
      let best = pts[0], err = Infinity;
      for (const [x, y] of pts) if (y > peak[1] && Math.abs(x - peak[0]) < err) { err = Math.abs(x - peak[0]); best = [x, y]; }
      labels[i].style.left = `${((best[0] - vx) / vw) * 100}%`;
      labels[i].style.top = `${((best[1] - vy) / vh) * 100}%`;
    });
    const setActive = (n) => {
      paths.forEach((p, i) => { p.setAttribute("opacity", i <= n ? "1" : "0.15"); p.setAttribute("stroke-width", i === n ? "2.4" : "1.4"); });
      labels.forEach((l, i) => l.classList.toggle("on", i <= n));
    };
    if (reduce) setActive(4);
    else {
      let ticking = false;
      const update = () => {
        ticking = false;
        const r = layers.getBoundingClientRect();
        const p = (innerHeight * 0.85 - r.top) / (innerHeight * 0.5 + r.height * 0.5);
        setActive(Math.max(-1, Math.min(4, Math.floor(p * 5))));
      };
      addEventListener("scroll", () => { if (!ticking) { ticking = true; requestAnimationFrame(update); } }, { passive: true });
      update();
    }
  }
})();
