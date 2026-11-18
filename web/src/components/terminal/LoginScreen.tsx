import { FormEvent, useState } from "react";
import { Atom, KeyRound, Loader2 } from "lucide-react";
import { login, User } from "../../lib/api";

/** Sign-on screen. mode: "login" (accounts exist), "setup" (no account yet), "offline" (API unreachable or snapshot build). */
export default function LoginScreen({ mode, onUser, onGuest }: {
  mode: "login" | "setup" | "offline"; onUser: (u: User) => void; onGuest: () => void;
}) {
  const [username, setUsername] = useState("Nabi");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const submit = async (e: FormEvent) => {
    e.preventDefault(); setBusy(true); setErr(null);
    try { onUser(await login(username.trim(), password)); } catch (x) { setErr(String((x as Error).message)); } finally { setBusy(false); setPassword(""); }
  };
  const now = new Date();
  return (
    <div className="flex min-h-full items-center justify-center bg-bg p-4">
      <div className="w-full max-w-[560px] border border-line bg-surface">
        <div className="panel-bar flex items-center justify-between px-3 py-1.5">
          <span className="card-title flex items-center gap-2"><Atom size={14} /> Q-STOCK TERMINAL · SIGN ON</span>
          <span className="text-[11px] font-semibold">{now.toLocaleDateString("en-GB", { day: "2-digit", month: "short", year: "numeric" }).toUpperCase()}</span>
        </div>
        <div className="space-y-4 p-6">
          <pre className="select-none text-[11px] leading-4 text-accent" aria-hidden>{`  ___        ____  _             _
 / _ \\      / ___|| |_ ___   ___| | __
| | | |_____\\___ \\| __/ _ \\ / __| |/ /
| |_| |_____|___) | || (_) | (__|   <
 \\__\\_\\     |____/ \\__\\___/ \\___|_|\\_\\`}</pre>
          <p className="text-[12px] text-muted">Quantum-walk market analytics · NSE &amp; NASDAQ · classical simulation in R</p>

          {mode === "login" && (
            <form onSubmit={submit} className="space-y-3">
              <label className="block text-[11px] uppercase tracking-widest text-muted">User
                <input className="term-input mt-1 !normal-case !text-ink" value={username} onChange={(e) => setUsername(e.target.value)} autoComplete="username" required />
              </label>
              <label className="block text-[11px] uppercase tracking-widest text-muted">Password
                <input className="term-input mt-1 !normal-case !text-ink" type="password" value={password} onChange={(e) => setPassword(e.target.value)} autoComplete="current-password" autoFocus required />
              </label>
              {err && <div className="border border-down/60 bg-down/10 px-2 py-1 text-[12px] text-down">{err}</div>}
              <div className="flex items-center gap-2">
                <button type="submit" className="fkey fkey-on !px-4 !py-1.5" disabled={busy}>
                  {busy ? <Loader2 size={13} className="animate-spin" /> : <KeyRound size={13} />} Sign on <kbd>GO</kbd>
                </button>
                <button type="button" className="btn" onClick={onGuest}>Read-only guest</button>
              </div>
              <p className="text-[11px] text-muted">Guests see every page except the assistant. Sessions last 12 hours.</p>
            </form>
          )}

          {mode === "setup" && (
            <div className="space-y-3 text-[12px]">
              <p className="text-warn">No account exists on this server yet.</p>
              <p className="text-ink/90">Create yours once, from the project root (the password is asked for in the terminal and stored only as a hash):</p>
              <pre className="border border-line bg-black px-3 py-2 text-accent">Rscript scripts/32_create_user.R Nabi</pre>
              <p className="text-ink/90">Then restart the API (<code className="text-accent">Rscript api/run_api.R</code>) and reload this page.</p>
              <button className="btn" onClick={onGuest}>Continue without signing in</button>
            </div>
          )}

          {mode === "offline" && (
            <div className="space-y-3 text-[12px]">
              <p className="text-warn">The R API is not reachable{import.meta.env.VITE_SNAPSHOT === "1" ? " (static snapshot build)" : " (it may be waking up)"}, so signing in is unavailable.</p>
              <p className="text-ink/90">You can browse the saved snapshot read-only; the assistant needs the live API.</p>
              <button className="fkey fkey-on !px-4 !py-1.5" onClick={onGuest}>Continue read-only <kbd>GO</kbd></button>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
