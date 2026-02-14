"use client";

import { useSiteConfig } from "@/contexts/SiteConfigContext";

export function EmailDisplay() {
  const config = useSiteConfig();
  return (
    <a href={`mailto:${config.SUPPORT_EMAIL}`} className="text-accent-blue hover:underline">
      {config.SUPPORT_EMAIL}
    </a>
  );
}
