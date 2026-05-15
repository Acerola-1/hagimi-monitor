import { createFileRoute } from "@tanstack/react-router";
import MenuBarApp from "@/components/MenuBarApp";

export const Route = createFileRoute("/")({
  component: MenuBarApp,
});
