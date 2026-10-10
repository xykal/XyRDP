import fs from 'node:fs';
const base='https://rdpfree-next.dikanjut.workers.dev';
const r=await fetch(base+'/api/auth/csrf');const {csrfToken}=await r.json();
const cookie=r.headers.getSetCookie().map(v=>v.split(';')[0]).join('; ');
const s=await fetch(base+'/api/auth/signin/github',{method:'POST',headers:{cookie,'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({csrfToken,callbackUrl:base+'/dashboard',json:'true'}),redirect:'manual'});
const d=await s.json(); const u=new URL(d.url);
console.log(JSON.stringify({test:'OAuth initiation',status:s.status,provider:u.hostname,callback:u.searchParams.get('redirect_uri'),statePresent:!!u.searchParams.get('state'),cookies:s.headers.getSetCookie().map(c=>({name:c.split('=')[0],httpOnly:c.includes('HttpOnly'),secure:c.includes('Secure'),sameSite:c.match(/SameSite=([^;]+)/)?.[1]}))},null,2));
