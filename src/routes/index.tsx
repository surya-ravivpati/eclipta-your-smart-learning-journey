import { createFileRoute } from "@tanstack/react-router";
import { LandingShowcase } from "@/components/landing/LandingShowcase";

export const Route = createFileRoute("/")({
  head: () => ({
    meta: [
      { title: "Eclipta — Study is dead. Fight for it." },
      { name: "description", content: "1v1 knowledge battles, 8 classes, 8 ranked tiers, and collectible Ecliptars. Eclipta turns learning into a competitive arena." },
      { property: "og:title", content: "Eclipta — Study is dead. Fight for it." },
      { property: "og:description", content: "Pick a class. Queue up. Land combos. Climb the ranks. Eclipta is the learning arena — battle-first, AI-tutored, fully gamified." },
    ],
  }),
  component: Index,
});

function Index() {
  return <LandingShowcase />;
}
