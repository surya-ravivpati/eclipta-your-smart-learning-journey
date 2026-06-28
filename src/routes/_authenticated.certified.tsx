import { createFileRoute, redirect } from "@tanstack/react-router";

// The Certified / Community split was retired in favor of one unified Courses
// hub (see docs/courses-redesign.md). This listing route now redirects there;
// individual certified courses still live at /certified/$slug.
export const Route = createFileRoute("/_authenticated/certified")({
  beforeLoad: () => {
    throw redirect({ to: "/courses" });
  },
});
