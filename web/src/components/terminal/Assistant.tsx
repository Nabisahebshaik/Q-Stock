import { FormEvent, ReactNode, useEffect, useRef, useState } from "react";
import { Bot, Loader2, Send, X } from "lucide-react";
import { ask, ChatReply, Market } from "../../lib/api";

type Msg = { who: "me" | "bot"; text: string; sources?: string[]; err?: boolean };

const SUGGEST = ["Why is RELIANCE's volatility forecast high?", "Riskiest NASDAQ stocks this week", "News on Infosys",
                 "What does the quantum dial ω do?", "Did the quantum features beat the baseline?"];

/** Inline markdown subset (bold, italic, links) rendered as React elements: no HTML injection. */
function inline(s: string, key: string): ReactNode[] {
  const out: ReactNode[] = []; const re = /\*\*([^*]+)\*\*|\*([^*]+)\*|\[([^\]]+)\]\((https?:[^)\s]+)\)/g;
  let last = 0, m: RegExpExecArray | null, i = 0;
  while ((m = re.exec(s))) {
    if (m.index > last) out.push(s.slice(last, m.index));
    if (m[1]) out.push(<strong key={`${key}b${i}`}>{m[1]}</strong>);
    else if (m[2]) out.push(<em key={`${key}i${i}`}>{m[2]}</em>);
    else out.push(<a key={`${key}a${i}`} href={m[4]} target="_blank" rel="noreferrer noopener">{m[3]}</a>);
    last = re.lastIndex; i++;
  }
  if (last < s.length) out.push(s.slice(last));
  return out;
}
export function Markdown({ text }: { text: string }) {
  const blocks: ReactNode[] = []; let list: string[] = [];
  const flush = (k: number) => { if (list.length) { blocks.push(<ul key={`u${k}`}>{list.map((l, j) => <li key={j}>{inline(l, `l${k}-${j}`)}</li>)}</ul>); list = []; } };
  text.split("\n").forEach((line, k) => {
    if (/^- /.test(line)) { list.push(line.slice(2)); return; }
    flush(k);
    if (line.trim()) blocks.push(<p key={`p${k}`}>{inline(line, `p${k}`)}</p>);
  });
  flush(-1);
  return <div className="md">{blocks}</div>;
}

export default function Assistant({ open, onClose, market, canAsk, userName, seed }: {
  open: boolean; onClose: () => void; market: Market; canAsk: boolean; userName: string | null; seed?: { q: string; n: number } | null;
}) {
  const [msgs, setMsgs] = useState<Msg[]>([]);
  const [text, setText] = useState("");
  const [busy, setBusy] = useState(false);
  const end = useRef<HTMLDivElement>(null);
  useEffect(() => { end.current?.scrollIntoView({ behavior: "smooth" }); }, [msgs, busy]);
  const go = async (q: string) => {
    if (!q.trim() || busy) return;
    setMsgs((m) => [...m, { who: "me", text: q }]); setText(""); setBusy(true);
    try { const r: ChatReply = await ask(q, market); setMsgs((m) => [...m, { who: "bot", text: r.reply, sources: r.sources }]); }
    catch (e) { setMsgs((m) => [...m, { who: "bot", text: String((e as Error).message), err: true }]); }
    finally { setBusy(false); }
  };
  // eslint-disable-next-line react-hooks/exhaustive-deps
  useEffect(() => { if (seed && canAsk) void go(seed.q); }, [seed?.n]);
  const submit = (e: FormEvent) => { e.preventDefault(); void go(text); };
  if (!open) return null;
  return (
    <aside className="fixed bottom-7 right-0 top-[86px] z-50 flex w-full max-w-[440px] flex-col border-l border-line bg-surface shadow-[0_0_40px_rgba(0,0,0,0.7)]" aria-label="assistant">
      <div className="panel-bar flex items-center justify-between px-3 py-1.5">
        <span className="card-title flex items-center gap-2"><Bot size={14} /> ASK · Q-Stock assistant</span>
        <button onClick={onClose} aria-label="close assistant" className="hover:opacity-70"><X size={15} /></button>
      </div>
      <div className="flex-1 space-y-3 overflow-y-auto p-3 text-[12.5px] leading-relaxed">
        {!msgs.length && (
          <div className="space-y-3">
            <p className="text-muted">{userName ? `Hello ${userName}. ` : ""}I answer from Q-Stock's own data — live quotes, the volatility forecast and its exact explanation, news headlines and the research tables — and cite where each number comes from. No buy/sell advice.</p>
            <div className="flex flex-wrap gap-1.5">{SUGGEST.map((s) => <button key={s} className="chip hover:border-accent hover:text-accent !normal-case" onClick={() => go(s)} disabled={!canAsk}>{s}</button>)}</div>
          </div>
        )}
        {msgs.map((m, i) => (
          <div key={i} className={m.who === "me" ? "ml-8 border border-accent/40 bg-accent/10 px-2.5 py-1.5" : `mr-4 border px-2.5 py-1.5 ${m.err ? "border-down/50 text-down" : "border-line bg-raised"}`}>
            <div className="mb-0.5 text-[10px] uppercase tracking-widest text-muted">{m.who === "me" ? (userName ?? "you") : "Q-Stock"}</div>
            {m.who === "bot" && !m.err ? <Markdown text={m.text} /> : <div>{m.text}</div>}
            {!!m.sources?.length && <div className="mt-1 border-t border-line pt-1 text-[10.5px] text-muted">Sources: {m.sources.join(" · ")}</div>}
          </div>
        ))}
        {busy && <div className="flex items-center gap-2 text-muted"><Loader2 size={13} className="animate-spin" /> computing in R…</div>}
        <div ref={end} />
      </div>
      <form onSubmit={submit} className="flex gap-1.5 border-t border-line p-2">
        <input className="term-input !normal-case !text-ink" value={text} onChange={(e) => setText(e.target.value)} disabled={!canAsk}
               placeholder={canAsk ? "Ask about a stock, the forecast, news or the results…" : "Sign in (live API) to use the assistant"} maxLength={500} />
        <button className="fkey fkey-on" disabled={!canAsk || busy} aria-label="send"><Send size={13} /></button>
      </form>
    </aside>
  );
}
