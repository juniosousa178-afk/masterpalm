import { Hero } from "@/components/Hero";
import { FeaturesGrid } from "@/components/FeaturesGrid";
import { ScreenshotsMock } from "@/components/ScreenshotsMock";
import { CTASection } from "@/components/CTASection";
import { FAQ } from "@/components/FAQ";
import { PlansSection } from "@/components/PlansSection";
import { ContactSection } from "@/components/ContactSection";
import { ChangelogSection } from "@/components/ChangelogSection";
import { DepoimentosSection } from "@/components/DepoimentosSection";

export default function HomePage() {
  return (
    <>
      <Hero />
      <FeaturesGrid />
      <ScreenshotsMock />
      <DepoimentosSection />
      <CTASection />
      <FAQ />
      <PlansSection />
      <ChangelogSection />
      <ContactSection />
    </>
  );
}
