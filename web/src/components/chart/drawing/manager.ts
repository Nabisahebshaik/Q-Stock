import type {
  IChartApi, ISeriesApi, ISeriesPrimitive, ISeriesPrimitiveAxisView, ISeriesPrimitivePaneRenderer,
  ISeriesPrimitivePaneView, Logical, MouseEventParams, PrimitiveHoveredItem, SeriesAttachedParameter, Time,
} from "lightweight-charts";
import { cssColor } from "../../../lib/util";
import {
  TimeIndex, cloneDrawings, distToRay, distToSegment, extendRay, formatSpan, parseDrawings, timeToSec,
} from "./geometry";
import { FIB_LEVELS, TWO_POINT, type Anchor, type Drawing, type DrawingManager, type DrawingTool, type ShapeType } from "./types";

type Target = Parameters<ISeriesPrimitivePaneRenderer["draw"]>[0];
type HandleKey = "a" | "b" | "ab" | "ba";
interface Hit { id: string; handle?: HandleKey }
interface Pt { x: number; y: number }
interface Box { x: number; y: number; w: number; h: number }
type BarLike = Partial<{ open: number; high: number; low: number; close: number; value: number }>;

const HIT_TOL = 6;           // px (media) distance that counts as "on" a line
const HANDLE_R = 4.5;        // handle radius (media px)
const HANDLE_TOL = 8;
const UNDO_CAP = 100;
const FONT = "Inter, ui-sans-serif, system-ui, 'Segoe UI', sans-serif";

const newId = () => Math.random().toString(36).slice(2, 9) + Date.now().toString(36).slice(-4);
const isEditable = (t: EventTarget | null) => {
  const el = t as HTMLElement | null;
  return !!el && (el.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(el.tagName ?? ""));
};

export function createDrawingManager(
  chart: IChartApi,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  series: ISeriesApi<any>,
  opts: { storageKey: string; onChange?: () => void },
): DrawingManager {
  const index = new TimeIndex();
  const el = chart.chartElement();

  let drawings: Drawing[] = [];
  try { drawings = parseDrawings(localStorage.getItem(opts.storageKey)); } catch { drawings = []; }
  let undoStack: Drawing[][] = [];
  let redoStack: Drawing[][] = [];

  let tool: DrawingTool = "cursor";
  let magnet = false, locked = false, visible = true;
  let selectedId: string | null = null;
  let pending: { type: ShapeType; a: Anchor } | null = null;
  let hover: Pt | null = null;           // last crosshair point (pane coords)
  let active = false;                    // keyboard shortcuts apply to the last chart the user pressed in
  let destroyed = false;
  let requestUpdate: () => void = () => undefined;
  const textBoxes = new Map<string, Box>();
  type ScrollOpt = ReturnType<IChartApi["options"]>["handleScroll"];
  type ScaleOpt = ReturnType<IChartApi["options"]>["handleScale"];
  let drag: {
    kind: "handle" | "body"; id: string; handle?: HandleKey; orig: Drawing; before: Drawing[];
    start: { l: number; p: number }; scroll: ScrollOpt; scale: ScaleOpt; moved: boolean;
  } | null = null;

  // ---------------- colours (re-read on theme switch) ----------------
  let colorCache = new Map<string, string>();
  const col = (name: string, alpha = 1) => {
    const k = `${name}|${alpha}`;
    let v = colorCache.get(k);
    if (!v) { v = cssColor(name, alpha); colorCache.set(k, v); }
    return v;
  };
  const onTheme = () => { colorCache = new Map(); requestUpdate(); };
  window.addEventListener("qstock-theme", onTheme);

  // ---------------- data space <-> pixels ----------------
  const refreshIndex = () => {
    try { index.set(series.data().map((d: { time: Time }) => timeToSec(d.time))); } catch { index.set([]); }
  };
  refreshIndex();
  const onData = () => { refreshIndex(); requestUpdate(); };
  series.subscribeDataChanged(onData);

  const ts = () => chart.timeScale();
  const xOf = (time: number): number | null => {
    const l = index.logicalOf(time);
    if (l == null) return null;
    const x = ts().logicalToCoordinate(l as Logical);
    return x == null ? null : x;
  };
  const yOf = (price: number): number | null => {
    const y = series.priceToCoordinate(price);
    return y == null ? null : y;
  };
  const paneW = () => ts().width();
  const paneH = () => Math.max(0, el.clientHeight - ts().height());
  const fmt = (p: number) => { try { return series.priceFormatter().format(p); } catch { return p.toFixed(2); } };

  /** Pointer (pane coords) -> anchor. Time snaps to the nearest bar (extrapolated beyond the
   *  data); with the magnet the price snaps to the closest of that bar's O/H/L/C. */
  function anchorAt(x: number, y: number, useMagnet = magnet): Anchor | null {
    const l = ts().coordinateToLogical(x);
    const price = series.coordinateToPrice(y);
    if (l == null || price == null) return null;
    const i = Math.round(l);
    const time = index.timeAt(i);
    if (time == null) return null;
    let p = price as number;
    if (useMagnet && i >= 0 && i < index.length) {
      const bar = series.dataByIndex(i) as BarLike | null;
      const cands = bar ? [bar.open, bar.high, bar.low, bar.close, bar.value].filter((v): v is number => typeof v === "number" && isFinite(v)) : [];
      let best = Infinity;
      for (const c of cands) {
        const cy = yOf(c);
        if (cy != null && Math.abs(cy - y) < best) { best = Math.abs(cy - y); p = c; }
      }
    }
    return { time, price: p };
  }

  /** Pointer position without snapping, as (logical, price) — used to move whole drawings. */
  function rawAt(x: number, y: number): { l: number; p: number } | null {
    const l = ts().coordinateToLogical(x), p = series.coordinateToPrice(y);
    return l == null || p == null ? null : { l, p: p as number };
  }

  // ---------------- history / persistence ----------------
  const persist = () => {
    try { localStorage.setItem(opts.storageKey, JSON.stringify({ v: 1, drawings })); } catch { /* storage full/blocked */ }
  };
  const changed = () => { persist(); requestUpdate(); opts.onChange?.(); };
  function commit(next: Drawing[], before: Drawing[] = drawings) {
    undoStack.push(cloneDrawings(before));
    if (undoStack.length > UNDO_CAP) undoStack = undoStack.slice(-UNDO_CAP);
    redoStack = [];
    drawings = next;
    if (selectedId && !drawings.some((d) => d.id === selectedId)) selectedId = null;
    changed();
  }

  // ---------------- handles & hit testing (media px, pane coords) ----------------
  function handlesOf(d: Drawing): { key: HandleKey; x: number; y: number }[] {
    const ax = xOf(d.a.time), ay = yOf(d.a.price);
    if (d.type === "hline") return ay == null ? [] : [{ key: "a", x: ax ?? paneW() / 2, y: ay }];
    if (d.type === "vline") return ax == null ? [] : [{ key: "a", x: ax, y: paneH() / 2 }];
    if (ax == null || ay == null) return [];
    const out: { key: HandleKey; x: number; y: number }[] = [{ key: "a", x: ax, y: ay }];
    if (d.b) {
      const bx = xOf(d.b.time), by = yOf(d.b.price);
      if (bx != null && by != null) {
        out.push({ key: "b", x: bx, y: by });
        if (d.type === "rect") out.push({ key: "ab", x: ax, y: by }, { key: "ba", x: bx, y: ay });
      }
    }
    return d.type === "text" ? [] : out;
  }

  function hitDrawing(d: Drawing, x: number, y: number): boolean {
    const ax = xOf(d.a.time), ay = yOf(d.a.price);
    const bx = d.b ? xOf(d.b.time) : null, by = d.b ? yOf(d.b.price) : null;
    const T = HIT_TOL;
    switch (d.type) {
      case "hline": return ay != null && Math.abs(y - ay) <= T;
      case "vline": return ax != null && Math.abs(x - ax) <= T;
      case "hray": return ax != null && ay != null && x >= ax - T && Math.abs(y - ay) <= T;
      case "text": {
        const b = textBoxes.get(d.id);
        return !!b && x >= b.x - 2 && x <= b.x + b.w + 2 && y >= b.y - 2 && y <= b.y + b.h + 2;
      }
    }
    if (ax == null || ay == null || bx == null || by == null) return false;
    switch (d.type) {
      case "trend": return distToSegment(x, y, ax, ay, bx, by) <= T;
      case "ray": return distToRay(x, y, ax, ay, bx, by) <= T;
      case "rect": case "measure": case "fib": {
        const x1 = Math.min(ax, bx), x2 = Math.max(ax, bx), y1 = Math.min(ay, by), y2 = Math.max(ay, by);
        return x >= x1 - T && x <= x2 + T && y >= y1 - T && y <= y2 + T;
      }
    }
    return false;
  }

  function hitAt(x: number, y: number): Hit | null {
    if (!visible) return null;
    const sel = selectedId ? drawings.find((d) => d.id === selectedId) : undefined;
    if (sel) for (const h of handlesOf(sel)) if (Math.hypot(x - h.x, y - h.y) <= HANDLE_TOL) return { id: sel.id, handle: h.key };
    for (let i = drawings.length - 1; i >= 0; i--) if (hitDrawing(drawings[i], x, y)) return { id: drawings[i].id };
    return null;
  }

  // ---------------- rendering (bitmap coordinate space) ----------------
  function paint(target: Target) {
    if (!visible) return;
    target.useBitmapCoordinateSpace(({ context: ctx, horizontalPixelRatio: hr, verticalPixelRatio: vr, mediaSize }) => {
      const W = mediaSize.width, H = mediaSize.height;
      const lw = (w: number) => Math.max(1, Math.round(w * hr));
      const line = (x1: number, y1: number, x2: number, y2: number, color: string, w = 1, dash?: number[]) => {
        const width = lw(w), off = width % 2 ? 0.5 : 0;
        let X1 = x1 * hr, Y1 = y1 * vr, X2 = x2 * hr, Y2 = y2 * vr;
        if (y1 === y2) { Y1 = Y2 = Math.round(Y1) + off; }
        if (x1 === x2) { X1 = X2 = Math.round(X1) + off; }
        ctx.beginPath();
        ctx.lineWidth = width;
        ctx.strokeStyle = color;
        ctx.setLineDash(dash ? dash.map((v) => v * hr) : []);
        ctx.moveTo(X1, Y1);
        ctx.lineTo(X2, Y2);
        ctx.stroke();
      };
      const fillRect = (x1: number, y1: number, x2: number, y2: number, color: string) => {
        ctx.fillStyle = color;
        const X = Math.round(Math.min(x1, x2) * hr), Y = Math.round(Math.min(y1, y2) * vr);
        ctx.fillRect(X, Y, Math.round(Math.max(x1, x2) * hr) - X, Math.round(Math.max(y1, y2) * vr) - Y);
      };
      const strokeRect = (x1: number, y1: number, x2: number, y2: number, color: string, w = 1) => {
        line(x1, y1, x2, y1, color, w); line(x2, y1, x2, y2, color, w);
        line(x2, y2, x1, y2, color, w); line(x1, y2, x1, y1, color, w);
      };
      /** Text with optional background; (x, y) is the top-left in media px. Returns its box. */
      const label = (lines: string[], x: number, y: number, color: string, bg?: string, size = 11, align: "left" | "center" | "right" = "left", border?: string): Box => {
        ctx.font = `${Math.round(size * vr)}px ${FONT}`;
        ctx.textBaseline = "top";
        ctx.textAlign = "left";
        ctx.setLineDash([]);
        const pad = 4, lh = size + 3;
        const w = Math.max(...lines.map((s) => ctx.measureText(s).width)) / hr + 2 * pad;
        const h = lines.length * lh + 2 * pad - 3;
        const bx = align === "center" ? x - w / 2 : align === "right" ? x - w : x;
        if (bg) {
          ctx.fillStyle = bg;
          ctx.beginPath();
          const r = 3 * hr;
          const X = bx * hr, Y = y * vr, WW = w * hr, HH = h * vr;
          ctx.moveTo(X + r, Y); ctx.arcTo(X + WW, Y, X + WW, Y + HH, r); ctx.arcTo(X + WW, Y + HH, X, Y + HH, r);
          ctx.arcTo(X, Y + HH, X, Y, r); ctx.arcTo(X, Y, X + WW, Y, r); ctx.closePath();
          ctx.fill();
          if (border) { ctx.lineWidth = lw(1); ctx.strokeStyle = border; ctx.stroke(); }
        }
        ctx.fillStyle = color;
        lines.forEach((s, i) => ctx.fillText(s, (bx + pad) * hr, (y + pad + i * lh) * vr));
        return { x: bx, y, w, h };
      };
      const handle = (x: number, y: number) => {
        ctx.beginPath();
        ctx.setLineDash([]);
        ctx.arc(x * hr, y * vr, HANDLE_R * hr, 0, Math.PI * 2);
        ctx.fillStyle = col("bg");
        ctx.fill();
        ctx.lineWidth = lw(1.5);
        ctx.strokeStyle = col("accent");
        ctx.stroke();
      };

      const draw = (d: Drawing, selected: boolean, preview: boolean) => {
        const ax = xOf(d.a.time), ay = yOf(d.a.price);
        const bx = d.b ? xOf(d.b.time) : null, by = d.b ? yOf(d.b.price) : null;
        const w = selected ? 2 : 1.25;
        const main = col("accent");
        switch (d.type) {
          case "hline":
            if (ay != null) line(0, ay, W, ay, main, w);
            break;
          case "hray":
            if (ax != null && ay != null) line(ax, ay, W, ay, main, w);
            break;
          case "vline":
            if (ax != null) line(ax, 0, ax, H, main, w);
            break;
          case "text":
            if (ax != null && ay != null) {
              const box = label([d.text || "Text"], ax, ay, col("ink"), col("surface", 0.85), 12, "left",
                selected ? col("accent") : col("line", 0.9));
              textBoxes.set(d.id, box);
            }
            break;
        }
        if (ax != null && ay != null && bx != null && by != null) {
          switch (d.type) {
            case "trend": line(ax, ay, bx, by, main, w); break;
            case "ray": { const e = extendRay(ax, ay, bx, by, W, H); line(ax, ay, e.x, e.y, main, w); break; }
            case "rect":
              fillRect(ax, ay, bx, by, col("quantum", 0.12));
              strokeRect(ax, ay, bx, by, col("quantum", 0.9), w);
              break;
            case "fib": {
              const x1 = Math.min(ax, bx), x2 = Math.max(ax, bx);
              const palette = ["muted", "down", "warn", "up", "accent", "quantum", "muted"];
              const pa = d.a.price, pb = d.b!.price;
              let prevY: number | null = null;
              FIB_LEVELS.forEach((lvl, k) => {
                const p = pb + (pa - pb) * lvl, y = yOf(p);
                if (y == null) return;
                if (prevY != null) fillRect(x1, prevY, x2, y, col(palette[k], 0.08));
                line(x1, y, x2, y, col(palette[k], 0.95), selected ? 1.5 : 1);
                label([`${lvl} (${fmt(p)})`], x1, y - 16, col(palette[k]), undefined, 10);
                prevY = y;
              });
              line(ax, ay, bx, by, col("muted", 0.7), 1, [4, 4]);
              break;
            }
            case "measure": {
              const up = d.b!.price >= d.a.price;
              const c = up ? "up" : "down";
              fillRect(ax, ay, bx, by, col(c, 0.14));
              const mx = (ax + bx) / 2, my = (ay + by) / 2;
              line(mx, ay, mx, by, col(c), 1.25);
              line(ax, my, bx, my, col(c), 1.25);
              // arrow head at B's price
              const dir = by < ay ? 1 : -1;
              ctx.beginPath(); ctx.setLineDash([]);
              ctx.moveTo((mx - 4) * hr, (by + 5 * dir) * vr); ctx.lineTo(mx * hr, by * vr); ctx.lineTo((mx + 4) * hr, (by + 5 * dir) * vr);
              ctx.strokeStyle = col(c); ctx.lineWidth = lw(1.25); ctx.stroke();
              const dp = d.b!.price - d.a.price;
              const pc = d.a.price !== 0 ? (100 * dp) / d.a.price : 0;
              const la = index.logicalOf(d.a.time), lb = index.logicalOf(d.b!.time);
              const bars = la != null && lb != null ? Math.round(lb) - Math.round(la) : 0;
              const lines = [
                `${dp >= 0 ? "+" : ""}${fmt(dp)} (${pc >= 0 ? "+" : ""}${pc.toFixed(2)}%)`,
                `${bars} bars, ${formatSpan(d.b!.time - d.a.time)}`,
              ];
              const top = Math.min(ay, by), bottom = Math.max(ay, by);
              const ly = up ? top - 42 : bottom + 8;
              label(lines, mx, Math.max(2, Math.min(H - 40, ly)), "#ffffff", col(c, 0.92), 11, "center");
              break;
            }
          }
        }
        if (selected && !preview) for (const h of handlesOf(d)) handle(h.x, h.y);
        if (preview && d.type !== "text") {
          if (ax != null && ay != null) handle(ax, ay);
          if (bx != null && by != null) handle(bx, by);
        }
      };

      for (const d of drawings) draw(d, d.id === selectedId && !locked, false);
      const pv = previewDrawing();
      if (pv) draw(pv, false, true);
      ctx.setLineDash([]);
    });
  }

  function previewDrawing(): Drawing | null {
    if (!pending || !hover) return null;
    const b = anchorAt(hover.x, hover.y);
    return b ? { id: "__preview", type: pending.type, a: pending.a, b } : null;
  }

  // ---------------- the primitive ----------------
  const renderer: ISeriesPrimitivePaneRenderer = { draw: paint };
  const paneView: ISeriesPrimitivePaneView = { zOrder: () => "top", renderer: () => (visible ? renderer : null) };
  const paneViews = [paneView];
  let axisViews: ISeriesPrimitiveAxisView[] = [];

  const primitive: ISeriesPrimitive<Time> = {
    attached(p: SeriesAttachedParameter<Time>) { requestUpdate = p.requestUpdate; },
    detached() { requestUpdate = () => undefined; },
    updateAllViews() {
      if (!visible) { if (axisViews.length) axisViews = []; return; }
      const next: ISeriesPrimitiveAxisView[] = [];
      for (const d of drawings) {
        if (d.type !== "hline" && d.type !== "hray") continue;
        const sel = d.id === selectedId;
        const y = yOf(d.a.price);
        if (y == null) continue;
        next.push({
          coordinate: () => y,
          text: () => fmt(d.a.price),
          textColor: () => "#ffffff",
          backColor: () => col("accent", sel ? 1 : 0.85),
          visible: () => true,
          tickVisible: () => true,
        });
      }
      axisViews = next;
    },
    paneViews: () => paneViews,
    priceAxisViews: () => axisViews,
    hitTest(x: number, y: number): PrimitiveHoveredItem | null {
      if (drag) return { externalId: "drawing", zOrder: "top", cursorStyle: drag.kind === "body" ? "grabbing" : "move" };
      if (tool !== "cursor" && tool !== "crosshair") return { externalId: "drawing-tool", zOrder: "top", cursorStyle: "crosshair" };
      const h = locked ? null : hitAt(x, y);
      if (h) return { externalId: h.id, zOrder: "top", cursorStyle: h.handle ? "move" : "pointer" };
      return tool === "crosshair" ? { externalId: "crosshair", zOrder: "bottom", cursorStyle: "crosshair" } : null;
    },
  };
  series.attachPrimitive(primitive);

  // ---------------- chart events ----------------
  const isShape = (t: DrawingTool): t is ShapeType => t !== "cursor" && t !== "crosshair";

  function setToolInternal(t: DrawingTool, notify: boolean) {
    if (t === tool) return;
    tool = t;
    pending = null;
    if (isShape(t)) selectedId = null;
    requestUpdate();
    if (notify) opts.onChange?.();
  }

  /** A click in the pane (own detection: the chart's click event swallows a second click that
   *  follows within 500 ms anywhere on the chart, which loses quick two-point placements). */
  const onPaneClick = (x: number, y: number) => {
    if (drag) return;
    if (isShape(tool)) {
      if (!visible) return;
      const at = anchorAt(x, y);
      if (!at) return;
      if (TWO_POINT.has(tool)) {
        if (!pending) { pending = { type: tool, a: at }; hover = { x, y }; requestUpdate(); return; }
        const ax = xOf(pending.a.time), ay = yOf(pending.a.price);
        if (ax != null && ay != null && Math.abs(ax - x) < 2 && Math.abs(ay - y) < 2) return; // same spot: keep waiting
        const d: Drawing = { id: newId(), type: pending.type, a: pending.a, b: at };
        pending = null;
        commit([...drawings, d]);
        selectedId = d.id;
      } else {
        let text: string | undefined;
        if (tool === "text") {
          const s = window.prompt("Text", "");
          if (s == null || !s.trim()) return;
          text = s.trim();
        }
        const d: Drawing = { id: newId(), type: tool, a: at, ...(text ? { text } : {}) };
        commit([...drawings, d]);
        selectedId = d.id;
      }
      setToolInternal("cursor", true);
      return;
    }
    const h = locked ? null : hitAt(x, y);
    const next = h ? h.id : null;
    if (next !== selectedId) { selectedId = next; requestUpdate(); }
  };

  const onDblClick = (e: MouseEvent) => {
    if (locked || isShape(tool)) return;
    const { x, y } = panePoint(e.clientX, e.clientY);
    const h = hitAt(x, y);
    const d = h && drawings.find((k) => k.id === h.id);
    if (!d || d.type !== "text") return;
    const s = window.prompt("Edit text", d.text ?? "");
    if (s == null || !s.trim() || s.trim() === d.text) return;
    commit(drawings.map((k) => (k.id === d.id ? { ...k, text: s.trim() } : k)));
  };

  const onMove = (param: MouseEventParams<Time>) => {
    hover = param.point ? { x: param.point.x, y: param.point.y } : null;
    if (pending) requestUpdate();
  };

  chart.subscribeCrosshairMove(onMove);

  // ---------------- dragging handles / bodies ----------------

  const panePoint = (clientX: number, clientY: number): Pt => {
    const r = el.getBoundingClientRect();
    let left = 0;
    try { left = chart.priceScale("left").width(); } catch { left = 0; }
    return { x: clientX - r.left - left, y: clientY - r.top };
  };

  function beginDrag(clientX: number, clientY: number): boolean {
    if (destroyed || locked || !visible || isShape(tool)) return false;
    if (drag) return true; // repeated press (e.g. touchstart + compat mousedown): keep the running drag
    const { x, y } = panePoint(clientX, clientY);
    if (x < 0 || y < 0 || x > paneW() || y > paneH()) return false;
    const h = hitAt(x, y);
    if (!h) return false;
    const d = drawings.find((k) => k.id === h.id);
    const start = rawAt(x, y);
    if (!d || !start) return false;
    // options() hands out the live options object, which applyOptions mutates: snapshot by value.
    const o = JSON.parse(JSON.stringify({ handleScroll: chart.options().handleScroll, handleScale: chart.options().handleScale })) as
      { handleScroll: ScrollOpt; handleScale: ScaleOpt };
    drag = {
      kind: h.handle ? "handle" : "body", id: d.id, handle: h.handle, orig: cloneDrawings([d])[0],
      before: cloneDrawings(drawings), start, scroll: o.handleScroll, scale: o.handleScale, moved: false,
    };
    chart.applyOptions({ handleScroll: false, handleScale: false });
    down = null; // a drag is not a click
    selectedId = d.id;
    requestUpdate();
    return true;
  }

  function moveDrag(clientX: number, clientY: number) {
    if (!drag) return;
    const { x, y } = panePoint(clientX, clientY);
    const o = drag.orig;
    let next: Drawing | null = null;
    if (drag.kind === "handle") {
      const p = anchorAt(x, y);
      if (!p) return;
      const n = cloneDrawings([o])[0];
      switch (drag.handle) {
        case "a": n.a = p; break;
        case "b": n.b = p; break;
        case "ab": n.a = { time: p.time, price: o.a.price }; n.b = { time: o.b!.time, price: p.price }; break;
        case "ba": n.b = { time: p.time, price: o.b!.price }; n.a = { time: o.a.time, price: p.price }; break;
      }
      next = n;
    } else {
      const now = rawAt(x, y);
      if (!now) return;
      const dl = Math.round(now.l - drag.start.l), dp = now.p - drag.start.p;
      const shift = (a: Anchor): Anchor => {
        const l = index.logicalOf(a.time);
        const t = l == null ? null : index.timeAt(l + dl);
        return { time: t ?? a.time, price: a.price + dp };
      };
      next = { ...o, a: shift(o.a), b: o.b ? shift(o.b) : undefined };
    }
    drag.moved = true;
    const id = drag.id;
    drawings = drawings.map((k) => (k.id === id ? next! : k));
    requestUpdate();
  }

  function endDrag() {
    if (!drag) return;
    const d = drag;
    drag = null;
    chart.applyOptions({ handleScroll: d.scroll, handleScale: d.scale });
    detachWindowDrag();
    if (d.moved) commit(drawings, d.before);
    else requestUpdate();
  }

  const onWinMouseMove = (e: MouseEvent) => { e.preventDefault(); moveDrag(e.clientX, e.clientY); };
  const onWinMouseUp = () => endDrag();
  const onWinTouchMove = (e: TouchEvent) => { const t = e.touches[0]; if (t) { e.preventDefault(); moveDrag(t.clientX, t.clientY); } };
  const onWinTouchEnd = () => endDrag();
  function attachWindowDrag() {
    window.addEventListener("mousemove", onWinMouseMove);
    window.addEventListener("mouseup", onWinMouseUp);
    window.addEventListener("touchmove", onWinTouchMove, { passive: false });
    window.addEventListener("touchend", onWinTouchEnd);
    window.addEventListener("touchcancel", onWinTouchEnd);
  }
  function detachWindowDrag() {
    window.removeEventListener("mousemove", onWinMouseMove);
    window.removeEventListener("mouseup", onWinMouseUp);
    window.removeEventListener("touchmove", onWinTouchMove);
    window.removeEventListener("touchend", onWinTouchEnd);
    window.removeEventListener("touchcancel", onWinTouchEnd);
  }

  // Capture phase on the chart root: runs before the chart's own handlers, so a press on a
  // drawing never starts a pan; presses elsewhere pass through untouched.
  const onMouseDown = (e: MouseEvent) => {
    active = true;
    if (e.button !== 0) return;
    if (beginDrag(e.clientX, e.clientY)) { e.stopPropagation(); e.preventDefault(); attachWindowDrag(); }
  };
  const onTouchStart = (e: TouchEvent) => {
    active = true;
    const t = e.touches[0];
    if (e.touches.length === 1 && t && beginDrag(t.clientX, t.clientY)) { e.stopPropagation(); e.preventDefault(); attachWindowDrag(); }
  };
  let down: Pt | null = null;
  const onPointerDown = (e: PointerEvent) => { down = e.button === 0 && e.isPrimary ? { x: e.clientX, y: e.clientY } : null; };
  const onPointerUp = (e: PointerEvent) => {
    const d = down;
    down = null;
    if (!d || e.button !== 0 || !e.isPrimary || Math.abs(e.clientX - d.x) + Math.abs(e.clientY - d.y) >= 5) return;
    const { x, y } = panePoint(e.clientX, e.clientY);
    if (x < 0 || y < 0 || x > paneW() || y > paneH()) return;
    onPaneClick(x, y);
  };
  el.addEventListener("pointerdown", onPointerDown, true);
  el.addEventListener("pointerup", onPointerUp, true);
  el.addEventListener("dblclick", onDblClick);
  const onDocDown = (e: Event) => { if (!el.contains(e.target as Node)) active = false; };
  el.addEventListener("mousedown", onMouseDown, true);
  el.addEventListener("touchstart", onTouchStart, { capture: true, passive: false });
  document.addEventListener("mousedown", onDocDown, true);
  document.addEventListener("touchstart", onDocDown, { capture: true, passive: true });

  // ---------------- keyboard ----------------
  const onKey = (e: KeyboardEvent) => {
    if (isEditable(e.target)) return;
    if (e.key === "Escape") {
      if (drag) { drawings = drag.before; drag.moved = false; endDrag(); return; }
      if (pending) { pending = null; requestUpdate(); return; }
      if (active && isShape(tool)) { setToolInternal("cursor", true); return; }
      if (active && selectedId) { selectedId = null; requestUpdate(); }
      return;
    }
    if (!active) return;
    if ((e.key === "Delete" || e.key === "Backspace") && selectedId && !locked) {
      e.preventDefault();
      const id = selectedId;
      selectedId = null;
      commit(drawings.filter((d) => d.id !== id));
      return;
    }
    const mod = e.ctrlKey || e.metaKey;
    if (mod && !e.altKey && (e.key === "z" || e.key === "Z")) { e.preventDefault(); if (e.shiftKey) api.redo(); else api.undo(); return; }
    if (mod && !e.altKey && (e.key === "y" || e.key === "Y")) { e.preventDefault(); api.redo(); }
  };
  window.addEventListener("keydown", onKey);

  // ---------------- public API ----------------
  const api: DrawingManager = {
    setTool: (t) => setToolInternal(t, false),
    getTool: () => tool,
    setMagnet: (b) => { magnet = b; requestUpdate(); },
    setLocked: (b) => {
      locked = b;
      if (b) { if (drag) endDrag(); selectedId = null; }
      requestUpdate();
    },
    setVisible: (b) => {
      visible = b;
      if (!b) { if (drag) endDrag(); pending = null; selectedId = null; }
      requestUpdate();
    },
    clear: () => { if (drawings.length) { selectedId = null; pending = null; commit([]); } },
    undo: () => {
      const prev = undoStack.pop();
      if (!prev) return;
      redoStack.push(cloneDrawings(drawings));
      drawings = prev;
      if (selectedId && !drawings.some((d) => d.id === selectedId)) selectedId = null;
      changed();
    },
    redo: () => {
      const next = redoStack.pop();
      if (!next) return;
      undoStack.push(cloneDrawings(drawings));
      drawings = next;
      if (selectedId && !drawings.some((d) => d.id === selectedId)) selectedId = null;
      changed();
    },
    canUndo: () => undoStack.length > 0,
    canRedo: () => redoStack.length > 0,
    destroy: () => {
      if (destroyed) return;
      destroyed = true;
      if (drag) { const d = drag; drag = null; try { chart.applyOptions({ handleScroll: d.scroll, handleScale: d.scale }); } catch { /* chart gone */ } }
      detachWindowDrag();
      window.removeEventListener("keydown", onKey);
      window.removeEventListener("qstock-theme", onTheme);
      el.removeEventListener("mousedown", onMouseDown, true);
      el.removeEventListener("touchstart", onTouchStart, true);
      document.removeEventListener("mousedown", onDocDown, true);
      document.removeEventListener("touchstart", onDocDown, true);
      el.removeEventListener("pointerdown", onPointerDown, true);
      el.removeEventListener("pointerup", onPointerUp, true);
      el.removeEventListener("dblclick", onDblClick);
      try {
        chart.unsubscribeCrosshairMove(onMove);
        series.unsubscribeDataChanged(onData);
        series.detachPrimitive(primitive);
      } catch { /* chart already removed */ }
      textBoxes.clear();
    },
  };
  return api;
}
