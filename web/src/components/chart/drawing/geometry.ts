import type { Time } from "lightweight-charts";
import type { Anchor, Drawing, ShapeType } from "./types";

/** Chart time (UTCTimestamp, business-day string or object) -> epoch seconds. */
export function timeToSec(t: Time): number {
  if (typeof t === "number") return t;
  if (typeof t === "string") return Date.parse(`${t}T00:00:00Z`) / 1000;
  return Date.UTC(t.year, t.month - 1, t.day) / 1000;
}

/** Maps bar times <-> (fractional) logical indices, extrapolating with the edge bar spacing
 *  beyond the data so anchors in the empty space right of the last bar stay stable. */
export class TimeIndex {
  private times: number[] = [];

  set(times: number[]) { this.times = times; }
  get length() { return this.times.length; }

  private stepStart() { const t = this.times; return t.length > 1 && t[1] > t[0] ? t[1] - t[0] : 60; }
  private stepEnd() { const t = this.times, n = t.length; return n > 1 && t[n - 1] > t[n - 2] ? t[n - 1] - t[n - 2] : 60; }

  /** Fractional logical index of a time (interpolated between bars, extrapolated outside). */
  logicalOf(time: number): number | null {
    const t = this.times, n = t.length;
    if (n === 0 || !isFinite(time)) return null;
    if (time >= t[n - 1]) return n - 1 + (time - t[n - 1]) / this.stepEnd();
    if (time <= t[0]) return (time - t[0]) / this.stepStart();
    let lo = 0, hi = n - 1;
    while (hi - lo > 1) { const m = (lo + hi) >> 1; if (t[m] <= time) lo = m; else hi = m; }
    const span = t[hi] - t[lo];
    return lo + (span > 0 ? (time - t[lo]) / span : 0);
  }

  /** Time at a (fractional) logical index; inverse of logicalOf. */
  timeAt(logical: number): number | null {
    const t = this.times, n = t.length;
    if (n === 0 || !isFinite(logical)) return null;
    if (logical <= 0) return Math.round(t[0] + logical * this.stepStart());
    if (logical >= n - 1) return Math.round(t[n - 1] + (logical - (n - 1)) * this.stepEnd());
    const i = Math.floor(logical), f = logical - i;
    return Math.round(t[i] + f * (t[i + 1] - t[i]));
  }
}

export function distToSegment(px: number, py: number, ax: number, ay: number, bx: number, by: number) {
  const dx = bx - ax, dy = by - ay, L = dx * dx + dy * dy;
  const u = L === 0 ? 0 : Math.max(0, Math.min(1, ((px - ax) * dx + (py - ay) * dy) / L));
  return Math.hypot(px - (ax + u * dx), py - (ay + u * dy));
}

export function distToRay(px: number, py: number, ax: number, ay: number, bx: number, by: number) {
  const dx = bx - ax, dy = by - ay, L = dx * dx + dy * dy;
  const u = L === 0 ? 0 : Math.max(0, ((px - ax) * dx + (py - ay) * dy) / L);
  return Math.hypot(px - (ax + u * dx), py - (ay + u * dy));
}

/** Point far beyond B along A->B (the canvas clips it). */
export function extendRay(ax: number, ay: number, bx: number, by: number, w: number, h: number) {
  const dx = bx - ax, dy = by - ay, L = Math.hypot(dx, dy);
  if (L === 0) return { x: bx, y: by };
  const k = (4 * (w + h)) / L;
  return { x: ax + dx * k, y: ay + dy * k };
}

export function formatSpan(sec: number): string {
  const s = Math.abs(Math.round(sec));
  const d = Math.floor(s / 86400), h = Math.floor((s % 86400) / 3600), m = Math.floor((s % 3600) / 60);
  if (d > 0) return h > 0 && d < 7 ? `${d}d ${h}h` : `${d}d`;
  if (h > 0) return m > 0 ? `${h}h ${m}m` : `${h}h`;
  if (m > 0) return `${m}m`;
  return `${s}s`;
}

const TYPES: ReadonlySet<string> = new Set<ShapeType>(["trend", "ray", "hline", "hray", "vline", "rect", "fib", "measure", "text"]);
const okAnchor = (a: unknown): a is Anchor =>
  !!a && typeof a === "object" && isFinite((a as Anchor).time) && isFinite((a as Anchor).price);

/** Validates persisted JSON; silently drops malformed entries. */
export function parseDrawings(raw: string | null): Drawing[] {
  if (!raw) return [];
  try {
    const v = JSON.parse(raw) as { drawings?: unknown } | unknown[];
    const arr = Array.isArray(v) ? v : (v as { drawings?: unknown }).drawings;
    if (!Array.isArray(arr)) return [];
    const out: Drawing[] = [];
    for (const x of arr as Partial<Drawing>[]) {
      if (!x || typeof x.id !== "string" || !TYPES.has(x.type as string) || !okAnchor(x.a)) continue;
      const d: Drawing = { id: x.id, type: x.type as ShapeType, a: { time: x.a.time, price: x.a.price } };
      if (okAnchor(x.b)) d.b = { time: x.b.time, price: x.b.price };
      if (typeof x.text === "string") d.text = x.text;
      if (["trend", "ray", "rect", "fib", "measure"].includes(d.type) && !d.b) continue;
      out.push(d);
    }
    return out;
  } catch {
    return [];
  }
}

export const cloneDrawings = (ds: readonly Drawing[]): Drawing[] =>
  ds.map((d) => ({ ...d, a: { ...d.a }, b: d.b ? { ...d.b } : undefined }));
