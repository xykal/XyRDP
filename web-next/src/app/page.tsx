import {T} from "@/app/locale-provider";
import FloatingScene from "./floating-scene";
import CommunityStats from "./community-stats";
import GitHubIcon from "./github-icon";
import Link from "next/link";
import Navigation from "./dashboard/navigation";
import CommunitySupport from "./community-support";
import BrandSlider from "./brand-slider";
import TutorialVideo from "./tutorial-video";
import {tutorialVideo} from "@/lib/tutorial";

export default function Home(){
  return (
    <main className="landing">
      <Navigation publicMode/>
      <section className="hero hero-orbital">
        <div className="hero-copy">
          <span className="eyebrow">Your desktop. Your repository.</span>
          <h1><T text={"RDP gratis untuk semua."}/><br/><span><T text={"Coba sekarang."}/></span></h1>
          <p><T text={"Satu dashboard untuk menyiapkan Windows, menjalankan workflow GitHub, dan membuka desktop lewat XyDesk Remote."}/></p>
          <div className="actions">
            <Link href="/login" className="button github-cta"><GitHubIcon/><T text={"Mulai dengan GitHub →"}/></Link>
            <a className="button secondary" href="https://github.com/xykal/XyRDP" target="_blank" rel="noreferrer"><T text={"Lihat template ↗"}/></a>
          </div>
          <CommunityStats/>
          <p className="muted"><T text={"Workflow berjalan di akun GitHub kamu, mengikuti kuota dan kebijakan GitHub Actions."}/></p>
        </div>
        <FloatingScene/>
      </section>

      <BrandSlider/>

      <div id="panduan">
        <TutorialVideo {...tutorialVideo}/>
      </div>

      <section className="landing-steps">
        <article>
          <span>01</span>
          <h2><T text={"Gunakan template"}/></h2>
          <p><T text={"Pilih nama repository kamu sendiri."}/></p>
        </article>
        <article>
          <span>02</span>
          <h2><T text={"Izinkan repo, lalu setup"}/></h2>
          <p><T text={"Pilih repo untuk GitHub App, lalu siapkan jalur akses dan password Windows."}/></p>
        </article>
        <article>
          <span>03</span>
          <h2><T text={"Hubungkan desktop"}/></h2>
          <p><T text={"Jalankan workflow dan gunakan XyDesk Remote."}/></p>
        </article>
      </section>

      <section id="tentang" className="about-xy-section">
        <div className="support-heading">
          <span className="eyebrow"><T text={"Tentang & Arsitektur Native"}/></span>
          <h2><T text={"Dibangun oleh XyVerse di Indonesia."}/></h2>
          <p><T text={"Fokus murni pada koneksi Remote Desktop cepat, runtime 3D lengkap, utilitas kreator, dan integrasi penuh dengan aplikasi XyDesk Remote."}/></p>
        </div>
        <div className="about-xy-grid">
          <article className="about-xy-card">
            <span className="eyebrow"><T text={"Founder & Tim"}/></span>
            <h3>Haekal Saputra (xykal)</h3>
            <p><T text={"Founder & arsitek utama ekosistem XyRDP dan XyDesk Remote bersama tim independen XyVerse Technology Global, dikembangkan di Indonesia sejak 2026."}/></p>
            <div className="stack-pills">
              <span className="stack-pill accent">Founder: xykal</span>
              <span className="stack-pill">Haekal Saputra</span>
              <span className="stack-pill">Tim XyVerse</span>
              <span className="stack-pill">Indonesia</span>
            </div>
          </article>
          <article className="about-xy-card">
            <span className="eyebrow"><T text={"Teknologi & Modul Native"}/></span>
            <h3><T text={"Multi-Bahasa Sistem (TS · Rust · C# · C++ · C)"}/></h3>
            <p><T text={"Bukan sekadar skrip: XyRDP menyertakan probe X.224 RDP & Tailscale dalam Rust, booster 1ms DWM dalam C11, auditor DirectX/Mesa3D dalam C++17, serta XyMac OS Launcher bergaya macOS dalam C#."}/></p>
            <div className="stack-pills">
              <span className="stack-pill accent">Rust · xyrdp-probe</span>
              <span className="stack-pill accent">C# · XyMacLauncher</span>
              <span className="stack-pill">C++17 · Grafis Check</span>
              <span className="stack-pill">C11 · 1ms Booster</span>
              <span className="stack-pill">TypeScript · Next.js</span>
            </div>
          </article>
          <article className="about-xy-card">
            <span className="eyebrow"><T text={"Lingkungan Desktop Siap Pakai"}/></span>
            <h3><T text={"XyMac Dock, Studio 3D & WinRAR"}/></h3>
            <p><T text={"Dilengkapi WinRAR, Chrome, 7-Zip, Lightshot, Blender 3D 4.2 LTS (Mesa3D OpenGL 4.6), Roblox Studio resmi, serta opsi dock & menu bar bergaya macOS."}/></p>
            <div className="stack-pills">
              <span className="stack-pill">XyMac OS Dock</span>
              <span className="stack-pill">Blender 3D 4.2</span>
              <span className="stack-pill">Roblox Studio</span>
              <span className="stack-pill">WinRAR 7.23</span>
              <span className="stack-pill">LLVM / .NET / Rust SDK</span>
            </div>
          </article>
        </div>
      </section>

      <CommunitySupport/>
      <footer>Founder: xykal (Haekal Saputra) · Tim XyVerse · <T text={"Dikembangkan di Indonesia"}/></footer>
    </main>
  );
}
