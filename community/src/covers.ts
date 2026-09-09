import type {SupabaseClient} from '@supabase/supabase-js';

const allowedCoverTypes:Record<string,string>={
  'image/png':'png',
  'image/jpeg':'jpg',
  'image/webp':'webp',
};

export function coverExtension(file:File):string {
  const extension=allowedCoverTypes[file.type];
  if(!extension)throw Error('封面只支持 PNG、JPG 或 WebP。');
  if(file.size<=0)throw Error('封面文件为空。');
  if(file.size>5_000_000)throw Error('封面不能超过 5 MB。');
  return extension;
}

export async function validateCover(file:File):Promise<string> {
  const extension=coverExtension(file);
  const url=URL.createObjectURL(file);
  try {
    const size=await new Promise<{width:number;height:number}>((resolve,reject)=>{
      const image=new Image();
      image.onload=()=>resolve({width:image.naturalWidth,height:image.naturalHeight});
      image.onerror=()=>reject(Error('无法读取这张图片，请换一张 PNG、JPG 或 WebP。'));
      image.src=url;
    });
    if(size.width<120||size.height<120)throw Error('封面尺寸至少需要 120 × 120。');
    if(size.width>8192||size.height>8192||size.width*size.height>20_000_000)throw Error('封面像素过大，请压缩后再上传。');
    return extension;
  } finally {
    URL.revokeObjectURL(url);
  }
}

export async function hydrateCovers(db:SupabaseClient,scope:ParentNode=document):Promise<void>{
  const images=[...scope.querySelectorAll<HTMLImageElement>('img[data-cover-path]')];
  const paths=[...new Set(images.map(image=>image.dataset.coverPath).filter((path):path is string=>Boolean(path)))];
  if(!paths.length)return;
  const {data,error}=await db.storage.from('shared-previews').createSignedUrls(paths,3600);
  if(error)return;
  const signed=new Map((data??[]).flatMap(item=>item.path&&item.signedUrl?[[item.path,item.signedUrl] as const]:[]));
  for(const image of images){
    const url=signed.get(image.dataset.coverPath??'');
    if(!url)continue;
    image.src=url;
    image.hidden=false;
  }
}

export function mountCoverEditor(db:SupabaseClient,host:HTMLElement,shareId:string,ownerId:string,onSaved:()=>void):()=>void {
  host.innerHTML=`<details><summary>添加／更换封面</summary><form><p class="muted">为已上传的作品添加图片，无需重新上传 JSON。支持 PNG/JPG/WebP，最大 5 MB。</p><label>选择新封面<input name="cover" type="file" accept="image/png,image/jpeg,image/webp" required></label><img class="upload-cover-preview" alt="新封面预览" hidden><div class="actions"><button class="primary" disabled>保存封面</button></div><p role="status" aria-live="polite"></p></form></details>`;
  const form=host.querySelector('form')!,input=host.querySelector('input')!,preview=host.querySelector('img')!,button=host.querySelector('button')!,status=host.querySelector('[role=status]')!;
  let active=true,selection=0,previewUrl:string|undefined;
  const clear=()=>{if(previewUrl)URL.revokeObjectURL(previewUrl);previewUrl=undefined;preview.hidden=true;preview.removeAttribute('src');};
  input.addEventListener('change',async()=>{
    const current=++selection;clear();button.disabled=true;status.textContent='';
    const file=input.files?.[0];if(!file)return;
    try {
      await validateCover(file);if(!active||current!==selection)return;
      previewUrl=URL.createObjectURL(file);preview.src=previewUrl;preview.hidden=false;button.disabled=false;
    } catch(error){if(active&&current===selection){input.value='';status.textContent=error instanceof Error?error.message:'无法读取图片';}}
  });
  form.addEventListener('submit',async event=>{
    event.preventDefault();const file=input.files?.[0];if(!file||button.disabled)return;
    button.disabled=true;input.disabled=true;status.textContent='正在保存封面…';
    try {
      const extension=await validateCover(file);
      const path=`${ownerId}/${shareId}/cover-${crypto.randomUUID()}.${extension}`;
      const uploaded=await db.storage.from('shared-previews').upload(path,file,{upsert:false,contentType:file.type,cacheControl:'3600'});
      if(uploaded.error)throw Error(uploaded.error.message);
      const updated=await db.from('shared_contents').update({cover_url:path}).eq('id',shareId).eq('author_user_id',ownerId).select('id').single();
      if(updated.error)throw Error(updated.error.message);
      // Keep prior objects: another open editor or a previously issued URL may use them.
      if(active){clear();onSaved();}
    }catch(error){if(active)status.textContent=error instanceof Error?error.message:'保存失败，请重试';}
    finally{if(active){button.disabled=false;input.disabled=false;}}
  });
  return ()=>{active=false;selection++;clear();};
}
