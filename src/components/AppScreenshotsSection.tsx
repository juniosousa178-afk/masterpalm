"use client";

import { useState, useEffect } from "react";
import { siteConfig } from "@/config/site";

const SCREENSHOTS = siteConfig.screenshots;

export function AppScreenshotsSection() {
  const [currentIndex, setCurrentIndex] = useState(0);

  useEffect(() => {
    if (SCREENSHOTS.length <= 1) return;
    const interval = setInterval(() => {
      setCurrentIndex((prev) => (prev + 1) % SCREENSHOTS.length);
    }, 4000);
    return () => clearInterval(interval);
  }, []);

  return (
    <section
      className="py-20 px-4 sm:px-6 lg:px-8"
      aria-labelledby="screenshots-app-title"
    >
      <div className="max-w-6xl mx-auto">
        <h2
          id="screenshots-app-title"
          className="text-3xl sm:text-4xl font-bold text-white text-center mb-4"
        >
          Conheça o MasterPalm
        </h2>
        <p className="text-gray-400 text-center mb-14 max-w-2xl mx-auto">
          Interface intuitiva para gestão completa da sua loja. Veja as telas do
          aplicativo em ação.
        </p>

        <div className="flex justify-center">
          {/* Phone frame */}
          <div className="relative">
            {/* Phone bezel - estilo moderno com notch */}
            <div
              className="relative w-[280px] sm:w-[320px] rounded-[2.5rem] p-2 sm:p-3 bg-graphite-800 border-[3px] border-graphite-600 shadow-2xl shadow-black/50"
              style={{
                boxShadow:
                  "0 25px 50px -12px rgba(0,0,0,0.5), inset 0 1px 0 rgba(255,255,255,0.05)",
              }}
            >
              {/* Notch */}
              <div className="absolute top-2 left-1/2 -translate-x-1/2 w-24 h-6 bg-graphite-900 rounded-b-xl z-10" />

              {/* Screen area */}
              <div className="relative w-full aspect-[9/19] max-h-[580px] rounded-[2rem] overflow-hidden bg-graphite-900">
                {SCREENSHOTS.length > 0 ? (
                  <>
                    {SCREENSHOTS.map((src, i) => (
                      <div
                        key={src}
                        className={`absolute inset-0 transition-opacity duration-700 ease-in-out ${
                          i === currentIndex ? "opacity-100 z-[1]" : "opacity-0 z-0"
                        }`}
                      >
                        <img
                          src={src}
                          alt={`Tela do app ${i + 1}`}
                          className="w-full h-full object-cover object-top"
                        />
                      </div>
                    ))}

                    {/* Dots de navegação */}
                    {SCREENSHOTS.length > 1 && (
                      <div className="absolute bottom-4 left-0 right-0 flex justify-center gap-2 z-20">
                        {SCREENSHOTS.map((_, i) => (
                          <button
                            key={i}
                            onClick={() => setCurrentIndex(i)}
                            className={`w-2 h-2 rounded-full transition-all duration-300 ${
                              i === currentIndex
                                ? "bg-accent-blue w-6"
                                : "bg-white/40 hover:bg-white/60"
                            }`}
                            aria-label={`Ir para tela ${i + 1}`}
                          />
                        ))}
                      </div>
                    )}
                  </>
                ) : (
                  /* Placeholder quando não há screenshots */
                  <div className="absolute inset-0 flex flex-col items-center justify-center p-6 text-center">
                    <div className="w-16 h-16 rounded-2xl bg-graphite-700 flex items-center justify-center mb-4">
                      <svg
                        className="w-8 h-8 text-gray-500"
                        fill="none"
                        stroke="currentColor"
                        viewBox="0 0 24 24"
                      >
                        <path
                          strokeLinecap="round"
                          strokeLinejoin="round"
                          strokeWidth={1.5}
                          d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"
                        />
                      </svg>
                    </div>
                    <p className="text-gray-500 text-sm">
                      Adicione screenshots em
                      <br />
                      <code className="text-gray-400">/public/screenshots/</code>
                    </p>
                  </div>
                )}
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
