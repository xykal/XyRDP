// 1.1.29: tunnel Tailscale only — portmap selalu terkunci.
export function portmapEndpointReady(_inputs:Partial<Record<string,string>>){return false;}
