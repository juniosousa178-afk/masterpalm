import type { Config } from "tailwindcss";

const config: Config = {
  content: [
    "./src/pages/**/*.{js,ts,jsx,tsx,mdx}",
    "./src/components/**/*.{js,ts,jsx,tsx,mdx}",
    "./src/app/**/*.{js,ts,jsx,tsx,mdx}",
  ],
  theme: {
    extend: {
      colors: {
        graphite: {
          50: "#f6f6f7",
          100: "#e2e2e4",
          200: "#c4c4c9",
          300: "#9f9fa6",
          400: "#7a7a83",
          500: "#5f5f67",
          600: "#4c4c52",
          700: "#3f3f44",
          800: "#36363a",
          900: "#1a1a1c",
          950: "#0d0d0e",
        },
        silver: {
          400: "#e0e0e0",
          500: "#c0c0c0",
          600: "#a0a0a0",
        },
        accent: {
          blue: "#3b82f6",
          "blue-light": "#60a5fa",
        },
      },
      fontFamily: {
        sans: ["var(--font-plus-jakarta)", "system-ui", "sans-serif"],
      },
      boxShadow: {
        "soft": "0 4px 20px rgba(0, 0, 0, 0.25)",
        "glow": "0 0 30px rgba(59, 130, 246, 0.25)",
      },
    },
  },
  plugins: [],
};

export default config;
