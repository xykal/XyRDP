import type {Metadata} from "next";
import "./globals.css";
import {headers,cookies} from "next/headers";
import LocaleProvider,{LanguageSwitcher} from "./locale-provider";
import {preferredLocale} from "@/lib/i18n/locale";

const structuredData={
  "@context":"https://schema.org",
  "@graph":[
    {
      "@type":"Person",
      "@id":"https://rdpfree.projectkal.my.id/#founder",
      "name":"Haekal Saputra",
      "alternateName":["xykal","KallAncrit"],
      "jobTitle":"Founder & Lead Developer",
      "nationality":"Indonesian",
      "sameAs":["https://github.com/xykal"]
    },
    {
      "@type":"Organization",
      "@id":"https://rdpfree.projectkal.my.id/#organization",
      "name":"XyVerse Technology Global",
      "alternateName":"XyVerse",
      "url":"https://rdpfree.projectkal.my.id",
      "foundingDate":"2026",
      "location":{"@type":"Place","name":"Indonesia"},
      "founder":{"@id":"https://rdpfree.projectkal.my.id/#founder"},
      "sameAs":["https://github.com/xykal/XyRDP","https://github.com/xykal/XyDesk-Remote","https://www.xydeskremote.biz.id/"]
    },
    {
      "@type":"WebApplication",
      "@id":"https://rdpfree.projectkal.my.id/#webapp",
      "name":"RdpFree (XyRDP)",
      "applicationCategory":"UtilitiesApplication",
      "operatingSystem":"Web, Windows Server 2022/2025, Ubuntu Linux, Android (XyDesk Remote)",
      "url":"https://rdpfree.projectkal.my.id",
      "author":{"@id":"https://rdpfree.projectkal.my.id/#founder"},
      "publisher":{"@id":"https://rdpfree.projectkal.my.id/#organization"},
      "description":"Dashboard Cloud RDP berbasis repository GitHub milik pengguna, terintegrasi dengan XyDesk Remote, modul native C/C++/C#/Rust, Studio 3D (Blender & Roblox Studio), WinRAR, dan XyMac OS Launcher."
    }
  ]
};

export const metadata:Metadata={
  icons:{icon:[{url:"/favicon.svg",type:"image/svg+xml"},{url:"/favicon.ico",sizes:"any"}],apple:"/apple-touch-icon.png"},
  metadataBase:new URL("https://rdpfree.projectkal.my.id"),
  title:{default:"RdpFree (XyRDP) — Cloud Desktop kamu, dari mana saja",template:"%s · RdpFree"},
  description:"Buat repository dari template XyRDP, atur sesi Windows/Linux dengan modul native C/C++/C#/Rust, Studio 3D & XyMac Launcher, lalu hubungkan lewat XyDesk Remote. Dikembangkan oleh Haekal Saputra (xykal) · Tim XyVerse di Indonesia.",
  keywords:["xyrdp","rdpfree","xydesk remote","xydesk","rdp gratis","cloud pc","windows rdp github","remote desktop android","haekal saputra","xykal","xyverse","mac launcher rdp","blender cloud rdp","roblox studio rdp"],
  authors:[{name:"Haekal Saputra (xykal)",url:"https://github.com/xykal"}],
  creator:"Haekal Saputra (xykal) · XyVerse",
  publisher:"XyVerse Technology Global",
  openGraph:{type:"website",locale:"id_ID",siteName:"RdpFree · XyRDP",title:"RdpFree (XyRDP) — Cloud Desktop kamu, dari mana saja",description:"Template XyRDP, modul native C/C++/C#/Rust, XyMac Launcher, dan koneksi XyDesk Remote. Founder: xykal (Haekal Saputra) · XyVerse · Indonesia.",url:"https://rdpfree.projectkal.my.id",images:[{url:"/og-rdpfree.jpg?v=2",width:1200,height:630,alt:"RdpFree XyRDP — Cloud Desktop dengan ekosistem XyVerse"}]},
  twitter:{card:"summary_large_image",title:"RdpFree (XyRDP) — Cloud Desktop kamu, dari mana saja",description:"Dashboard Cloud RDP XyVerse oleh Haekal Saputra (xykal). Terintegrasi penuh dengan XyDesk Remote.",images:["/og-rdpfree.jpg?v=2"]}
};

export default async function Layout({children}:{children:React.ReactNode}){
  const lang=preferredLocale((await cookies()).get("rdpfree_locale")?.value,(await headers()).get("accept-language"));
  return <html lang={lang}><head><script type="application/ld+json" dangerouslySetInnerHTML={{__html:JSON.stringify(structuredData)}}/></head><body><LocaleProvider initialLocale={lang}>{children}<div className="global-language"><LanguageSwitcher/></div></LocaleProvider></body></html>;
}
