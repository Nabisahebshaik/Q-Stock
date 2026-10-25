import { useEffect, useState } from "react";
import { useQuery } from "@tanstack/react-query";

// Types mirror api/plumber.R. Every number shown in the UI comes from these endpoints.
export type Market = "NSE" | "NASDAQ";

export interface Quote {
  ticker: string; label: string; name: string; last: number; change: number | null;
  rv: number | null; volume: number; last_time: number;
}
export interface LiveData {
  market: Market; open: boolean; local_time: string; updated_at: number; stale: boolean; errors: string[];
  newest_bar_age?: number; session_day?: string; fetch_sec?: number; range?: string;
  quotes: Quote[]; spark?: Record<string, number[]>;
  store?: { candles: number; tickers: number; written: number; rejected: number };
}
export interface Candle { time: number; open: number; high: number; low: number; close: number; volume: number; vwap: number | null }
export interface CandleData { ticker: string; label: string; active_last: boolean; candles: Candle[] }
export interface GraphData {
  market: Market; omega: number; n_bars: number;
  nodes: { id: string[]; label: string[]; change?: (number | null)[]; rv?: number[]; q_self?: number[]; q_ent?: number[]; q_volspill?: number[] } | null;
  edges: { source: string[]; target: string[]; rho: number[] };
  P: number[][];
}
export interface DialData extends GraphData { date: string; min_date: string; max_date: string; P_quantum: number[][]; P_classical: number[][] }
export interface Forecast { ticker: string; as_of: string; pred_lrv5: number; vol5_ann: number }
export interface ForecastData { market: Market; available: boolean; forecasts: Forecast[] | null; model: { train_from: string; train_to: string; n: number } | null }
export interface StatusData { market: Market; open: boolean; local_time: string; tz: string; tickers: { ticker: string; label: string; name: string }[] }
type Row = Record<string, number | string | boolean | null>;
export interface ResultsData {
  dial_curve: { market: Market; loss: string; diff: number; ci_lo: number; ci_hi: number; p_holm: number; omega: number }[];
  tuned: Row[]; tuned_tests: Row[]; lightgbm: Row[]; ghar_pairwise: Row[]; naive: Row[]; power: Row[];
  gpu: Row[]; spark: Row[]; robustness: Row[]; economic: Row[]; mlp: Row[] | null; mlp_status: "pending" | "final"; mr_groups: number | null;
}

/** Snapshot mode (static hosting, e.g. Vercel): read JSON exported by scripts/25_export_snapshot.R.
 *  Live mode: call the R API, same origin by default or VITE_API_URL if it is hosted elsewhere. */
export const SNAPSHOT = import.meta.env.VITE_SNAPSHOT === "1";
const API = (import.meta.env.VITE_API_URL ?? "").replace(/\/$/, "");
const tag = (w: number) => String(Math.round(w * 100)).padStart(3, "0");
const every = (ms: number) => (SNAPSHOT ? false : ms);
/** With a remote R API (VITE_API_URL), fall back to the bundled snapshot while the API is
 *  unreachable, e.g. a sleeping free-tier container; live data resume automatically. */
const FALLBACK = !SNAPSHOT && API !== "";
let usingFallback = false;
const setFallback = (on: boolean) => {
  if (on !== usingFallback) { usingFallback = on; window.dispatchEvent(new Event("qstock-fallback")); }
};
export function useFallback() {
  const [on, setOn] = useState(usingFallback);
  useEffect(() => { const f = () => setOn(usingFallback); window.addEventListener("qstock-fallback", f); return () => window.removeEventListener("qstock-fallback", f); }, []);
  return on;
}
/** True when the page shows saved data (snapshot build or fallback). */
export const useShowingSnapshot = () => { const fb = useFallback(); return SNAPSHOT || fb; };

async function get<T>(path: string): Promise<T> {
  const r = await fetch(path);
  if (!r.ok) throw new Error(`${path}: HTTP ${r.status}`);
  return r.json() as Promise<T>;
}
async function load<T>(live: string, snap: string): Promise<T> {
  if (SNAPSHOT) return get<T>(`/data/${snap}`);
  try {
    const out = await get<T>(`${API}${live}`);
    setFallback(false);
    return out;
  } catch (e) {
    if (!FALLBACK) throw e;
    const out = await get<T>(`/data/${snap}`);
    setFallback(true);
    return out;
  }
}

export interface SnapshotMeta { snapshot_at: number; snapshot_iso: string; omega_step: number; look: number }
export const useSnapshotMeta = () =>
  useQuery({ queryKey: ["meta"], queryFn: () => get<SnapshotMeta>("/data/meta.json"), enabled: SNAPSHOT || FALLBACK, staleTime: Infinity });

export const useStatus = () => useQuery({ queryKey: ["status"], queryFn: () => load<StatusData[]>("/api/status", "status.json"), refetchInterval: every(30_000) });
export const useLive = (m: Market) =>
  useQuery({ queryKey: ["live", m], queryFn: () => load<LiveData>(`/api/live/${m}`, `live_${m}.json`), refetchInterval: every(60_000), placeholderData: (p) => p });
export const useCandles = (m: Market, t: string | null) =>
  useQuery({ queryKey: ["candles", m, t], queryFn: () => load<CandleData>(`/api/candles/${m}/${encodeURIComponent(t!)}`, `candles_${m}_${t}.json`),
             enabled: !!t, refetchInterval: every(60_000), placeholderData: (p) => p });
export const useGraph = (m: Market, omega: number, look: number) =>
  useQuery({ queryKey: ["graph", m, omega, look], queryFn: () => load<GraphData>(`/api/graph/${m}?omega=${omega}&look=${look}`, `graph_${m}_${tag(omega)}.json`),
             refetchInterval: every(60_000), placeholderData: (p) => p });
export const useForecast = (m: Market) =>
  useQuery({ queryKey: ["forecast", m], queryFn: () => load<ForecastData>(`/api/forecast/${m}`, `forecast_${m}.json`), staleTime: 30 * 60_000 });
export const useDial = (m: Market, date: string, omega: number) =>
  useQuery({ queryKey: ["dial", m, date, omega], queryFn: () => load<DialData>(`/api/dial?market=${m}&date=${date}&omega=${omega}`, `dial_${m}_${tag(omega)}.json`),
             placeholderData: (p) => p, staleTime: Infinity });
export const useResults = () => useQuery({ queryKey: ["results"], queryFn: () => load<ResultsData>("/api/results", "results.json"), staleTime: 5 * 60_000 });

// Chart workspace (docs/design/CHART_WORKSPACE.md §3). Times are exchange-local epoch seconds.
export type BarInterval = "5s" | "1m" | "5m" | "15m" | "30m" | "1h" | "1d" | "1w" | "1mo";
export type BarRange = "1D" | "5D" | "1M" | "3M" | "6M" | "YTD" | "1Y" | "5Y" | "ALL";
export interface Bar { time: number; open: number; high: number; low: number; close: number; volume: number }
export interface IndicatorOut {
  id: string; type: "vwap" | "sma" | "ema" | "bb" | "rsi"; pane: "price" | "rsi";
  params: { n?: number; k?: number };
  lines: { name: string; values: { time: number; value: number }[] }[];
}
export interface BarsData {
  market: Market; ticker: string; label: string; name: string;
  interval: BarInterval; range: BarRange; tz: string; source: "store" | "daily" | "snapshot_5s";
  live: boolean; as_of: number | null; note: string | null;
  bars: Bar[]; indicators: IndicatorOut[];
}
const INTRADAY: BarInterval[] = ["1m", "5m", "15m", "30m", "1h"];
/** Bars + server-computed indicators. `ind` is the contract's comma list (e.g. "vwap,sma:20"). */
export const useBars = (m: Market, t: string | null, interval: BarInterval, range: BarRange, ind: string) =>
  useQuery({
    queryKey: ["bars", m, t, interval, range, ind],
    queryFn: () => load<BarsData>(
      `/api/bars/${m}/${encodeURIComponent(t!)}?interval=${interval}&range=${range}${ind ? `&ind=${encodeURIComponent(ind)}` : ""}`,
      `bars_${m}_${t}_${interval}.json`),
    enabled: !!t,
    refetchInterval: every(interval === "5s" ? 2_000 : INTRADAY.includes(interval) ? 60_000 : 30 * 60_000),
    placeholderData: (p) => p,
  });
