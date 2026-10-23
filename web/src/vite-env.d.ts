/// <reference types="vite/client" />

interface ImportMetaEnv {
  /** "1" = static snapshot build (reads /data/*.json exported by scripts/25_export_snapshot.R) */
  readonly VITE_SNAPSHOT?: string;
  /** Base URL of a hosted R API for live mode (default: same origin) */
  readonly VITE_API_URL?: string;
}
interface ImportMeta { readonly env: ImportMetaEnv }
