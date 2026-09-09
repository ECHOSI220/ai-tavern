// Explicit production smoke test; temporary private fixtures are removed in finally.
// Never imported by the browser bundle.
import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
import {createClient} from '@supabase/supabase-js';
import {checksum} from '../src/package.mjs';
const config=Object.fromEntries(readFileSync('../server/.env.production.local','utf8').split(/\r?\n/).filter(l=>/^[A-Z_]+=/.test(l)).map(l=>{const i=l.indexOf('=');return [l.slice(0,i),l.slice(i+1).replace(/^['"]|['"]$/g,'')]}));
const options={auth:{persistSession:false,autoRefreshToken:false}};
if(!config.SUPABASE_SERVICE_ROLE_KEY){console.error('SKIPPED: admin credential is not stored locally; real Auth/upload smoke test has not run.');process.exit(2);}
const admin=createClient(config.SUPABASE_URL,config.SUPABASE_SERVICE_ROLE_KEY,options);
const anon=createClient(config.SUPABASE_URL,config.SUPABASE_ANON_KEY,options);
const accounts=[],paths=[],ids=[];
function ok(result){if(result.error)throw Error(result.error.message);return result.data;}
try{
 for(let i=0;i<2;i++){
  const email=`cloud-verify-${crypto.randomUUID()}@example.invalid`,password=crypto.randomUUID()+'Aa!';
  const account=ok(await admin.auth.admin.createUser({email,password,email_confirm:true})).user;accounts.push(account.id);
  const client=createClient(config.SUPABASE_URL,config.SUPABASE_ANON_KEY,options);
  ok(await client.auth.signInWithPassword({email,password}));
  if(i===0)globalThis.author=client;else globalThis.outsider=client;
 }
 for(const visibility of ['PRIVATE','UNLISTED']){
  const id=crypto.randomUUID(),path=`${accounts[0]}/${id}/1.json`;
  const text=JSON.stringify({schemaVersion:1,contentType:'OTHER',data:{name:'Temporary verification fixture'}});
  ok(await author.storage.from('shared-content').upload(path,new Blob([text],{type:'application/json'})));paths.push(path);
  ok(await author.rpc('cloud_publish_share',{share_id:id,share_title:'Temporary verification fixture',share_description:'Removed automatically after test',share_type:'OTHER',share_visibility:visibility,share_tags:[],object_path:path,object_size:new TextEncoder().encode(text).length,object_checksum:await checksum(text)}));ids.push(id);
  const authorView=ok(await author.rpc('cloud_share_by_id',{share_id:id}));assert.equal(authorView.content.visibility,visibility);
  assert.equal(ok(await anon.from('shared_contents').select('id').eq('id',id)).length,0);
  const visitorView=ok(await anon.rpc('cloud_share_by_id',{share_id:id}));assert.equal(Boolean(visitorView),visibility==='UNLISTED');
  const otherView=ok(await outsider.rpc('cloud_share_by_id',{share_id:id}));assert.equal(Boolean(otherView),visibility==='UNLISTED');
  const direct=await anon.storage.from('shared-content').download(path);assert.ok(direct.error,'Unlisted storage listing/read should not be public');
  const download=await fetch(config.GAME_SERVER_URL+'/v1/public/shares/'+id+'/download');assert.equal(download.ok,visibility==='UNLISTED');
  if(download.ok){const signed=await download.json();const file=await fetch(signed.url);assert.equal(await checksum(await file.text()),await checksum(text));}
  const replacement=await author.storage.from('shared-content').update(path,new Blob(['{}'],{type:'application/json'}));assert.ok(replacement.error,'Version object was overwritten');
  ok(await outsider.from('shared_contents').delete().eq('id',id));assert.ok(ok(await author.rpc('cloud_share_by_id',{share_id:id})));
  if(visibility==='UNLISTED'){
   ok(await outsider.from('favorites').upsert({user_id:accounts[1],content_id:id},{onConflict:'user_id,content_id',ignoreDuplicates:true}));
   ok(await outsider.from('comments').insert({user_id:accounts[1],content_id:id,body:'Temporary verification comment'}));
   assert.equal(ok(await anon.rpc('cloud_share_by_id',{share_id:id})).comments.length,1);
  }
 }
 console.log('PASS real Auth login, private/unlisted publish, anonymous/other-user RLS, JSON checksum download, immutable storage, favorites and comments');
}finally{
 for(const id of ids)ok(await admin.from('shared_contents').delete().eq('id',id));
 if(paths.length)ok(await admin.storage.from('shared-content').remove(paths));
 for(const id of accounts)ok(await admin.auth.admin.deleteUser(id));
 console.log('Temporary test shares, files and accounts removed.');
}
