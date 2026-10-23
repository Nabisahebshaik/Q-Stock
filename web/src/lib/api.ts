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
const src = (live: string, snap: string) => (SNAPSHOT ? `/data/${snap}` : `${API}${live}`);
const every = (ms: number) => (SNAPSHOT ? false : ms);

async function get<T>(path: string): Promise<T> {
  const r = await fetch(path);
  if (!r.ok) throw new Error(`${path}: HTTP ${r.status}`);
  return r.json() as Promise<T>;
}

export interface SnapshotMeta { snapshot_at: number; snapshot_iso: string; omega_step: number; look: number }
export const useSnapshotMeta = () =>
  useQuery({ queryKey: ["meta"], queryFn: () => get<SnapshotMeta>("/data/meta.json"), enabled: SNAPSHOT, staleTime: Infinity });

export const useStatus = () => useQuery({ queryKey: ["status"], queryFn: () => get<StatusData[]>(src("/api/status", "status.json")), refetchInterval: every(30_000) });
export const useLive = (m: Market) =>
  useQuery({ queryKey: ["live", m], queryFn: () => get<LiveData>(src(`/api/live/${m}`, `live_${m}.json`)), refetchInterval: every(60_000), placeholderData: (p) => p });
export const useCandles = (m: Market, t: string | null) =>
  useQuery({ queryKey: ["candles", m, t], queryFn: () => get<CandleData>(src(`/api/candles/${m}/${encodeURIComponent(t!)}`, `candles_${m}_${t}.json`)),
             enabled: !!t, refetchInterval: every(60_000), placeholderData: (p) => p });
export const useGraph = (m: Market, omega: number, look: number) =>
  useQuery({ queryKey: ["graph", m, omega, look], queryFn: () => get<GraphData>(src(`/api/graph/${m}?omega=${omega}&look=${look}`, `graph_${m}_${tag(omega)}.json`)),
             refetchInterval: every(60_000), placeholderData: (p) => p });
export const useForecast = (m: Market) =>
  useQuery({ queryKey: ["forecast", m], queryFn: () => get<ForecastData>(src(`/api/forecast/${m}`, `forecast_${m}.json`)), staleTime: 30 * 60_000 });
export const useDial = (m: Market, date: string, omega: number) =>
  useQuery({ queryKey: ["dial", m, date, omega], queryFn: () => get<DialData>(src(`/api/dial?market=${m}&date=${date}&omega=${omega}`, `dial_${m}_${tag(omega)}.json`)),
             placeholderData: (p) => p, staleTime: Infinity });
export const useResults = () => useQuery({ queryKey: ["results"], queryFn: () => get<ResultsData>(src("/api/results", "results.json")), staleTime: 5 * 60_000 });
