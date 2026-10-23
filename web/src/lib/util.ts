import { useEffect, useState } from "react";

export const pct = (x: number | null | undefined, d = 2, sign = false) =>
  x == null || !isFinite(x) ? "—" : `${sign && x > 0 ? "+" : ""}${(100 * x).toFixed(d)}%`;
export const price = (x: number | null | undefined, market?: string) =>
  x == null ? "—" : `${market === "NSE" ? "₹" : "$"}${x.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
// International grouping (en-US): a locale such as en-IN would print lakhs ("74.9L").
export const compact = (x: number) => Intl.NumberFormat("en-US", { notation: "compact", maximumFractionDigits: 2 }).format(x);
export const exact = (x: number) => x.toLocaleString("en-US");
export const ago = (sec: number) => (sec < 90 ? `${Math.round(sec)} s` : sec < 5400 ? `${Math.round(sec / 60)} min` : `${(sec / 3600).toFixed(1)} h`);

/** CSS variable (RGB triplet) -> "rgba(r, g, b, a)" (comma syntax: canvas chart libraries
 *  do not parse CSS Color 4 "rgb(r g b / a)"); re-read when the theme changes. */
export const cssColor = (name: string, alpha = 1) => {
  const v = getComputedStyle(document.documentElement).getPropertyValue(`--${name}`).trim().split(/\s+/).join(", ");
  return `rgba(${v}, ${alpha})`;
};
export const cssHex = (name: string) => {
  const [r, g, b] = getComputedStyle(document.documentElement).getPropertyValue(`--${name}`).trim().split(/\s+/).map(Number);
  return "#" + [r, g, b].map((c) => c.toString(16).padStart(2, "0")).join("");
};

export type Theme = "dark" | "light";
export function useTheme(): [Theme, (t: Theme) => void] {
  const [theme, setTheme] = useState<Theme>(() => (document.documentElement.dataset.theme as Theme) || "dark");
  useEffect(() => {
    document.documentElement.dataset.theme = theme;
    try { localStorage.setItem("qstock-theme", theme); } catch { /* storage unavailable: theme still applies */ }
    window.dispatchEvent(new Event("qstock-theme"));
  }, [theme]);
  return [theme, setTheme];
}
/** Re-render on theme switch (for canvas/WebGL colours that read CSS variables). */
export function useThemeTick() {
  const [n, setN] = useState(0);
  useEffect(() => { const f = () => setN((k) => k + 1); window.addEventListener("qstock-theme", f); return () => window.removeEventListener("qstock-theme", f); }, []);
  return n;
}
export function useReducedMotion() {
  const q = "(prefers-reduced-motion: reduce)";
  const [r, setR] = useState(() => window.matchMedia(q).matches);
  useEffect(() => { const m = window.matchMedia(q); const f = () => setR(m.matches); m.addEventListener("change", f); return () => m.removeEventListener("change", f); }, []);
  return r;
}
/** Diverging colour for a daily change: down (red) - neutral grey - up (green), saturating at ±3%. */
export function changeColor(ch: number | null | undefined, up: string, down: string, flat: string) {
  if (ch == null || !isFinite(ch)) return flat;
  const z = Math.max(-1, Math.min(1, ch / 0.03));
  return mix(flat, z >= 0 ? up : down, Math.abs(z));
}
export function mix(a: string, b: string, t: number) {
  const pa = hex(a), pb = hex(b);
  return "#" + pa.map((v, i) => Math.round(v + (pb[i] - v) * t).toString(16).padStart(2, "0")).join("");
}
const hex = (h: string) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16));
