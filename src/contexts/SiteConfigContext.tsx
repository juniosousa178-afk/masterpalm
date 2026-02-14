"use client";

import React, { createContext, useContext, useEffect, useState } from "react";
import { doc, getDoc } from "firebase/firestore";
import { db } from "@/lib/firebase";
import { siteConfig as defaultConfig } from "@/config/site";

export type SiteConfigDynamic = {
  APK_DOWNLOAD_URL: string;
  APP_WEB_URL: string;
  SUPPORT_WHATSAPP_URL: string;
  INSTAGRAM_URL: string;
  SUPPORT_EMAIL: string;
  apkVersion: string;
  apkSize: string;
  apkReleaseDate: string;
};

const defaultDynamic: SiteConfigDynamic = {
  APK_DOWNLOAD_URL: defaultConfig.APK_DOWNLOAD_URL,
  APP_WEB_URL: defaultConfig.APP_WEB_URL,
  SUPPORT_WHATSAPP_URL: defaultConfig.SUPPORT_WHATSAPP_URL,
  INSTAGRAM_URL: defaultConfig.INSTAGRAM_URL,
  SUPPORT_EMAIL: defaultConfig.SUPPORT_EMAIL,
  apkVersion: defaultConfig.apkVersion,
  apkSize: defaultConfig.apkSize,
  apkReleaseDate: defaultConfig.apkReleaseDate,
};

const SiteConfigContext = createContext<{
  config: SiteConfigDynamic;
  loading: boolean;
}>({
  config: defaultDynamic,
  loading: true,
});

export function SiteConfigProvider({ children }: { children: React.ReactNode }) {
  const [config, setConfig] = useState<SiteConfigDynamic>(defaultDynamic);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    async function fetchConfig() {
      try {
        const docRef = doc(db, "app_config", "site_config");
        const snap = await getDoc(docRef);
        if (snap.exists() && snap.data()) {
          const d = snap.data();
          setConfig({
            APK_DOWNLOAD_URL: (d.apkDownloadUrl ?? defaultDynamic.APK_DOWNLOAD_URL).toString(),
            APP_WEB_URL: (d.appWebUrl ?? defaultDynamic.APP_WEB_URL).toString(),
            SUPPORT_WHATSAPP_URL: (d.supportWhatsappUrl ?? defaultDynamic.SUPPORT_WHATSAPP_URL).toString(),
            INSTAGRAM_URL: (d.instagramUrl ?? defaultDynamic.INSTAGRAM_URL).toString(),
            SUPPORT_EMAIL: (d.supportEmail ?? defaultDynamic.SUPPORT_EMAIL).toString(),
            apkVersion: (d.apkVersion ?? defaultDynamic.apkVersion).toString(),
            apkSize: (d.apkSize ?? defaultDynamic.apkSize).toString(),
            apkReleaseDate: (d.apkReleaseDate ?? defaultDynamic.apkReleaseDate).toString(),
          });
        }
      } catch {
        // Mantém default em caso de erro
      } finally {
        setLoading(false);
      }
    }
    fetchConfig();
  }, []);

  return (
    <SiteConfigContext.Provider value={{ config, loading }}>
      {children}
    </SiteConfigContext.Provider>
  );
}

export function useSiteConfig() {
  const ctx = useContext(SiteConfigContext);
  return ctx.config;
}
