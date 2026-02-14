import type { Metadata } from "next";
import { DownloadContent } from "@/components/DownloadContent";

export const metadata: Metadata = {
  title: "Download",
  description: "Baixe o APK do MasterPalm para Android ou acesse o AppWeb no navegador.",
};

export default function DownloadPage() {
  return <DownloadContent />;
}
