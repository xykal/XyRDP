import {test} from 'node:test';import assert from 'node:assert/strict';
import {sessionState,type SessionFile} from '../src/lib/session-status';
const session:SessionFile={run_id:'123',run_attempt:'1',active:true,expires_at:'2099-01-01',akses:{tailscale:{status:'ok',ip:'100.64.12.34'}}};
const run={id:123,run_attempt:1,status:'in_progress',conclusion:null};
test('only matching live attempt exposes a private connection',()=>{
 assert.equal(sessionState(run,session).phase,'ready');
 assert.equal(sessionState({...run,run_attempt:2},session).connection,null);
 assert.equal(sessionState({...run,id:124},session).connection,null);
 assert.equal(sessionState({...run,status:'queued'},session).phase,'queued');
 assert.equal(sessionState({...run,status:'queued'},session).connection,null);
 assert.equal(sessionState(run,{...session,expires_at:'2000-01-01'}).connection,null);
 assert.equal(sessionState(run,{...session,akses:{tailscale:{status:'ok',ip:'8.8.8.8'}}}).connection,null);
});
test('failed and cancelled runs cannot be presented as ready or merely idle',()=>{
 assert.equal(sessionState({...run,status:'completed',conclusion:'failure'},session).phase,'failed');
 assert.equal(sessionState({...run,status:'completed',conclusion:'cancelled'},session).phase,'cancelled');
 assert.equal(sessionState({...run,status:'completed',conclusion:'success'},session).connection,null);
 const state=sessionState(run,session,[{id:1,name:'rdp',status:'in_progress',conclusion:null,steps:[{name:'Setup akses privat Tailscale',number:11,status:'completed',conclusion:'failure'}]}]);
 assert.equal(state.phase,'failed');assert.equal(state.progress.failed_step,'Setup akses privat Tailscale');assert.equal(state.connection,null);assert.equal(state.active,true);
});

test('Tailscale only: legacy portmap status is ignored',()=>{const legacy={...session,akses:{mode:'portmap',portmap:{status:'ok',host:'owner.portmap.host',port:41858},tailscale:{status:'ok',ip:'100.64.12.34'}}} as unknown as SessionFile;const st=sessionState(run,legacy);assert.equal(st.connection?.host,'100.64.12.34');assert.equal(st.connection?.port,3389);assert.equal(st.connection?.transport,'tailscale');const noTs={...session,akses:{mode:'portmap',portmap:{status:'ok',host:'owner.portmap.host',port:41858}}} as unknown as SessionFile;assert.equal(sessionState(run,noTs).connection,null);assert.equal(sessionState({...run,status:'completed'},legacy).connection,null);});
