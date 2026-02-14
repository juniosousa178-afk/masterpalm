"use client";

import { useSiteConfig } from "@/contexts/SiteConfigContext";
import { getMailtoHref } from "@/lib/urlUtils";

export function EmailDisplay() {
  const config = useSiteConfig();
  const href = getMailtoHref(config.SUPPORT_EMAIL);
  return (
    <a href={href} className="text-accent-blue hover:underline">
      {config.SUPPORT_EMAIL}
    </a>
  );
}
