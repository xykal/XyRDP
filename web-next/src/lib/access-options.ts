import {type Context} from './api';

// 1.1.29: tunnel Tailscale only (arahan pemilik). Opsi portmap/railway dihapus
// dari workflow, dashboard, dan API. Nama fungsi dipertahankan agar call-site
// lama tetap kompatibel; keduanya kini no-op / selalu terkunci.
export function portmapEndpointReady(_inputs:Partial<Record<string,string>>):boolean {
  return false;
}

export async function requirePortmapConfiguration(_c:Context,_inputs:Partial<Record<string,string>>){}
