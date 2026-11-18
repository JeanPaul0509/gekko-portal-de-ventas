import { redirect } from "next/navigation";

// El middleware ya manda a /menu o /login; esto es solo un respaldo.
export default function Home() {
  redirect("/menu");
}
