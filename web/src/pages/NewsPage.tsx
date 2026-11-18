import { AlertTriangle, ExternalLink, Newspaper } from "lucide-react";
import { Market, useLive, useNews, useShowingSnapshot, useStatus } from "../lib/api";
import { ago, pct, price } from "../lib/util";
import { Card, Delta, Segmented, Skeleton } from "../components/ui";

/** Company news (Yahoo Finance; GDELT when Yahoo has nothing). Headlines are shown as published: no scores are invented. */
export default function NewsPage({ market, setMarket, ticker, setTicker }: {
  market: Market; setMarket: (m: Market) => void; ticker: string; setTicker: (t: string) => void;
}) {
  const SNAPSHOT = useShowingSnapshot();
  const status = useStatus();
  const live = useLive(market);
  const news = useNews(market, ticker);
  const tickers = status.data?.find((s) => s.market === market)?.tickers ?? [];
  const q = live.data?.quotes?.find((x) => x.ticker === ticker);
  const N = news.data;
  const errs = N ? Object.entries(Array.isArray(N.errors) ? {} : N.errors ?? {}) : [];
  const tz = market === "NSE" ? "Asia/Kolkata" : "America/New_York";
  const when = (t: number) => new Date(t * 1000).toLocaleString("en-GB", { timeZone: tz, day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit" });
  const nowSec = Date.now() / 1000;

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center gap-2">
        <Segmented value={market} onChange={setMarket} options={[{ value: "NSE", label: "NSE" }, { value: "NASDAQ", label: "NASDAQ" }]} />
        <span className="chip"><Newspaper size={12} /> source: Yahoo Finance · GDELT fallback</span>
        {SNAPSHOT && <span className="chip border-warn/60 text-warn">headlines saved at snapshot time</span>}
      </div>
      <div className="grid gap-3 lg:grid-cols-[260px_1fr]">
        <Card title="Monitor" bodyClass="max-h-[680px] overflow-y-auto">
          <ul>{tickers.map((t) => {
            const x = live.data?.quotes?.find((y) => y.ticker === t.ticker);
            return (
              <li key={t.ticker}>
                <button onClick={() => setTicker(t.ticker)} className={`grid w-full grid-cols-[1fr_auto] items-center gap-x-2 border-b border-line/50 px-3 py-1.5 text-left text-[12px] ${t.ticker === ticker ? "bg-accent text-black" : "hover:bg-raised"}`}>
                  <span className="font-semibold">{t.label}</span>
                  <span className="num">{x ? pct(x.change, 2, true) : ""}</span>
                  <span className={`col-span-2 truncate text-[10.5px] ${t.ticker === ticker ? "text-black/70" : "text-muted"}`}>{t.name}</span>
                </button>
              </li>);
          })}</ul>
        </Card>

        <Card title={`${ticker.replace(/\.NS$/, "")} · news`} right={q && <span className="flex items-center gap-2 text-[12px] font-semibold">{price(q.last, market)} <span className="bg-black px-1"><Delta x={q.change} /></span></span>}>
          {news.isLoading && <Skeleton h={300} />}
          {N && (
            <div className="flex flex-wrap items-center gap-2 border-b border-line px-3 py-1.5 text-[11px] text-muted">
              {N.fetched_at && <span>fetched {ago(nowSec - N.fetched_at)} ago</span>}
              {N.stale && <span className="chip border-warn/50 text-warn"><AlertTriangle size={11} /> feed failed · showing last good list</span>}
              {errs.map(([k, v]) => <span key={k} className="chip border-down/50 text-down">{k}: {String(v)}</span>)}
            </div>
          )}
          {N && !N.items?.length && <p className="p-4 text-warn">No headlines returned for this stock right now. Nothing is shown in their place.</p>}
          <ol>
            {(N?.items ?? []).map((n, i) => (
              <li key={n.id} className="grid grid-cols-[34px_1fr] gap-2 border-b border-line/50 px-3 py-2 hover:bg-raised">
                <span className="num pt-0.5 text-accent">{String(i + 1).padStart(2, "0")})</span>
                <div>
                  <a href={n.url} target="_blank" rel="noreferrer noopener" className="group inline-flex items-start gap-1.5 text-[13px] font-semibold text-ink hover:text-accent">
                    {n.title}<ExternalLink size={12} className="mt-1 shrink-0 opacity-50 group-hover:opacity-100" />
                  </a>
                  <div className="mt-0.5 text-[11px] text-muted">
                    <span className="text-quantum">{n.publisher}</span> · {when(n.published)} · {ago(Math.max(0, nowSec - n.published))} ago · via {n.source}
                  </div>
                </div>
              </li>
            ))}
          </ol>
        </Card>
      </div>
    </div>
  );
}
