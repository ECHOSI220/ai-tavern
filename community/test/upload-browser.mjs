import {chromium} from '@playwright/test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
// PW_CHANNEL lets CI or a machine without the bundled Playwright browser use an
// installed one (e.g. PW_CHANNEL=msedge). Unset keeps the default bundled Chromium.
const browser=await chromium.launch({headless:true,...(process.env.PW_CHANNEL?{channel:process.env.PW_CHANNEL}:{})});
const base=process.env.WEB_TEST_URL??'https://ai-tavern-cloud.pages.dev';
try {
 const page=await browser.newPage({viewport:{width:375,height:900}});
 const errors=[];page.on('pageerror',error=>errors.push(error.message));
 // Vite preview does not serve Pages' _headers; enforce the production CSP here.
 const csp=readFileSync(new URL('../public/_headers',import.meta.url),'utf8').match(/Content-Security-Policy: (.*)/)[1];
 await page.route(base+'/**',async route=>{const response=await route.fetch();await route.fulfill({response,headers:{...response.headers(),'content-security-policy':csp}});});
 const coverBuffer=await page.screenshot({type:'png'});
 const uid='00000000-0000-4000-8000-000000000001';
 const claims={sub:uid,exp:Math.floor(Date.now()/1000)+3600,role:'authenticated'};
 const token=[{alg:'HS256'},claims].map(x=>Buffer.from(JSON.stringify(x)).toString('base64url')).join('.')+'.test';
 await page.addInitScript(({token,uid})=>localStorage.setItem('sb-gveqrxurrvqfjawejwuh-auth-token',JSON.stringify({access_token:token,refresh_token:'test-only',expires_at:Math.floor(Date.now()/1000)+3600,token_type:'bearer',user:{id:uid,email:'test@example.invalid'}})),{token,uid});
 let stored, storedPreview, published, publishRpc;
 const coverPath=uid+'/public-fixture/cover.png';
 const publicItem={id:'public-fixture',title:'公开封面测试',description:'封面展示验证',content_type:'WORLD_BOOK',visibility:'PUBLIC',current_version:1,created_at:new Date().toISOString(),author_user_id:uid,tags:[],cover_url:coverPath};
 // All cloud requests are intercepted: this test never uploads fixtures to production.
 await page.route('https://*.supabase.co/**',async route=>{
  const request=route.request(),url=new URL(request.url());
  if(url.pathname.includes('/storage/v1/object/sign/'))return route.fulfill({json:[{path:coverPath,signedURL:'/object/sign/shared-previews/'+coverPath+'?token=test'}]});
  if(url.pathname.includes('/storage/v1/object/sign/')===false&&request.method()==='GET'&&url.pathname.includes('/shared-previews/'))return route.fulfill({body:coverBuffer,contentType:'image/png'});
  if(url.pathname.includes('/storage/v1/object/')) {
   const form=await new Response(request.postDataBuffer(),{headers:{'content-type':request.headers()['content-type']}}).formData();
   const file=[...form.values()].find(value=>typeof value!=='string');
   if(url.pathname.includes('/shared-content/'))stored=JSON.parse(await file.text());
   else storedPreview={name:file.name,type:file.type,size:file.size};
   return route.fulfill({json:{Key:'test'}});
  }
  if(url.pathname.includes('/cloud_publish_share')) {published=request.postDataJSON();publishRpc=url.pathname;return route.fulfill({json:null});}
  if(url.pathname.endsWith('/cloud_share_by_id'))return route.fulfill({json:{content:{id:'test',title:'世界书测试',content_type:'WORLD_BOOK',visibility:'PRIVATE',current_version:1,author_user_id:uid,tags:[]},versions:[],comments:[]}});
  if(url.pathname.endsWith('/auth/v1/user'))return route.fulfill({json:{id:uid}});
  return route.fulfill({json:[]});
 });
 page.on('dialog',dialog=>dialog.accept());
 await page.goto(base+'/me/uploads?new=1',{waitUntil:'networkidle'});
 assert.equal(await page.locator('#cover-preview').isVisible(),false);
 await page.getByLabel('作品名称').fill('世界书测试');await page.getByLabel('简介',{exact:true}).fill('仅本机拦截测试');
 await page.locator('[name=contentType]').selectOption('WORLD_BOOK');
 await page.locator('[name=file]').setInputFiles({name:'world.json',mimeType:'application/json',buffer:Buffer.from(JSON.stringify({entries:{'0':{content:'公开设定',key:['测试'],secrets:['剧情伏笔']}}}))});
 await page.locator('[name=cover]').setInputFiles({name:'cover.png',mimeType:'image/png',buffer:coverBuffer});
 await page.locator('#cover-preview').waitFor({state:'visible'});
 await page.waitForFunction(()=>document.querySelector('#cover-preview').naturalWidth>0);
 assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);
 await page.screenshot({path:'test-results/upload-cover-mobile.png',fullPage:true});
 await page.getByRole('checkbox').check();await page.getByRole('button',{name:'检查并确认发布'}).click();
 await page.waitForURL('**/share/**');
 assert.equal(stored.contentType,'WORLD_BOOK');assert.equal(stored.data.entries['0'].content,'公开设定');assert.deepEqual(stored.data.entries['0'].secrets,['剧情伏笔']);
 assert.deepEqual(storedPreview,{name:'cover.png',type:'image/png',size:coverBuffer.length});
 assert.ok(publishRpc.endsWith('/cloud_publish_share_with_preview'));assert.match(published.preview_path,/\/cover\.png$/);
 assert.equal(published.share_visibility,'PRIVATE');assert.equal(published.share_type,'WORLD_BOOK');
 await page.getByRole('heading',{name:'世界书测试',exact:true}).waitFor();assert.deepEqual(errors,[]);
 // Check cards and detail rendering using signed cover responses, without cloud writes.
 await page.route('https://*.supabase.co/storage/v1/object/sign/**',route=>route.request().method()==='GET'?route.fulfill({body:coverBuffer,contentType:'image/png'}):route.fulfill({json:[{path:coverPath,signedURL:'/object/sign/shared-previews/'+coverPath+'?token=test'}]}));
 await page.route('https://*.supabase.co/rest/v1/shared_contents*',route=>route.fulfill({json:[publicItem]}));
 await page.route('https://*.supabase.co/rest/v1/rpc/cloud_share_by_id',route=>route.fulfill({json:{content:publicItem,versions:[],comments:[]}}));
 await page.goto(base+'/discover',{waitUntil:'networkidle'});
 await page.waitForFunction(()=>document.querySelector('.card img')?.naturalWidth>0);
 await page.locator('.card').click();
 await page.waitForFunction(()=>document.querySelector('.detail-cover')?.naturalWidth>0);
 let changedCover;
 await page.route('https://*.supabase.co/rest/v1/shared_contents*',route=>{
  if(route.request().method()==='PATCH'){
   const payload=route.request().postDataJSON();assert.deepEqual(Object.keys(payload),['cover_url']);
   assert.ok(route.request().url().includes('author_user_id=eq.'+uid));
   changedCover=payload.cover_url;publicItem.cover_url=changedCover;
   return route.fulfill({json:{id:publicItem.id}});
  }
  return route.fulfill({json:[publicItem]});
 });
 for(const initialCover of [undefined,coverPath]){
  publicItem.cover_url=initialCover;changedCover=undefined;
  await page.goto(base+'/share/public-fixture',{waitUntil:'networkidle'});
  await page.getByText('添加／更换封面',{exact:true}).click();
  await page.getByLabel('选择新封面').setInputFiles({name:'updated.png',mimeType:'image/png',buffer:coverBuffer});
  await page.getByRole('button',{name:'保存封面',exact:true}).waitFor();
  await page.waitForFunction(()=>!document.querySelector('details button').disabled);
  await page.getByRole('button',{name:'保存封面',exact:true}).click();
  await page.waitForFunction(()=>!document.querySelector('details')?.open);
  assert.match(changedCover,/\/cover-[0-9a-f-]+\.png$/);
 }
 publicItem.author_user_id='00000000-0000-4000-8000-000000000002';
 await page.goto(base+'/share/public-fixture',{waitUntil:'networkidle'});
 assert.equal(await page.getByText('添加／更换封面',{exact:true}).count(),0);
 assert.deepEqual(errors,[]);
 console.log('PASS mobile upload form converts ordinary JSON, keeps PRIVATE default, sends matching storage/RPC payloads (network mocked, no remote writes).');
} finally {await browser.close();}
