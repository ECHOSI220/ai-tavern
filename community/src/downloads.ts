const escape=(value:unknown)=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]!));
const languageBlocks=(value:unknown)=>String(value??'').split(' / ').map((text,i)=>`<section lang="${i===0?'zh-CN':'en'}"><h3>${i===0?'中文说明':'English'}</h3><p>${escape(text)}</p></section>`).join('');
export async function downloadsPage(target:Element){
 const response=await fetch('/releases.json',{cache:'no-store',signal:AbortSignal.timeout(10000)});
 if(!response.ok)throw Error('版本信息暂时不可用');
 const release=await response.json();
 const sourceUrl=typeof release.sourceUrl==='string'&&/^https:\/\//.test(release.sourceUrl)?release.sourceUrl:'https://github.com/ECHOSI220/ai-tavern/tree/main/community';
 target.innerHTML=`<section class="page-heading"><small>TAKE YOUR STORIES WITH YOU</small><h1>下载 AI 酒馆</h1><p>Windows 电脑与安卓手机，在你熟悉的设备继续冒险。 / Continue your adventure on Windows or Android.</p><p>当前版本 ${escape(release.version)} · ${escape(release.publishedAt)}</p></section><div class="menu-grid">${release.downloads.map((item:{platform:string;architecture:string;format:string;url:string|null;size?:number;instructions:string;sha256?:string})=>{
   const link=item.url&&/^https:\/\//.test(item.url)?`<a class="button primary" href="${escape(item.url)}" download rel="noopener">下载 ${escape(item.platform)} 版 ↓</a>`:'<button disabled>下载文件尚未上架</button><p class="muted">正在配置安装包存储，暂时不能从网页直接下载。</p>';
   return `<article class="panel"><h2>${escape(item.platform)}</h2><p>${escape(item.architecture)} · ${escape(item.format)}${item.size?` · ${(item.size/1048576).toFixed(1)} MB`:''}</p>${link}${languageBlocks(item.instructions)}${item.sha256?`<details><summary>SHA-256 校验值</summary><p class="checksum">${escape(item.sha256)}</p></details>`:''}</article>`;
 }).join('')}</div><section class="panel"><h2>更新说明</h2>${languageBlocks(release.notes)}${languageBlocks('不会要求你上传 AI API 密钥。已有本地存档建议先备份，再覆盖安装。 / Your AI API key is never requested here. Back up local saves before upgrading.')}<p><a class="button" href="${escape(sourceUrl)}" target="_blank" rel="noopener">查看网页开源代码 ↗</a></p></section>`;
}
