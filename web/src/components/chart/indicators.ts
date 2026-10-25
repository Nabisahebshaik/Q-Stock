import type { IndicatorOut } from "../../lib/api";
import { specToken, type IndicatorSpec } from "./types";

/** The server's output for a UI indicator: by contract id, else by type and parameters. */
export function matchIndicator(spec: IndicatorSpec, outs: IndicatorOut[]): IndicatorOut | undefined {
  const tok = specToken(spec); if (!tok) return undefined;
  return outs.find((o) => o.id === tok) ??
    outs.find((o) => o.type === spec.type && (spec.n == null || Number(o.params?.n) === spec.n) && (spec.k == null || Number(o.params?.k) === spec.k));
}

/** time -> value lookup per line, for legend values under the crosshair. */
export const lineLookup = (o: IndicatorOut) => o.lines.map((l) => ({ name: l.name, at: new Map(l.values.map((v) => [v.time, v.value])) }));
