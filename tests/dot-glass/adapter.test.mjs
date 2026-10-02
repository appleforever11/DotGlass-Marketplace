import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {dumpDOM} from './headless-html.mjs';
const browser='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const swift=await fs.readFile(new URL('../../Widgets/DotGlass/DotPageAdapter.swift',import.meta.url),'utf8');
const production=swift.split('#"""')[1].split('"""#')[0];
test('adapter ignores non-ChatGPT origins',async()=>{
 const vm=await import('node:vm');
 const ctx={location:{origin:'https://untrusted.example'},window:{}};
 vm.runInNewContext(production,ctx);
 assert.equal(ctx.window.__dotGlass,undefined);
});
test('rendered messages, guarded sends, duplicate suppression and acknowledgement',async()=>{
 const dir=await fs.mkdtemp(path.join(os.tmpdir(),'dot-glass-test-'));
 try {
  // Only this local fixture supplies its own origin/room. Production guards remain in source.
  const code=production.replace("location.origin !== 'https://chatgpt.com'",'false')
   .replace(/const room = \(\) => .*?;/,"const room = () => 'https://chatgpt.com/dots/test-room';");
  const html=`<!doctype html><html><body><main class="messaging-root"><div class="message-row" data-message-id="a"><div class="message-text">Hello from the fixture.</div></div><div class="composer-wrap"><div contenteditable="true" role="textbox"></div><button aria-label="Send" disabled>Send</button></div></main><pre id="report"></pre><script>
  window.received=[];window.webkit={messageHandlers:{dotGlass:{postMessage:s=>received.push(s)}}};
  const input=document.querySelector('[contenteditable]'),button=document.querySelector('button');let sends=0;
  input.addEventListener('input',()=>button.disabled=!input.innerText.trim());
  button.addEventListener('click',()=>{sends++;let row=document.createElement('div');row.className='message-row self';row.dataset.messageId='sent-'+sends;let text=document.createElement('div');text.className='message-text';text.textContent=input.innerText;row.append(text);document.querySelector('main').prepend(row);input.textContent='';button.disabled=true;});
  ${code}
  (async()=>{const check=(v,m)=>{if(!v)throw Error(m)};
   check(__dotGlass.startCall('https://chatgpt.com/dots/other')==='not-ready','call room guard');
   check(__dotGlass.startCall('https://chatgpt.com/dots/test-room')==='call-unavailable','missing call control');
   const call=document.createElement('button');call.setAttribute('aria-label','Start call');document.body.append(call);let calls=0;call.onclick=()=>calls++;
   check(__dotGlass.startCall('https://chatgpt.com/dots/test-room')==='started','start real control');
   check(__dotGlass.startCall('https://chatgpt.com/dots/test-room')==='pending' && calls===1,'prevent duplicate call');
   check(__dotGlass.openSignIn()===false,'no invented sign-in control');
   const login=document.createElement('button');login.textContent='Log in';document.body.append(login);let logins=0;login.onclick=()=>logins++;
   check(__dotGlass.openSignIn()===true,'open visible login');__dotGlass.openSignIn();check(logins===1,'sign-in clicks only once');
   check(received.at(-1).messages[0].text==='Hello from the fixture.','read rendered content');
   check(await __dotGlass.send('Hello','wrong','https://chatgpt.com/dots/other')==='not-ready','room guard');
   input.textContent='existing draft';check(await __dotGlass.send('Hello','t0','https://chatgpt.com/dots/test-room')==='existing-draft','preserve existing draft');input.textContent='';
   check(await __dotGlass.send('   ','empty','https://chatgpt.com/dots/test-room')==='invalid','empty guard');
   check(await __dotGlass.send('Hello <script>literal</scr'+'ipt>','t1','https://chatgpt.com/dots/test-room')==='submitted','submit');
   check(await __dotGlass.send('Second','t2','https://chatgpt.com/dots/test-room')==='pending','duplicate guard');
   __dotGlass.refresh();check(received.at(-1).acknowledgement==='t1','acknowledgement');check(sends===1,'exactly one click');
   check(received.at(-1).messages.find(m=>m.id==='sent-1').isMine,'mine role');
   document.getElementById('report').textContent=JSON.stringify({pass:true});
  })().catch(e=>document.getElementById('report').textContent=JSON.stringify({error:e.message}));
  </script></body></html>`;
  const file=path.join(dir,'fixture.html');await fs.writeFile(file,html);
  const output=await dumpDOM(browser,['--headless','--disable-gpu','--no-first-run','--no-default-browser-check',`--user-data-dir=${dir}/profile`,'--virtual-time-budget=4000','--dump-dom',pathToFileURL(file).href]);
  const report=output.match(/<pre id="report">([^<]+)<\/pre>/)?.[1];assert.ok(report,'fixture produced a result');assert.deepEqual(JSON.parse(report),{pass:true});
 }finally{await fs.rm(dir,{recursive:true,force:true});}
});

test('voice meter observes only inbound audio and stops after disconnect', async()=>{
 const vm=await import('node:vm');
 const source=(await fs.readFile(new URL('../../Widgets/DotGlass/DotVoiceAdapter.swift',import.meta.url),'utf8')).split('#"""')[1].split('"""#')[0];
 const received=[], timers=[];
 class Peer {
  connectionState='connected';
  microphone=true;
  muted=false;
  getSenders(){return this.microphone ? [{track:{kind:'audio',readyState:'live',enabled:!this.muted}}] : []}
  getReceivers(){return [{track:{kind:'audio',readyState:'live'}}]}
  addEventListener(){}
  async getStats(){return new Map([
   ['out',{id:'out',type:'outbound-rtp',kind:'audio',audioLevel:1}],
   ['in',{id:'in',type:'inbound-rtp',kind:'audio',audioLevel:0.04}]
  ])}
 }
 const window={RTCPeerConnection:Peer,webkit:{messageHandlers:{dotGlass:{postMessage:v=>received.push(v)}}},addEventListener(){}};
 vm.runInNewContext(source,{window,location:{origin:'https://chatgpt.com'},setInterval:f=>{timers.push(f);return 1},clearInterval(){},Map,Set,Math,JSON,Number});
 const peer=new window.RTCPeerConnection();await window.__dotGlassVoice.sample();
 assert.equal(received.at(-1).connected,true);assert.equal(received.at(-1).level,0.2);
 assert.equal(received.at(-1).meterAvailable,true);
 peer.muted=true;await window.__dotGlassVoice.sample();assert.equal(received.at(-1).connected,true,'muting does not end the call');
 peer.microphone=false;await window.__dotGlassVoice.sample();assert.equal(received.at(-1).connected,false);
 peer.microphone=true;peer.connectionState='closed';await window.__dotGlassVoice.sample();assert.equal(received.at(-1).connected,false);assert.equal(received.at(-1).level,0);
});
