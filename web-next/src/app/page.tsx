import {getServerSession} from "next-auth";
import {authOptions} from "@/lib/auth";
import {redirect} from "next/navigation";
export default async function Home(){redirect(await getServerSession(authOptions)?"/dashboard":"/login")}
