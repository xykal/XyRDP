import {getServerSession} from "next-auth";
import {authOptions} from "@/lib/auth";
import {redirect} from "next/navigation";
import Button from "./button";
export default async function Login({searchParams}:{searchParams:Promise<{error?:string}>}){
 if(await getServerSession(authOptions)) redirect("/dashboard");
 const {error}=await searchParams;
 return <main className="login"><span className="eyebrow">RdpFree / Account</span><h1>Selamat datang kembali.</h1><p>Masuk untuk mengelola repository dan melihat aktivitas RDP kamu.</p><section className="card"><h2>Satu akun. Satu dashboard.</h2><p>Gunakan akun GitHub yang terhubung dengan repository kamu.</p>{error&&<p className="error">Login belum berhasil. Coba lagi atau periksa konfigurasi OAuth.</p>}<Button/></section><footer>Credit: KallAncrit</footer></main>
}
