/** @type {import('tailwindcss').Config} */
export default {
  content: ["./index.html", "./src/**/*.{ts,tsx}"],
  darkMode: ["selector", '[data-theme="dark"]'],
  theme: {
    extend: {
      colors: {
        bg: "rgb(var(--bg) / <alpha-value>)",
        surface: "rgb(var(--surface) / <alpha-value>)",
        raised: "rgb(var(--raised) / <alpha-value>)",
        line: "rgb(var(--line) / <alpha-value>)",
        ink: "rgb(var(--ink) / <alpha-value>)",
        muted: "rgb(var(--muted) / <alpha-value>)",
        accent: "rgb(var(--accent) / <alpha-value>)",
        quantum: "rgb(var(--quantum) / <alpha-value>)",
        up: "rgb(var(--up) / <alpha-value>)",
        down: "rgb(var(--down) / <alpha-value>)",
        warn: "rgb(var(--warn) / <alpha-value>)",
      },
      fontFamily: {
        sans: ["Inter", "ui-sans-serif", "system-ui", "Segoe UI", "sans-serif"],
        mono: ["JetBrains Mono", "ui-monospace", "Cascadia Code", "monospace"],
      },
      keyframes: {
        marquee: { "0%": { transform: "translateX(0)" }, "100%": { transform: "translateX(-50%)" } },
        pulseDot: { "0%,100%": { opacity: "1" }, "50%": { opacity: "0.35" } },
      },
      animation: { marquee: "marquee 60s linear infinite", pulseDot: "pulseDot 1.6s ease-in-out infinite" },
    },
  },
  plugins: [],
};
