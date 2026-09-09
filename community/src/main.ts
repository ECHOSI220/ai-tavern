import {createClient} from '@supabase/supabase-js';
import {types, validatePackage, prepareUpload, checksum} from './package.mjs';
import './style.css';
import {downloadsPage} from './downloads';
import {coverExtension,hydrateCovers,validateCover,mountCoverEditor} from './covers';

const root=document.querySelector<HTMLDivElement>('#app')!;
const url=import.meta.env.VITE_SUPABASE_URL, key=import.meta.env.VITE_SUPABASE_ANON_KEY;
if(!url || !key) { root.textContent='网站尚未配置云端地址，请联系管理员。'; throw Error('Missing public configuration'); }
const db=createClient(url,key);
const escape=(v:unknown)=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]!));
const e=escape;
let userId:string|undefined, renderId=0, dispose:()=>void=()=>{};
const labels=types as Record<string,string>;
const date=(s:string)=>new Date(s).toLocaleDateString('zh-CN');
const icon=(s:string)=>`<span class="symbol" aria-hidden="true">${s}</span>`;
function notify(message:string){ const n=document.querySelector('#notice')!; n.textContent=message; }
function content(html:string){document.querySelector('#content')!.innerHTML=html;}
function fail(error:unknown){notify(error instanceof Error?error.message:'请求失败，请稍后重试。');}
function shell(){
  root.innerHTML=`<header><a class="brand" href="/">${icon('✦')}<span>TAVERN<span class="brand-sub">CLOUD</span></span></a><nav aria-label="主导航"><a href="/discover">发现</a><a href="/join">联机邀请</a><a href="/me/uploads">创作中心</a><a href="/downloads">下载</a></nav><a class="account" href="${userId?'/me':'/login'}">${userId?'我的空间':'登录 / 注册'} ${icon('↗')}</a></header><div id="offline" ${navigator.onLine?'hidden':''}>当前网络已断开，恢复连接后可重试。</div><main id="content" aria-live="polite"><div class="skeleton"></div><div class="skeleton"></div></main><div id="notice" role="status" aria-live="polite"></div><footer><a href="/">Tavern Cloud</a><span>每一个故事，都值得被发现。</span><small>AI 酒馆 · 共用账号，独立创作</small></footer><nav class="mobile-nav" aria-label="手机导航"><a href="/discover">发现</a><a href="/join">联机</a><a href="/me/uploads">创作</a><a href="/downloads">下载</a><a href="/me">我的</a></nav>`;
}
type Item={id:string;title:string;description:string;content_type:string;visibility:string;current_version:number;created_at:string;tags:string[];author_user_id:string;cover_url?:string};
function card(item:Item){return `<a class="card" href="/share/${e(item.id)}"><div class="cover type-${e(item.content_type)}">${item.cover_url?`<img data-cover-path="${e(item.cover_url)}" alt="" loading="lazy" hidden>`:'' }<span class="cover-orbit"></span><span class="cover-mark">${e(({CHARACTER_CARD:'♙',WORLD_BOOK:'◎',CAMPAIGN_TEMPLATE:'◇',THEME_PACK:'◐',RULE_PACK:'⚄',PROMPT_PACK:'✧'} as Record<string,string>)[item.content_type]??'✦')}</span><span class="badge">${e(labels[item.content_type])}</span></div><div class="card-body"><small>V${item.current_version} · ${date(item.created_at)}</small><h3>${e(item.title)}</h3><p>${e(item.description||'这个故事，等你开启。')}</p><div class="tags">${(item.tags??[]).slice(0,3).map(t=>`<span>${e(t)}</span>`).join('')}</div></div></a>`;}
async function discover(id:number, mode='discover'){
 const search=new URLSearchParams(location.search), type=search.get('type')??'', q=search.get('q')??'';
 content(`${mode==='discover'?`<section class="hero"><div class="eyebrow">THE NEXT STORY IS YOURS</div><h1>故事，在此<span>相遇。</span></h1><p>一个角色，一段未知的旅途。<br>发现创作者的世界，把灵感带回你的酒馆。</p><a class="button primary" href="/me/uploads">分享我的创作 ${icon('↗')}</a><div class="hero-art" aria-hidden="true"><span>✧</span><i></i><b>STORIES<br>WITHOUT LIMITS</b></div></section>`:`<section class="page-heading"><small>YOUR LIBRARY</small><h1>${mode==='uploads'?'我的创作':'我的收藏'}</h1><p>创作属于你，是否公开由你决定。</p>${mode==='uploads'?'<a class="button primary" href="/me/uploads?new=1">＋ 上传分享包</a>':''}</section>`}<section class="section-title"><h2>${mode==='discover'?'探索灵感':'内容库'}</h2><span id="count">正在读取云端…</span></section><form id="search" class="search"><input name="q" aria-label="搜索标题" placeholder="搜索角色、世界与故事…" value="${e(q)}" maxlength="80"><button>搜索</button></form><div class="filters"><a class="${!type?'selected':''}" href="${location.pathname}">全部</a>${Object.entries(labels).map(([v,l])=>`<a class="${type===v?'selected':''}" href="${location.pathname}?type=${v}">${l}</a>`).join('')}</div><section id="grid" class="grid"><div class="skeleton"></div><div class="skeleton"></div></section>`);
 document.querySelector('#search')!.addEventListener('submit',event=>{event.preventDefault(); const data=new FormData(event.target as HTMLFormElement);go(`${location.pathname}?q=${encodeURIComponent(String(data.get('q')??''))}&type=${encodeURIComponent(type)}`);});
 let query=db.from('shared_contents').select('*').order('created_at',{ascending:false}).limit(60);
 if(mode==='discover') query=query.eq('visibility','PUBLIC').eq('status','PUBLISHED');
 if(mode==='uploads') query=query.eq('author_user_id',userId!);
 if(mode==='favorites'){
  const {data,error}=await db.from('favorites').select('content_id').eq('user_id',userId!);if(error)throw error;
  query=query.in('id',data.map(x=>x.content_id));
 }
 if(type&&labels[type])query=query.eq('content_type',type);
 if(q)query=query.ilike('title',`%${q.replace(/[%_\\]/g,'')}%`);
 const {data,error}=await query; if(id!==renderId)return; if(error)throw error;
 document.querySelector('#count')!.textContent=`${data.length} 个内容 · 最近发布`;
 document.querySelector('#grid')!.innerHTML=data.length?data.map(card).join(''):'<div class="empty"><span>✦</span><h3>这里还没有内容</h3><p>没有预填充的演示数据。发布你的第一个作品，或换个关键词试试。</p></div>';await hydrateCovers(db,document.querySelector('#grid')!);if(id!==renderId)return;
}
async function authPage(register:boolean){
 content(`<section class="auth panel"><small>WELCOME TO TAVERN CLOUD</small><h1>${register?'开启你的故事':'欢迎回来。'}</h1><p>使用 AI 酒馆的同一个邮箱账号。<br>你的 API 密钥和本地聊天不会上传。</p><form id="auth"><label>邮箱<input name="email" type="email" autocomplete="email" required placeholder="you@example.com"></label><label>密码<input name="password" type="password" autocomplete="${register?'new-password':'current-password'}" minlength="8" required></label><button class="primary">${register?'注册账号':'登录'}</button></form><a href="/${register?'login':'register'}">${register?'已有账号？登录':'没有账号？注册'}</a></section>`);
 document.querySelector('#auth')!.addEventListener('submit',async event=>{event.preventDefault();const form=event.target as HTMLFormElement,button=form.querySelector('button')!;button.disabled=true;const data=new FormData(form);try{const credentials={email:String(data.get('email')),password:String(data.get('password'))};const result=register?await db.auth.signUp(credentials):await db.auth.signInWithPassword(credentials);if(result.error)throw result.error;if(result.data.session){userId=result.data.session.user.id;go('/me');}else notify('注册成功，请打开邮箱中的验证邮件，再回来登录。');}catch(error){fail(error);}finally{button.disabled=false;}});
}
async function me(){content(`<section class="page-heading"><small>YOUR CORNER OF THE CLOUD</small><h1>我的空间</h1><p>账号与酒馆共用，创作自由流动。</p></section><div class="menu-grid"><a class="panel" href="/me/uploads"><h2>我的创作 ↗</h2><p>上传、查看与管理作品</p></a><a class="panel" href="/me/favorites"><h2>我的收藏 ↗</h2><p>保存触动你的世界</p></a></div><button id="logout">退出登录</button>`);document.querySelector('#logout')!.addEventListener('click',async()=>{const {error}=await db.auth.signOut();if(error){fail(error);return;}userId=undefined;go('/');});}
async function share(id:number,contentId:string){
 const {data,error}=await db.rpc('cloud_share_by_id',{share_id:contentId});if(id!==renderId)return;if(error)throw error;if(!data)throw Error('内容不存在、未发布或你没有访问权限。');
 const item=data.content as Item,versions=data.versions as {version:number;file_path:string;checksum:string;changelog:string}[];
 content(`<a class="back" href="/discover">← 返回发现</a><section class="detail panel">${item.cover_url?`<img class="detail-cover" data-cover-path="${e(item.cover_url)}" alt="${e(item.title)} 的封面" hidden>`:'' }<small>${e(labels[item.content_type])} · V${item.current_version} · ${e(item.visibility)}</small><h1>${e(item.title)}</h1><p class="description">${e(item.description)}</p><div class="tags">${(item.tags??[]).map(t=>`<span>${e(t)}</span>`).join('')}</div><div class="actions"><button id="download" class="primary" ${versions.length?'':'disabled'}>下载分享包 ↓</button><button id="copy">复制分享链接</button><button id="favorite">收藏</button><button id="like">点赞</button></div><p class="muted">下载前请确认作者与内容可信。App 内一键导入正在接入，目前可以先保存 JSON 分享包。</p>${userId===item.author_user_id?'<button id="delete" class="danger">删除此分享</button>':''}</section><section class="panel"><h2>版本记录</h2>${versions.map(v=>`<p>V${v.version} · ${e(v.changelog||'首次发布')}</p>`).join('')||'<p>尚无可下载版本</p>'}</section><section class="panel"><h2>讨论</h2><div id="comments"></div>${userId?'<form id="comment"><label>分享你的想法<textarea name="body" required maxlength="1000"></textarea></label><button>发送评论</button></form>':'<a href="/login">登录后参与讨论</a>'}</section>`);
 if(userId===item.author_user_id){
  const editor=document.createElement('section');editor.className='panel';
  document.querySelector('.detail')!.after(editor);
  dispose=mountCoverEditor(db,editor,contentId,userId,()=>{void route();});
 }
 await hydrateCovers(db,document.querySelector('.detail')!);if(id!==renderId)return;
 document.querySelector('#copy')!.addEventListener('click',()=>navigator.clipboard.writeText(location.href).then(()=>notify('链接已复制。')).catch(fail));
 document.querySelector('#download')!.addEventListener('click',async()=>{try{const v=versions.find(v=>v.version===item.current_version);if(!v)throw Error('当前版本不可下载');const session=(await db.auth.getSession()).data.session;const signedResponse=await fetch(String(import.meta.env.VITE_GAME_SERVER_URL).replace(/\/$/,'')+'/v1/public/shares/'+item.id+'/download',{headers:session?{Authorization:`Bearer ${session.access_token}`}:{},signal:AbortSignal.timeout(15000)});const signed=await signedResponse.json();if(!signedResponse.ok)throw Error(signed.error?.message??'下载服务暂时不可达');const response=await fetch(signed.url,{signal:AbortSignal.timeout(15000)});if(!response.ok)throw Error('文件下载失败');const file=await response.blob();if(file.size>2000000)throw Error('分享包超过大小限制');const text=await file.text();if(await checksum(text)!==v.checksum)throw Error('校验失败，文件未保存。');validatePackage(JSON.parse(text));const blob=URL.createObjectURL(file);const a=document.createElement('a');a.href=blob;a.download=`${item.id}-v${v.version}.tavern.json`;a.click();setTimeout(()=>URL.revokeObjectURL(blob),1000);}catch(error){fail(error);}});
 for(const [button,table] of [['favorite','favorites'],['like','likes']]){
  document.querySelector('#'+button)!.addEventListener('click',async()=>{if(!userId){go('/login');return;}const result=await db.from(table).upsert({user_id:userId,content_id:contentId},{onConflict:'user_id,content_id',ignoreDuplicates:true});if(result.error)fail(result.error);else notify(button==='favorite'?'已收藏，可在我的空间查看。':'已点赞。');});
 }
 document.querySelector('#delete')?.addEventListener('click',async()=>{if(!confirm('删除此云端分享？本地文件不受影响。'))return;const result=await db.from('shared_contents').delete().eq('id',contentId).eq('author_user_id',userId!);if(result.error)fail(result.error);else go('/me/uploads');});
 const comments=data.comments as {body:string;created_at:string}[];document.querySelector('#comments')!.innerHTML=comments.map(c=>`<article class="comment"><small>${date(c.created_at)}</small><p>${e(c.body)}</p></article>`).join('')||'<p class="muted">还没有评论，来聊聊你的灵感。</p>';
 document.querySelector('#comment')?.addEventListener('submit',async event=>{event.preventDefault();const form=event.target as HTMLFormElement,button=form.querySelector('button')!;button.disabled=true;const result=await db.from('comments').insert({content_id:contentId,user_id:userId,body:String(new FormData(form).get('body')).trim()});if(result.error){fail(result.error);button.disabled=false;}else route();});
}
async function upload(){
 content(`<section class="page-heading"><small>CREATOR STUDIO</small><h1>发布一份灵感。</h1><p>只上传你主动选择的分享包，不读取本地聊天和账号配置。</p></section><form id="upload" class="panel form"><label>作品名称<input name="title" required maxlength="120"></label><label>简介<textarea name="description" maxlength="2000" required></textarea></label><label>标签（逗号分隔）<input name="tags" maxlength="120" placeholder="奇幻, 探索, 原创"></label><label>可见性<select name="visibility"><option value="PRIVATE">仅自己</option><option value="UNLISTED">仅链接可见</option><option value="PUBLIC">公开到发现页</option></select></label><label>普通 JSON 的内容类型<select name="contentType"><option value="">请选择类型（专用分享包可不选）</option>${Object.entries(labels).map(([v,l])=>`<option value="${v}">${l}</option>`).join('')}</select></label><label>创作文件（JSON，最大 2 MB）<input name="file" type="file" accept=".json,application/json" required></label><label>封面图（可选，PNG/JPG/WebP，最大 5 MB）<input name="cover" type="file" accept="image/png,image/jpeg,image/webp"><img id="cover-preview" class="upload-cover-preview" alt="封面预览" hidden></label><p class="muted">支持普通世界书、角色卡等 JSON，也支持 Tavern 分享包。普通 JSON 将按所选类型自动转换，原文件不修改；剧情字段 secret / secrets 会正常保留。仍会拦截账号密钥、Token、密码、私聊记录、ZIP 和程序。</p><label class="check"><input type="checkbox" required>我有权分享此内容，并已检查其中不含账号密钥、真实隐私和他人聊天记录。</label><button class="primary">检查并确认发布</button><details id="upload-preview" hidden><summary>查看实际上传内容</summary><pre class="upload-json"></pre></details><p id="upload-error" role="alert"></p></form>`);
 const form=document.querySelector<HTMLFormElement>('#upload')!;
 const coverInput=form.elements.namedItem('cover') as HTMLInputElement;
 const coverPreview=form.querySelector<HTMLImageElement>('#cover-preview')!;
 let coverPreviewUrl:string|undefined,coverSelection=0;
 const clearCoverPreview=()=>{if(coverPreviewUrl)URL.revokeObjectURL(coverPreviewUrl);coverPreviewUrl=undefined;coverPreview.hidden=true;coverPreview.removeAttribute('src');};
 dispose=()=>{coverSelection++;clearCoverPreview();};
 coverInput.addEventListener('change',async()=>{
  const selection=++coverSelection;clearCoverPreview();const cover=coverInput.files?.[0];if(!cover)return;
  try{await validateCover(cover);if(selection!==coverSelection)return;coverPreviewUrl=URL.createObjectURL(cover);coverPreview.src=coverPreviewUrl;coverPreview.hidden=false;form.querySelector('#upload-error')!.textContent='';}
  catch(error){if(selection!==coverSelection)return;coverInput.value='';form.querySelector('#upload-error')!.textContent=error instanceof Error?error.message:'无法读取封面';fail(error);}
 });
 form.addEventListener('submit',async event=>{
  event.preventDefault();const button=form.querySelector<HTMLButtonElement>('button.primary')!;button.disabled=true;let objectPath:string|undefined,previewPath:string|undefined;
  try{
   const fields=new FormData(form),file=fields.get('file') as File,cover=fields.get('cover') as File;
   if(file.size>2_000_000)throw Error('文件超过 2 MB');
   const coverType=cover instanceof File&&cover.size?await validateCover(cover):undefined;
   const prepared=prepareUpload(JSON.parse((await file.text()).replace(/^\uFEFF/,'')),String(fields.get('contentType')??''));const pack=prepared.pack;
   const preview=form.querySelector<HTMLDetailsElement>('#upload-preview')!;preview.hidden=false;preview.querySelector('pre')!.textContent=JSON.stringify(pack,null,2);form.querySelector('#upload-error')!.textContent='';
   if(!confirm(`即将发布「${fields.get('title')}」\n${prepared.converted?'普通 JSON 已自动转换为分享包；原文件不修改。\\n':''}类型：${labels[pack.contentType]}\n封面：${coverType?cover.name:'未添加'}\n可见性：${fields.get('visibility')}\n确认继续？`))return;
   const shareId=crypto.randomUUID();objectPath=`${userId}/${shareId}/1.json`;const text=JSON.stringify(pack);
   const uploaded=await db.storage.from('shared-content').upload(objectPath,new Blob([text],{type:'application/json'}),{upsert:false});if(uploaded.error)throw uploaded.error;
   if(coverType){const extension=coverExtension(cover);previewPath=`${userId}/${shareId}/cover.${extension}`;const imageUpload=await db.storage.from('shared-previews').upload(previewPath,cover,{upsert:false,contentType:cover.type,cacheControl:'3600'});if(imageUpload.error)throw imageUpload.error;}
   const rpcName=previewPath?'cloud_publish_share_with_preview':'cloud_publish_share';
   const rpcArgs={share_id:shareId,share_title:String(fields.get('title')).trim(),share_description:String(fields.get('description')).trim(),share_type:pack.contentType,share_visibility:String(fields.get('visibility')),share_tags:String(fields.get('tags')).split(/[,，]/).map(t=>t.trim()).filter(Boolean).slice(0,8),object_path:objectPath,object_size:new TextEncoder().encode(text).length,object_checksum:await checksum(text),...(previewPath?{preview_path:previewPath}:{})};
   const result=await db.rpc(rpcName,rpcArgs);if(result.error)throw result.error;
   objectPath=undefined;previewPath=undefined;clearCoverPreview();go('/share/'+shareId);
  }catch(error){
   if(previewPath)await db.storage.from('shared-previews').remove([previewPath]);if(objectPath)await db.storage.from('shared-content').remove([objectPath]);
   form.querySelector('#upload-error')!.textContent=error instanceof Error?error.message:'上传失败，请稍后重试';fail(error);
  }finally{button.disabled=false;}
 });
}
function join(code:string){
 content(`<section class="auth panel"><small>AN ADVENTURE AWAITS</small><h1>与朋友，一起入席。</h1><p>输入好友的房间码，在酒馆 App 中加入旅程。</p><form id="join"><label>房间码<input name="code" required minlength="6" maxlength="6" pattern="[A-Za-z2-9]{6}" value="${e(code)}" placeholder="ABC234" autocomplete="off"></label><button class="primary">查看邀请</button></form>${code?`<div id="room-status" class="muted">正在读取公开房间状态…</div><div id="room-players"></div><p>请在 App 的多人跑团中输入此房间码。网页不会读取私聊或行动内容。</p><button id="copy-code">复制房间码</button>`:''}</section>`);
 document.querySelector('#join')!.addEventListener('submit',event=>{event.preventDefault();const code=String(new FormData(event.target as HTMLFormElement).get('code')).trim().toUpperCase();go('/join/'+encodeURIComponent(code));});
 document.querySelector('#copy-code')?.addEventListener('click',()=>navigator.clipboard.writeText(code).then(()=>notify('房间码已复制。')).catch(fail));
 if(code && /^[A-HJ-NP-Z2-9]{6}$/.test(code)){
  let stopped=false,socket:WebSocket|undefined,retry:ReturnType<typeof setTimeout>|undefined,ping:ReturnType<typeof setInterval>|undefined,attempt=0;
  const status=document.querySelector('#room-status')!,players=document.querySelector('#room-players')!;
  const endpoint=String(import.meta.env.VITE_GAME_SERVER_URL??'').replace(/\/$/,'')+'/v1/public/rooms/'+code;
  function draw(room:{roomName:string;status:string;currentPlayers:number;maxPlayers:number;aiProviderConnected:boolean;players:{displayName:string;ready:boolean;connected:boolean;isOwner:boolean}[]}){
   status.textContent=`${room.roomName} · ${room.currentPlayers}/${room.maxPlayers} 人 · ${({lobby:'等待准备',playing:'游戏中',paused:'已暂停',closed:'已关闭',finished:'已结束'} as Record<string,string>)[room.status]??room.status} · AI ${room.aiProviderConnected?'在线':'未连接'}`;
   players.innerHTML=room.players.map(p=>`<article class="comment"><strong>${e(p.displayName)}${p.isOwner?' · 房主':''}</strong><small> · ${p.connected?'在线':'离线'} · ${p.ready?'已准备':'未准备'}</small></article>`).join('');
  }
  async function connect(){
   try{
    const response=await fetch(endpoint,{signal:AbortSignal.timeout(10000)});const result=await response.json();if(stopped)return;
    if(!response.ok)throw Error(result.error?.message??'房间暂时不可达');draw(result);
    const wsUrl=new URL(endpoint+'/socket');wsUrl.protocol=wsUrl.protocol==='https:'?'wss:':'ws:';socket=new WebSocket(wsUrl);
    socket.onopen=()=>{attempt=0;ping=setInterval(()=>{if(socket?.readyState===WebSocket.OPEN)socket.send('__ping__');},25000);};
    socket.onmessage=event=>{if(stopped||event.data==='__pong__')return;try{const data=JSON.parse(event.data);if(data.type==='publicRoomState')draw(data.room);}catch{status.textContent='房间返回了无法识别的数据。';}};
    socket.onclose=()=>{if(ping)clearInterval(ping);if(!stopped){status.textContent='实时连接已断开，正在重连…';schedule();}};
   }catch(error){if(!stopped){status.textContent=error instanceof Error?error.message:'连接失败';schedule();}}
  }
  function schedule(){if(attempt>=5){status.textContent+='；请点击“查看邀请”重试。';return;}retry=setTimeout(connect,Math.min(30000,2000*2**attempt++));}
  dispose=()=>{stopped=true;if(retry)clearTimeout(retry);if(ping)clearInterval(ping);socket?.close();};
  void connect();
 }
}
function go(path:string){history.pushState(null,'',path);route();window.scrollTo(0,0);}
async function route(){const id=++renderId;dispose();dispose=()=>{};shell();try{const path=location.pathname;if(path.startsWith('/me')&&!userId){await authPage(false);return;}if(path==='/login'||path==='/register')await authPage(path==='/register');else if(path==='/downloads')await downloadsPage(document.querySelector('#content')!);else if(path==='/me')await me();else if(path==='/me/uploads'&&new URLSearchParams(location.search).has('new'))await upload();else if(path.startsWith('/share/'))await share(id,path.split('/')[2]);else if(path.startsWith('/join'))join(path.split('/')[2]??'');else if(['/','/discover','/me/uploads','/me/favorites'].includes(path))await discover(id,path==='/me/uploads'?'uploads':path==='/me/favorites'?'favorites':'discover');else content('<section class="empty"><h1>页面不存在</h1><a href="/">返回首页</a></section>');}catch(error){if(id!==renderId)return;content('<section class="empty"><h2>暂时无法读取云端</h2><p>请检查网络，或稍后重试。你的本地内容不受影响。</p><button id="retry">重试</button></section>');document.querySelector('#retry')!.addEventListener('click',route);fail(error);}}
document.addEventListener('click',event=>{const a=(event.target as Element).closest('a');if(!a||a.origin!==location.origin||a.hasAttribute('download')||(event as MouseEvent).ctrlKey||(event as MouseEvent).metaKey)return;event.preventDefault();go(a.pathname+a.search);});
window.addEventListener('popstate',route);
window.addEventListener('online',()=>{document.querySelector('#offline')?.setAttribute('hidden','');});
window.addEventListener('offline',()=>{document.querySelector('#offline')?.removeAttribute('hidden');});
db.auth.onAuthStateChange((_event,session)=>{userId=session?.user.id;});
const session=await db.auth.getSession();userId=session.data.session?.user.id;route();
